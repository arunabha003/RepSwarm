// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// ============ Top-Level Types (for easier imports) ============

/// @notice Types of agents supported by the protocol
enum AgentType {
    ARBITRAGE,      // Detects and captures MEV/arbitrage
    DYNAMIC_FEE,    // Calculates optimal swap fees
    BACKRUN,        // Executes backrun opportunities
    LIQUIDITY,      // Manages liquidity optimization
    ORACLE          // Provides price data
}

/// @notice Context passed to agent for decision making
struct SwapContext {
    PoolKey poolKey;
    PoolId poolId;
    SwapParams params;
    uint256 poolPrice;          // Current pool price
    uint256 oraclePrice;        // Oracle reference price
    uint256 oracleConfidence;   // Oracle confidence interval
    uint128 liquidity;          // Current pool liquidity
    bytes hookData;             // Additional hook data
}

/// @notice Result from agent execution
struct AgentResult {
    AgentType agentType;
    bool success;
    bool shouldAct;             // Whether agent recommends action
    uint256 value;              // Primary value (fee, amount, etc.)
    uint256 secondaryValue;     // Secondary value if needed
    int256 delta0;
    int256 delta1;
    uint24 feeOverride;
    bytes data;                 // Additional data for complex actions
}

/// @title ISwarmAgent
/// @notice Standard interface for ALL Swarm agents - ERC-8004 compatible
/// @dev Every agent in the protocol MUST implement this interface
/// @dev Agents are hot-swappable by admin via AgentExecutor
interface ISwarmAgent {
    // ============ Core Functions ============

    /// @notice Get the type of this agent
    /// @return agentType The agent's type
    function agentType() external pure returns (AgentType);

    /// @notice Get the agent's ERC-8004 identity ID
    /// @return agentId The ERC-8004 identity token ID (0 if not registered)
    function getAgentId() external view returns (uint256 agentId);

    /// @notice Execute agent logic for a swap context
    /// @param context The swap context with all relevant data
    /// @return result The agent's recommendation/result
    function execute(SwapContext calldata context) external returns (AgentResult memory result);

    /// @notice Get agent's recommendation without state changes (view)
    /// @param context The swap context
    /// @return result The agent's recommendation
    function getRecommendation(SwapContext calldata context) external view returns (AgentResult memory result);

    /// @notice Check if agent is active and ready
    /// @return active True if agent is operational
    function isActive() external view returns (bool active);

    /// @notice Get agent's confidence score (0-100)
    /// @dev Used for weighted consensus when multiple agents vote
    /// @return confidence Agent's self-reported confidence
    function getConfidence() external view returns (uint8 confidence);
}

/// @title IArbitrageAgent
/// @notice Extended interface for arbitrage-specific agents
interface IArbitrageAgent is ISwarmAgent {
    /// @notice Arbitrage-specific result
    struct ArbitrageResult {
        bool shouldCapture;         // Whether to capture arbitrage
        uint256 arbitrageAmount;    // Total arbitrage opportunity
        uint256 hookShare;          // Amount for hook/LPs
        uint256 divergenceBps;      // Price divergence in bps
        bool isOutsideConfidence;   // Outside oracle confidence band
    }

    /// @notice Analyze arbitrage opportunity for a swap
    /// @param context The swap context
    /// @return result Detailed arbitrage analysis
    function analyzeArbitrage(
        SwapContext calldata context
    ) external view returns (ArbitrageResult memory result);
}

/// @title IDynamicFeeAgent
/// @notice Extended interface for fee calculation agents
interface IDynamicFeeAgent is ISwarmAgent {
    /// @notice Fee recommendation result
    struct FeeResult {
        uint24 recommendedFee;      // Fee in hundredths of bps
        uint256 mevRisk;            // MEV risk score (0-100)
        uint256 volatility;         // Volatility score (0-100)
        bool useOverride;           // Whether to override pool fee
    }

    /// @notice Calculate recommended fee for a swap
    /// @param context The swap context
    /// @return result Detailed fee recommendation
    function calculateFee(
        SwapContext calldata context
    ) external view returns (FeeResult memory result);
}

/// @title IBackrunAgent
/// @notice Extended interface for backrun execution agents
interface IBackrunAgent is ISwarmAgent {
    /// @notice Backrun opportunity details
    struct BackrunOpportunity {
        bool shouldBackrun;         // Whether backrun is profitable
        uint256 backrunAmount;      // Optimal backrun size
        uint256 expectedProfit;     // Expected profit
        bool zeroForOne;            // Backrun direction
        uint256 targetPrice;        // Target price to restore
    }

    /// @notice Analyze backrun opportunity after a swap
    /// @param context The swap context
    /// @param newPoolPrice Pool price after swap
    /// @return opportunity Backrun analysis
    function analyzeBackrun(
        SwapContext calldata context,
        uint256 newPoolPrice
    ) external view returns (BackrunOpportunity memory opportunity);

    /// @notice Execute a backrun (requires flash loan or capital)
    /// @param context The swap context
    /// @param opportunity The backrun opportunity
    /// @return success Whether backrun executed successfully
    /// @return profit Actual profit captured
    function executeBackrun(
        SwapContext calldata context,
        BackrunOpportunity calldata opportunity
    ) external returns (bool success, uint256 profit);
}
