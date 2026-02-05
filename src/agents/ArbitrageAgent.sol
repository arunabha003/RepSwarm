// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {SwarmAgentBase} from "./base/SwarmAgentBase.sol";
import {ISwarmAgent, IArbitrageAgent, AgentType, SwapContext, AgentResult} from "../interfaces/ISwarmAgent.sol";

/// @title ArbitrageAgent
/// @notice Detects and captures MEV/arbitrage opportunities
/// @dev Implements IArbitrageAgent - contains ALL arbitrage logic (moved from hook)
/// @dev ERC-8004 compatible - can be registered with identity registry
contract ArbitrageAgent is SwarmAgentBase, IArbitrageAgent {
    // ============ Constants ============

    /// @notice Price precision (18 decimals)
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Basis points scale
    uint256 public constant BASIS_POINTS = 10_000;

    /// @notice Minimum confidence threshold (0.1%)
    uint256 public constant MIN_CONFIDENCE_BPS = 10;

    // ============ Configuration ============

    /// @notice Hook's share of captured MEV (basis points)
    uint256 public hookShareBps;

    /// @notice Minimum divergence to trigger capture (basis points)
    uint256 public minDivergenceBps;

    /// @notice Maximum capture ratio (prevents over-capture)
    uint256 public maxCaptureRatio;

    // ============ Events ============

    event ConfigUpdated(uint256 hookShareBps, uint256 minDivergenceBps, uint256 maxCaptureRatio);

    // ============ Constructor ============

    constructor(
        IPoolManager _poolManager,
        address _owner,
        uint256 _hookShareBps,
        uint256 _minDivergenceBps
    ) SwarmAgentBase(_poolManager, _owner) {
        hookShareBps = _hookShareBps;
        minDivergenceBps = _minDivergenceBps;
        maxCaptureRatio = 5000; // 50% max capture by default
    }

    // ============ ISwarmAgent Implementation ============

    /// @inheritdoc ISwarmAgent
    function agentType() external pure override returns (AgentType) {
        return AgentType.ARBITRAGE;
    }

    /// @inheritdoc SwarmAgentBase
    function _execute(
        SwapContext calldata context
    ) internal override returns (AgentResult memory result) {
        ArbitrageResult memory arbResult = _analyzeArbitrage(context);
        
        result.shouldAct = arbResult.shouldCapture;
        result.value = arbResult.hookShare;
        result.secondaryValue = arbResult.arbitrageAmount;
        result.data = abi.encode(arbResult);
    }

    /// @inheritdoc SwarmAgentBase
    function _getRecommendation(
        SwapContext calldata context
    ) internal view override returns (AgentResult memory result) {
        ArbitrageResult memory arbResult = _analyzeArbitrage(context);
        
        result.shouldAct = arbResult.shouldCapture;
        result.value = arbResult.hookShare;
        result.secondaryValue = arbResult.arbitrageAmount;
        result.data = abi.encode(arbResult);
    }

    // ============ IArbitrageAgent Implementation ============

    /// @inheritdoc IArbitrageAgent
    function analyzeArbitrage(
        SwapContext calldata context
    ) external view override returns (ArbitrageResult memory result) {
        return _analyzeArbitrage(context);
    }

    // ============ Core Logic (Moved from Hook) ============

    /// @notice Internal arbitrage analysis - THE CORE LOGIC
    function _analyzeArbitrage(
        SwapContext calldata context
    ) internal view returns (ArbitrageResult memory result) {
        // Validate inputs
        if (context.poolPrice == 0 || context.oraclePrice == 0) {
            return result;
        }

        // Calculate price divergence in basis points
        result.divergenceBps = _calculateDivergenceBps(
            context.poolPrice,
            context.oraclePrice
        );

        // Check if outside oracle confidence band
        result.isOutsideConfidence = _isOutsideConfidenceBand(
            context.poolPrice,
            context.oraclePrice,
            context.oracleConfidence
        );

        // Determine if we should capture
        // Must be: outside confidence band AND divergence > threshold AND advantageous direction
        bool isAdvantageous = _isArbitrageAdvantageous(
            context.poolPrice,
            context.oraclePrice,
            context.params.zeroForOne
        );

        result.shouldCapture = result.isOutsideConfidence 
            && result.divergenceBps >= minDivergenceBps
            && isAdvantageous;

        if (!result.shouldCapture) {
            return result;
        }

        // Calculate arbitrage opportunity
        uint256 swapAmount = _getSwapAmount(context.params.amountSpecified);
        result.arbitrageAmount = _calculateArbitrageOpportunity(
            context.poolPrice,
            context.oraclePrice,
            context.oracleConfidence,
            swapAmount,
            context.params.zeroForOne
        );

        // Calculate hook share
        if (result.arbitrageAmount > 0) {
            result.hookShare = FullMath.mulDiv(
                result.arbitrageAmount,
                hookShareBps,
                BASIS_POINTS
            );

            // Apply capture ratio cap
            uint256 maxCapture = FullMath.mulDiv(swapAmount, maxCaptureRatio, BASIS_POINTS);
            if (result.hookShare > maxCapture) {
                result.hookShare = maxCapture;
            }
        }
    }

    /// @notice Calculate price divergence in basis points
    function _calculateDivergenceBps(
        uint256 poolPrice,
        uint256 oraclePrice
    ) internal pure returns (uint256 divergenceBps) {
        if (oraclePrice == 0) return 0;
        
        if (poolPrice > oraclePrice) {
            divergenceBps = FullMath.mulDiv(poolPrice - oraclePrice, BASIS_POINTS, oraclePrice);
        } else {
            divergenceBps = FullMath.mulDiv(oraclePrice - poolPrice, BASIS_POINTS, oraclePrice);
        }
    }

    /// @notice Check if pool price is outside oracle confidence band
    function _isOutsideConfidenceBand(
        uint256 poolPrice,
        uint256 oraclePrice,
        uint256 oracleConfidence
    ) internal pure returns (bool) {
        if (oraclePrice == 0 || poolPrice == 0) return false;
        
        // Calculate bounds
        uint256 minConfidence = FullMath.mulDiv(oraclePrice, MIN_CONFIDENCE_BPS, BASIS_POINTS);
        uint256 effectiveConfidence = oracleConfidence > minConfidence ? oracleConfidence : minConfidence;
        
        uint256 lower = oraclePrice > effectiveConfidence ? oraclePrice - effectiveConfidence : 0;
        uint256 upper = oraclePrice + effectiveConfidence;
        
        return poolPrice < lower || poolPrice > upper;
    }

    /// @notice Determine if arbitrage is advantageous for the swap direction
    function _isArbitrageAdvantageous(
        uint256 poolPrice,
        uint256 oraclePrice,
        bool zeroForOne
    ) internal pure returns (bool) {
        if (zeroForOne) {
            // Selling token0 for token1 - advantageous if pool gives better rate
            return poolPrice > oraclePrice;
        } else {
            // Selling token1 for token0 - advantageous if pool gives better rate
            return poolPrice < oraclePrice;
        }
    }

    /// @notice Calculate raw arbitrage opportunity
    function _calculateArbitrageOpportunity(
        uint256 poolPrice,
        uint256 oraclePrice,
        uint256 oracleConfidence,
        uint256 swapAmount,
        bool zeroForOne
    ) internal pure returns (uint256 opportunity) {
        if (swapAmount == 0 || oraclePrice == 0 || poolPrice == 0) {
            return 0;
        }

        // Calculate bounds
        uint256 minConfidence = FullMath.mulDiv(oraclePrice, MIN_CONFIDENCE_BPS, BASIS_POINTS);
        uint256 effectiveConfidence = oracleConfidence > minConfidence ? oracleConfidence : minConfidence;
        
        uint256 priceLower = oraclePrice > effectiveConfidence ? oraclePrice - effectiveConfidence : 0;
        uint256 priceUpper = oraclePrice + effectiveConfidence;

        if (zeroForOne) {
            // Use upper bound for conservative calculation
            if (poolPrice <= priceUpper) return 0;
            uint256 priceDiff = poolPrice - priceUpper;
            opportunity = FullMath.mulDiv(swapAmount, priceDiff, PRICE_PRECISION);
        } else {
            // Use lower bound for conservative calculation
            if (poolPrice >= priceLower) return 0;
            uint256 priceDiff = priceLower - poolPrice;
            opportunity = FullMath.mulDiv(swapAmount, priceDiff, PRICE_PRECISION);
        }
    }

    /// @notice Get absolute swap amount from amountSpecified
    function _getSwapAmount(int256 amountSpecified) internal pure returns (uint256) {
        return amountSpecified < 0 ? uint256(-amountSpecified) : uint256(amountSpecified);
    }

    // ============ Admin Functions ============

    /// @notice Update arbitrage configuration
    function setConfig(
        uint256 _hookShareBps,
        uint256 _minDivergenceBps,
        uint256 _maxCaptureRatio
    ) external onlyOwner {
        require(_hookShareBps <= BASIS_POINTS, "Invalid hook share");
        require(_minDivergenceBps <= BASIS_POINTS, "Invalid divergence");
        require(_maxCaptureRatio <= BASIS_POINTS, "Invalid capture ratio");
        
        hookShareBps = _hookShareBps;
        minDivergenceBps = _minDivergenceBps;
        maxCaptureRatio = _maxCaptureRatio;
        
        emit ConfigUpdated(_hookShareBps, _minDivergenceBps, _maxCaptureRatio);
    }
}
