# Swarm Protocol Architecture

## Overview

Swarm Protocol is an **agent-driven MEV protection and redistribution layer** built on Uniswap v4 hooks. It uses a modular architecture where specialized AI agents analyze and optimize each swap, capturing MEV value and redistributing it to liquidity providers.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          USER TRANSACTION                               │
│                         (Swap Request)                                  │
└─────────────────────────────────────┬───────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         UNISWAP V4 POOLMANAGER                          │
│                      (0xE03A1074...Sepolia)                             │
│                                                                         │
│  • Routes swap to pool                                                  │
│  • Calls hook.beforeSwap() / hook.afterSwap()                          │
└─────────────────────────────────────┬───────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                             SWARM HOOK                                   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        SwarmHook.sol                             │   │
│  │                                                                   │   │
│  │  • beforeSwap() → Delegates to AgentExecutor                    │   │
│  │  • afterSwap()  → Delegates to AgentExecutor                    │   │
│  │  • Applies BeforeSwapDelta for MEV capture                      │   │
│  │  • Manages pool fee updates                                      │   │
│  │                                                                   │   │
│  │  Dependencies:                                                    │   │
│  │    - AgentExecutor                                               │   │
│  │    - OracleRegistry                                              │   │
│  │    - LPFeeAccumulator                                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────┬───────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          AGENT EXECUTOR                                  │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     AgentExecutor.sol                            │   │
│  │                                                                   │   │
│  │  • Central routing hub for all agents                           │   │
│  │  • processBeforeSwap() → Routes to ARBITRAGE + DYNAMIC_FEE      │   │
│  │  • processAfterSwap()  → Routes to BACKRUN                      │   │
│  │  • Aggregates agent results                                      │   │
│  │  • Hot-swap capability (enable/disable agents)                  │   │
│  │  • Admin agent replacement                                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────┬───────────────────────┬───────────────────┬───────────────┘
              │                       │                   │
              ▼                       ▼                   ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│  ARBITRAGE AGENT    │ │  DYNAMIC FEE AGENT  │ │   BACKRUN AGENT     │
│                     │ │                     │ │                     │
│ ┌─────────────────┐ │ │ ┌─────────────────┐ │ │ ┌─────────────────┐ │
│ │ArbitrageAgent   │ │ │ │DynamicFeeAgent  │ │ │ │BackrunAgent     │ │
│ │                 │ │ │ │                 │ │ │ │                 │ │
│ │• Detects MEV    │ │ │ │• Calculates     │ │ │ │• Analyzes post- │ │
│ │  opportunities  │ │ │ │  optimal fees   │ │ │ │  swap state     │ │
│ │• Compares pool  │ │ │ │  based on:      │ │ │ │• Detects        │ │
│ │  vs oracle      │ │ │ │  - Volatility   │ │ │ │  backrun        │ │
│ │  prices         │ │ │ │  - Liquidity    │ │ │ │  opportunities  │ │
│ │• Captures       │ │ │ │  - MEV risk     │ │ │ │• Distributes    │ │
│ │  arbitrage      │ │ │ │  - Swap size    │ │ │ │  profits to LPs │ │
│ │  profit         │ │ │ │                 │ │ │ │                 │ │
│ │• 80% → LPs      │ │ │ │• Returns fee    │ │ │ │• 80% → LPs      │ │
│ │• 20% → Protocol │ │ │ │  override       │ │ │ │• 20% → Protocol │ │
│ └─────────────────┘ │ │ └─────────────────┘ │ │ └─────────────────┘ │
│                     │ │                     │ │                     │
│ ERC-8004 Identity   │ │ ERC-8004 Identity   │ │ ERC-8004 Identity   │
│ Confidence: 80      │ │ Confidence: 80      │ │ Confidence: 80      │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
              │                       │                   │
              └───────────────────────┼───────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         SUPPORT SYSTEMS                                  │
│                                                                         │
│  ┌──────────────────────┐  ┌──────────────────────┐                    │
│  │   OracleRegistry     │  │   LPFeeAccumulator   │                    │
│  │                      │  │                      │                    │
│  │ • Chainlink feeds    │  │ • Collects MEV       │                    │
│  │ • Price lookups      │  │   capture profits    │                    │
│  │ • Multi-oracle       │  │ • Distributes to LPs │                    │
│  │   support            │  │ • Threshold-based    │                    │
│  │                      │  │   donations          │                    │
│  └──────────────────────┘  └──────────────────────┘                    │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                     ERC-8004 Integration                          │  │
│  │                                                                    │  │
│  │  • Identity Registry: 0x8004A818...                               │  │
│  │  • Reputation Registry: 0x8004B663...                             │  │
│  │  • Each agent has on-chain identity                               │  │
│  │  • Reputation tracking for agent performance                      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. SwarmHook (`src/hooks/SwarmHook.sol`)

The main Uniswap v4 hook that intercepts swaps. It's a **thin delegation layer** that routes all logic to the AgentExecutor.

**Key Features:**
- Implements `beforeSwap()` and `afterSwap()` hooks
- Uses `BEFORE_SWAP_RETURNS_DELTA_FLAG` for MEV capture
- Dynamic fee support via `DYNAMIC_FEE_FLAG`
- Owner-configurable agent executor, oracle registry, and LP accumulator

**Hook Flags:**
```solidity
Hooks.BEFORE_SWAP_FLAG |
Hooks.AFTER_SWAP_FLAG |
Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
```

### 2. AgentExecutor (`src/agents/AgentExecutor.sol`)

Central routing hub that manages agent lifecycle and aggregates results.

**Key Features:**
- Register/unregister agents by type
- Enable/disable agents (hot-swap)
- Route swap context to appropriate agents
- Aggregate results from multiple agents

**Agent Types:**
```solidity
enum AgentType {
    ARBITRAGE,    // 0 - MEV detection and capture
    DYNAMIC_FEE,  // 1 - Optimal fee calculation
    BACKRUN       // 2 - Post-swap opportunity detection
}
```

### 3. SwarmAgentBase (`src/agents/base/SwarmAgentBase.sol`)

Abstract base class for all agents providing common functionality.

**Key Features:**
- ERC-8004 identity integration
- Confidence scoring (0-100)
- Authorized caller management
- Activation/deactivation

### 4. ArbitrageAgent (`src/agents/ArbitrageAgent.sol`)

Detects arbitrage opportunities by comparing pool price to oracle price.

**Parameters:**
- `hookShareBps`: Percentage of captured value for LPs (default: 8000 = 80%)
- `minDivergenceBps`: Minimum price divergence to trigger (default: 50 = 0.5%)

**Logic:**
```
1. Get current pool price
2. Get oracle price (Chainlink)
3. Calculate divergence
4. If divergence > threshold:
   - Calculate capture amount
   - Return result to hook
   - 80% distributed to LPs
```

### 5. DynamicFeeAgent (`src/agents/DynamicFeeAgent.sol`)

Calculates optimal swap fees based on market conditions.

**Fee Factors:**
- Base fee: 0.30% (3000 bps)
- Volatility adjustment: up to 1.5x
- Liquidity depth adjustment
- MEV risk premium

**Logic:**
```
optimalFee = baseFee * volatilityMultiplier * liquidityFactor * mevRiskFactor
```

### 6. BackrunAgent (`src/agents/BackrunAgent.sol`)

Analyzes post-swap state for backrun opportunities.

**Parameters:**
- `lpShareBps`: LP share of profits (default: 8000 = 80%)
- `minDivergenceBps`: Minimum opportunity threshold (default: 30 = 0.3%)

**Logic:**
```
1. Analyze post-swap price impact
2. Detect if price diverges from external markets
3. Calculate potential backrun profit
4. Route profits to LPFeeAccumulator
```

### 7. OracleRegistry (`src/oracles/OracleRegistry.sol`)

Manages price feed registrations for token pairs.

**Features:**
- Register Chainlink price feeds
- Multi-oracle support
- Price staleness checks

### 8. LPFeeAccumulator (`src/LPFeeAccumulator.sol`)

Collects and distributes MEV profits to liquidity providers.

**Features:**
- Accumulates fees per pool
- Threshold-based distribution
- Time-based donation intervals
- Integration with PoolManager.donate()

## Data Flow

### Before Swap Flow

```
User Swap Request
       │
       ▼
PoolManager.swap()
       │
       ▼
SwarmHook.beforeSwap()
       │
       ├──► Build SwapContext (poolKey, params, prices, etc.)
       │
       ▼
AgentExecutor.processBeforeSwap()
       │
       ├──► ArbitrageAgent.execute() ───► Returns (captureAmount, confidence)
       │
       ├──► DynamicFeeAgent.execute() ──► Returns (feeOverride, confidence)
       │
       ▼
Aggregate Results
       │
       ├──► Apply fee override if needed
       ├──► Calculate BeforeSwapDelta for MEV capture
       │
       ▼
Return to PoolManager
```

### After Swap Flow

```
PoolManager.afterSwap()
       │
       ▼
SwarmHook.afterSwap()
       │
       ▼
AgentExecutor.processAfterSwap()
       │
       ├──► BackrunAgent.execute() ───► Analyze opportunity
       │
       ▼
LPFeeAccumulator.accumulate()
       │
       ▼
Return to PoolManager
```

## Interfaces

### ISwarmAgent

```solidity
interface ISwarmAgent {
    function agentType() external view returns (AgentType);
    function execute(SwapContext memory ctx) external returns (AgentResult memory);
    function isActive() external view returns (bool);
    function getConfidence() external view returns (uint256);
    function getAgentId() external view returns (uint256);
}
```

### SwapContext

```solidity
struct SwapContext {
    PoolKey poolKey;
    PoolId poolId;
    SwapParams params;
    uint256 poolPrice;
    uint256 oraclePrice;
    uint256 oracleConfidence;
    uint128 liquidity;
    bytes hookData;
}
```

### AgentResult

```solidity
struct AgentResult {
    bool shouldAct;
    uint256 value;
    uint24 feeOverride;
    uint8 confidence;
    bytes data;
}
```

## Admin Operations

### Hot-Swap Agents

```solidity
// Disable an agent temporarily
agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, false);

// Re-enable
agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, true);
```

### Replace Agent

```solidity
// Deploy new agent with different parameters
ArbitrageAgent newAgent = new ArbitrageAgent(poolManager, owner, 9000, 30);

// Authorize new agent
newAgent.authorizeCaller(address(agentExecutor), true);

// Replace (hot-swap)
agentExecutor.registerAgent(AgentType.ARBITRAGE, address(newAgent));
```

### Configure ERC-8004 Identity

```solidity
arbitrageAgent.configureIdentity(1001, ERC8004_IDENTITY_REGISTRY);
```

## Security Considerations

1. **Access Control**: All agents use `onlyAuthorized` modifier
2. **Caller Whitelisting**: Only authorized callers (executor, hook) can invoke agents
3. **Owner-Only Admin**: Critical functions (registration, enabling) are owner-only
4. **Graceful Degradation**: If an agent fails, swaps still proceed
5. **Price Staleness**: Oracle prices checked for freshness

## Testing

Run the complete E2E test suite:

```bash
# All E2E tests (requires Sepolia RPC)
SEPOLIA_RPC_URL="your-rpc-url" forge test --match-contract E2ETest -vv

# Agent integration tests
forge test --match-contract AgentIntegrationTest -vv

# MEV integration tests (requires fork)
SEPOLIA_RPC_URL="your-rpc-url" forge test --match-contract MevIntegrationTest -vv
```

## Deployment

See [ETH_SEPOLIA_DEPLOYMENT.md](./ETH_SEPOLIA_DEPLOYMENT.md) for deployment instructions.

## Contract Addresses (Sepolia)

| Contract | Address |
|----------|---------|
| PoolManager | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| ERC-8004 Identity | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| ERC-8004 Reputation | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |
| USDC (Aave) | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` |
| ETH/USD Chainlink | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |

## Future Extensions

1. **More Agent Types**: Sandwich protection, liquidity rebalancing
2. **Agent Staking**: Skin-in-the-game for agents
3. **Reputation System**: Performance-based agent ranking via ERC-8004
4. **Multi-Pool Coordination**: Cross-pool arbitrage optimization
5. **AI/ML Integration**: Off-chain AI with on-chain verification
