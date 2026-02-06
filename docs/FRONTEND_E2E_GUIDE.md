# Frontend E2E Guide (Local Sepolia Fork)

This guide is the practical, step-by-step way to test the whole protocol **from the frontend** against your local Anvil (forking Sepolia).

Prereq: you already have Anvil running and you deployed contracts using `script/DeployAnvilSepoliaFork.s.sol`.

## 1) Start Anvil (Sepolia Fork)

```bash
anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo \
  --chain-id 31337 \
  --auto-impersonate
```

## 2) Fund DAI For Liquidity + Deploy

The deploy script creates pools + adds liquidity. You must fund DAI on the fork first:

```bash
python3 tools/anvil_set_erc20_balance.py \
  --rpc http://127.0.0.1:8545 \
  --token 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357 \
  --account 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --amount 5000000000000000000000000
```

Deploy:

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
SEED_AAVE_LIQUIDITY=true \
REGISTER_ERC8004_HOOK_AGENTS=true \
forge script script/DeployAnvilSepoliaFork.s.sol:DeployAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv
```

From the deploy output, copy the `.env` values.

## 3) Configure + Run Frontend

```bash
cd frontend
cp .env.example .env
pnpm install
pnpm dev
```

Fill `frontend/.env` with addresses printed by the deploy script:

- `VITE_READ_RPC_URL=http://127.0.0.1:8545`
- `VITE_COORDINATOR=...`
- `VITE_AGENT_EXECUTOR=...`
- `VITE_LP_ACCUMULATOR=...`
- `VITE_FLASH_BACKRUNNER=...`
- `VITE_SWARM_AGENT_REGISTRY=...`
- `VITE_ORACLE_REGISTRY=...`
- `VITE_POOL_MANAGER=0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A`
- `VITE_POOL_CURRENCY_IN=<DAI>`
- `VITE_POOL_CURRENCY_OUT=<WETH>`
- `VITE_POOL_FEE=8388608`
- `VITE_POOL_TICK_SPACING=60`
- `VITE_POOL_HOOKS=<SwarmHook>`

## 4) MetaMask Setup

1. Add network:
- RPC: `http://127.0.0.1:8545`
- Chain ID: `31337`

2. Import the deployer key (admin wallet for local testing):
- `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## 5) Test Flows From The UI

Open the UI and click `Connect Wallet`.

### 5.1 Dashboard (Visibility)

Click `Refresh Dashboard`.

You should see:
- Oracle price vs pool spot price
- Diff in bps
- Wallet balances (ETH + the 2 pool tokens)
- Hook agent status (addresses + ERC-8004 id if linked)

If oracle/pool values are empty:
- verify `VITE_ORACLE_REGISTRY` and `VITE_POOL_MANAGER` are set correctly
- verify pool parameters in `.env` match the deployed pool

### 5.2 Create an Intent (User Swap Request)

Tab `Quick Intent`:

1. Click `Refresh Balance/Allowance`
2. Click `Approve In Token` (first time only)
3. Set `Amount In` (use decimals, e.g. `1000.0`)
4. Click `Create Intent`

Copy the `intentId` from the toast.

### 5.3 Propose + Execute (Complete the Swap)

Tab `Admin` (one-time):
- Set `Enforce Identity=false`, `Enforce Reputation=false`, click `Set Enforcement`
- Register your wallet as a route agent (so you can propose in this demo):
  - `Register Route Agent` -> `Agent Address=<your wallet>`, `ERC-8004 Agent ID=1`, `Active=true`

Tab `Intent Desk`:
1. Paste `Intent ID`, click `Load`
2. Under `Submit Proposal`:
- `Candidate ID=0`
- `Score=0`
- `Data=0x`
3. Click `Submit Proposal`
4. Click `Execute (Requester)`

Success = intent becomes `Executed=true` and your balances change.

### 5.4 LP Donation (Profit Redistribution)

Tab `LP Donations`:
1. Paste `poolId` from deploy output (hook pool)
2. Click `Load`
3. If `Can Donate=true` and amounts are non-zero, click `Donate To LPs`

### 5.5 Backrun (Capital Mode)

Tab `Backrun`:
1. Paste the hook `poolId`
2. Click `Load`
3. If `Backrun Amount=0`, do a bigger swap (repeat intent with higher `Amount In`)
4. Click `Execute (Capital)`

### 5.6 Backrun (Flashloan Mode)

Flashloan mode requires Aave liquidity on the fork.

If you deployed with `SEED_AAVE_LIQUIDITY=true`, it should work.

Tab `Backrun` -> click `Execute (Flashloan)`.

### 5.7 Automatic Backrun (Event-Driven Keeper)

Run the keeper:

```bash
cd keeper
npm install
cp .env.example .env
npm run start
```

Set in `keeper/.env`:
- `SEPOLIA_RPC_URL=http://127.0.0.1:8545`
- `FLASH_BACKRUNNER_ADDRESS=<deployed FlashLoanBackrunner>`
- `KEEPER_PRIVATE_KEY=<anvil key>`

Now perform a big intent swap again. The keeper should auto-execute the backrun when it sees the event.

### 5.8 Hook Agent Switching (Admin)

Tab `Admin`:
- `AgentExecutor (Hook Agents)` lets you:
  - switch a hook agent by type (`Register/Switch Agent`)
  - set a backup agent (`Set Backup`)
  - force switch to backup (`Switch To Backup Now`)

### 5.9 Reputation-Based Switching (Threshold)

To make threshold switching meaningful, you need reputation entries for hook agents.

Run the scoring keeper:

```bash
cd keeper
npm run score
```

In `keeper/.env`, set:
- `AGENT_EXECUTOR_ADDRESS=<AgentExecutor>`
- `ERC8004_REPUTATION_REGISTRY=0x8004B663056A597Dffe9eCcC1965A193B7388713`

In the frontend `Admin` tab:
1. Configure reputation switch config (registry + tags + min threshold + enabled)
2. Set switch clients to include the scorer keeper EOA address
3. Click `Check & Switch (Reputation)` for the agent type

## Troubleshooting

- If `Submit Proposal` reverts:
  - you didn’t register a route agent in `Coordinator.registerAgent(...)` (Admin tab)
- If `Execute (Flashloan)` reverts:
  - seed Aave liquidity (deploy with `SEED_AAVE_LIQUIDITY=true`)
- If dashboard is blank:
  - ensure `VITE_POOL_*` params are correct for the deployed pool and `VITE_POOL_MANAGER` is set

