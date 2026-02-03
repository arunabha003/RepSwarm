// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @title ArbitrageLib
/// @notice Library for production-grade arbitrage opportunity calculations
/// @dev Adapted from detox-hook patterns with confidence interval support
library ArbitrageLib {
    /// @notice Precision for price calculations (18 decimals)
    uint256 internal constant PRICE_PRECISION = 1e18;
    
    /// @notice Basis points scale
    uint256 internal constant BASIS_POINTS = 10_000;
    
    /// @notice Minimum confidence threshold (0.1%)
    uint256 internal constant MIN_CONFIDENCE_BPS = 10;

    /// @notice Parameters for arbitrage calculation
    /// @param poolPrice Pool price (token1/token0) scaled to PRICE_PRECISION
    /// @param oraclePrice Oracle price scaled to PRICE_PRECISION  
    /// @param oracleConfidence Oracle confidence interval scaled to PRICE_PRECISION
    /// @param swapAmount The exact input amount for the swap
    /// @param zeroForOne The swap direction (true = token0 → token1)
    struct ArbitrageParams {
        uint256 poolPrice;
        uint256 oraclePrice;
        uint256 oracleConfidence;
        uint256 swapAmount;
        bool zeroForOne;
    }

    /// @notice Result of arbitrage calculation
    /// @param arbitrageOpportunity The total arbitrage opportunity amount
    /// @param shouldInterfere Whether the opportunity exceeds the threshold
    /// @param hookShare The amount the hook should capture
    /// @param isOutsideConfidenceBand Whether pool price is outside oracle confidence band
    /// @param priceDivergenceBps Price divergence in basis points
    struct ArbitrageResult {
        uint256 arbitrageOpportunity;
        bool shouldInterfere;
        uint256 hookShare;
        bool isOutsideConfidenceBand;
        uint256 priceDivergenceBps;
    }

    /// @notice Calculate market price bounds using oracle confidence interval
    /// @param oraclePrice Oracle price
    /// @param oracleConfidence Confidence interval
    /// @return lower Lower bound of market price
    /// @return upper Upper bound of market price
    function calculatePriceBounds(
        uint256 oraclePrice,
        uint256 oracleConfidence
    ) internal pure returns (uint256 lower, uint256 upper) {
        if (oraclePrice == 0) return (0, 0);
        
        // Ensure minimum confidence interval
        uint256 minConfidence = FullMath.mulDiv(oraclePrice, MIN_CONFIDENCE_BPS, BASIS_POINTS);
        uint256 effectiveConfidence = oracleConfidence > minConfidence ? oracleConfidence : minConfidence;
        
        lower = oraclePrice > effectiveConfidence ? oraclePrice - effectiveConfidence : 0;
        upper = oraclePrice + effectiveConfidence;
    }

    /// @notice Check if pool price is outside oracle confidence band
    /// @param poolPrice The current pool price
    /// @param oraclePrice The oracle reference price
    /// @param oracleConfidence The oracle confidence interval
    /// @return isOutside True if pool price is outside confidence bounds
    function isOutsideConfidenceBand(
        uint256 poolPrice,
        uint256 oraclePrice,
        uint256 oracleConfidence
    ) internal pure returns (bool isOutside) {
        if (oraclePrice == 0 || poolPrice == 0) return false;
        
        (uint256 lower, uint256 upper) = calculatePriceBounds(oraclePrice, oracleConfidence);
        return poolPrice < lower || poolPrice > upper;
    }

    /// @notice Calculate price divergence in basis points
    /// @param poolPrice The pool price
    /// @param oraclePrice The oracle price  
    /// @return divergenceBps Absolute divergence in basis points
    function calculateDivergenceBps(
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

    /// @notice Determine if arbitrage is advantageous for the direction
    /// @param poolPrice The pool price
    /// @param oraclePrice The oracle (fair market) price
    /// @param zeroForOne The swap direction
    /// @return isAdvantageous Whether the swap direction benefits from the deviation
    function isArbitrageAdvantageous(
        uint256 poolPrice,
        uint256 oraclePrice,
        bool zeroForOne
    ) internal pure returns (bool isAdvantageous) {
        if (zeroForOne) {
            // Selling token0 for token1
            // Advantageous if pool gives better rate (poolPrice > oraclePrice)
            return poolPrice > oraclePrice;
        } else {
            // Selling token1 for token0
            // Advantageous if pool gives better rate (poolPrice < oraclePrice)
            return poolPrice < oraclePrice;
        }
    }

    /// @notice Calculate the raw arbitrage opportunity amount
    /// @param params The arbitrage parameters
    /// @return opportunity The arbitrage opportunity in input token units
    function calculateArbitrageOpportunity(
        ArbitrageParams memory params
    ) internal pure returns (uint256 opportunity) {
        if (params.swapAmount == 0 || params.oraclePrice == 0 || params.poolPrice == 0) {
            return 0;
        }

        // Calculate bounds with confidence
        (uint256 priceLower, uint256 priceUpper) = calculatePriceBounds(
            params.oraclePrice,
            params.oracleConfidence
        );

        if (params.zeroForOne) {
            // zeroForOne: selling token0 for token1
            // Use upper bound for conservative calculation (worst case for arbitrager)
            if (params.poolPrice <= priceUpper) return 0;
            
            uint256 priceDiff = params.poolPrice - priceUpper;
            opportunity = FullMath.mulDiv(params.swapAmount, priceDiff, PRICE_PRECISION);
        } else {
            // oneForZero: selling token1 for token0
            // Use lower bound for conservative calculation
            if (params.poolPrice >= priceLower) return 0;
            
            uint256 priceDiff = priceLower - params.poolPrice;
            opportunity = FullMath.mulDiv(params.swapAmount, priceDiff, PRICE_PRECISION);
        }
    }

    /// @notice Calculate hook's share of the arbitrage opportunity
    /// @param arbitrageOpp The total arbitrage opportunity
    /// @param hookShareBps The hook's share in basis points
    /// @return hookShare The amount the hook should capture
    function calculateHookShare(
        uint256 arbitrageOpp,
        uint256 hookShareBps
    ) internal pure returns (uint256 hookShare) {
        if (arbitrageOpp == 0 || hookShareBps == 0) return 0;
        hookShare = FullMath.mulDiv(arbitrageOpp, hookShareBps, BASIS_POINTS);
    }

    /// @notice Comprehensive arbitrage analysis
    /// @param params The arbitrage parameters
    /// @param hookShareBps The hook's share in basis points (e.g., 8000 = 80%)
    /// @param minDivergenceBps Minimum divergence to trigger interference
    /// @return result Complete arbitrage analysis result
    function analyzeArbitrageOpportunity(
        ArbitrageParams memory params,
        uint256 hookShareBps,
        uint256 minDivergenceBps
    ) internal pure returns (ArbitrageResult memory result) {
        // Calculate price divergence
        result.priceDivergenceBps = calculateDivergenceBps(params.poolPrice, params.oraclePrice);
        
        // Check if outside confidence band
        result.isOutsideConfidenceBand = isOutsideConfidenceBand(
            params.poolPrice,
            params.oraclePrice,
            params.oracleConfidence
        );
        
        // Determine if we should interfere
        // Must be: outside confidence band AND divergence > threshold AND advantageous direction
        result.shouldInterfere = result.isOutsideConfidenceBand 
            && result.priceDivergenceBps >= minDivergenceBps
            && isArbitrageAdvantageous(params.poolPrice, params.oraclePrice, params.zeroForOne);
        
        // Calculate arbitrage opportunity
        result.arbitrageOpportunity = calculateArbitrageOpportunity(params);
        
        // Calculate hook share if interfering
        if (result.shouldInterfere && result.arbitrageOpportunity > 0) {
            result.hookShare = calculateHookShare(result.arbitrageOpportunity, hookShareBps);
        }
    }

    /// @notice Calculate the backrun amount that would restore price to oracle level
    /// @param poolPrice Current pool price
    /// @param oraclePrice Target oracle price
    /// @param liquidity Pool liquidity
    /// @param zeroForOne Direction of the original swap
    /// @return backrunAmount Amount needed to backrun
    function calculateBackrunAmount(
        uint256 poolPrice,
        uint256 oraclePrice,
        uint128 liquidity,
        bool zeroForOne
    ) internal pure returns (uint256 backrunAmount) {
        if (liquidity == 0 || poolPrice == 0 || oraclePrice == 0) return 0;
        
        // Calculate the price difference
        uint256 priceDiff;
        if (zeroForOne) {
            // After zeroForOne swap, price has decreased
            // Need to buy token0 with token1 to restore price
            if (poolPrice >= oraclePrice) return 0;
            priceDiff = oraclePrice - poolPrice;
        } else {
            // After oneForZero swap, price has increased
            // Need to sell token0 for token1 to restore price
            if (poolPrice <= oraclePrice) return 0;
            priceDiff = poolPrice - oraclePrice;
        }
        
        // Approximate backrun amount based on liquidity and price change
        // backrunAmount ≈ liquidity * priceDiff / oraclePrice
        // This is a simplified calculation - real implementation would use SwapMath
        backrunAmount = FullMath.mulDiv(uint256(liquidity), priceDiff, oraclePrice);
        
        // Cap at a reasonable maximum (50% of liquidity)
        uint256 maxBackrun = uint256(liquidity) / 2;
        if (backrunAmount > maxBackrun) {
            backrunAmount = maxBackrun;
        }
    }
}
