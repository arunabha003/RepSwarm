# Local E2E Guide (Anvil + Sepolia Fork)

> Deploy and test SwarmRep locally using Anvil forking Sepolia.

---

## Prerequisites

- Foundry (`forge`, `cast`, `anvil`)
- Node.js ≥ 18 + pnpm
- Python 3

---

## 1) Start Anvil

```bash
anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/<YOUR_KEY> \
  --chain-id 31337 --auto-impersonate
```

## 2) Fund DAI

The deploy script needs DAI in the deployer wallet. WETH is auto-wrapped from ETH.

```bash
python3 tools/anvil_set_erc20_balance.py \
  --rpc http://127.0.0.1:8545 \
  --token 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357 \
  --account 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --amount 5000000000000000000000000
```

## 3) Deploy

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
SEED_AAVE_LIQUIDITY=true \
SEED_AAVE_DAI=false \
forge script script/DeployAnvilSepoliaFork.s.sol:DeployAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 --broadcast -vvv
```

**Default bootstrap values:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BOOTSTRAP_WRAP_WETH_AMOUNT` | 1,000 WETH | ETH wrapped as WETH before adding liquidity |
| `BOOTSTRAP_STABLE_AMOUNT` | 5,000,000 DAI | Minimum stable balance required in deployer |
| `HOOK_LIQUIDITY_DELTA` | 100 WETH | Hooked pool depth (main swap path) |
| `REPAY_LIQUIDITY_DELTA` | 300 WETH | Repay pool depth (backrun round-trip path) |

**Deep liquidity deployment** (for larger swaps):

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
BOOTSTRAP_WRAP_WETH_AMOUNT=5000000000000000000000 \
BOOTSTRAP_STABLE_AMOUNT=20000000000000000000000000 \
HOOK_LIQUIDITY_DELTA=2000000000000000000000 \
REPAY_LIQUIDITY_DELTA=4000000000000000000000 \
SEED_AAVE_LIQUIDITY=true \
SEED_AAVE_DAI=false \
forge script script/DeployAnvilSepoliaFork.s.sol:DeployAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 --broadcast -vvv
```

The script prints a **LOCAL DEPLOY SUMMARY** with all contract addresses and pool parameters. Use these for the frontend `.env`.

## 4) Seed Aave (If Not Done During Deploy)

Skip if you deployed with `SEED_AAVE_LIQUIDITY=true`.

```bash
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
AAVE_WETH_SUPPLY=10000000000000000000 \
SEED_AAVE_DAI=false \
forge script script/SeedAaveLiquidityAnvilSepoliaFork.s.sol:SeedAaveLiquidityAnvilSepoliaFork \
  --rpc-url http://127.0.0.1:8545 --broadcast -vvv
```

## 5) Configure & Run Frontend

```bash
cd frontend
cp .env.example .env    # fill with addresses from deploy output
pnpm install && pnpm dev
```

Required `.env` variables (all printed by the deploy script):

```
VITE_READ_RPC_URL=http://127.0.0.1:8545
VITE_COORDINATOR=<address>
VITE_AGENT_EXECUTOR=<address>
VITE_LP_ACCUMULATOR=<address>
VITE_FLASH_BACKRUNNER=<address>
VITE_FLASH_BACKRUN_EXECUTOR_AGENT=<address>
VITE_SIMPLE_ROUTE_AGENT=<address>
VITE_SWARM_AGENT_REGISTRY=<address>
VITE_ORACLE_REGISTRY=<address>
VITE_POOL_MANAGER=0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A
VITE_POOL_CURRENCY_IN=<DAI address>
VITE_POOL_CURRENCY_OUT=<WETH address>
VITE_POOL_FEE=8388608
VITE_POOL_TICK_SPACING=60
VITE_POOL_HOOKS=<SwarmHook address>
```

## 6) Test the Flow

1. **MetaMask** — Add network: RPC `http://127.0.0.1:8545`, Chain ID `31337`
2. **Import deployer key**: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
3. **Quick Intent** → Approve Token → Set amount (e.g. `1000`) → Create Intent
4. **Intent Desk** → Paste intentId → Load → Auto Propose + Execute via Router
5. **Backrun** → Load (use hook poolId) → Execute (Executor Agent)
6. **LP Donations** → Load → Donate To LPs (when accumulated amounts are non-zero)

## 7) Backrun Without Frontend (Optional)

```bash
cast send <FLASH_BACKRUN_EXECUTOR_AGENT> \
  "execute(bytes32)(address,uint256)" <HOOK_POOL_ID> \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANY_FUNDED_ANVIL_KEY>
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Router proposal reverts | Ensure `SimpleRouteAgent` is registered in coordinator (deploy script does this) |
| Execute reverts | Ensure intent has a candidate path and `VITE_SIMPLE_ROUTE_AGENT` is set |
| Backrun says "not profitable" | Swap amount too small — use ≥ 20,000 DAI to create > 0.3% price divergence |
| Flashloan reverts | Aave liquidity not seeded — redeploy with `SEED_AAVE_LIQUIDITY=true` |
| Dashboard is blank | Verify `VITE_POOL_*` params match the deployed pool |

