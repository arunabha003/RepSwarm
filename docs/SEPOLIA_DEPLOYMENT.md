# Sepolia Deployment Guide

> Deploy SwarmRep contracts to Ethereum Sepolia (no mocks).

---

## Integrations

| Protocol | Sepolia Address |
|----------|----------------|
| Uniswap v4 PoolManager | `0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A` |
| WETH (Aave-market) | `0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c` |
| DAI (Aave-market) | `0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357` |
| Chainlink ETH/USD | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |
| Aave v3 Pool | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` |

> DAI is 18 decimals. USDC (6 decimals) is not supported without decimal-normalization changes.

---

## 1) Prerequisites

- Foundry installed (`forge`, `cast`)
- Sepolia RPC URL + funded deployer private key
- DAI balance in deployer wallet (acquire from faucet or transfer)

## 2) Configure Environment

```bash
export SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/<YOUR_KEY>"
export PRIVATE_KEY="<YOUR_DEPLOYER_PRIVATE_KEY>"

export POOL_MANAGER=0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A
export TREASURY=<YOUR_TREASURY_ADDRESS>
export WETH_TOKEN=0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
export STABLE_TOKEN=0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357
export ORACLE_FEED=0x694AA1769357215DE4FAC081bf1f309aDC325306
export AAVE_POOL=0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951

export BOOTSTRAP_POOLS=false
export REGISTER_ERC8004_AGENTS=true
export ENABLE_ONCHAIN_SCORING=true

export BOOTSTRAP_WRAP_WETH_AMOUNT=5000000000000000000       # 5 WETH
export BOOTSTRAP_STABLE_AMOUNT=10000000000000000000000      # 10,000 DAI
export HOOK_LIQUIDITY_DELTA=100000000000000000000           # 100 WETH
export REPAY_LIQUIDITY_DELTA=300000000000000000000          # 300 WETH
```

## 3) Deploy

Dry run:
```bash
forge script script/DeploySwarmProtocol.s.sol:DeploySwarmProtocol \
  --rpc-url $SEPOLIA_RPC_URL -vvv
```

Broadcast:
```bash
forge script script/DeploySwarmProtocol.s.sol:DeploySwarmProtocol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
```

## 4) Pools

The deployment creates two pools:

| Pool | Fee | Tick Spacing | Hooks |
|------|-----|-------------|-------|
| Hook pool (user swaps) | `8388608` (dynamic fee flag) | `60` | SwarmHook |
| Repay pool (backrun leg) | `3000` | `60` | None |

`FlashLoanBackrunner` is configured so hook-pool backruns repay through the repay pool.

## 5) Verify

```bash
cast call $FLASH_BACKRUNNER "repayPoolKeySet(bytes32)(bool)" $HOOK_POOL_ID \
  --rpc-url $SEPOLIA_RPC_URL
# Should return: true
```

## 6) Frontend Wiring

Copy printed addresses into `frontend/.env`:

```
VITE_READ_RPC_URL=<SEPOLIA_RPC_URL>
VITE_COORDINATOR=<address>
VITE_AGENT_EXECUTOR=<address>
VITE_LP_ACCUMULATOR=<address>
VITE_FLASH_BACKRUNNER=<address>
VITE_FLASH_BACKRUN_EXECUTOR_AGENT=<address>
VITE_SIMPLE_ROUTE_AGENT=<address>
VITE_SWARM_AGENT_REGISTRY=<address>
VITE_ORACLE_REGISTRY=<address>
VITE_POOL_MANAGER=0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A
VITE_POOL_CURRENCY_IN=0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357
VITE_POOL_CURRENCY_OUT=0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
VITE_POOL_FEE=8388608
VITE_POOL_TICK_SPACING=60
VITE_POOL_HOOKS=<SwarmHook address>
```

---

## Latest Deployment

Deployed on Sepolia (`chainId=11155111`):

| Contract | Address | ERC-8004 ID |
|----------|---------|-------------|
| Deployer / Treasury | [`0x28ea4eF61ac4cca3ed6a64dBb5b2D4be1aDC9814`](https://sepolia.etherscan.io/address/0x28ea4eF61ac4cca3ed6a64dBb5b2D4be1aDC9814) | — |
| SwarmHook | [`0x653557bE812E70CD5B9Abc0f4Ee8f5f4604e00cc`](https://sepolia.etherscan.io/address/0x653557bE812E70CD5B9Abc0f4Ee8f5f4604e00cc) | — |
| SwarmCoordinator | [`0x5be7B30051264fECf6a248551bd408b98eCfd5d2`](https://sepolia.etherscan.io/address/0x5be7B30051264fECf6a248551bd408b98eCfd5d2) | — |
| AgentExecutor | [`0xAC8B64ee8DF2dcdcCbF471B9E2a4a281d14b03FF`](https://sepolia.etherscan.io/address/0xAC8B64ee8DF2dcdcCbF471B9E2a4a281d14b03FF) | — |
| LPFeeAccumulator | [`0xe7D6cDe8f3Af7088D1999F1969F877ebe0d78517`](https://sepolia.etherscan.io/address/0xe7D6cDe8f3Af7088D1999F1969F877ebe0d78517) | — |
| OracleRegistry | [`0x42b598ff76b62A0fd273560F691896102c5a3A4A`](https://sepolia.etherscan.io/address/0x42b598ff76b62A0fd273560F691896102c5a3A4A) | — |
| FlashLoanBackrunner | [`0xAf26D906b2AE22276D8d07183aEc66609035F196`](https://sepolia.etherscan.io/address/0xAf26D906b2AE22276D8d07183aEc66609035F196) | — |
| FlashBackrunExecutorAgent | [`0xD6D9473EA9f155F25f9D15CE896171075961A2a4`](https://sepolia.etherscan.io/address/0xD6D9473EA9f155F25f9D15CE896171075961A2a4) | — |
| SimpleRouteAgent | [`0xDf1cb317Fff7CC63100682e9E3ea0eAce8D514d4`](https://sepolia.etherscan.io/address/0xDf1cb317Fff7CC63100682e9E3ea0eAce8D514d4) | `983` |
| SwarmAgentRegistry | [`0x048b0819f3942e1B548579004a486b6029217d13`](https://sepolia.etherscan.io/address/0x048b0819f3942e1B548579004a486b6029217d13) | — |
| ArbitrageAgent | [`0xFA1591069f7f1e48e8758179014f19F65fF44b26`](https://sepolia.etherscan.io/address/0xFA1591069f7f1e48e8758179014f19F65fF44b26) | `980` |
| DynamicFeeAgent | [`0x6Be9E7Db2335fe26fB0741D9E1fC8c581FCBfBDd`](https://sepolia.etherscan.io/address/0x6Be9E7Db2335fe26fB0741D9E1fC8c581FCBfBDd) | `981` |
| BackrunAgent | [`0xe2B466898D45f6Ae73Ca20b5e85eA584d0589216`](https://sepolia.etherscan.io/address/0xe2B466898D45f6Ae73Ca20b5e85eA584d0589216) | `982` |

