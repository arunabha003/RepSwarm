# Sepolia Deployment Guide (No Mocks)

This guide is for deploying the **real protocol contracts** to **Ethereum Sepolia**.
It uses:

- Sepolia Uniswap v4 `PoolManager`
- Sepolia Chainlink feed
- Sepolia Aave v3 pool
- Sepolia ERC-8004 registries

No mocked contracts are used in `src/` deployment.

## 1) Prerequisites

- `forge` installed
- Sepolia RPC URL
- Deployer private key with Sepolia ETH
- Enough token balances for initial liquidity

Recommended pair for this repo right now:

- WETH: `0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c`
- DAI: `0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357`

Important:

- Current protocol math/oracle bootstrap assumes **18-decimal quote token**.
- Use **DAI** for production/demo flow here.
- USDC (`6` decimals) is not recommended without decimal-normalization changes.

## 2) Funding: ETH -> WETH + DAI

You need both sides for liquidity.

- WETH side: script can wrap ETH into WETH automatically using `BOOTSTRAP_WRAP_WETH_AMOUNT`.
- DAI side: acquire Sepolia DAI beforehand (faucet or swap flow that mints/transfers this exact DAI token address).

Check balances before deploy:

```bash
cast call 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c "balanceOf(address)(uint256)" <YOUR_WALLET> --rpc-url $SEPOLIA_RPC_URL
cast call 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357 "balanceOf(address)(uint256)" <YOUR_WALLET> --rpc-url $SEPOLIA_RPC_URL
```

## 3) Configure Environment

```bash
export SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/APIKEY"
export PRIVATE_KEY=""

export POOL_MANAGER=0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A
export TREASURY=0x28ea4eF61ac4cca3ed6a64dBb5b2D4be1aDC9814

export WETH_TOKEN=0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
export STABLE_TOKEN=0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357
export ORACLE_FEED=0x694AA1769357215DE4FAC081bf1f309aDC325306
export AAVE_POOL=0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951

export BOOTSTRAP_POOLS=false
export REGISTER_ERC8004_AGENTS=true
export ENABLE_ONCHAIN_SCORING=true

export SIMPLE_ROUTE_AGENT_ID=1
export FLASH_EXECUTOR_MAX_FLASHLOAN_AMOUNT=50000000000000000   # 0.05 WETH
export FLASH_EXECUTOR_MIN_PROFIT=0

export BOOTSTRAP_WRAP_WETH_AMOUNT=5000000000000000000          # 5 WETH
export BOOTSTRAP_STABLE_AMOUNT=10000000000000000000000         # 10,000 DAI
export HOOK_LIQUIDITY_DELTA=100000000000000000000              # 100e18
export REPAY_LIQUIDITY_DELTA=300000000000000000000             # 300e18
```

## 4) Dry Run Then Broadcast

Dry run first:

```bash
forge script script/DeploySwarmProtocol.s.sol:DeploySwarmProtocol \
  --rpc-url $SEPOLIA_RPC_URL -vvv
```

Broadcast:

```bash
forge script script/DeploySwarmProtocol.s.sol:DeploySwarmProtocol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast -vvv
```

## 5) Correct Pools (Critical)

Deployment creates/uses **two pools**:

1. Hook pool (user intent swaps):
- `fee = 8388608` (dynamic fee flag)
- `tickSpacing = 60`
- `hooks = <deployed SwarmHook>`

2. Repay pool (backrun repayment leg):
- `fee = 3000`
- `tickSpacing = 60`
- `hooks = 0x0000000000000000000000000000000000000000`

`FlashLoanBackrunner` is configured so hook-pool backruns repay through this repay pool.

The script prints:

- `Hook Pool ID`
- `Repay Pool ID`
- all deployed contract addresses

Use those exact values in frontend `.env`.

## 6) Post-Deploy Verification

From script output, set:

- `HOOK_POOL_ID=<printed bytes32>`
- `FLASH_BACKRUNNER=<printed address>`

Verify repay mapping exists:

```bash
cast call $FLASH_BACKRUNNER "repayPoolKeySet(bytes32)(bool)" $HOOK_POOL_ID --rpc-url $SEPOLIA_RPC_URL
```

Should return `true`.

## 7) Frontend Wiring

Use printed addresses in `frontend/.env`:

- `VITE_COORDINATOR`
- `VITE_AGENT_EXECUTOR`
- `VITE_LP_ACCUMULATOR`
- `VITE_FLASH_BACKRUNNER`
- `VITE_FLASH_BACKRUN_EXECUTOR_AGENT`
- `VITE_SIMPLE_ROUTE_AGENT`
- `VITE_SWARM_AGENT_REGISTRY`
- `VITE_ORACLE_REGISTRY`
- `VITE_POOL_MANAGER`
- `VITE_POOL_CURRENCY_IN` = DAI
- `VITE_POOL_CURRENCY_OUT` = WETH
- `VITE_POOL_FEE` = `8388608`
- `VITE_POOL_TICK_SPACING` = `60`
- `VITE_POOL_HOOKS` = deployed `SwarmHook`

## 8) Operational Notes

- Backrun detection is automatic in hook flow.
- Backrun execution is transaction-triggered (permissionless via `FlashBackrunExecutorAgent`).
- Route proposal/execution can be one-click from frontend using `SimpleRouteAgent`.
- On-chain scoring is enabled via `AgentExecutor.setOnchainScoringConfig`, so no separate scoring server is required.

