# Architecture

> System design, data flows, and agent switching model.

---

## Overview

SwarmRep operates on two planes:

- **Swap Plane** — On every swap, the Uniswap v4 hook calls on-chain hook agents via `AgentExecutor` to capture arbitrage, set fees, and detect backrun opportunities.
- **Intent Plane** — Users submit swap intents to `SwarmCoordinator`. Route agents compete to propose execution paths. The coordinator executes through v4 with MEV-aware hookData.

All off-chain-dependent behavior (backrun execution, reputation switching) is intentionally **off-path** — user swaps never revert due to automation failures.

---

## Contracts

| Contract | Role |
|----------|------|
| `SwarmHook` | Uniswap v4 hook — delegates to `AgentExecutor`, applies MEV accounting (capture delta, dynamic fee, MEV fee skim), accumulates value into `LPFeeAccumulator`, records backrun opportunities via `FlashLoanBackrunner` |
| `AgentExecutor` | Manages hook agents per type (ARBITRAGE / DYNAMIC_FEE / BACKRUN). Supports enable/disable, backup failover, per-agent stats, and optional on-chain ERC-8004 scoring |
| `ArbitrageAgent` | Compares pool price vs oracle price → recommends pre-swap value capture amount |
| `DynamicFeeAgent` | Recommends dynamic fee override (Uniswap v4 dynamic fee feature) |
| `BackrunAgent` | Detects post-swap price dislocations → signals backrun opportunity recording |
| `FlashLoanBackrunner` | Stores one pending opportunity per pool. Executes via keeper capital or Aave v3 flashloan. Splits profit: 80% to LPs, 20% to keeper |
| `FlashBackrunExecutorAgent` | Permissionless on-chain executor — any caller triggers backrun and receives keeper bounty |
| `LPFeeAccumulator` | Accumulates MEV profits per pool/currency. `donateToLPs(poolId)` sends to LPs via Uniswap v4 `donate()` |
| `OracleRegistry` | Maps token pairs to Chainlink price feeds. `getLatestPrice(base, quote)` returns 1e18-normalized price |
| `SwarmCoordinator` | Intent router: create intent → route agent proposals → execute. Optional ERC-8004 identity/reputation gating. Writes feedback on success |
| `SimpleRouteAgent` | Minimal on-chain route agent for submitting coordinator proposals with configurable defaults |
| `SwarmAgentRegistry` | Mints and links ERC-8004 identities (ERC-721 NFTs with agent metadata) for agent contracts |

---

## Data Flows

### A) Swap Plane (Hook Path)

```
1. Swap → PoolManager
2. PoolManager → SwarmHook.beforeSwap()
3. Hook builds SwapContext (poolKey, params, pool price, oracle price)
4. Hook → AgentExecutor.processBeforeSwap(context)
   ├── ArbitrageAgent → pre-swap capture recommendation
   └── DynamicFeeAgent → fee override recommendation
5. Swap executes in PoolManager
6. PoolManager → SwarmHook.afterSwap()
7. Hook → AgentExecutor.processAfterSwap(context, newPoolPrice)
   └── BackrunAgent → if dislocation detected, signal recording
8. Hook → FlashLoanBackrunner.recordBackrunOpportunity() [if signaled]
9. Hook accounts for MEV fee donation (when hookData is present)
```

### B) Intent Plane (Coordinator Path)

```
1. User → SwarmCoordinator.createIntent() with candidate paths
2. Route agents → submitProposal(intentId, candidateId, score, data)
   └── Optional: ERC-8004 identity + reputation enforcement
3. User → executeIntent(intentId)
   ├── Coordinator selects winning candidate
   ├── Encodes hookData → executes via v4 router
   └── Swap runs through hooked pool (swap plane executes)
4. Coordinator writes +1 WAD ERC-8004 feedback for winning agent (best-effort)
```

### C) Backrun Execution (Permissionless)

```
1. Hook records opportunity → emits BackrunOpportunityDetected
2. Executor calls one of:
   ├── FlashBackrunExecutorAgent.execute(poolId)        [permissionless]
   ├── FlashLoanBackrunner.executeBackrunPartial()      [flashloan mode]
   └── FlashLoanBackrunner.executeBackrunWithCapital()  [capital mode]
3. Profit split:
   ├── 80% → LPFeeAccumulator (donated to LPs later)
   └── 20% → keeper bounty
```

---

## Agent Switching Model

Three layers, from simple to advanced:

| Layer | Mechanism | Trigger |
|-------|-----------|---------|
| **Manual** | `AgentExecutor.registerAgent(type, newAgent)` | Admin call |
| **Failover** | If primary agent reverts, `AgentExecutor` tries the configured backup | Automatic (runtime) |
| **Reputation** | Switch agent when ERC-8004 reputation falls below threshold | Admin-triggered via `checkAndSwitchAgentIfBelowThreshold()` |

Reputation switching is always **off-path** — never called inside swaps to avoid introducing external call failures.

---
