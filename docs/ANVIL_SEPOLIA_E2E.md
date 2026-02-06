# Local Sepolia-Fork E2E (Anvil + Frontend + Keeper)

This guide runs a full end-to-end demo locally using:

- Anvil forking Sepolia (`chainId=31337`)
- Swarm contracts deployed into that local chain
- The React frontend (`frontend/`)
- Optional event-driven keeper (`keeper/`) for automatic backrun execution

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

## 3) Deploy Swarm + Create Pools + Add Liquidity

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
SEED_AAVE_LIQUIDITY=true \
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

If you already deployed without seeding, you can run:

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
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
- Tab `Admin`: register a route agent (you can use your own address + any non-zero agentId for local demo).
- Tab `Intent Desk`: load the intentId, submit a proposal, then execute the intent as requester.
- Tab `LP Donations`: compute `poolId` (helper) and call `Donate To LPs` once there are accumulated fees/profits.

## 6) Optional: Event-Driven Keeper (Automatic Backruns)

The keeper watches for backrun events and calls the backrunner automatically (flashloan path).

```bash
cd keeper
npm install
cp .env.example .env
```

Set:
- `SEPOLIA_RPC_URL=http://127.0.0.1:8545`
- `FLASH_BACKRUNNER_ADDRESS=<FlashLoanBackrunner from deploy summary>`
- `KEEPER_PRIVATE_KEY=<a funded anvil private key>`

Then run:

```bash
npm run start
```

Important:
- The backrunner owner must authorize your keeper EOA:
- `FlashLoanBackrunner.setKeeperAuthorization(keeper,true)`
- The deploy script already authorizes the deployer as keeper; if you use a different key, authorize it.
