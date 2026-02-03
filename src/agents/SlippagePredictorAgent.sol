// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SwarmAgentBase} from "./SwarmAgentBase.sol";
import {ISwarmCoordinator} from "../interfaces/ISwarmCoordinator.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SwapMath} from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/// @title SlippagePredictorAgent - Production-Grade Slippage Prediction
/// @notice Predicts actual swap slippage using Uniswap v4 SwapMath
/// @dev Uses computeSwapStep to simulate real swap execution step-by-step
/// @dev Based on v4-core SwapMath library (github.com/Uniswap/v4-core)
contract SlippagePredictorAgent is SwarmAgentBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @notice Precision for slippage calculations (basis points scaled)
    uint256 private constant BPS_SCALE = 10_000;
    
    /// @notice Precision for price calculations
    uint256 private constant PRICE_SCALE = 1e18;
    
    /// @notice Maximum acceptable slippage score (very high slippage - DON'T EXECUTE)
    int256 private constant MAX_SLIPPAGE_SCORE = 1000;

    /// @notice Slippage thresholds in basis points
    uint256 private constant LOW_SLIPPAGE_BPS = 10;      // 0.1% - excellent
    uint256 private constant MODERATE_SLIPPAGE_BPS = 50; // 0.5% - acceptable
    uint256 private constant HIGH_SLIPPAGE_BPS = 100;    // 1% - concerning
    uint256 private constant CRITICAL_SLIPPAGE_BPS = 300; // 3% - dangerous

    /// @notice Slippage prediction results
    struct SlippagePrediction {
        uint256 expectedOutputWad;     // Expected output at ideal price (no slippage)
        uint256 simulatedOutputWad;    // Simulated output after swap
        uint256 slippageBps;           // Actual slippage in basis points
        uint256 priceImpactBps;        // Price impact in basis points
        uint256 effectiveFeesBps;      // Total fees including LP fee
        uint128 availableLiquidity;    // Liquidity available for the swap
        bool insufficientLiquidity;    // True if swap would fail
    }

    event SlippageAnalysisCompleted(
        uint256 indexed intentId,
        uint256 expectedOutput,
        uint256 simulatedOutput,
        uint256 slippageBps,
        int256 score
    );

    constructor(
        ISwarmCoordinator coordinator_,
        IPoolManager poolManager_
    ) SwarmAgentBase(coordinator_, poolManager_) {}

    /// @notice Score a candidate path based on predicted slippage
    /// @dev Uses SwapMath to simulate actual swap execution
    /// @param intent The swap intent details
    /// @param path The candidate swap path
    /// @return score Lower = better (less slippage), Higher = worse
    function _score(ISwarmCoordinator.IntentView memory intent, PathKey[] memory path)
        internal
        view
        override
        returns (int256)
    {
        if (path.length == 0) return MAX_SLIPPAGE_SCORE;

        int256 totalScore = 0;
        Currency currentCurrency = intent.currencyIn;
        uint256 currentAmount = intent.amountIn;

        for (uint256 i = 0; i < path.length; i++) {
            SlippagePrediction memory prediction = _predictSlippage(
                path[i],
                currentCurrency,
                currentAmount
            );

            // Calculate score for this hop
            int256 hopScore = _calculateSlippageScore(prediction);
            totalScore += hopScore;

            // Use simulated output as input for next hop
            currentAmount = prediction.simulatedOutputWad;
            currentCurrency = path[i].intermediateCurrency;
        }

        // Average score across hops
        return totalScore / int256(path.length);
    }

    /// @notice Predict slippage for a single swap step using SwapMath
    /// @param step The path step (pool hop)
    /// @param currencyIn The input currency
    /// @param amountIn The input amount
    /// @return prediction The slippage prediction results
    function _predictSlippage(
        PathKey memory step,
        Currency currencyIn,
        uint256 amountIn
    ) internal view returns (SlippagePrediction memory prediction) {
        // Build pool key and get metrics
        (PoolKey memory key, uint24 lpFee, uint128 liquidity) = _poolMetrics(step, currencyIn);
        PoolId poolId = key.toId();

        // Get current pool state
        (uint160 sqrtPriceX96, int24 currentTick,,) = poolManager.getSlot0(poolId);
        
        prediction.availableLiquidity = liquidity;

        // Check for insufficient liquidity
        if (liquidity == 0) {
            prediction.insufficientLiquidity = true;
            return prediction;
        }

        // Determine swap direction
        bool zeroForOne = currencyIn == key.currency0;
        
        // Calculate expected output at current price (no slippage - ideal case)
        prediction.expectedOutputWad = _calculateIdealOutput(
            sqrtPriceX96,
            amountIn,
            zeroForOne
        );

        // Simulate the actual swap using SwapMath.computeSwapStep
        (uint256 simulatedOutput, uint256 priceImpactBps, uint256 feesPaid) = _simulateSwap(
            sqrtPriceX96,
            liquidity,
            amountIn,
            lpFee,
            zeroForOne
        );

        prediction.simulatedOutputWad = simulatedOutput;
        prediction.priceImpactBps = priceImpactBps;
        prediction.effectiveFeesBps = (feesPaid * BPS_SCALE) / amountIn;

        // Calculate actual slippage
        if (prediction.expectedOutputWad > 0) {
            if (simulatedOutput < prediction.expectedOutputWad) {
                prediction.slippageBps = ((prediction.expectedOutputWad - simulatedOutput) * BPS_SCALE) 
                    / prediction.expectedOutputWad;
            }
        }

        // Check if liquidity is sufficient for the swap
        if (simulatedOutput == 0 && amountIn > 0) {
            prediction.insufficientLiquidity = true;
        }
    }

    /// @notice Calculate ideal output at current price (no slippage)
    /// @param sqrtPriceX96 Current sqrt price
    /// @param amountIn Input amount
    /// @param zeroForOne Swap direction
    /// @return idealOutput Expected output at spot price
    function _calculateIdealOutput(
        uint160 sqrtPriceX96,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint256 idealOutput) {
        // Convert sqrtPriceX96 to price
        // price = (sqrtPriceX96 / 2^96)^2
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 priceX192 = sqrtPrice * sqrtPrice;
        
        if (zeroForOne) {
            // Selling token0 for token1: output = input * price
            // price = token1/token0, so output_token1 = input_token0 * price
            idealOutput = FullMath.mulDiv(amountIn, priceX192, 1 << 192);
        } else {
            // Selling token1 for token0: output = input / price
            // output_token0 = input_token1 / price
            if (priceX192 > 0) {
                idealOutput = FullMath.mulDiv(amountIn, 1 << 192, priceX192);
            }
        }
    }

    /// @notice Simulate swap execution using SwapMath.computeSwapStep
    /// @param sqrtPriceX96 Current sqrt price
    /// @param liquidity Available liquidity
    /// @param amountIn Input amount
    /// @param feePips LP fee in hundredths of a bip
    /// @param zeroForOne Swap direction
    /// @return amountOut Simulated output amount
    /// @return priceImpactBps Price impact in basis points
    /// @return feesPaid Total fees paid
    function _simulateSwap(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 amountIn,
        uint24 feePips,
        bool zeroForOne
    ) internal pure returns (uint256 amountOut, uint256 priceImpactBps, uint256 feesPaid) {
        // Determine price limit based on direction
        uint160 sqrtPriceLimitX96 = zeroForOne 
            ? TickMath.MIN_SQRT_PRICE + 1 
            : TickMath.MAX_SQRT_PRICE - 1;

        // Get the price target for this step
        uint160 sqrtPriceTargetX96 = SwapMath.getSqrtPriceTarget(
            zeroForOne,
            sqrtPriceLimitX96,  // Use limit as next tick price (worst case)
            sqrtPriceLimitX96
        );

        // Compute the swap step
        // amountSpecified is negative for exact input swaps
        int256 amountSpecified = -int256(amountIn);
        
        (
            uint160 sqrtPriceNextX96,
            uint256 amountInUsed,
            uint256 amountOutResult,
            uint256 feeAmount
        ) = SwapMath.computeSwapStep(
            sqrtPriceX96,
            sqrtPriceTargetX96,
            liquidity,
            amountSpecified,
            feePips
        );

        amountOut = amountOutResult;
        feesPaid = feeAmount;

        // Calculate price impact
        // priceImpact = |newPrice - oldPrice| / oldPrice
        if (sqrtPriceX96 > 0) {
            uint256 oldPriceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
            uint256 newPriceX192 = uint256(sqrtPriceNextX96) * uint256(sqrtPriceNextX96);
            
            if (oldPriceX192 > newPriceX192) {
                priceImpactBps = ((oldPriceX192 - newPriceX192) * BPS_SCALE) / oldPriceX192;
            } else {
                priceImpactBps = ((newPriceX192 - oldPriceX192) * BPS_SCALE) / oldPriceX192;
            }
        }
    }

    /// @notice Calculate score based on slippage prediction
    /// @dev Lower scores = better (less slippage, recommend execution)
    /// @dev Higher scores = worse (high slippage, recommend rejection)
    /// @param prediction The slippage prediction
    /// @return score The slippage score
    function _calculateSlippageScore(
        SlippagePrediction memory prediction
    ) internal pure returns (int256 score) {
        // Insufficient liquidity = maximum penalty
        if (prediction.insufficientLiquidity) {
            return MAX_SLIPPAGE_SCORE;
        }

        // === SLIPPAGE-BASED SCORING ===
        
        if (prediction.slippageBps >= CRITICAL_SLIPPAGE_BPS) {
            // Critical slippage (>3%): Very high penalty
            score = int256(300 + (prediction.slippageBps - CRITICAL_SLIPPAGE_BPS) / 2);
        } else if (prediction.slippageBps >= HIGH_SLIPPAGE_BPS) {
            // High slippage (1-3%): Moderate penalty
            score = int256(100 + (prediction.slippageBps - HIGH_SLIPPAGE_BPS));
        } else if (prediction.slippageBps >= MODERATE_SLIPPAGE_BPS) {
            // Moderate slippage (0.5-1%): Small penalty
            score = int256(prediction.slippageBps - MODERATE_SLIPPAGE_BPS);
        } else if (prediction.slippageBps >= LOW_SLIPPAGE_BPS) {
            // Low slippage (0.1-0.5%): Neutral to slight bonus
            score = -int256((MODERATE_SLIPPAGE_BPS - prediction.slippageBps) / 2);
        } else {
            // Excellent slippage (<0.1%): Good bonus
            score = -int256(50 + (LOW_SLIPPAGE_BPS - prediction.slippageBps));
        }

        // === LIQUIDITY BONUS/PENALTY ===
        
        if (prediction.availableLiquidity >= 1e20) {
            score -= 30; // Very deep liquidity bonus
        } else if (prediction.availableLiquidity >= 1e18) {
            score -= 15; // Good liquidity bonus
        } else if (prediction.availableLiquidity < 1e15) {
            score += 100; // Low liquidity penalty
        }

        // === PRICE IMPACT PENALTY ===
        
        if (prediction.priceImpactBps > 100) { // >1% price impact
            score += int256(prediction.priceImpactBps / 10);
        }

        // Clamp to reasonable range
        if (score > MAX_SLIPPAGE_SCORE) score = MAX_SLIPPAGE_SCORE;
        if (score < -MAX_SLIPPAGE_SCORE) score = -MAX_SLIPPAGE_SCORE;
    }

    /// @notice External view function to predict slippage for a specific swap
    /// @param key The pool key
    /// @param amountIn The input amount
    /// @param zeroForOne The swap direction
    /// @return prediction The slippage prediction
    function predictSwapSlippage(
        PoolKey calldata key,
        uint256 amountIn,
        bool zeroForOne
    ) external view returns (SlippagePrediction memory prediction) {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint128 liquidity = poolManager.getLiquidity(poolId);
        
        prediction.availableLiquidity = liquidity;

        if (liquidity == 0) {
            prediction.insufficientLiquidity = true;
            return prediction;
        }

        // Calculate expected output at current price
        prediction.expectedOutputWad = _calculateIdealOutput(
            sqrtPriceX96,
            amountIn,
            zeroForOne
        );

        // Simulate the swap
        (uint256 simulatedOutput, uint256 priceImpactBps, uint256 feesPaid) = _simulateSwap(
            sqrtPriceX96,
            liquidity,
            amountIn,
            key.fee,
            zeroForOne
        );

        prediction.simulatedOutputWad = simulatedOutput;
        prediction.priceImpactBps = priceImpactBps;
        prediction.effectiveFeesBps = amountIn > 0 ? (feesPaid * BPS_SCALE) / amountIn : 0;

        // Calculate slippage
        if (prediction.expectedOutputWad > 0 && simulatedOutput < prediction.expectedOutputWad) {
            prediction.slippageBps = ((prediction.expectedOutputWad - simulatedOutput) * BPS_SCALE) 
                / prediction.expectedOutputWad;
        }

        if (simulatedOutput == 0 && amountIn > 0) {
            prediction.insufficientLiquidity = true;
        }
    }

    /// @notice Calculate the expected output amount for a given input
    /// @param key The pool key
    /// @param amountIn The input amount
    /// @param zeroForOne The swap direction
    /// @return expectedOut The expected output amount
    /// @return slippageBps The expected slippage in basis points
    function getExpectedOutput(
        PoolKey calldata key,
        uint256 amountIn,
        bool zeroForOne
    ) external view returns (uint256 expectedOut, uint256 slippageBps) {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint128 liquidity = poolManager.getLiquidity(poolId);

        if (liquidity == 0) return (0, BPS_SCALE); // 100% slippage = no liquidity

        uint256 idealOutput = _calculateIdealOutput(sqrtPriceX96, amountIn, zeroForOne);
        
        (uint256 simulatedOutput,,) = _simulateSwap(
            sqrtPriceX96,
            liquidity,
            amountIn,
            key.fee,
            zeroForOne
        );

        expectedOut = simulatedOutput;
        
        if (idealOutput > 0 && simulatedOutput < idealOutput) {
            slippageBps = ((idealOutput - simulatedOutput) * BPS_SCALE) / idealOutput;
        }
    }
}
