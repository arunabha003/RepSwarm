# Swarm Protocol (Uniswap v4 Hook + AI Agents)

Swarm is an on-chain MEV-protection + value-redistribution protocol built on **Uniswap v4 hooks**.

What it does:

- Runs **hook agents** on every swap (arb capture, dynamic fee, backrun detection).
- Records backrun opportunities on-chain and supports executing them with **keeper capital** or **Aave v3 flashloans**.
- Accumulates MEV value in `LPFeeAccumulator` and lets anyone donate it to LPs.
- Provides a **Coordinator intent flow** (create intent → route-agent proposals → execute) with optional **ERC-8004 identity + reputation** enforcement.

This repo is designed to be runnable and verifiable on a **Sepolia fork** with **no mocked integrations in the E2E flow**:

- Uniswap v4 `PoolManager` (Sepolia deployment)
- Chainlink ETH/USD feed (Sepolia deployment)
- Aave v3 Pool (Sepolia deployment)
- ERC-8004 Identity + Reputation registries (official Sepolia deployments)

## Quick Start (Local Sepolia Fork + Frontend)

Use the docs:

- `docs/ANVIL_SEPOLIA_E2E.md` (Anvil + deploy scripts)
- `docs/FRONTEND_E2E_GUIDE.md` (step-by-step UI testing)

In short:

1. Start Anvil forking Sepolia.
2. Fund the deployer with DAI on the fork.
3. Deploy using `script/DeployAnvilSepoliaFork.s.sol` (creates pools + liquidity, wires everything).
4. Run the frontend in `frontend/` and test the full flow.

## Architecture (One-Liners)

- `SwarmHook` is the Uniswap v4 hook attached to the pool.
- `AgentExecutor` is the hook’s “agent manager”: it decides which agent contracts run and lets admin hot-swap them.
- Hook agents are on-chain contracts:
  - `ArbitrageAgent`: pre-swap oracle divergence capture (hook take + delta)
  - `DynamicFeeAgent`: recommends v4 dynamic fee override
  - `BackrunAgent`: detects post-swap divergence and records backrun opportunities
- `FlashLoanBackrunner`: stores opportunities and executes backruns (capital mode or Aave flashloan mode); distributes profits (LPs + keeper).
- `LPFeeAccumulator`: accumulates captured value and donates to LPs.
- `OracleRegistry`: maps token pairs to Chainlink feeds and exposes `getLatestPrice`.
- `SwarmCoordinator`: intent-based swap flow (route proposals + execute), optionally gated by ERC-8004 identity/reputation; writes ERC-8004 feedback on success.
- `SwarmAgentRegistry`: helper for minting/linking ERC-8004 identities for agent contracts (metadata + mapping).

For the full diagram and flow: `ARCHITECTURE.md`.

## User Flows (Practical)

### Intent Swap (What the frontend uses)

1. User creates an intent (“swap tokenIn → tokenOut”).
2. Route agents (bots/services) submit proposals (which candidate path to use).
3. User executes the intent, which swaps through v4 and attaches hookData so the hook can enforce MEV fee rules.

In the local demo, you can register your wallet as a route agent so you can submit proposals manually from the UI.
In production, your team runs route agents off-chain; users should not do that step manually.

### Hook Swap (What happens during execution)

When a swap executes through the hooked pool:

- `beforeSwap`: `AgentExecutor` asks the hook agents for capture + fee override recommendations.
- `afterSwap`: `AgentExecutor` asks the backrun agent whether to record a backrun opportunity.
- Hook accounts for MEV fees and accumulates value for LP donation.

### Backrun Execution (Off-Path by design)

Backrun execution is intentionally a separate transaction so swaps never revert because “automation failed”.

- Manual: execute from the frontend `Backrun` tab.
- Automatic: run the keeper (`keeper/`) to listen for `BackrunOpportunityDetected` and execute immediately.

## ERC-8004 (Where It Fits)

ERC-8004 is used in two places:

- Coordinator (route agent gating + feedback):
  - Can enforce identity + minimum reputation for proposal submission.
  - Writes +1 WAD feedback for the winning route agent on successful execution.
- Hook agent lifecycle (optional):
  - Hook agents can be linked to ERC-8004 identity IDs (for “official agent identities”).
  - Admin can configure reputation threshold switching in `AgentExecutor` (off-path, never inside swaps).

Note: a reputation threshold only matters if someone is actually writing reputation feedback. For local demos, you can run
the scoring keeper in `keeper/` (`npm run score`) to post +1/-1 feedback from `AgentExecutor.AgentExecuted` events.

## Tests

Run everything:

```bash
forge test -vvv
```

Sepolia end-to-end suite (real integrations on fork):

```bash
forge test --match-contract E2ESepoliaTest -vvv
```

Mainnet end-to-end suite (gated by env var):

```bash
RUN_MAINNET_E2E=true forge test --match-contract E2EMainnetTest -vvv
```

## Deployment Scripts

Local Sepolia-fork deployment:

- `script/DeployAnvilSepoliaFork.s.sol` creates:
  - hook deployment (CREATE2 + hook flag bits)
  - hooked pool + repay pool
  - liquidity for both pools
  - Aave repay pool mapping
  - optional Aave seeding (recommended for deterministic flashloans)
  - optional ERC-8004 registration + linking for hook agents

See:

- `docs/ANVIL_SEPOLIA_E2E.md`
- `docs/FRONTEND_E2E_GUIDE.md`

## Notes / Assumptions

- Oracle pricing in the demo uses the Chainlink ETH/USD feed as a proxy for WETH/DAI (assumes DAI ~= USD). For production, configure pair-specific feeds or safer composite oracles.
- This repo is not an audit.
