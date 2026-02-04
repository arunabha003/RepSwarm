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

### Local Testing (Anvil Fork)

For detailed instructions, see [ETH_SEPOLIA_DEPLOYMENT.md](./ETH_SEPOLIA_DEPLOYMENT.md).

**Quick Start:**
```bash
# 1. Start Anvil (in one terminal)
anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo --chain-id 31337 --auto-impersonate

# 2. Deploy contracts (in another terminal)
forge script script/DeployEthSepoliaComplete.s.sol:DeployEthSepoliaComplete --rpc-url http://127.0.0.1:8545 --broadcast

# 3. Mint USDC and add liquidity
SLOT=$(cast keccak256 $(cast abi-encode "f(address,uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 0))
cast rpc anvil_setStorageAt 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 $SLOT 0x00000000000000000000000000000000000000000000d3c21bcecceda1000000 --rpc-url http://127.0.0.1:8545
cast send 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8 "approve(address,uint256)" 0x1A9a6FABC4412dd3f829a1be122Ff0A081a2412b 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
cast send 0x1A9a6FABC4412dd3f829a1be122Ff0A081a2412b "modifyLiquidity((address,address,uint24,int24,address),(int24,int24,int256,bytes32),bytes)" "(0x0000000000000000000000000000000000000000,0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8,500,10,0x115e0e9E6A7B475E883e1f9723dc4C082f0640Cc)" "(72240,84240,1000000000000000000,0x0000000000000000000000000000000000000000000000000000000000000000)" "0x" --value 200ether --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 4. Start frontend
cd frontend && npm install && npm run dev
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

### Deploy to Live Sepolia

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

## Contract Addresses (Anvil Fork)

### Core Contracts
| Contract | Address |
|----------|---------|
| PoolManager | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| PoolSwapTest | `0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe` |
| PoolModifyLiquidityTest | `0x1A9a6FABC4412dd3f829a1be122Ff0A081a2412b` |
| MevRouterHookV2 | `0x115e0e9E6A7B475E883e1f9723dc4C082f0640Cc` |
| LPFeeAccumulator | `0xc1ec8B65bb137602963f88eb063fa7236f4744f2` |
| SwarmCoordinator | `0x79cA020FeE712048cAA49De800B4606cC516A331` |
| OracleRegistry | `0x7A1efaf375798B6B0df2BE94CF8A13F68c9E74eE` |
| FlashLoanBackrunner | `0xd91d0433c10291448a8DC00C3ba14Af8b94c7656` |

### ERC-8004 Registries (Official)
| Registry | Address |
|----------|---------|
| Identity Registry | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| Reputation Registry | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |

### Swarm Agents
| Agent | Address |
|-------|---------|
| AgentRegistry | `0x26c13B3900bf570d9830678D2e22C439778627EA` |
| FeeOptimizerAgent | `0xae6D0f561c4907D211Ed69cBCc2fd0A0e03A2AaE` |
| MevHunterAgent | `0x95Ce3FE31BB597AD6aAc2639a03ca8f24741b508` |
| SlippagePredictorAgent | `0x3440e175a85aa6CD595e9E8b05c515ac546FB91c` |

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
