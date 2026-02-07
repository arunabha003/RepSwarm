# Local Sepolia-Fork E2E (Anvil + Frontend)

This guide runs a full end-to-end demo locally using:

- Anvil forking Sepolia (`chainId=31337`)
- SwarmRep contracts deployed into that local chain
- The React frontend (`frontend/`)
- Optional external automation bot for automatic backrun execution (not bundled in this repo)

## 1) Start Anvil (Sepolia Fork)

```bash
anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo \
  --chain-id 31337 \
  --auto-impersonate
```

## 2) Fund Your Deployer With DAI (Local Fork Only)

The deploy script adds liquidity to a WETH/DAI pool. WETH is obtained by depositing ETH, but DAI must exist in the deployer account.

Use the helper that searches for the ERC20 `balances` mapping slot and sets it via `anvil_setStorageAt`:

```bash
python3 tools/anvil_set_erc20_balance.py \
  --rpc http://127.0.0.1:8545 \
  --token 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357 \
  --account 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --amount 5000000000000000000000000
```

Notes:
- The default Anvil account `0xf39f...` corresponds to the default private key below.
- Amount is raw integer (DAI on Sepolia is 18 decimals).

## 3) Deploy SwarmRep + Create Pools + Add Liquidity

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
SEED_AAVE_LIQUIDITY=true \
SEED_AAVE_DAI=false \
forge script script/DeployAnvilSepoliaFork.s.sol:DeployAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv
```

The script prints a “LOCAL DEPLOY SUMMARY” including:
- `SwarmCoordinator`
- `AgentExecutor`
- `LPFeeAccumulator`
- `FlashLoanBackrunner`
- Hook pool params (tokens/fee/tickSpacing/hook address)

Notes:
- `SEED_AAVE_LIQUIDITY=true` is recommended for local E2E. It tries (best-effort) to `supply()` WETH + DAI into Aave so flashloans work deterministically on the fork.
- Some Aave Sepolia reserves (notably stables) can be disabled/frozen at times. By default we only seed WETH now.
- To also attempt seeding DAI: set `SEED_AAVE_DAI=true` (may revert depending on Aave config).

If you already deployed without seeding, you can run:

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
AAVE_WETH_SUPPLY=10000000000000000000 \
SEED_AAVE_DAI=false \
forge script script/SeedAaveLiquidityAnvilSepoliaFork.s.sol:SeedAaveLiquidityAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv
```

If you want to also seed DAI for broader flashloan tests:

```bash
python3 tools/anvil_set_erc20_balance.py \
  --rpc http://127.0.0.1:8545 \
  --token 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357 \
  --account 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --amount 500000000000000000000000

PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
AAVE_WETH_SUPPLY=10000000000000000000 \
SEED_AAVE_DAI=true \
AAVE_DAI_SUPPLY=100000000000000000000000 \
forge script script/SeedAaveLiquidityAnvilSepoliaFork.s.sol:SeedAaveLiquidityAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv
```

## 4) Configure Frontend

```bash
cd frontend
cp .env.example .env
```

Fill `.env` with the addresses printed by the deploy script. At minimum:

- `VITE_READ_RPC_URL=http://127.0.0.1:8545`
- `VITE_COORDINATOR=...`
- `VITE_AGENT_EXECUTOR=...`
- `VITE_LP_ACCUMULATOR=...`
- `VITE_FLASH_BACKRUNNER=...`
- `VITE_SWARM_AGENT_REGISTRY=...` (ERC-8004 helper; used for hook-agent registration)
- `VITE_ORACLE_REGISTRY=...`
- `VITE_POOL_MANAGER=0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A`
- `VITE_POOL_CURRENCY_IN=...` (DAI)
- `VITE_POOL_CURRENCY_OUT=...` (WETH)
- `VITE_POOL_FEE=...` (likely `8388608`)
- `VITE_POOL_TICK_SPACING=60`
- `VITE_POOL_HOOKS=...` (SwarmHook)

Then run:

```bash
pnpm install
pnpm dev
```

Open the printed URL (default `http://localhost:3000`).

## 5) End-to-End Protocol Test (UI)

1. Connect MetaMask to the Anvil network:
- RPC: `http://127.0.0.1:8545`
- ChainId: `31337`

2. Import the deployer account (so you are coordinator/executor owner):
- Private key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

3. In the frontend:
- Tab `Quick Intent`: click `Approve In Token`, then `Create Intent`.
- Tab `Intent Desk`: load the `intentId`, then click `Auto Propose + Execute via Router`.
- Tab `LP Donations`: compute `poolId` (helper) and call `Donate To LPs` once there are accumulated fees/profits.

## 6) Optional: External Automation Bot (Automatic Backruns)

No local keeper service is required. If you want automatic execution, run any external bot that watches
`BackrunOpportunityDetected` and submits:

```bash
cast send <FLASH_BACKRUN_EXECUTOR_AGENT_ADDRESS> \
  "execute(bytes32)(address,uint256)" <HOOK_POOL_ID> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANY_FUNDED_ANVIL_KEY>
```

Important:
- The deploy script already authorizes `FlashBackrunExecutorAgent` as keeper/forwarder.
- If your automation calls backrunner methods directly, authorize that caller with:
  - `FlashLoanBackrunner.setKeeperAuthorization(caller,true)`
  - `FlashLoanBackrunner.setForwarderAuthorization(caller,true)`
