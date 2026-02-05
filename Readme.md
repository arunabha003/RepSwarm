# Swarm Protocol

> **ETHGlobal HackMoney 2024** — An agent-driven MEV protection and redistribution layer built on Uniswap v4 hooks.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org/)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4-pink)](https://docs.uniswap.org/contracts/v4/overview)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)](https://book.getfoundry.sh/)
[![ERC-8004](https://img.shields.io/badge/ERC--8004-Compatible-green)](https://eips.ethereum.org/EIPS/eip-8004)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

Swarm Protocol is a **modular agent-driven system** that protects traders from MEV extraction while redistributing captured value to liquidity providers. Built on Uniswap v4 hooks, it uses specialized on-chain agents to analyze and optimize every swap.

### How It Works

```
User Swap → SwarmHook → AgentExecutor → [Agents] → MEV Capture → LP Distribution
```

1. **ArbitrageAgent** detects price divergence between pool and oracles
2. **DynamicFeeAgent** calculates optimal fees based on volatility and MEV risk
3. **BackrunAgent** identifies post-swap opportunities
4. **LPFeeAccumulator** distributes captured value to liquidity providers

## Key Features

### 🤖 Agent-Driven Architecture
- **Modular Agents**: Each agent specializes in one task
- **Hot-Swappable**: Admins can replace agents without redeploying
- **ERC-8004 Compatible**: Agents have on-chain identity and reputation

### 🛡️ MEV Protection
- **Arbitrage Capture**: Hook captures MEV instead of external bots
- **Dynamic Fees**: Fees adjust based on MEV risk
- **80% LP Share**: Majority of captured value goes to LPs

### 💰 LP Fee Redistribution
- **Real Donations**: Uses Uniswap v4's native `donate()` function
- **Threshold-Based**: Batches fees for gas efficiency
- **Transparent**: All flows trackable on-chain

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         SwarmHook                               │
│  • beforeSwap() / afterSwap()                                  │
│  • Delegates ALL logic to AgentExecutor                        │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       AgentExecutor                             │
│  • Routes to registered agents                                 │
│  • Hot-swap capability                                         │
│  • Aggregates agent results                                    │
└─────────┬─────────────────────┬─────────────────────┬───────────┘
          │                     │                     │
          ▼                     ▼                     ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ ArbitrageAgent  │   │ DynamicFeeAgent │   │  BackrunAgent   │
│  MEV Detection  │   │  Fee Optimizer  │   │  Opportunity    │
│  80% → LPs      │   │  Volatility     │   │  Detection      │
│  ERC-8004 ID    │   │  ERC-8004 ID    │   │  ERC-8004 ID    │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed system design.

## Project Structure

```
├── src/
│   ├── hooks/
│   │   └── SwarmHook.sol           # Main Uniswap v4 hook
│   ├── agents/
│   │   ├── AgentExecutor.sol       # Central agent routing
│   │   ├── ArbitrageAgent.sol      # MEV detection & capture
│   │   ├── DynamicFeeAgent.sol     # Fee optimization
│   │   ├── BackrunAgent.sol        # Backrun opportunities
│   │   └── base/
│   │       └── SwarmAgentBase.sol  # Base agent class
│   ├── interfaces/
│   │   └── ISwarmAgent.sol         # Agent interface
│   ├── oracles/
│   │   └── OracleRegistry.sol      # Chainlink integration
│   ├── LPFeeAccumulator.sol        # LP fee distribution
│   └── SwarmCoordinator.sol        # Legacy coordinator
├── script/
│   ├── E2ETest.s.sol               # E2E deployment script
│   └── DeploySwarmProtocol.s.sol   # Production deployment
├── test/
│   ├── E2ETest.t.sol               # Full E2E tests (14 tests)
│   ├── AgentIntegration.t.sol      # Agent tests (11 tests)
│   └── MevIntegration.t.sol        # MEV tests (5 tests)
├── docs/
│   └── PROTOCOL_EXPLAINED.md       # Protocol documentation
└── frontend/                        # Next.js interface
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Alchemy API key (for Sepolia fork)

### Installation

```bash
git clone https://github.com/your-repo/swarm-protocol.git
cd swarm-protocol

forge install
forge build
```

### Run Tests

```bash
# E2E Tests (full protocol - recommended)
SEPOLIA_RPC_URL="your-alchemy-url" forge test --match-contract E2ETest -vv

# Agent Integration Tests
forge test --match-contract AgentIntegrationTest -vv

# MEV Integration Tests (fork required)
SEPOLIA_RPC_URL="your-alchemy-url" forge test --match-contract MevIntegrationTest -vv

# All tests
SEPOLIA_RPC_URL="your-alchemy-url" forge test -vv
```

### Test Results

```
✅ E2ETest: 14 passed
   - Protocol deployment verification
   - Agent registration
   - Multiple swaps
   - Admin agent control
   - Hot-swap agent
   - ERC-8004 identity
   - Liquidity operations
   - Dynamic fee calculation
   - Oracle integration
   - Complete user journey

✅ AgentIntegrationTest: 11 passed
✅ MevIntegrationTest: 5 passed

Total: 30 tests passing
```

## Agent System

### ArbitrageAgent

Detects MEV opportunities by comparing pool prices to oracle prices.

```solidity
ArbitrageAgent(poolManager, owner, hookShareBps, minDivergenceBps)
```

- `hookShareBps`: LP share of captured value (default: 8000 = 80%)
- `minDivergenceBps`: Minimum price divergence to trigger (default: 50 = 0.5%)

### DynamicFeeAgent

Calculates optimal fees based on market conditions.

```solidity
DynamicFeeAgent(poolManager, owner)
```

Fee factors:
- Base fee: 0.30%
- Volatility adjustment: up to 1.5x
- Liquidity depth
- MEV risk premium

### BackrunAgent

Analyzes post-swap state for backrun opportunities.

```solidity
BackrunAgent(poolManager, owner)
```

- Detects price divergence after large swaps
- Routes 80% of profits to LPs via LPFeeAccumulator

## Admin Operations

### Hot-Swap Agents

```solidity
// Disable agent temporarily
agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, false);

// Re-enable
agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, true);
```

### Replace Agent

```solidity
// Deploy new agent
ArbitrageAgent newAgent = new ArbitrageAgent(poolManager, owner, 9000, 30);

// Register (replaces old)
agentExecutor.registerAgent(AgentType.ARBITRAGE, address(newAgent));
```

### Configure ERC-8004 Identity

```solidity
arbitrageAgent.configureIdentity(1001, ERC8004_IDENTITY_REGISTRY);
```

## Sepolia Addresses

| Contract | Address |
|----------|---------|
| PoolManager | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| ERC-8004 Identity | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| ERC-8004 Reputation | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |
| USDC (Aave) | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` |
| ETH/USD Chainlink | `0x694AA1769357215DE4FAC081bf1f309aDC325306` |

## Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Detailed system architecture
- [docs/PROTOCOL_EXPLAINED.md](./docs/PROTOCOL_EXPLAINED.md) - Protocol mechanics
- [ETH_SEPOLIA_DEPLOYMENT.md](./ETH_SEPOLIA_DEPLOYMENT.md) - Deployment guide

## Development

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Format

```bash
forge fmt
```

### Gas Report

```bash
forge test --gas-report
```

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Acknowledgements

- [Uniswap v4](https://docs.uniswap.org/contracts/v4/overview)
- [Foundry](https://book.getfoundry.sh/)
- [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004)
- [Chainlink](https://docs.chain.link/)
- [ETHGlobal HackMoney](https://ethglobal.com/events/hackmoney2024)
