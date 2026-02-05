# Swarm Protocol (Uniswap v4 Hook + Agents)

Swarm is an on-chain MEV-protection and value-redistribution protocol built on **Uniswap v4 hooks**. It runs a set of specialized **agents** around each swap, captures value that would otherwise be extracted by external searchers, and redistributes value to LPs (and optionally a treasury) using a fee accumulator + donation flow.

This repo is designed to be runnable and verifiable on a **Sepolia fork** with **no mocked integrations in the E2E flow** (real Uniswap v4 `PoolManager`, real Chainlink feed, real Aave v3 pool, real ERC-8004 registries).

## Status (Sepolia)

The protocol wiring is end-to-end functional on **Sepolia fork**:

- Hook deployment + pool initialization + liquidity.
- Swap path with agents enabled.
- Arbitrage capture (pre-swap capture).
- Dynamic fee override.
- MEV fee (post-swap output skim via hookData payload).
- Backrun opportunity recording (after swap).
- Backrun execution:
- Keeper-capital mode (no flashloan).
- Aave v3 flashloan mode (real Aave pool on Sepolia).
- Coordinator intent flow (create intent -> proposals -> execute).
- ERC-8004 identity enforcement and reputation enforcement against the official registries.
- ERC-8004 feedback write on successful intent execution.
- Agent hot-swap, backup agent failover, and reputation-based agent switching (admin driven).

What is not “automatic” on a live chain:

- Backruns are recorded on-chain, but executing them still requires a keeper/bot to call the backrunner (or additional automation infrastructure you deploy).

## Components

Core contracts:

- `src/hooks/SwarmHook.sol`: Uniswap v4 hook. Delegates decisions to `AgentExecutor` and applies MEV fee + capture accounting.
- `src/agents/AgentExecutor.sol`: Registers agents, routes hook calls to agents, supports enable/disable, backups, and admin-driven reputation-based switching.
- `src/agents/ArbitrageAgent.sol`: Detects oracle divergence and recommends pre-swap capture amount.
- `src/agents/DynamicFeeAgent.sol`: Recommends fee override (v4 dynamic fee override).
- `src/agents/BackrunAgent.sol`: Detects post-swap divergence and triggers backrun recording; can forward execution through `FlashLoanBackrunner`.
- `src/backrun/FlashLoanBackrunner.sol`: Records opportunities and executes backruns either with keeper capital or via Aave v3 flashloan; distributes profits to LPs via `LPFeeAccumulator`.
- `src/LPFeeAccumulator.sol`: Accumulates fees/profits per pool and donates to LPs (threshold + time window).
- `src/oracles/OracleRegistry.sol`: Maps token pairs to Chainlink feeds and provides `getLatestPrice`.
- `src/SwarmCoordinator.sol`: Intent-based routing coordinator. Adds ERC-8004 identity/reputation enforcement and writes reputation feedback for successful executions.

ERC-8004 integration:

- `src/erc8004/ERC8004Integration.sol`: Official registry addresses and helpers (Sepolia + Mainnet).
- `src/erc8004/SwarmAgentRegistry.sol`: Helper for agent identity/reputation integration and feedback client authorization.

## User Flows

1) Direct swap with MEV fee

- A user swaps through a pool whose `hooks` is `SwarmHook`.
- If the user (or a router/coordinator) provides `hookData` (the `SwarmHookData` payload), the hook skims an MEV fee from the swap output, splits it between treasury and LP accumulator, and returns an `afterSwapReturnDelta` so the user receives output minus fee.

2) Arbitrage capture (pre-swap)

- In `beforeSwap`, `ArbitrageAgent` compares pool price vs oracle price and can recommend capturing a portion of input.
- The hook `take()`s that input amount from `PoolManager` and routes it to:
- Treasury (optional, via payload), and
- LP accumulator (default path).
- Swap continues with reduced effective input (hook returns a `BeforeSwapDelta` for exact-input swaps).

3) Dynamic fee override

- In `beforeSwap`, `DynamicFeeAgent` can recommend an override fee.
- Hook emits `FeeOverrideApplied` and returns the `LPFeeLibrary.OVERRIDE_FEE_FLAG`-encoded fee to `PoolManager`.

4) Backrun detection + execution

- In `afterSwap`, `BackrunAgent` compares the post-swap pool price to the oracle price.
- When profitable divergence exists, the hook records the opportunity via `FlashLoanBackrunner.recordBackrunOpportunity(...)`.
- Keepers can execute:
- `executeBackrunWithCapital(...)` (uses keeper’s tokens), or
- `executeBackrunPartial(...)` / `executeBackrun(...)` (Aave v3 flashloan).
- Profit is distributed on-chain:
- 80% to LPs through `LPFeeAccumulator.accumulateFees(...)` + donation flow.
- 20% to keeper.

5) Coordinator intent execution (multi-agent routing)

- User creates an intent with candidate paths.
- Registered route agents submit proposals for which candidate path to use.
- Coordinator selects the best path (based on proposal scoring) and executes the swap through Uniswap v4, attaching Swarm hookData payload to every hop so MEV fee accounting is applied by the hook.
- If configured, coordinator enforces:
- ERC-8004 identity ownership/authorization for proposal submission.
- ERC-8004 minimum reputation threshold (tag + clients configurable).
- Coordinator writes ERC-8004 feedback (+1 WAD) on successful execution.

## “No Mocks” Guarantee (E2E)

The Sepolia E2E tests use real contracts on a Sepolia fork:

- Uniswap v4 `PoolManager` (Sepolia deployment).
- Aave v3 Pool (Sepolia deployment) for flashloans.
- Chainlink ETH/USD feed (Sepolia deployment) for oracle pricing.
- ERC-8004 Identity + Reputation registries (official Sepolia deployments).

Test-only conveniences still exist (these do not mock protocol logic):

- Forking and balance funding via Foundry cheatcodes for deterministic test setup.

## Running Tests

All tests:

```bash
forge test -vvv
```

Sepolia end-to-end suite (real integrations on fork):

```bash
forge test --match-contract E2ESepoliaTest -vvv
```

Mainnet end-to-end suite (disabled by default):

```bash
RUN_MAINNET_E2E=true forge test --match-contract E2EMainnetTest -vvv
```

Important test files:

- `test/E2E_Sepolia.t.sol`: Full Sepolia fork E2E (includes flashloan + ERC-8004 enforcement).
- `test/E2E_Mainnet.t.sol`: Mainnet fork E2E (gated by `RUN_MAINNET_E2E=true`).
- `test/AgentExecutorFailover.t.sol`: Backup agent failover behavior (primary revert -> backup used).
- `test/AgentExecutorReputationSwitch_Sepolia.t.sol`: Reputation-based switching against real ERC-8004 registries (Sepolia fork).
- `test/MevIntegration.t.sol`: Additional integration coverage.
- `test/SwarmUnit.t.sol`: Unit tests for utilities and registries.

## Admin Operations

Agent lifecycle:

- Register/switch an agent: `AgentExecutor.registerAgent(agentType, agent)`
- Set backup agent: `AgentExecutor.setBackupAgent(agentType, agent)`
- Enable/disable: `AgentExecutor.setAgentEnabled(agentType, enabled)`

Reputation-based switching (admin initiated, off swap-path):

- Configure: `setReputationSwitchConfig(...)` + `setReputationSwitchClients(...)`
- Switch if below threshold: `checkAndSwitchAgentIfBelowThreshold(agentType)`

## Deployment

Deployment scripts live in `script/`. For Sepolia deployment notes see:

- `ETH_SEPOLIA_DEPLOYMENT.md`
- `ARCHITECTURE.md`

## Notes / Assumptions

- Oracle pricing in E2E uses the Chainlink ETH/USD feed as a proxy for WETH/DAI (assuming DAI ~= USD). For production, configure pair-specific feeds or a safer composite oracle.
- This repo is not an audit. Use at your own risk until formally reviewed.

