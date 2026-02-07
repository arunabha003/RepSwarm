# SwarmRep Architecture

SwarmRep is a Uniswap v4 hook-based protocol with two distinct “planes”:

- Swap plane (hook path): on every swap, the hook calls on-chain **hook agents** via an **AgentExecutor**.
- Intent plane (coordinator path): users submit **intents** and **route agents** propose which route to use; the coordinator executes the swap through v4 while attaching hookData so the hook applies MEV rules.

The system is designed so user swaps never depend on off-chain automation. Anything that can fail (backrun execution, reputation switching) is intentionally off-path.

## Key Actors

- User: creates and executes intents (frontend).
- Route agent (`SimpleRouteAgent`): on-chain proposer contract, optionally driven by off-chain bots/services.
- Backrun executor caller (on-chain): any EOA/bot can trigger `FlashBackrunExecutorAgent.execute(poolId)`.
- Admin: can hot-swap hook agents and configure enforcement/switching policies.

## Contracts (What Each Does)

- `src/hooks/SwarmHook.sol`
  - Uniswap v4 hook attached to the pool.
  - Builds swap context and delegates decisions to `AgentExecutor`.
  - Applies accounting:
    - pre-swap capture delta (exact-in only)
    - dynamic fee override
    - MEV fee skim (when hookData is present)
    - profit accumulation into `LPFeeAccumulator`
  - Records backrun opportunities via `FlashLoanBackrunner` when backrun agent signals it.

- `src/agents/AgentExecutor.sol`
  - Agent manager for the hook:
    - stores current agent per type (ARBITRAGE / DYNAMIC_FEE / BACKRUN)
    - supports enable/disable
    - supports backup agents (failover if primary reverts)
    - tracks basic per-agent stats (`agentStats`)
    - optional on-chain ERC-8004 scoring (`setOnchainScoringConfig`) to write feedback without an off-chain scorer
  - Optional reputation-based switching is supported, but it is admin-triggered and never called inside swaps.

- Hook agents (on-chain)
  - `src/agents/ArbitrageAgent.sol`
    - compares pool price vs oracle price and recommends how much to capture pre-swap.
  - `src/agents/DynamicFeeAgent.sol`
    - recommends a dynamic fee override (v4 dynamic fee feature).
  - `src/agents/BackrunAgent.sol`
    - detects post-swap dislocations and recommends recording a backrun opportunity.

- `src/backrun/FlashLoanBackrunner.sol`
  - Stores a single pending opportunity per pool.
  - Executes backruns:
    - `executeBackrunWithCapital(...)` (keeper supplies tokens)
    - `executeBackrunPartial(...)` (Aave v3 flashloan)
  - Profit distribution:
    - 80% accumulated for LPs via `LPFeeAccumulator`
    - 20% paid to keeper
  - Emits:
    - `BackrunOpportunityDetected`
    - `BackrunExecuted`

- `src/agents/FlashBackrunExecutorAgent.sol`
  - Permissionless on-chain executor for `FlashLoanBackrunner`.
  - Any caller can trigger execution and receive bounty routed through the agent contract.
  - Requires owner setup on `FlashLoanBackrunner` (authorize as forwarder + keeper).

- `src/LPFeeAccumulator.sol`
  - Accumulates profits per pool/currency.
  - Anyone can call `donateToLPs(poolId)` when thresholds are met.

- `src/oracles/OracleRegistry.sol`
  - Maps token pairs to Chainlink price feeds.
  - Exposes `getLatestPrice(base, quote)` normalized to 1e18.

- `src/SwarmCoordinator.sol`
  - Intent router for MEV-protected swaps.
  - Users submit intents with candidate paths.
  - Route agents submit proposals for which candidate to execute.
  - Coordinator selects best candidate (based on submitted scores) and executes via v4 router.
  - Attaches `SwarmHookData` payload to each hop so the hook can apply MEV fee logic.
  - Optional ERC-8004 enforcement for route agents:
    - identity gating
    - reputation threshold gating
  - Writes ERC-8004 feedback (+1 WAD) on successful execution (best-effort, never reverts the swap on feedback failure).

- `src/erc8004/SimpleRouteAgent.sol`
  - Minimal on-chain route agent that submits coordinator proposals with configurable defaults.
  - Replaces manual UI proposal submission loops for basic demos.

- `src/erc8004/SwarmAgentRegistry.sol`
  - Helper for minting and tracking ERC-8004 agent identities (metadata + mapping).
  - Used to register/link agent contracts to official ERC-8004 IdentityRegistry IDs.
  - Can be used for hook agents or route agents, depending on how you operate your system.

## Data Flows

### A) Swap Plane (Hook Path)

1. Swap hits v4 PoolManager.
2. PoolManager calls `SwarmHook.beforeSwap(...)`.
3. Hook builds `SwapContext` (poolKey, params, pool price, oracle price/confidence).
4. Hook calls `AgentExecutor.processBeforeSwap(context)`:
   - arbitrage agent recommendation may trigger pre-swap capture
   - dynamic fee agent recommendation may trigger fee override
5. Swap executes in PoolManager.
6. PoolManager calls `SwarmHook.afterSwap(...)`.
7. Hook calls `AgentExecutor.processAfterSwap(context, newPoolPrice)`:
   - backrun agent may signal recording an opportunity
8. Hook (if signaled) calls `FlashLoanBackrunner.recordBackrunOpportunity(...)`.
9. Hook accounts for MEV fee donation when hookData is present.

### B) Intent Plane (Coordinator Path)

1. User calls `SwarmCoordinator.createIntent(...)` with candidate paths.
2. Route agents call `submitProposal(intentId, candidateId, score, data)`:
   - optional enforcement checks:
     - ERC-8004 identity ownership/authorization
     - ERC-8004 minimum reputation (configurable clients/tags)
3. User calls `executeIntent(intentId)`:
   - coordinator selects the winning candidate
   - coordinator encodes hookData and executes the v4 router actions
   - the swap occurs through the hooked pool, so the hook logic runs (swap plane)
4. Coordinator writes positive ERC-8004 feedback for the winning route agent (best-effort).

### C) Backrun Execution (Permissionless)

1. Hook records opportunity and emits `BackrunOpportunityDetected`.
2. Executor calls:
   - permissionless on-chain `FlashBackrunExecutorAgent.execute(poolId)`, or
   - direct backrunner methods:
     - `FlashLoanBackrunner.executeBackrunPartial(...)` (flashloan mode), or
     - `FlashLoanBackrunner.executeBackrunWithCapital(...)` (capital mode)
3. Profits are routed:
   - 80% to `LPFeeAccumulator` (donation later)
   - 20% to keeper

## Agent Switching Model

SwarmRep supports three layers of switching:

1. Manual switching (admin)
  - `AgentExecutor.registerAgent(agentType, newAgent)`

2. Backup failover (runtime)
  - if the primary agent reverts, `AgentExecutor` attempts the configured backup.

3. Reputation threshold switching (admin-triggered, off-path)
  - configure:
    - `setReputationSwitchConfig(...)`
    - `setReputationSwitchClients(...)`
  - trigger:
    - `checkAndSwitchAgentIfBelowThreshold(agentType)`

This is off-path to avoid introducing external calls and failure modes into swaps.

## External Automation (Optional)

- Backrun automation bot (not bundled in this repo)
  - can listen to `BackrunOpportunityDetected`
  - can call `FlashBackrunExecutorAgent.execute(poolId)` automatically

- Scoring bot (not bundled in this repo)
  - can write additional +1/-1 feedback to ERC-8004 ReputationRegistry
  - optional when on-chain scoring is enabled in `AgentExecutor`

## Deployment (Local Sepolia Fork)

- `script/DeployAnvilSepoliaFork.s.sol`
  - deploys and wires everything for `chainId=31337` (Anvil forking Sepolia)
  - creates two pools:
    - hooked pool (dynamic fee flag, hooks set to `SwarmHook`)
    - repay pool (no hook, used for reverse swap in backruns)
  - optionally seeds Aave liquidity on the fork for deterministic flashloans
  - optionally registers hook agents on ERC-8004 and links their IDs into the agent contracts

See:

- `docs/ANVIL_SEPOLIA_E2E.md`
- `docs/FRONTEND_E2E_GUIDE.md`
