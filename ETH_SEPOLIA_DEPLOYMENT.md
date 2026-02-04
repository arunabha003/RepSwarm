# ETH Sepolia Fork Deployment Guide

Complete step-by-step guide for deploying the Multi-Agent Trade Router Swarm on an ETH Sepolia fork using Anvil.

## Prerequisites

1. **Foundry** - Install via: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. **Node.js** (v18+) - For frontend
3. **MetaMask** - Browser wallet extension
4. **Alchemy API Key** (optional) - For forking Sepolia

---

## Quick Start (Copy-Paste Commands)

Run these commands in order from the project root directory:

```bash
# 1. Start Anvil Fork
anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo --chain-id 31337 --auto-impersonate &

# Wait 10 seconds for Anvil to start
sleep 10

# 2. Deploy All Contracts
forge script script/DeployEthSepoliaComplete.s.sol:DeployEthSepoliaComplete --rpc-url http://127.0.0.1:8545 --broadcast

# 3. Set USDC Balance (1M USDC with 18 decimals)
SLOT=$(cast keccak256 $(cast abi-encode "f(address,uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0))
cast rpc anvil_setStorageAt 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 $SLOT 0x00000000000000000000000000000000000000000000d3c21bcecceda1000000 --rpc-url http://127.0.0.1:8545

# 4. Approve USDC for Liquidity Router
cast send 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 "approve(address,uint256)" 0x1A9a6FABC4412dd3f829a1be122Ff0A081a2412b 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 5. Add Liquidity (200 ETH worth - supports up to 100 ETH swaps)
cast send 0x1A9a6FABC4412dd3f829a1be122Ff0A081a2412b "modifyLiquidity((address,address,uint24,int24,address),(int24,int24,int256,bytes32),bytes)" "(0x0000000000000000000000000000000000000000,0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8,500,10,0x115e0e9E6A7B475E883e1f9723dc4C082f0640Cc)" "(72240,84240,1000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000)" "0x" --value 200ether --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 6. Test Swap
forge script script/TestSwapWithHook.s.sol:TestSwapWithHook --rpc-url http://127.0.0.1:8545 --broadcast

# 7. Start Frontend
cd frontend && npm run dev
```

---

## Detailed Step-by-Step Guide

### Step 1: Start Anvil Fork

Open a terminal and run:

```bash
anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo \
  --chain-id 31337 \
  --auto-impersonate
```

**Expected Output:**
```
                             _   _
                            (_) | |
      __ _   _ __   __   __  _  | |
     / _` | | '_ \  \ \ / / | | | |
    | (_| | | | | |  \ V /  | | | |
     \__,_| |_| |_|   \_/   |_| |_|

    0.2.0 (...)

Available Accounts
==================
(0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
...
```

**Key Points:**
- Anvil runs on `http://127.0.0.1:8545`
- Chain ID: `31337`
- Default account has 10,000 ETH
- Keep this terminal open!

---

### Step 2: Deploy All Contracts

In a **new terminal**, run:

```bash
cd /path/to/HackMoney-ETHGlobal

forge script script/DeployEthSepoliaComplete.s.sol:DeployEthSepoliaComplete \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

**Expected Output:**
```
=== Step 1: Deploy PoolManager ===
...
===========================================
  DEPLOYMENT COMPLETE!
===========================================

Addresses:
  Hook: 0x115e0e9E6A7B475E883e1f9723dc4C082f0640Cc
  Coordinator: 0x79cA020FeE712048cAA49De800B4606cC516A331
  OracleRegistry: 0x7A1efaf375798B6B0df2BE94CF8A13F68c9E74eE
  LPFeeAccumulator: 0xc1ec8B65bb137602963f88eb063fa7236f4744f2

Pool 1 ID: 0x95b11fca6d60f13963a5b2cb6cb351526a344d28bb9a6ae169ca9bdd6a5b48f5
Pool 2 ID: 0xc73ebad18f9cb0c5c21cf3d4270dfded17b10412a15a8b9bb8e4cc9b9b6e2117

ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.
```

---

### Step 3: Mint USDC Tokens

The deployer account needs USDC for liquidity. Run:

```bash
# Calculate storage slot for balance mapping
SLOT=$(cast keccak256 $(cast abi-encode "f(address,uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0))

# Set balance to 1 million USDC (18 decimals)
cast rpc anvil_setStorageAt \
  0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 \
  $SLOT \
  0x00000000000000000000000000000000000000000000d3c21bcecceda1000000 \
  --rpc-url http://127.0.0.1:8545
```

**Verify Balance:**
```bash
cast call 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 \
  "balanceOf(address)(uint256)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --rpc-url http://127.0.0.1:8545
# Expected: 1000000000000000000000000 [1e24] = 1,000,000 USDC
```

---

### Step 4: Approve USDC for Liquidity

The PoolModifyLiquidityTest contract needs approval to spend USDC:

```bash
cast send 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 \
  "approve(address,uint256)" \
  0x1A9a6FABC4412dd3f829a1be122Ff0A081a2412b \
  0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

**Expected:** `status: 1 (success)`

---

### Step 5: Add Liquidity

Add liquidity to the ETH/USDC pool:

```bash
cast send 0x1A9a6FABC4412dd3f829a1be122Ff0A081a2412b \
  "modifyLiquidity((address,address,uint24,int24,address),(int24,int24,int256,bytes32),bytes)" \
  "(0x0000000000000000000000000000000000000000,0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8,500,10,0x115e0e9E6A7B475E883e1f9723dc4C082f0640Cc)" \
  "(72240,84240,1000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000)" \
  "0x" \
  --value 200ether \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

**Parameters Explained:**
- `poolKey`: (currency0=ETH, currency1=USDC, fee=500bps, tickSpacing=10, hook=MevRouterHook)
- `modifyParams`: (tickLower=72240, tickUpper=84240, liquidityDelta=1e18, salt=0)
- `hookData`: empty bytes
- `value`: 200 ETH (sent as liquidity)

**Expected:** `status: 1 (success)`

---

### Step 6: Test Swap

Verify swaps work through the MEV hook:

```bash
forge script script/TestSwapWithHook.s.sol:TestSwapWithHook \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

**Expected:** Script completes without errors.

---

### Step 7: Start Frontend

```bash
cd frontend
npm install  # First time only
npm run dev
```

Open http://localhost:3000 in your browser.

---

## MetaMask Configuration

### Add Anvil Network

1. Open MetaMask > Settings > Networks > Add Network
2. Fill in:
   - **Network Name:** Anvil (ETH Sepolia Fork)
   - **RPC URL:** http://127.0.0.1:8545
   - **Chain ID:** 31337
   - **Currency Symbol:** ETH
3. Click Save

### Import Test Account

1. MetaMask > Import Account
2. Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
3. This account has ~9,800 ETH and ~1,000,000 USDC

### Add USDC Token

1. MetaMask > Import Tokens
2. Token Contract Address: `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8`
3. Token Symbol: USDC
4. Token Decimals: 18

---

## Deployed Contract Addresses

| Contract | Address |
|----------|---------|
| PoolManager | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| PoolSwapTest | `0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe` |
| PoolModifyLiquidityTest | `0xFe2a7099f7810C486505016482beE86665244A2C` |
| MevRouterHookV2 | `0x115e0e9E6A7B475E883e1f9723dc4C082f0640Cc` |
| SwarmCoordinator | `0x79cA020FeE712048cAA49De800B4606cC516A331` |
| LPFeeAccumulator | `0xc1ec8B65bb137602963f88eb063fa7236f4744f2` |
| OracleRegistry | `0x7A1efaf375798B6B0df2BE94CF8A13F68c9E74eE` |
| AgentRegistry | `0x26c13B3900bf570d9830678D2e22C439778627EA` |
| FeeOptimizerAgent | `0xae6D0f561c4907D211Ed69cBCc2fd0A0e03A2AaE` |
| SlippagePredictorAgent | `0x3440e175a85aa6CD595e9E8b05c515ac546FB91c` |
| MevHunterAgent | `0x95Ce3FE31BB597AD6aAc2639a03ca8f24741b508` |
| FlashLoanBackrunner | `0xd91d0433c10291448a8DC00C3ba14Af8b94c7656` |

### Token Addresses

| Token | Address | Decimals |
|-------|---------|----------|
| ETH (Native) | `0x0000000000000000000000000000000000000000` | 18 |
| USDC (Aave Testnet) | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` | 18 |

### Pool IDs

| Pool | ID |
|------|-----|
| ETH/USDC Pool 1 (fee=500, tick=10) | `0x95b11fca6d60f13963a5b2cb6cb351526a344d28bb9a6ae169ca9bdd6a5b48f5` |
| ETH/USDC Pool 2 (fee=500, tick=60) | `0xc73ebad18f9cb0c5c21cf3d4270dfded17b10412a15a8b9bb8e4cc9b9b6e2117` |

### Chainlink Price Feeds (Sepolia)

| Feed | Address |
|------|---------|
| ETH/USD | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |
| USDC/USD | `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E` |
| LINK/USD | `0xc59E3633BAAC79493d908e63626716e204A45EdF` |

---

## Troubleshooting

### "Requested resource not available" Error
- **Cause:** Anvil was restarted and contracts are no longer deployed
- **Fix:** Re-run deployment from Step 2

### "InvalidSqrtPriceLimit" Error  
- **Cause:** Pool drained from previous swaps or no liquidity
- **Fix:** Restart Anvil fresh and re-deploy everything

### "ERC20: transfer amount exceeds balance"
- **Cause:** USDC balance not set
- **Fix:** Run Step 3 to mint USDC

### "Transaction reverted" on Swap
- **Cause:** USDC not approved for PoolSwapTest
- **Fix:** 
```bash
cast send 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 \
  "approve(address,uint256)" \
  0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe \
  0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Frontend Shows "Loading..." 
- **Cause:** Anvil not running or wrong RPC URL
- **Fix:** Ensure Anvil is running on `http://127.0.0.1:8545`

### MetaMask "Could not fetch chain ID"
- **Cause:** Anvil not running or network configured incorrectly
- **Fix:** Check Anvil is running and RPC URL is correct

---

## How the System Works

### Swap Flow

1. **User initiates swap** → Frontend calls PoolSwapTest.swap()
2. **PoolManager routes swap** → Pool with MEV hook receives the swap
3. **MevRouterHookV2.beforeSwap()** → Detects price deviation via Chainlink oracle
4. **Swap executes** → AMM performs the token exchange
5. **MevRouterHookV2.afterSwap()** → Captures MEV if profitable deviation detected
6. **MEV redistributed** → 80% to LPs, 10% treasury, 10% keepers

### Agent Scoring

Each swap is analyzed by 3 agents:
- **FeeOptimizerAgent**: Scores based on total LP fees
- **MevHunterAgent**: Scores based on oracle price deviation (MEV risk)
- **SlippagePredictorAgent**: Scores based on simulated slippage using SwapMath

---

## Verification Commands

Check if everything is working:

```bash
# Check Anvil is running
curl -s http://127.0.0.1:8545 -X POST -H "Content-Type: application/json" \
  --data '{"method":"eth_chainId","params":[],"id":1,"jsonrpc":"2.0"}'
# Expected: {"jsonrpc":"2.0","id":1,"result":"0x7a69"}

# Check ETH balance
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://127.0.0.1:8545

# Check USDC balance
cast call 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 \
  "balanceOf(address)(uint256)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --rpc-url http://127.0.0.1:8545

# Check PoolSwapTest is deployed
cast code 0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe --rpc-url http://127.0.0.1:8545 | head -c 100

# Get ETH price from Chainlink
cast call 0x694AA1769357215DE4FAC081bf1f309aDC325306 \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url http://127.0.0.1:8545
```

---

## Manual Swap Test

Execute a swap directly via cast:

```bash
# Swap 0.001 ETH for USDC
cast send 0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe \
  "swap((address,address,uint24,int24,address),(bool,int256,uint160),(bool,bool),bytes)" \
  "(0x0000000000000000000000000000000000000000,0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8,500,10,0x115e0e9E6A7B475E883e1f9723dc4C082f0640Cc)" \
  "(true,-1000000000000000,4295128740)" \
  "(false,false)" \
  "0x" \
  --value 0.002ether \
  --rpc-url http://127.0.0.1:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

---

## Summary

After completing all steps, you should have:

- ✅ Anvil running with ETH Sepolia fork
- ✅ All Swarm contracts deployed
- ✅ ETH/USDC pool with ~200 ETH liquidity
- ✅ 1M USDC tokens for the test account
- ✅ Frontend running at http://localhost:3000
- ✅ MetaMask configured to connect

**Test Account:**
- Address: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
- Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
- ETH Balance: ~9,800 ETH
- USDC Balance: ~1,000,000 USDC
