# SwarmRep Protocol — Cast Test Commands

> Complete E2E testing reference using `cast` commands on an Anvil fork.
> Replace all example addresses below with values from your latest deploy summary.

---

## 0. Environment Variables

```bash
# ── Network ──
export RPC=http://127.0.0.1:8545
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# ── Tokens ──
export WETH=0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c   # currency0 (lower addr)
export DAI=0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357    # currency1

# ── Core Contracts ──
export COORDINATOR=0x71cEE012bA3B9642277f189c2C26488cAA28CF13
export AGENT_EXECUTOR=0xC7D02Ae80f0ECb64543176EDBDD1153d34dFA622
export LP_ACCUMULATOR=0xf5dC296F38B10cF65E2702a69E1d56d55d520e91
export FLASH_BACKRUNNER=0x9841806AC68865af1FDE1033e04cC4241D4f911b
export FLASH_EXECUTOR=0x16A69B4a700D09234E79D6F87B4E9af4AFDfAE8a
export ROUTE_AGENT=0x79cA020FeE712048cAA49De800B4606cC516A331
export REGISTRY=0x899c160f64e5bC78c29e50BC75309635aCeb3586
export ORACLE_REGISTRY=0xdc8832f7bc16bE8a97E6c7cB66f912B6922246B5
export POOL_MANAGER=0x8C4BcBE6b9eF47855f97e675296FA3f6fafa5F1A
export SWARM_HOOK=0x9F3B0eC9A05aaB99f9a76CabB0bb18ba297200cc

# ── Hook Agents ──
export ARB_AGENT=0x731c8103f5e39e7241f6833F68617c4da4ec31Cb       # ERC-8004 id 953
export FEE_AGENT=0x2A12E7beEC60808b4e0a5340544947D56429430a       # ERC-8004 id 954
export BACKRUN_AGENT=0xc1ec8B65bb137602963f88eb063fa7236f4744f2    # ERC-8004 id 955

# ── ERC-8004 Registries (Sepolia) ──
export IDENTITY_REG=0x8004A818BFB912233c491871b3d84c89A494BD9e
export REPUTATION_REG=0x8004B663056A597Dffe9eCcC1965A193B7388713

# ── Pool ID (DAI/WETH hook pool) ──
export POOL_ID=0x2e8902690b6b0b84539807aeaf1192d215ec1753f614a9e7ceffcbebde7a425f

# ── Pre-encoded candidate path (single-hop DAI→WETH through hook pool) ──
export CANDIDATE_PATH=$(cast abi-encode \
  "x((address,uint24,int24,address,bytes)[])" \
  "[(${WETH},8388608,60,${SWARM_HOOK},0x)]")
```

---

## 1. Contract Wiring Verification

### 1.1 AgentExecutor — registered agents

```bash
# List all 3 hook agents + their status
cast call $AGENT_EXECUTOR "getAgent(uint8)(address,bool,uint256)" 0 --rpc-url $RPC   # ARBITRAGE
cast call $AGENT_EXECUTOR "getAgent(uint8)(address,bool,uint256)" 1 --rpc-url $RPC   # DYNAMIC_FEE
cast call $AGENT_EXECUTOR "getAgent(uint8)(address,bool,uint256)" 2 --rpc-url $RPC   # BACKRUN

# Array view
cast call $AGENT_EXECUTOR "getAllAgents()(address[5])" --rpc-url $RPC

# Scoring enabled?
cast call $AGENT_EXECUTOR "scoringEnabled()(bool)" --rpc-url $RPC

# Scoring registry pointer
cast call $AGENT_EXECUTOR "scoringReputationRegistry()(address)" --rpc-url $RPC
```

### 1.2 SwarmHook — downstream pointers

```bash
cast call $SWARM_HOOK "agentExecutor()(address)" --rpc-url $RPC
cast call $SWARM_HOOK "oracleRegistry()(address)" --rpc-url $RPC
cast call $SWARM_HOOK "lpFeeAccumulator()(address)" --rpc-url $RPC
cast call $SWARM_HOOK "backrunRecorder()(address)" --rpc-url $RPC
```

### 1.3 FlashLoanBackrunner — auth & config

```bash
# Keeper / forwarder authorization
cast call $FLASH_BACKRUNNER "authorizedKeepers(address)(bool)" $FLASH_EXECUTOR --rpc-url $RPC
cast call $FLASH_BACKRUNNER "authorizedForwarders(address)(bool)" $FLASH_EXECUTOR --rpc-url $RPC

# Repay pool key set?
cast call $FLASH_BACKRUNNER "repayPoolKeySet(bytes32)(bool)" $POOL_ID --rpc-url $RPC

# Max opportunity age
cast call $FLASH_BACKRUNNER "maxOpportunityAgeBlocks()(uint256)" --rpc-url $RPC
```

### 1.4 Coordinator — route agent

```bash
cast call $COORDINATOR "agents(address)(uint256,bool)" $ROUTE_AGENT --rpc-url $RPC
cast call $COORDINATOR "nextIntentId()(uint256)" --rpc-url $RPC
```

### 1.5 FlashBackrunExecutorAgent

```bash
cast call $FLASH_EXECUTOR "backrunner()(address)" --rpc-url $RPC
```

---

## 2. Token Balances & Approvals

```bash
# Check DAI balance
cast call $DAI "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC

# Check WETH balance
cast call $WETH "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC

# Approve DAI to Coordinator (for intent creation)
cast send $DAI "approve(address,uint256)" $COORDINATOR 1000000000000000000000 \
  --rpc-url $RPC --private-key $PK

# Approve WETH to FlashLoanBackrunner (for capital-backed execution)
cast send $WETH "approve(address,uint256)" $FLASH_BACKRUNNER 100000000000000000000 \
  --rpc-url $RPC --private-key $PK
```

---

## 3. E2E Swap Flow (Intent Lifecycle)

### 3.1 Create Intent

Swaps `AMOUNT_IN` DAI → WETH through the hook pool.

```bash
AMOUNT_IN=1000000000000000000000   # 1000 DAI (18 decimals)
DEADLINE=$(($(date +%s) + 86400))  # absolute timestamp = now + 24h

cast send $COORDINATOR \
  "createIntent((address,address,uint128,uint128,uint64,uint16,uint16,uint16),bytes[])" \
  "(${DAI},${WETH},${AMOUNT_IN},0,${DEADLINE},100,100,8000)" \
  "[${CANDIDATE_PATH}]" \
  --rpc-url $RPC --private-key $PK --gas-limit 500000
```

**Parameters:**
| Field | Value | Description |
|---|---|---|
| `tokenIn` | DAI address | Input token |
| `tokenOut` | WETH address | Desired output token |
| `amountIn` | 1000e18 | Amount of DAI to swap |
| `minAmountOut` | 0 | Min output (set 0 for testing) |
| `deadline` | now + 86400 | Absolute unix timestamp (NOT relative) |
| `mevFeeBps` | 100 | 1% MEV fee |
| `treasuryBps` | 100 | 1% treasury fee |
| `lpShareBps` | 8000 | 80% of MEV profit → LP donation |

### 3.2 Read Intent State

```bash
INTENT_ID=0   # increment for each new intent

cast call $COORDINATOR "getIntent(uint256)" $INTENT_ID --rpc-url $RPC
cast call $COORDINATOR "nextIntentId()(uint256)" --rpc-url $RPC
```

### 3.3 Propose with SimpleRouteAgent

```bash
cast send $ROUTE_AGENT "propose(uint256)" $INTENT_ID \
  --rpc-url $RPC --private-key $PK
```

### 3.4 Execute Intent

```bash
cast send $COORDINATOR "executeIntent(uint256)" $INTENT_ID \
  --rpc-url $RPC --private-key $PK --gas-limit 2000000 --value 0
```

> **Expected:** Status 1 (success). Logs show:
> - Swap events from PoolManager
> - ERC-8004 feedback for active agents
> - Backrun opportunity recorded in FlashLoanBackrunner
> - WETH transferred to user + LPFeeAccumulator

---

## 4. Post-Swap Verification

### 4.1 Agent Stats (per-agent execution counters)

```bash
cast call $AGENT_EXECUTOR "getAgentStats(address)(uint256,uint256,uint256,uint64)" $ARB_AGENT --rpc-url $RPC
cast call $AGENT_EXECUTOR "getAgentStats(address)(uint256,uint256,uint256,uint64)" $FEE_AGENT --rpc-url $RPC
cast call $AGENT_EXECUTOR "getAgentStats(address)(uint256,uint256,uint256,uint64)" $BACKRUN_AGENT --rpc-url $RPC
```

Returns: `(executions, successes, totalValueWei, lastExecBlock)`

### 4.2 ERC-8004 Reputation Scores

```bash
# BackrunAgent (id 955)
cast call $REPUTATION_REG "getReputation(uint256)(uint64,int256)" 955 --rpc-url $RPC

# FeeAgent (id 954)
cast call $REPUTATION_REG "getReputation(uint256)(uint64,int256)" 954 --rpc-url $RPC

# ArbAgent (id 953)
cast call $REPUTATION_REG "getReputation(uint256)(uint64,int256)" 953 --rpc-url $RPC

# RouteAgent (id 956)
cast call $REPUTATION_REG "getReputation(uint256)(uint64,int256)" 956 --rpc-url $RPC
```

Returns: `(interactionCount, reputationScore)`

### 4.3 Reputation Tier

```bash
cast call $REGISTRY "getAgentReputation(address)(uint64,int256,uint8)" $BACKRUN_AGENT --rpc-url $RPC
cast call $REGISTRY "getAgentReputation(address)(uint64,int256,uint8)" $FEE_AGENT --rpc-url $RPC
cast call $REGISTRY "getAgentReputation(address)(uint64,int256,uint8)" $ARB_AGENT --rpc-url $RPC
cast call $REGISTRY "getAgentReputation(address)(uint64,int256,uint8)" $ROUTE_AGENT --rpc-url $RPC
```

Returns: `(count, reputation, tier)`

---

## 5. Flashloan Backrun Flow

### 5.1 Check Pending Backrun

```bash
cast call $FLASH_BACKRUNNER \
  "getPendingBackrun(bytes32)(uint256,uint256,uint256,bool,uint64,uint64,bool)" \
  $POOL_ID --rpc-url $RPC
```

Returns: `(targetPrice, currentPrice, backrunAmount, zeroForOne, recordedBlock, expiryBlock, executed)`

### 5.2 Check Profitability

```bash
cast call $FLASH_BACKRUNNER \
  "checkProfitability(bytes32)(bool,uint256)" \
  $POOL_ID --rpc-url $RPC
```

Returns: `(isProfitable, estimatedProfit)`

### 5.3 Execute via FlashBackrunExecutorAgent (Aave flashloan path)

```bash
cast send $FLASH_EXECUTOR "execute(bytes32)(address,uint256)" $POOL_ID \
  --rpc-url $RPC --private-key $PK --gas-limit 2000000
```

> **Note:** Reverts with `InsufficientProfit()` if the round-trip swap isn't profitable. This is expected in test environments without real arbitrage opportunities.

### 5.4 Execute with Own Capital (no flashloan)

```bash
# First approve WETH to the backrunner
cast send $WETH "approve(address,uint256)" $FLASH_BACKRUNNER 100000000000000000000 \
  --rpc-url $RPC --private-key $PK

# Execute with capital (amount, minProfit)
cast send $FLASH_BACKRUNNER \
  "executeBackrunWithCapital(bytes32,uint256,uint256)" \
  $POOL_ID 10000000000000000000 0 \
  --rpc-url $RPC --private-key $PK --gas-limit 2000000
```

### 5.5 Admin — Extend Opportunity Window

```bash
# Default is 2 blocks; set to 100 (contract max) for testing
cast send $FLASH_BACKRUNNER "setMaxOpportunityAgeBlocks(uint256)" 100 \
  --rpc-url $RPC --private-key $PK
```

---

## 6. LP Fee Accumulator

### 6.1 Check Accumulated Fees

```bash
cast call $LP_ACCUMULATOR "getAccumulatedFees(bytes32,address)(uint256)" $POOL_ID $WETH --rpc-url $RPC
cast call $LP_ACCUMULATOR "getAccumulatedFees(bytes32,address)(uint256)" $POOL_ID $DAI --rpc-url $RPC
```

### 6.2 Check Donatable

```bash
cast call $LP_ACCUMULATOR "canDonate(bytes32)(bool,uint256,uint256)" $POOL_ID --rpc-url $RPC
```

Returns: `(canDonate, amount0, amount1)`

### 6.3 Donate to LPs

```bash
cast send $LP_ACCUMULATOR "donateToLPs(bytes32)" $POOL_ID \
  --rpc-url $RPC --private-key $PK --gas-limit 1000000
```

### 6.4 Verify Total Donated

```bash
cast call $LP_ACCUMULATOR "getTotalDonated(bytes32,address)(uint256)" $POOL_ID $WETH --rpc-url $RPC
cast call $LP_ACCUMULATOR "getTotalDonated(bytes32,address)(uint256)" $POOL_ID $DAI --rpc-url $RPC
```

---

## 7. Oracle Registry

```bash
# ⚠️  Only for older deploys: set this if your deploy script did not already configure max staleness.
cast send $ORACLE_REGISTRY "setMaxStaleness(uint256)" 315360000 \
  --rpc-url $RPC --private-key $PK

# Now oracle calls will work:
cast call $ORACLE_REGISTRY "getLatestPrice(address,address)(uint256)" $WETH $DAI --rpc-url $RPC
```

> **Critical for forks:** Without `setMaxStaleness`, the oracle reverts with `StalePrice` and BackrunAgent cannot detect divergence (no backrun opportunities are recorded). `DeployAnvilSepoliaFork.s.sol` already sets this to `365 days`, so run this only for older deployments.

---

## 8. Admin / Governance Commands

### 8.1 Register a New Agent

```bash
# AgentType: 0=ARBITRAGE, 1=DYNAMIC_FEE, 2=BACKRUN
cast send $AGENT_EXECUTOR "registerAgent(uint8,address)" 0 <NEW_AGENT_ADDRESS> \
  --rpc-url $RPC --private-key $PK
```

### 8.2 Check & Switch Agent (reputation failover)

```bash
# Checks if current agent for type is below reputation threshold, switches to backup if so
cast call $AGENT_EXECUTOR "checkAndSwitchAgentIfBelowThreshold(uint8)(bool)" 0 --rpc-url $RPC
```

### 8.3 Authorize Keeper / Forwarder

```bash
cast send $FLASH_BACKRUNNER "setKeeperAuthorization(address,bool)" <KEEPER_ADDRESS> true \
  --rpc-url $RPC --private-key $PK

cast send $FLASH_BACKRUNNER "setForwarderAuthorization(address,bool)" <FORWARDER_ADDRESS> true \
  --rpc-url $RPC --private-key $PK
```

### 8.4 ERC-8004 — Give Manual Feedback

```bash
cast send $REGISTRY "giveFeedback(address,int128,string)" \
  $BACKRUN_AGENT 1000000000000000000 "good backrun" \
  --rpc-url $RPC --private-key $PK
```

---

## 9. Full E2E Test Script

Run these in order for a complete protocol test:

```bash
#!/bin/bash
set -e

# Source environment variables (copy section 0 above into env.sh)
source env.sh

echo "═══════════════════════════════════════════════"
echo "  SWARMREP PROTOCOL — E2E TEST"
echo "═══════════════════════════════════════════════"

# ── Step 1: Verify wiring ──
echo "\n[1/8] Verifying contract wiring..."
SCORING=$(cast call $AGENT_EXECUTOR "scoringEnabled()(bool)" --rpc-url $RPC)
echo "  Scoring enabled: $SCORING"
HOOK_EXEC=$(cast call $SWARM_HOOK "agentExecutor()(address)" --rpc-url $RPC)
echo "  Hook → Executor: $HOOK_EXEC"

# ── Step 1b: Optional staleness fix for older deploys ──
echo "\n[1b/8] Optional oracle staleness update (older deploys)..."

# ── Step 2: Approve DAI ──
echo "\n[2/8] Approving DAI..."
cast send $DAI "approve(address,uint256)" $COORDINATOR 5000000000000000000000 \
  --rpc-url $RPC --private-key $PK --json | jq -r '.status'

# ── Step 3: Extend backrun window ──
echo "\n[3/8] Setting maxOpportunityAgeBlocks to 100..."
cast send $FLASH_BACKRUNNER "setMaxOpportunityAgeBlocks(uint256)" 100 \
  --rpc-url $RPC --private-key $PK --json | jq -r '.status'

# ── Step 4: Create intent ──
echo "\n[4/8] Creating intent (1000 DAI → WETH)..."
DEADLINE=$(($(date +%s) + 86400))
TX=$(cast send $COORDINATOR \
  "createIntent((address,address,uint128,uint128,uint64,uint16,uint16,uint16),bytes[])" \
  "(${DAI},${WETH},1000000000000000000000,0,${DEADLINE},100,100,8000)" \
  "[${CANDIDATE_PATH}]" \
  --rpc-url $RPC --private-key $PK --json)
echo "  Status: $(echo $TX | jq -r '.status')"
INTENT_ID=$(cast call $COORDINATOR "nextIntentId()(uint256)" --rpc-url $RPC)
INTENT_ID=$((INTENT_ID - 1))
echo "  Intent ID: $INTENT_ID"

# ── Step 5: Propose ──
echo "\n[5/8] SimpleRouteAgent proposing..."
cast send $ROUTE_AGENT "propose(uint256)" $INTENT_ID \
  --rpc-url $RPC --private-key $PK --json | jq -r '.status'

# ── Step 6: Execute ──
echo "\n[6/8] Executing intent..."
cast send $COORDINATOR "executeIntent(uint256)" $INTENT_ID \
  --rpc-url $RPC --private-key $PK --gas-limit 2000000 --json | jq -r '.status'

# ── Step 7: Check scoring ──
echo "\n[7/8] ERC-8004 Reputation scores:"
echo "  BackrunAgent (955): $(cast call $REPUTATION_REG 'getReputation(uint256)(uint64,int256)' 955 --rpc-url $RPC)"
echo "  FeeAgent     (954): $(cast call $REPUTATION_REG 'getReputation(uint256)(uint64,int256)' 954 --rpc-url $RPC)"
echo "  ArbAgent     (953): $(cast call $REPUTATION_REG 'getReputation(uint256)(uint64,int256)' 953 --rpc-url $RPC)"
echo "  RouteAgent   (956): $(cast call $REPUTATION_REG 'getReputation(uint256)(uint64,int256)' 956 --rpc-url $RPC)"

# ── Step 8: LP donation ──
echo "\n[8/8] Checking LP donation..."
CAN_DONATE=$(cast call $LP_ACCUMULATOR "canDonate(bytes32)(bool,uint256,uint256)" $POOL_ID --rpc-url $RPC)
echo "  canDonate: $CAN_DONATE"

# Donate if possible
if [[ "$CAN_DONATE" == *"true"* ]]; then
  echo "  Donating to LPs..."
  cast send $LP_ACCUMULATOR "donateToLPs(bytes32)" $POOL_ID \
    --rpc-url $RPC --private-key $PK --gas-limit 1000000 --json | jq -r '.status'
  echo "  Total donated WETH: $(cast call $LP_ACCUMULATOR 'getTotalDonated(bytes32,address)(uint256)' $POOL_ID $WETH --rpc-url $RPC)"
fi

echo "\n═══════════════════════════════════════════════"
echo "  ✅  E2E TEST COMPLETE"
echo "═══════════════════════════════════════════════"
```

---

## 10. Quick Reference — Common Checks

| What | Command |
|---|---|
| Next intent ID | `cast call $COORDINATOR "nextIntentId()(uint256)" --rpc-url $RPC` |
| WETH balance | `cast call $WETH "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC` |
| DAI balance | `cast call $DAI "balanceOf(address)(uint256)" $DEPLOYER --rpc-url $RPC` |
| Pending backrun | `cast call $FLASH_BACKRUNNER "getPendingBackrun(bytes32)(...)" $POOL_ID --rpc-url $RPC` |
| Agent stats | `cast call $AGENT_EXECUTOR "getAgentStats(address)(...)" <AGENT> --rpc-url $RPC` |
| Reputation | `cast call $REPUTATION_REG "getReputation(uint256)(uint64,int256)" <ID> --rpc-url $RPC` |
| Accumulated fees | `cast call $LP_ACCUMULATOR "getAccumulatedFees(bytes32,address)(uint256)" $POOL_ID $WETH --rpc-url $RPC` |
| LP donated total | `cast call $LP_ACCUMULATOR "getTotalDonated(bytes32,address)(uint256)" $POOL_ID $WETH --rpc-url $RPC` |
| Decode error | `cast 4byte <first-4-bytes>` |
| Trace failed tx | `cast run <TX_HASH> --rpc-url $RPC` |

---

## Expected E2E Results

After running the full flow:

| Agent | ID | Executions | Reputation | Notes |
|---|---|---|---|---|
| BackrunAgent | 955 | N (fires every swap) | +1e18 per swap | Records backrun opportunity |
| FeeAgent | 954 | Fires after 1st swap | +1e18 when fires | Dynamic fee override |
| ArbAgent | 953 | 0 | 0 | Only fires when oracle-pool diff > threshold |
| RouteAgent | 956 | N (proposes every intent) | +1e18 per intent | On-chain route proposal |

**Backrun execution:** `InsufficientProfit()` revert is **expected** in test environments. The detection, recording, and authorization all work correctly — execution only succeeds when a real cross-pool arbitrage exists.

**LP donation:** `donateToLPs()` redistributes accumulated WETH to pool LPs via PoolManager's `donate()`. After donation, `canDonate` returns false and `getAccumulatedFees` returns 0.
