// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SwarmAgentBase} from "./SwarmAgentBase.sol";
import {ISwarmCoordinator} from "../interfaces/ISwarmCoordinator.sol";
import {IOracleRegistry} from "../interfaces/IChainlinkOracle.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @title MevHunterAgent - Production-Grade MEV Detection Agent
/// @notice Detects MEV opportunities by analyzing pool-oracle price deviations
/// @dev Uses Chainlink oracle comparison + liquidity analysis for accurate scoring
/// @dev Inspired by backrunning-hook pattern (github.com/emmaguo13/backrunning-hook)
contract MevHunterAgent is SwarmAgentBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @notice Oracle registry for Chainlink price feeds
    IOracleRegistry public immutable oracleRegistry;

    /// @notice Scaling factor for price calculations (18 decimals)
    uint256 private constant PRICE_SCALE = 1e18;
    
    /// @notice Basis points scale
    uint256 private constant BPS_SCALE = 10_000;
    
    /// @notice Maximum MEV risk score (indicates very high risk - DON'T EXECUTE)
    int256 private constant MAX_RISK_SCORE = 1000;
    
    /// @notice Threshold for significant price deviation (50 bps = 0.5%)
    uint256 private constant SIGNIFICANT_DEVIATION_BPS = 50;
    
    /// @notice Threshold for dangerous price deviation (200 bps = 2%)  
    uint256 private constant DANGEROUS_DEVIATION_BPS = 200;

    /// @notice Minimum liquidity threshold for safe trading (in token units)
    uint128 private constant MIN_SAFE_LIQUIDITY = 1e15;
    
    /// @notice MEV analysis results packed into proposal data
    struct MevAnalysis {
        uint256 poolPriceWad;          // Pool price scaled to 18 decimals
        uint256 oraclePriceWad;        // Oracle price scaled to 18 decimals
        uint256 deviationBps;          // Price deviation in basis points
        uint256 arbitragePotentialWad; // Potential arbitrage profit in wei
        uint128 poolLiquidity;         // Current pool liquidity
        bool sandwichRisk;             // Sandwich attack risk flag
        bool lowLiquidityRisk;         // Low liquidity warning
    }

    event MevAnalysisCompleted(
        uint256 indexed intentId,
        uint256 poolPrice,
        uint256 oraclePrice,
        uint256 deviationBps,
        int256 score
    );

    constructor(
        ISwarmCoordinator coordinator_,
        IPoolManager poolManager_,
        IOracleRegistry oracleRegistry_
    ) SwarmAgentBase(coordinator_, poolManager_) {
        oracleRegistry = oracleRegistry_;
    }

    /// @notice Analyze MEV risk for an intent's candidate path
    /// @dev Uses oracle price deviation and liquidity analysis
    /// @param intent The swap intent details
    /// @param path The candidate swap path
    /// @return score Negative = SAFE (lower is better), Positive = RISKY (higher is worse)
    function _score(ISwarmCoordinator.IntentView memory intent, PathKey[] memory path)
        internal
        view
        override
        returns (int256)
    {
        if (path.length == 0) return MAX_RISK_SCORE;

        int256 totalScore = 0;
        Currency currentCurrency = intent.currencyIn;
        uint256 remainingAmount = intent.amountIn;

        for (uint256 i = 0; i < path.length; i++) {
            MevAnalysis memory analysis = _analyzePathStep(
                path[i],
                currentCurrency,
                remainingAmount
            );

            // Calculate score for this hop
            int256 hopScore = _calculateHopScore(analysis, remainingAmount);
            totalScore += hopScore;

            currentCurrency = path[i].intermediateCurrency;
        }

        // Average score across hops, weighted by path length
        return totalScore / int256(path.length);
    }

    /// @notice Analyze MEV risk for a single path step
    /// @param step The path step (pool hop)
    /// @param currencyIn The input currency for this hop
    /// @param amountIn The input amount for this hop
    /// @return analysis The MEV analysis results
    function _analyzePathStep(
        PathKey memory step,
        Currency currencyIn,
        uint256 amountIn
    ) internal view returns (MevAnalysis memory analysis) {
        // Build pool key and get metrics
        (PoolKey memory key,, uint128 liquidity) = _poolMetrics(step, currencyIn);
        PoolId poolId = key.toId();

        // Get current pool state
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        
        analysis.poolLiquidity = liquidity;
        analysis.poolPriceWad = _sqrtPriceToPrice(sqrtPriceX96);

        // Check for low liquidity risk
        if (liquidity < MIN_SAFE_LIQUIDITY) {
            analysis.lowLiquidityRisk = true;
        }

        // Get oracle price if available
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        
        try oracleRegistry.getLatestPrice(token0, token1) returns (uint256 oraclePrice, uint256) {
            if (oraclePrice > 0) {
                analysis.oraclePriceWad = oraclePrice;
                
                // Calculate deviation in basis points
                analysis.deviationBps = _calculateDeviationBps(
                    analysis.poolPriceWad,
                    analysis.oraclePriceWad
                );

                // Calculate potential arbitrage profit if deviation exists
                if (analysis.deviationBps > SIGNIFICANT_DEVIATION_BPS) {
                    analysis.arbitragePotentialWad = _calculateArbitragePotential(
                        amountIn,
                        analysis.poolPriceWad,
                        analysis.oraclePriceWad
                    );
                }

                // Detect sandwich attack risk
                // High deviation + large trade size relative to liquidity = sandwich target
                if (analysis.deviationBps > SIGNIFICANT_DEVIATION_BPS && liquidity > 0) {
                    uint256 tradeImpactBps = (amountIn * BPS_SCALE) / uint256(liquidity);
                    analysis.sandwichRisk = tradeImpactBps > 100; // >1% impact
                }
            }
        } catch {
            // Oracle not available - use liquidity-only analysis
            analysis.oraclePriceWad = 0;
        }
    }

    /// @notice Calculate the MEV risk score for a single hop
    /// @dev Score interpretation:
    ///      - Negative scores = SAFE (recommend execution)
    ///      - Near zero = NEUTRAL 
    ///      - Positive scores = RISKY (recommend caution/rejection)
    /// @param analysis The MEV analysis for this hop
    /// @param amountIn The trade amount
    /// @return hopScore The risk score for this hop
    function _calculateHopScore(
        MevAnalysis memory analysis,
        uint256 amountIn
    ) internal pure returns (int256 hopScore) {
        // Start with base score of 0 (neutral)
        hopScore = 0;

        // === RISK FACTORS (increase score / more positive = worse) ===
        
        // 1. Price deviation risk - main MEV indicator
        if (analysis.deviationBps > DANGEROUS_DEVIATION_BPS) {
            // Dangerous deviation: +200 to +500 based on severity
            hopScore += int256((analysis.deviationBps - DANGEROUS_DEVIATION_BPS) / 2);
            hopScore += 200; // Base penalty for dangerous deviation
        } else if (analysis.deviationBps > SIGNIFICANT_DEVIATION_BPS) {
            // Moderate deviation: +50 to +200
            hopScore += int256(analysis.deviationBps - SIGNIFICANT_DEVIATION_BPS);
        }

        // 2. Sandwich attack risk
        if (analysis.sandwichRisk) {
            hopScore += 150; // Significant penalty for sandwich risk
        }

        // 3. Low liquidity risk
        if (analysis.lowLiquidityRisk) {
            hopScore += 300; // High penalty for low liquidity
        }

        // 4. Large arbitrage potential indicates someone might frontrun
        if (amountIn > 0 && analysis.arbitragePotentialWad > amountIn / 100) { // >1% arb potential
            hopScore += int256(analysis.arbitragePotentialWad * 100 / amountIn);
        }

        // === SAFETY FACTORS (decrease score / more negative = better) ===

        // 5. Good liquidity depth reduces risk
        if (analysis.poolLiquidity >= 1e18) {
            hopScore -= 50; // Deep liquidity bonus
        } else if (analysis.poolLiquidity >= 1e17) {
            hopScore -= 25; // Moderate liquidity bonus
        }

        // 6. Tight oracle-pool price alignment is very good
        if (analysis.oraclePriceWad > 0 && analysis.deviationBps < 20) {
            hopScore -= 100; // Excellent alignment bonus
        } else if (analysis.oraclePriceWad > 0 && analysis.deviationBps < SIGNIFICANT_DEVIATION_BPS) {
            hopScore -= 50; // Good alignment bonus
        }

        // Clamp score to reasonable range
        if (hopScore > MAX_RISK_SCORE) hopScore = MAX_RISK_SCORE;
        if (hopScore < -MAX_RISK_SCORE) hopScore = -MAX_RISK_SCORE;
    }

    /// @notice Calculate price deviation in basis points
    /// @param poolPrice The pool price
    /// @param oraclePrice The oracle price
    /// @return deviationBps Absolute deviation in basis points
    function _calculateDeviationBps(
        uint256 poolPrice,
        uint256 oraclePrice
    ) internal pure returns (uint256 deviationBps) {
        if (oraclePrice == 0) return 0;
        
        if (poolPrice > oraclePrice) {
            deviationBps = ((poolPrice - oraclePrice) * BPS_SCALE) / oraclePrice;
        } else {
            deviationBps = ((oraclePrice - poolPrice) * BPS_SCALE) / oraclePrice;
        }
    }

    /// @notice Calculate potential arbitrage profit from price deviation
    /// @param amountIn The trade amount
    /// @param poolPrice The pool price
    /// @param oraclePrice The oracle (fair) price
    /// @return arbitragePotential The potential arbitrage profit in input token units
    function _calculateArbitragePotential(
        uint256 amountIn,
        uint256 poolPrice,
        uint256 oraclePrice
    ) internal pure returns (uint256 arbitragePotential) {
        if (oraclePrice == 0) return 0;
        
        // Arbitrage potential = |poolPrice - oraclePrice| / oraclePrice * amountIn
        uint256 priceDiff;
        if (poolPrice > oraclePrice) {
            priceDiff = poolPrice - oraclePrice;
        } else {
            priceDiff = oraclePrice - poolPrice;
        }
        
        arbitragePotential = FullMath.mulDiv(amountIn, priceDiff, oraclePrice);
    }

    /// @notice Convert sqrtPriceX96 to regular price scaled to 18 decimals
    /// @param sqrtPriceX96 The sqrt price in Q64.96 format
    /// @return price The price scaled to 18 decimals
    function _sqrtPriceToPrice(uint160 sqrtPriceX96) internal pure returns (uint256 price) {
        // price = (sqrtPriceX96 / 2^96)^2 scaled to 18 decimals
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 1 << 64);
        price = FullMath.mulDiv(priceX128, PRICE_SCALE, 1 << 128);
    }

    /// @notice External view function to analyze a specific pool for MEV risk
    /// @param key The pool key to analyze
    /// @param amountIn The proposed trade amount
    /// @return analysis The MEV analysis results
    function analyzePool(
        PoolKey calldata key,
        uint256 amountIn
    ) external view returns (MevAnalysis memory analysis) {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint128 liquidity = poolManager.getLiquidity(poolId);

        analysis.poolLiquidity = liquidity;
        analysis.poolPriceWad = _sqrtPriceToPrice(sqrtPriceX96);

        if (liquidity < MIN_SAFE_LIQUIDITY) {
            analysis.lowLiquidityRisk = true;
        }

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        try oracleRegistry.getLatestPrice(token0, token1) returns (uint256 oraclePrice, uint256) {
            if (oraclePrice > 0) {
                analysis.oraclePriceWad = oraclePrice;
                analysis.deviationBps = _calculateDeviationBps(analysis.poolPriceWad, oraclePrice);
                
                if (analysis.deviationBps > SIGNIFICANT_DEVIATION_BPS) {
                    analysis.arbitragePotentialWad = _calculateArbitragePotential(
                        amountIn,
                        analysis.poolPriceWad,
                        oraclePrice
                    );
                }

                if (analysis.deviationBps > SIGNIFICANT_DEVIATION_BPS && liquidity > 0) {
                    uint256 tradeImpactBps = (amountIn * BPS_SCALE) / uint256(liquidity);
                    analysis.sandwichRisk = tradeImpactBps > 100;
                }
            }
        } catch {}
    }

    /// @notice Get the oracle registry address
    function getOracleRegistry() external view returns (address) {
        return address(oracleRegistry);
    }
}
