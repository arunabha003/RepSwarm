# SwarmRep Protocol (Uniswap v4 Hook + AI Agents)

SwarmRep is an on-chain MEV-protection + value-redistribution protocol built on **Uniswap v4 hooks**.

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
- `docs/SEPOLIA_DEPLOYMENT.md` (live Sepolia deployment + liquidity bootstrap)

In short:

1. Start Anvil forking Sepolia.
2. Fund the deployer with DAI on the fork.
3. Deploy using `script/DeployAnvilSepoliaFork.s.sol` (creates pools + liquidity, wires everything).
4. Run the frontend in `frontend/` and test the full flow.

Current protocol status in this repo:

- No mocked contracts in the core protocol path (`src/`) for Sepolia/fork E2E.
- Backrun execution is on-chain and permissionless via `FlashBackrunExecutorAgent`.
- No dedicated keeper or scoring server is required.

## Architecture (One-Liners)

- `SwarmHook` is the Uniswap v4 hook attached to the pool.
- `AgentExecutor` is the hook’s “agent manager”: it decides which agent contracts run and lets admin hot-swap them.
- Hook agents are on-chain contracts:
  - `ArbitrageAgent`: pre-swap oracle divergence capture (hook take + delta)
  - `DynamicFeeAgent`: recommends v4 dynamic fee override
  - `BackrunAgent`: detects post-swap divergence and records backrun opportunities
- `FlashLoanBackrunner`: stores opportunities and executes backruns (capital mode or Aave flashloan mode); distributes profits (LPs + keeper).
- `FlashBackrunExecutorAgent`: permissionless on-chain executor that can trigger `FlashLoanBackrunner` (no dedicated keeper server required).
- `LPFeeAccumulator`: accumulates captured value and donates to LPs.
- `OracleRegistry`: maps token pairs to Chainlink feeds and exposes `getLatestPrice`.
- `SwarmCoordinator`: intent-based swap flow (route proposals + execute), optionally gated by ERC-8004 identity/reputation; writes ERC-8004 feedback on success.
- `SwarmAgentRegistry`: helper for minting/linking ERC-8004 identities for agent contracts (metadata + mapping).
- `SimpleRouteAgent`: minimal on-chain route agent that submits proposals to coordinator automatically with configurable defaults.

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
- Automatic (on-chain): call `FlashBackrunExecutorAgent.execute(poolId)` permissionlessly.
- Optional external automation: any bot/EOA can watch `BackrunOpportunityDetected` and call the same execute path.

## ERC-8004 (Where It Fits)

ERC-8004 is used in two places:

- Coordinator (route agent gating + feedback):
  - Can enforce identity + minimum reputation for proposal submission.
  - Writes +1 WAD feedback for the winning route agent on successful execution.
- Hook agent lifecycle (optional):
  - Hook agents can be linked to ERC-8004 identity IDs (for “official agent identities”).
  - Admin can configure reputation threshold switching in `AgentExecutor` (off-path, never inside swaps).

Note: a reputation threshold only matters if someone is writing reputation feedback. `AgentExecutor` supports
optional on-chain scoring (`setOnchainScoringConfig`) to post +1/-1 feedback directly. An external scoring service is optional.

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

## Live Sepolia Deployment

Latest live deployment from `script/DeploySwarmProtocol.s.sol` on Sepolia (`chainId=11155111`):

- Deployer / Treasury: `0x28ea4eF61ac4cca3ed6a64dBb5b2D4be1aDC9814`
  (https://sepolia.etherscan.io/address/0x28ea4eF61ac4cca3ed6a64dBb5b2D4be1aDC9814)
- PoolManager: `0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A`
  (https://sepolia.etherscan.io/address/0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A)
- WETH (Aave-market): `0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c`
  (https://sepolia.etherscan.io/address/0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c)
- DAI (Aave-market): `0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357`
  (https://sepolia.etherscan.io/address/0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357)
- Oracle feed (ETH/USD): `0x694AA1769357215DE4FAC081bf1f309aDC325306`
  (https://sepolia.etherscan.io/address/0x694AA1769357215DE4FAC081bf1f309aDC325306)
- OracleRegistry: `0x42b598ff76b62A0fd273560F691896102c5a3A4A`
  (https://sepolia.etherscan.io/address/0x42b598ff76b62A0fd273560F691896102c5a3A4A)
- LPFeeAccumulator: `0xe7D6cDe8f3Af7088D1999F1969F877ebe0d78517`
  (https://sepolia.etherscan.io/address/0xe7D6cDe8f3Af7088D1999F1969F877ebe0d78517)
- AgentExecutor: `0xAC8B64ee8DF2dcdcCbF471B9E2a4a281d14b03FF`
  (https://sepolia.etherscan.io/address/0xAC8B64ee8DF2dcdcCbF471B9E2a4a281d14b03FF)
- SwarmHook: `0x653557bE812E70CD5B9Abc0f4Ee8f5f4604e00cc`
  (https://sepolia.etherscan.io/address/0x653557bE812E70CD5B9Abc0f4Ee8f5f4604e00cc)
- SwarmCoordinator: `0x5be7B30051264fECf6a248551bd408b98eCfd5d2`
  (https://sepolia.etherscan.io/address/0x5be7B30051264fECf6a248551bd408b98eCfd5d2)
- SimpleRouteAgent: `0xDf1cb317Fff7CC63100682e9E3ea0eAce8D514d4`
  (https://sepolia.etherscan.io/address/0xDf1cb317Fff7CC63100682e9E3ea0eAce8D514d4)
- ArbitrageAgent: `0xFA1591069f7f1e48e8758179014f19F65fF44b26` (ERC-8004 ID `980`)
  (https://sepolia.etherscan.io/address/0xFA1591069f7f1e48e8758179014f19F65fF44b26)
- DynamicFeeAgent: `0x6Be9E7Db2335fe26fB0741D9E1fC8c581FCBfBDd` (ERC-8004 ID `981`)
  (https://sepolia.etherscan.io/address/0x6Be9E7Db2335fe26fB0741D9E1fC8c581FCBfBDd)
- BackrunAgent: `0xe2B466898D45f6Ae73Ca20b5e85eA584d0589216` (ERC-8004 ID `982`)
  (https://sepolia.etherscan.io/address/0xe2B466898D45f6Ae73Ca20b5e85eA584d0589216)
- FlashLoanBackrunner: `0xAf26D906b2AE22276D8d07183aEc66609035F196`
  (https://sepolia.etherscan.io/address/0xAf26D906b2AE22276D8d07183aEc66609035F196)
- FlashBackrunExecutorAgent: `0xD6D9473EA9f155F25f9D15CE896171075961A2a4`
  (https://sepolia.etherscan.io/address/0xD6D9473EA9f155F25f9D15CE896171075961A2a4)
- SwarmAgentRegistry: `0x048b0819f3942e1B548579004a486b6029217d13`
  (https://sepolia.etherscan.io/address/0x048b0819f3942e1B548579004a486b6029217d13)
- SimpleRouteAgent ERC-8004 ID: `983`

This run used `BOOTSTRAP_POOLS=false`, so pool creation/liquidity bootstrap is not included yet.

## Notes / Assumptions

- Oracle pricing in the demo uses the Chainlink ETH/USD feed as a proxy for WETH/DAI (assumes DAI ~= USD). For production, configure pair-specific feeds or safer composite oracles.
- This repo is not an audit.
