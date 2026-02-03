# Multi-Agent Trade Router Swarm

> **ETHGlobal HackMoney 2024** — A Uniswap v4 hook-powered MEV protection and redistribution system with multi-agent routing intelligence.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org/)
[![Uniswap v4](https://img.shields.io/badge/Uniswap-v4-pink)](https://docs.uniswap.org/contracts/v4/overview)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)](https://book.getfoundry.sh/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

Swarm is a Uniswap v4 hook that **protects traders from MEV extraction** while **redistributing captured value back to liquidity providers**. Instead of letting arbitrageurs and sandwich attackers extract value, Swarm:

1. **Detects arbitrage opportunities** using Chainlink oracle price feeds
2. **Captures MEV in beforeSwap** by applying dynamic fees based on price divergence
3. **Executes backruns** after large swaps to restore equilibrium pricing
4. **Donates profits to LPs** through Uniswap v4's native `donate()` function

## Key Features

### 🛡️ MEV Protection
- **Sandwich Attack Prevention**: Dynamic fees make sandwich attacks unprofitable
- **Front-run Detection**: Oracle price comparison identifies manipulation attempts
- **Arbitrage Capture**: Hook captures arbitrage instead of external MEV bots

### 💰 LP Fee Redistribution
- **Real LP Donations**: Uses Uniswap v4's `donate()` for actual fee distribution
- **Batched Donations**: Accumulates fees and donates when threshold is met
- **Transparent Accounting**: All captured MEV is trackable on-chain

### 🤖 Multi-Agent Intelligence with ERC-8004
- **On-chain Agent Identity**: Agents are NFTs on ERC-8004 Identity Registry
- **Reputation-Weighted Scoring**: Agent proposals weighted by ERC-8004 reputation
- **Automatic Feedback**: Successful swaps give positive reputation to winning agent
- **FeeOptimizerAgent**: Optimizes dynamic fee parameters
- **MevHunterAgent**: Identifies MEV opportunities using oracle comparison
- **SlippagePredictorAgent**: Predicts slippage using SwapMath simulation

### ⚡ Flash Loan Backrunning
- **Aave V3 Integration**: Capital-efficient backruns using flash loans
- **Automatic Profit Distribution**: Backrun profits go to LPs
- **Keeper Network Ready**: Permissioned keepers can trigger backruns

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      User Swap Request                          │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SwarmCoordinator                            │
│  - Intent-based routing                                         │
│  - Multi-agent proposal system                                  │
│  - ERC-8004 agent identity support                              │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                     MevRouterHookV2                             │
│  ┌──────────────────┐  ┌──────────────────┐                    │
│  │    beforeSwap    │  │    afterSwap     │                    │
│  │  - Oracle check  │  │  - Backrun setup │                    │
│  │  - Arb capture   │  │  - Fee donation  │                    │
│  │  - Dynamic fee   │  │  - LP payment    │                    │
│  └──────────────────┘  └──────────────────┘                    │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          ▼                       ▼                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  OracleRegistry │     │ LPFeeAccumulator│     │FlashLoanBackrun │
│  - Chainlink    │     │  - Batch fees   │     │  - Aave V3      │
│  - Price feeds  │     │  - LP donate()  │     │  - Keeper exec  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed system design.

## Project Structure

```
├── src/
│   ├── hooks/
│   │   └── MevRouterHookV2.sol    # Main hook - MEV detection & capture
│   ├── backrun/
│   │   ├── FlashLoanBackrunner.sol    # Aave V3 flash loan backruns
│   │   └── SimpleBackrunExecutor.sol  # Simple capital backruns
│   ├── agents/
│   │   ├── SwarmAgentBase.sol         # Base agent with reputation weighting
│   │   ├── FeeOptimizerAgent.sol      # Fee optimization agent
│   │   ├── MevHunterAgent.sol         # MEV hunting agent
│   │   └── SlippagePredictorAgent.sol # Slippage prediction agent
│   ├── erc8004/
│   │   ├── ERC8004Integration.sol     # ERC-8004 interfaces & helpers
│   │   └── SwarmAgentRegistry.sol     # Agent registration on ERC-8004
│   ├── LPFeeAccumulator.sol       # LP fee batching & donation
│   ├── SwarmCoordinator.sol       # Multi-agent routing with ERC-8004
│   └── oracles/
│       └── OracleRegistry.sol     # Chainlink price feed registry
├── script/
│   ├── DeploySwarmComplete.s.sol  # Full production deployment
│   ├── DeployERC8004Agents.s.sol  # Agent deployment with ERC-8004 registration
│   ├── DeployBackrunners.s.sol    # Backrunner deployment
│   └── DeployERC8004.s.sol        # ERC-8004 registry deployment
├── test/
│   ├── ERC8004Integration.t.sol   # ERC-8004 integration tests
│   ├── MevIntegration.t.sol       # Integration tests
│   ├── SepoliaFork.t.sol          # Fork tests with real Sepolia state
│   └── SwarmUnit.t.sol            # Unit tests
└── frontend/                       # Next.js swap interface
    └── src/
        ├── app/
        ├── components/
        ├── config/
        └── hooks/
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for frontend)
- Alchemy API key (for Sepolia fork tests)

### Installation

```bash
# Clone repository
git clone https://github.com/your-repo/swarm-mev-router.git
cd swarm-mev-router

# Install Foundry dependencies
forge install

# Build contracts
forge build
```

### Run Tests

```bash
# Unit tests (fast, no network)
forge test --match-path "test/SwarmUnit.t.sol" -vv

# Integration tests (local fork)
forge test --match-path "test/MevIntegration.t.sol" -vv

# Sepolia fork tests (requires ALCHEMY_SEPOLIA_RPC_URL)
ALCHEMY_SEPOLIA_RPC_URL=your_url forge test --match-path "test/SepoliaFork.t.sol" -vv
```

### Deploy to Sepolia

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export SEPOLIA_RPC_URL=your_sepolia_rpc

# Deploy all contracts
forge script script/DeploySwarmComplete.s.sol:DeploySwarmComplete \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify
```

### Frontend

```bash
cd frontend

# Install dependencies
npm install

# Copy environment file
cp .env.example .env.local
# Edit .env.local with your values

# Run development server
npm run dev
```

## Contract Addresses (Sepolia)

### Core Contracts
| Contract | Address |
|----------|---------|
| MevRouterHookV2 | `TBD` |
| LPFeeAccumulator | `TBD` |
| SwarmCoordinator | `TBD` |
| OracleRegistry | `TBD` |
| FlashLoanBackrunner | `TBD` |

### ERC-8004 Registries (Official)
| Registry | Address |
|----------|---------|
| Identity Registry | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| Reputation Registry | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |

### Swarm Agents
| Agent | Address | ERC-8004 ID |
|-------|---------|-------------|
| SwarmAgentRegistry | `TBD` | - |
| FeeOptimizerAgent | `TBD` | `TBD` |
| MevHunterAgent | `TBD` | `TBD` |
| SlippagePredictorAgent | `TBD` | `TBD` |

## Configuration

### Hook Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DEFAULT_HOOK_SHARE_BPS` | 8000 (80%) | Hook's share of captured arbitrage |
| `MIN_DIVERGENCE_BPS` | 50 (0.5%) | Minimum oracle divergence to trigger capture |
| `MAX_DYNAMIC_FEE` | 10000 (1%) | Maximum dynamic fee applied |
| `MIN_SAFE_LIQUIDITY` | 1e15 | Minimum liquidity for safe trading |

### LP Accumulator Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `minDonationThreshold` | 0.01 ETH | Minimum accumulated before donation |
| `minDonationInterval` | 1 hour | Minimum time between donations |

## Testing

### Test Categories

- **Unit Tests** (`SwarmUnit.t.sol`): Fast, isolated component tests
- **Integration Tests** (`MevIntegration.t.sol`): Full hook flow with mock pools
- **Fork Tests** (`SepoliaFork.t.sol`): Real network state with Aave, Chainlink

### Test Results

```
✓ 10 unit tests passing
✓ 6 integration tests passing
✓ 24 ERC-8004 integration tests passing
✓ 8 Sepolia fork tests passing
────────────────────────────
Total: 48 tests passing
```

## Security Considerations

⚠️ **This is hackathon code - NOT audited for production use**

- The hook handles user funds during swaps
- Flash loan callbacks must validate initiator
- Oracle price feeds can be stale or manipulated
- Dynamic fees could impact UX if misconfigured

## Known Limitations

See [ARCHITECTURE.md#production-gaps](./ARCHITECTURE.md#production-gaps) for a detailed analysis of what's needed for production.

Key items:
- ✅ ERC-8004 identity/reputation integration implemented
- Backrun keepers need off-chain infrastructure (Gelato/Chainlink Automation)
- Frontend needs mainnet contract addresses after deployment
- Security audit required before mainnet deployment

## License

MIT License - see [LICENSE](./LICENSE) for details.

## Acknowledgments

- [Uniswap v4](https://github.com/Uniswap/v4-core) for the hooks framework
- [detox-hook](https://github.com/detox-hook/detox-hook) for MEV capture inspiration
- [Aave V3](https://docs.aave.com/developers/getting-started/readme) for flash loans
- [Chainlink](https://docs.chain.link/data-feeds) for price oracles
- [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) for agent identity and reputation standards
- [8004.org](https://8004.org/) for builder resources and official registries
