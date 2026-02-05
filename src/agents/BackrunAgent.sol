// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {SwarmAgentBase} from "./base/SwarmAgentBase.sol";
import {ISwarmAgent, IBackrunAgent, AgentType, SwapContext, AgentResult} from "../interfaces/ISwarmAgent.sol";
import {LPFeeAccumulator} from "../LPFeeAccumulator.sol";

/// @title BackrunAgent
/// @notice Detects and executes backrun opportunities after swaps
/// @dev Implements IBackrunAgent - contains ALL backrun logic (moved from hook)
/// @dev ERC-8004 compatible - can be registered with identity registry
contract BackrunAgent is SwarmAgentBase, IBackrunAgent {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    // ============ Constants ============

    /// @notice Price precision
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Basis points scale
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Minimum profit threshold (basis points)
    uint256 public constant MIN_PROFIT_BPS = 10;

    /// @notice Maximum backrun as percentage of liquidity
    uint256 public constant MAX_BACKRUN_RATIO = 5000; // 50%

    // ============ Configuration ============

    /// @notice LP fee accumulator for profit distribution
    LPFeeAccumulator public lpFeeAccumulator;

    /// @notice Share of profit going to LPs (basis points)
    uint256 public lpShareBps;

    /// @notice Minimum price divergence for backrun (basis points)
    uint256 public minDivergenceBps;

    /// @notice Maximum blocks to store opportunity
    uint256 public maxOpportunityAge;

    // ============ State ============

    /// @notice Pending backrun opportunities
    mapping(bytes32 => BackrunOpportunity) public pendingOpportunities;

    /// @notice Timestamp of pending opportunities
    mapping(bytes32 => uint256) public opportunityTimestamp;

    /// @notice Total profits captured per pool
    mapping(bytes32 => uint256) public totalProfits;

    // ============ Events ============

    event BackrunOpportunityDetected(
        bytes32 indexed poolId,
        uint256 backrunAmount,
        uint256 expectedProfit,
        bool zeroForOne
    );

    event BackrunExecuted(
        bytes32 indexed poolId,
        uint256 profit,
        uint256 lpShare,
        address executor
    );

    event ConfigUpdated(uint256 lpShareBps, uint256 minDivergenceBps);

    // ============ Constructor ============

    constructor(
        IPoolManager _poolManager,
        address _owner
    ) SwarmAgentBase(_poolManager, _owner) {
        lpShareBps = 8000;        // 80% to LPs
        minDivergenceBps = 30;    // 0.3% minimum divergence
        maxOpportunityAge = 2;    // 2 blocks max
    }

    // ============ ISwarmAgent Implementation ============

    /// @inheritdoc ISwarmAgent
    function agentType() external pure override returns (AgentType) {
        return AgentType.BACKRUN;
    }

    /// @inheritdoc SwarmAgentBase
    function _execute(
        SwapContext calldata context
    ) internal override returns (AgentResult memory result) {
        // For execute, we analyze and store the opportunity
        BackrunOpportunity memory opportunity = _analyzeBackrun(
            context,
            context.poolPrice // Use current price as "new" price in execute context
        );
        
        if (opportunity.shouldBackrun) {
            bytes32 poolIdBytes = bytes32(PoolId.unwrap(context.poolId));
            pendingOpportunities[poolIdBytes] = opportunity;
            opportunityTimestamp[poolIdBytes] = block.number;
            
            emit BackrunOpportunityDetected(
                poolIdBytes,
                opportunity.backrunAmount,
                opportunity.expectedProfit,
                opportunity.zeroForOne
            );
        }
        
        result.shouldAct = opportunity.shouldBackrun;
        result.value = opportunity.backrunAmount;
        result.secondaryValue = opportunity.expectedProfit;
        result.data = abi.encode(opportunity);
    }

    /// @inheritdoc SwarmAgentBase
    function _getRecommendation(
        SwapContext calldata context
    ) internal view override returns (AgentResult memory result) {
        BackrunOpportunity memory opportunity = _analyzeBackrun(
            context,
            context.poolPrice
        );
        
        result.shouldAct = opportunity.shouldBackrun;
        result.value = opportunity.backrunAmount;
        result.secondaryValue = opportunity.expectedProfit;
        result.data = abi.encode(opportunity);
    }

    // ============ IBackrunAgent Implementation ============

    /// @inheritdoc IBackrunAgent
    function analyzeBackrun(
        SwapContext calldata context,
        uint256 newPoolPrice
    ) external view override returns (BackrunOpportunity memory opportunity) {
        return _analyzeBackrun(context, newPoolPrice);
    }

    /// @inheritdoc IBackrunAgent
    function executeBackrun(
        SwapContext calldata context,
        BackrunOpportunity calldata opportunity
    ) external override onlyAuthorized returns (bool success, uint256 profit) {
        bytes32 poolIdBytes = bytes32(PoolId.unwrap(context.poolId));
        
        // Verify opportunity is still valid
        BackrunOpportunity storage stored = pendingOpportunities[poolIdBytes];
        if (!stored.shouldBackrun || stored.backrunAmount == 0) {
            return (false, 0);
        }
        
        // Check age
        if (block.number > opportunityTimestamp[poolIdBytes] + maxOpportunityAge) {
            delete pendingOpportunities[poolIdBytes];
            return (false, 0);
        }
        
        // Mark as executed
        delete pendingOpportunities[poolIdBytes];
        
        // In production, this would execute the actual backrun swap
        // For now, we just record the expected profit
        profit = opportunity.expectedProfit;
        
        // Distribute profit
        if (profit > 0 && address(lpFeeAccumulator) != address(0)) {
            uint256 lpShare = FullMath.mulDiv(profit, lpShareBps, BASIS_POINTS);
            // Transfer would happen here in real implementation
            totalProfits[poolIdBytes] += profit;
        }
        
        emit BackrunExecuted(poolIdBytes, profit, 0, msg.sender);
        
        return (true, profit);
    }

    // ============ Core Logic ============

    /// @notice Analyze backrun opportunity - THE CORE LOGIC
    function _analyzeBackrun(
        SwapContext calldata context,
        uint256 newPoolPrice
    ) internal view returns (BackrunOpportunity memory opportunity) {
        // Need valid prices
        if (context.oraclePrice == 0 || newPoolPrice == 0) {
            return opportunity;
        }

        // Calculate divergence after swap
        uint256 divergenceBps;
        if (newPoolPrice > context.oraclePrice) {
            divergenceBps = FullMath.mulDiv(
                newPoolPrice - context.oraclePrice,
                BASIS_POINTS,
                context.oraclePrice
            );
        } else {
            divergenceBps = FullMath.mulDiv(
                context.oraclePrice - newPoolPrice,
                BASIS_POINTS,
                context.oraclePrice
            );
        }

        // Check if worth backrunning
        if (divergenceBps < minDivergenceBps) {
            return opportunity;
        }

        // Determine backrun direction (opposite of original swap)
        bool backrunZeroForOne = !context.params.zeroForOne;
        opportunity.zeroForOne = backrunZeroForOne;
        opportunity.targetPrice = context.oraclePrice;

        // Calculate backrun amount to restore price
        opportunity.backrunAmount = _calculateBackrunAmount(
            newPoolPrice,
            context.oraclePrice,
            context.liquidity,
            backrunZeroForOne
        );

        if (opportunity.backrunAmount == 0) {
            return opportunity;
        }

        // Estimate profit
        uint256 priceDiff;
        if (newPoolPrice > context.oraclePrice) {
            priceDiff = newPoolPrice - context.oraclePrice;
        } else {
            priceDiff = context.oraclePrice - newPoolPrice;
        }

        opportunity.expectedProfit = FullMath.mulDiv(
            opportunity.backrunAmount,
            priceDiff,
            PRICE_PRECISION
        );

        // Check if profitable after gas/slippage
        uint256 minProfit = FullMath.mulDiv(
            opportunity.backrunAmount,
            MIN_PROFIT_BPS,
            BASIS_POINTS
        );

        opportunity.shouldBackrun = opportunity.expectedProfit > minProfit;
    }

    /// @notice Calculate optimal backrun amount
    function _calculateBackrunAmount(
        uint256 poolPrice,
        uint256 oraclePrice,
        uint128 liquidity,
        bool zeroForOne
    ) internal pure returns (uint256 backrunAmount) {
        if (liquidity == 0 || poolPrice == 0 || oraclePrice == 0) {
            return 0;
        }

        uint256 priceDiff;
        if (zeroForOne) {
            // Backrun sells token0 for token1
            // Price should decrease toward oracle
            if (poolPrice <= oraclePrice) return 0;
            priceDiff = poolPrice - oraclePrice;
        } else {
            // Backrun sells token1 for token0
            // Price should increase toward oracle
            if (poolPrice >= oraclePrice) return 0;
            priceDiff = oraclePrice - poolPrice;
        }

        // Amount ≈ liquidity * priceDiff / oraclePrice
        backrunAmount = FullMath.mulDiv(
            uint256(liquidity),
            priceDiff,
            oraclePrice
        );

        // Cap at maximum ratio
        uint256 maxBackrun = FullMath.mulDiv(
            uint256(liquidity),
            MAX_BACKRUN_RATIO,
            BASIS_POINTS
        );
        
        if (backrunAmount > maxBackrun) {
            backrunAmount = maxBackrun;
        }
    }

    // ============ Admin Functions ============

    /// @notice Set LP fee accumulator
    function setLPFeeAccumulator(address _accumulator) external onlyOwner {
        lpFeeAccumulator = LPFeeAccumulator(payable(_accumulator));
    }

    /// @notice Update configuration
    function setConfig(
        uint256 _lpShareBps,
        uint256 _minDivergenceBps,
        uint256 _maxOpportunityAge
    ) external onlyOwner {
        require(_lpShareBps <= BASIS_POINTS, "Invalid LP share");
        
        lpShareBps = _lpShareBps;
        minDivergenceBps = _minDivergenceBps;
        maxOpportunityAge = _maxOpportunityAge;
        
        emit ConfigUpdated(_lpShareBps, _minDivergenceBps);
    }

    // ============ View Functions ============

    /// @notice Get pending opportunity for a pool
    function getPendingOpportunity(
        bytes32 poolId
    ) external view returns (BackrunOpportunity memory, bool isValid) {
        BackrunOpportunity storage opp = pendingOpportunities[poolId];
        uint256 timestamp = opportunityTimestamp[poolId];
        
        isValid = opp.shouldBackrun && 
                  block.number <= timestamp + maxOpportunityAge;
        
        return (opp, isValid);
    }

    /// @notice Get total profits for a pool
    function getPoolProfits(bytes32 poolId) external view returns (uint256) {
        return totalProfits[poolId];
    }
}
