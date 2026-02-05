// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @title HookLib
/// @notice Production-grade helper functions for Uniswap V4 hook development
/// @dev Adapted from detox-hook's HookLibrary with improvements
library HookLib {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @notice Price precision (18 decimals)
    uint256 private constant PRICE_PRECISION = 1e18;

    /// @notice Get the current sqrt price of a pool
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return sqrtPriceX96 The current sqrt price in Q64.96 format
    function getSqrtPrice(
        IPoolManager manager, 
        PoolKey memory poolKey
    ) internal view returns (uint160 sqrtPriceX96) {
        PoolId poolId = poolKey.toId();
        (sqrtPriceX96,,,) = manager.getSlot0(poolId);
    }

    /// @notice Get the current tick of a pool
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return tick The current tick
    function getTick(
        IPoolManager manager, 
        PoolKey memory poolKey
    ) internal view returns (int24 tick) {
        PoolId poolId = poolKey.toId();
        (, tick,,) = manager.getSlot0(poolId);
    }

    /// @notice Get the current liquidity of a pool
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return liquidity The current liquidity
    function getLiquidity(
        IPoolManager manager, 
        PoolKey memory poolKey
    ) internal view returns (uint128 liquidity) {
        PoolId poolId = poolKey.toId();
        liquidity = manager.getLiquidity(poolId);
    }

    /// @notice Get complete pool state in one call
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return sqrtPriceX96 The current sqrt price
    /// @return tick The current tick
    /// @return protocolFee The protocol fee
    /// @return lpFee The LP fee
    /// @return liquidity The current liquidity
    function getPoolState(
        IPoolManager manager, 
        PoolKey memory poolKey
    ) internal view returns (
        uint160 sqrtPriceX96, 
        int24 tick, 
        uint24 protocolFee, 
        uint24 lpFee, 
        uint128 liquidity
    ) {
        PoolId poolId = poolKey.toId();
        (sqrtPriceX96, tick, protocolFee, lpFee) = manager.getSlot0(poolId);
        liquidity = manager.getLiquidity(poolId);
    }

    /// @notice Convert sqrt price to human-readable price ratio (18 decimals)
    /// @param sqrtPriceX96 The sqrt price in Q64.96 format
    /// @return price The price as token1/token0 with 18 decimals
    function sqrtPriceToPrice(uint160 sqrtPriceX96) internal pure returns (uint256 price) {
        if (sqrtPriceX96 == 0) return 0;
        
        // price(1e18) = (sqrtPriceX96^2 / 2^192) * 1e18
        // Multiply by 1e18 before dividing so we don't lose precision for prices < 1.
        uint256 scaledB = uint256(sqrtPriceX96) * PRICE_PRECISION;
        price = FullMath.mulDiv(uint256(sqrtPriceX96), scaledB, 1 << 192);
    }

    /// @notice Convert human-readable price to sqrt price
    /// @param price The price as token1/token0 with 18 decimals
    /// @return sqrtPriceX96 The sqrt price in Q64.96 format
    function priceToSqrtPrice(uint256 price) internal pure returns (uint160 sqrtPriceX96) {
        if (price == 0) return 0;
        
        // sqrtPriceX96 = sqrt(price * 2^192 / 10^18)
        uint256 numerator = FullMath.mulDiv(price, 1 << 192, PRICE_PRECISION);
        uint256 sqrtPrice = sqrt(numerator);
        
        require(sqrtPrice <= type(uint160).max, "Price too large");
        sqrtPriceX96 = uint160(sqrtPrice);
    }

    /// @notice Get the pool price scaled to 18 decimals
    /// @param manager The pool manager
    /// @param poolKey The pool key
    /// @return price Pool price as token1/token0 with 18 decimals
    function getPoolPrice(
        IPoolManager manager, 
        PoolKey memory poolKey
    ) internal view returns (uint256 price) {
        uint160 sqrtPriceX96 = getSqrtPrice(manager, poolKey);
        price = sqrtPriceToPrice(sqrtPriceX96);
    }

    /// @notice Calculate the price impact of a swap based on liquidity
    /// @param swapAmount The amount being swapped
    /// @param liquidity The pool liquidity
    /// @return impactBps Price impact in basis points
    function calculatePriceImpact(
        uint256 swapAmount,
        uint128 liquidity
    ) internal pure returns (uint256 impactBps) {
        if (liquidity == 0) return 10_000; // 100% impact if no liquidity
        
        // Simplified impact calculation: swapAmount / (2 * liquidity) * 10000
        impactBps = FullMath.mulDiv(swapAmount, 10_000, 2 * uint256(liquidity));
        
        // Cap at 100%
        if (impactBps > 10_000) impactBps = 10_000;
    }

    /// @notice Integer square root using binary search
    /// @param x The value to find square root of
    /// @return y The square root
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /// @notice Check if swap is exact input
    /// @param amountSpecified The amount specified in swap params
    /// @return isExactInput True if exact input swap
    function isExactInput(int256 amountSpecified) internal pure returns (bool) {
        return amountSpecified < 0;
    }

    /// @notice Get the absolute swap amount
    /// @param amountSpecified The amount specified (negative for exact input)
    /// @return amount The absolute amount
    function getSwapAmount(int256 amountSpecified) internal pure returns (uint256 amount) {
        amount = amountSpecified < 0 
            ? uint256(-amountSpecified) 
            : uint256(amountSpecified);
    }

    /// @notice Determine input and output currencies from swap direction
    /// @param poolKey The pool key
    /// @param zeroForOne The swap direction
    /// @return inputCurrency The currency being sold
    /// @return outputCurrency The currency being bought
    function getSwapCurrencies(
        PoolKey memory poolKey,
        bool zeroForOne
    ) internal pure returns (Currency inputCurrency, Currency outputCurrency) {
        if (zeroForOne) {
            inputCurrency = poolKey.currency0;
            outputCurrency = poolKey.currency1;
        } else {
            inputCurrency = poolKey.currency1;
            outputCurrency = poolKey.currency0;
        }
    }

    /// @notice Calculate tick from sqrt price
    /// @param sqrtPriceX96 The sqrt price
    /// @return tick The corresponding tick
    function sqrtPriceToTick(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    /// @notice Get the sqrt price limit for a swap direction
    /// @param zeroForOne The swap direction
    /// @return sqrtPriceLimitX96 The price limit
    function getSqrtPriceLimit(bool zeroForOne) internal pure returns (uint160 sqrtPriceLimitX96) {
        sqrtPriceLimitX96 = zeroForOne 
            ? TickMath.MIN_SQRT_PRICE + 1 
            : TickMath.MAX_SQRT_PRICE - 1;
    }
}
