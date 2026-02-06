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
SEED_AAVE_DAI=false \
REGISTER_ERC8004_HOOK_AGENTS=true \
ENABLE_ONCHAIN_SCORING=true \
forge script script/DeployAnvilSepoliaFork.s.sol:DeployAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast -vvv
```

From the deploy output, copy the `.env` values.
Also copy:
- `SimpleRouteAgent`
- `FlashBackrunExecutorAgent`

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
- `VITE_FLASH_BACKRUN_EXECUTOR_AGENT=...`
- `VITE_SIMPLE_ROUTE_AGENT=...`
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

1. Click `Refresh Balance`
2. Click `Approve Token` (first time only)
3. Set `Amount In` (use decimals, e.g. `1000.0`)
4. Click `Create Intent`

Copy the `intentId` from the toast.

### 5.3 Route Proposal Without Server (From UI)

Use `SimpleRouteAgent` from the frontend (no off-chain route-agent service and no `cast` needed):

1. Tab `Intent Desk` -> paste `Intent ID`, click `Load Intent`
2. Click `Auto Propose + Execute via Router`

Success = intent becomes `Executed=true` and your balances change.

### 5.4 LP Donation (Profit Redistribution)

Tab `LP Donations`:
1. Paste `poolId` from deploy output (hook pool)
2. Click `Load`
3. If `Can Donate=true` and amounts are non-zero, click `Donate To LPs`

### 5.5 Backrun (Detection vs Execution)

Tab `Backrun`:
1. Use the hook `poolId` (bytes32) from deploy output (`Hook Pool -> poolId`).  
   The frontend auto-fills this if your `VITE_POOL_*` values are correct.
2. Click `Load`
3. If `Backrun Amount=0`, do a bigger swap (repeat intent with higher `Amount In`)
4. Verify `Status=Available`

Important behavior:
- Opportunity detection is done automatically in swap flow by the hook/backrun agent.
- Execution is not self-triggered on-chain. A transaction must call one of the execute paths.

### 5.6 Backrun via Frontend (No keeper server)

Tab `Backrun`:
1. Click `Execute (Executor Agent)`
2. Wait for confirmation toast
3. Click `Load` again
4. Verify telemetry fields update:
   - `Last Executor Event` / `Executor Bounty` / `Executor Caller`
   - `Last Backrunner Event` / `Backrunner Profit` / `Backrunner Keeper`

This is the permissionless on-chain flow, no external keeper process required.

### 5.7 Backrun Flashloan Prereq

Flashloan mode requires Aave liquidity on the fork.

If you deployed with `SEED_AAVE_LIQUIDITY=true`, it should work.

### 5.8 Backrun Without Frontend (Optional cast path)

Use `FlashBackrunExecutorAgent` directly from CLI:

```bash
cast send <FLASH_BACKRUN_EXECUTOR_AGENT_ADDRESS> \
  "execute(bytes32)(address,uint256)" <HOOK_POOL_ID> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANY_FUNDED_ANVIL_KEY>
```

Any funded caller can trigger this transaction and receive the keeper bounty routed via the agent contract.

### 5.9 Hook Agent Switching (Admin)

Tab `Admin`:
- `AgentExecutor (Hook Agents)` lets you:
  - switch a hook agent by type (`Register/Switch Agent`)
  - set a backup agent (`Set Backup`)
  - force switch to backup (`Switch To Backup Now`)

### 5.10 Reputation Scoring (No scoring server required)

`AgentExecutor` can write ERC-8004 feedback directly when agents execute (configured by deploy script with `ENABLE_ONCHAIN_SCORING=true`).

After a few swaps:
1. Click `Refresh Dashboard`
2. In `Hook Agents`, verify `Rep` shows signed values and feedback count.
3. Use `Admin` tab to configure reputation threshold switching and call `Check & Switch (Reputation)`.

## Troubleshooting

- If router proposal step reverts:
  - ensure `SimpleRouteAgent` is registered in coordinator (deploy script does this by default)
- If `Auto Propose + Execute via Router` reverts:
  - ensure `VITE_SIMPLE_ROUTE_AGENT` is set and the intent has at least one candidate path (`candidateId=0` exists)
- If `FlashBackrunExecutorAgent.execute(poolId)` reverts:
  - there may be no pending opportunity, opportunity expired, flashloan path not profitable, or Aave fork liquidity not seeded
- If `Execute (Executor Agent)` button is disabled:
  - set `VITE_FLASH_BACKRUN_EXECUTOR_AGENT` in `frontend/.env`
- If dashboard is blank:
  - ensure `VITE_POOL_*` params are correct for the deployed pool and `VITE_POOL_MANAGER` is set
