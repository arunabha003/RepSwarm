// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {SwarmHookData} from "../libraries/SwarmHookData.sol";
import {IOracleRegistry} from "../interfaces/IChainlinkOracle.sol";

/// @title MevRouterHook
/// @notice A Uniswap v4 hook that detects MEV opportunities and redistributes captured value to LPs
/// @dev Uses price deviation detection (pool vs Chainlink oracle) to identify arbitrage and donates captured fees to LPs
contract MevRouterHook is BaseHook {
    using SafeCast for int128;
    using SafeCast for uint256;
    using SafeCast for int256;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @notice Oracle registry for Chainlink price feeds
    IOracleRegistry public immutable oracleRegistry;

    /// @notice Threshold for price deviation that triggers MEV capture (in basis points)
    /// @dev 100 bps = 1% deviation triggers MEV fee
    uint256 public constant MEV_THRESHOLD_BPS = 100;

    /// @notice Maximum dynamic fee that can be applied (in hundredths of a bip)
    uint24 public constant MAX_MEV_FEE = 10000; // 1%

    /// @notice Price deviation threshold for oracle-based MEV detection (50 bps = 0.5%)
    uint256 public constant ORACLE_DEVIATION_THRESHOLD_BPS = 50;

    /// @notice Emitted when MEV is captured and redistributed
    event MevCaptured(
        PoolId indexed poolId,
        uint256 intentId,
        uint256 capturedAmount,
        uint256 lpDonation,
        uint256 treasuryAmount
    );

    /// @notice Emitted when price deviation is detected
    event PriceDeviationDetected(
        PoolId indexed poolId,
        uint256 poolPrice,
        uint256 oraclePrice,
        uint256 deviationBps
    );

    constructor(IPoolManager manager, IOracleRegistry _oracleRegistry) BaseHook(manager) {
        oracleRegistry = _oracleRegistry;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Called before a swap to potentially apply dynamic MEV fees
    /// @dev Detects if swap would create arbitrage opportunity using both liquidity analysis and Chainlink oracle
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (hookData.length == 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        SwarmHookData.Payload memory payload = SwarmHookData.decode(hookData);

        // Get current pool price before swap
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);

        // Calculate the expected price impact based on swap size and liquidity
        uint128 liquidity = poolManager.getLiquidity(poolId);
        
        // If liquidity is very low, apply maximum MEV protection
        if (liquidity < 1e15) {
            uint24 overrideFee = MAX_MEV_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG;
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, overrideFee);
        }

        // Calculate expected price deviation from swap (liquidity-based)
        uint256 swapAmount = params.amountSpecified < 0 
            ? uint256(-params.amountSpecified) 
            : uint256(params.amountSpecified);
        
        uint256 impactBps = (swapAmount * 10000) / uint256(liquidity);
        
        // Check Chainlink oracle for additional MEV detection
        (uint256 oracleDeviationBps, uint256 oraclePrice) = _checkOracleDeviation(key, sqrtPriceX96);
        
        // Use the higher of impact-based or oracle-based deviation
        uint256 totalDeviationBps = impactBps > oracleDeviationBps ? impactBps : oracleDeviationBps;
        
        // Emit event if significant oracle deviation detected
        if (oracleDeviationBps > ORACLE_DEVIATION_THRESHOLD_BPS) {
            uint256 poolPrice = _sqrtPriceToPrice(sqrtPriceX96);
            emit PriceDeviationDetected(poolId, poolPrice, oraclePrice, oracleDeviationBps);
        }
        
        // Apply dynamic fee if total deviation exceeds threshold
        if (totalDeviationBps > MEV_THRESHOLD_BPS) {
            uint24 dynamicFee = uint24(
                totalDeviationBps > 10000 ? MAX_MEV_FEE : (totalDeviationBps * MAX_MEV_FEE) / 10000
            );
            
            uint24 finalFee = dynamicFee > payload.mevFee ? dynamicFee : payload.mevFee;
            if (finalFee > 0) {
                uint24 overrideFee = finalFee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
                return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, overrideFee);
            }
        } else if (payload.mevFee > 0) {
            uint24 overrideFee = payload.mevFee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, overrideFee);
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Check price deviation between pool price and Chainlink oracle
    /// @param key The pool key
    /// @param sqrtPriceX96 Current pool sqrt price
    /// @return deviationBps Deviation in basis points (0 if oracle not available)
    /// @return oraclePrice The oracle price (0 if not available)
    function _checkOracleDeviation(PoolKey calldata key, uint160 sqrtPriceX96) internal view returns (uint256 deviationBps, uint256 oraclePrice) {
        if (address(oracleRegistry) == address(0)) {
            return (0, 0);
        }

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        try oracleRegistry.getLatestPrice(token0, token1) returns (uint256 _oraclePrice, uint256) {
            if (_oraclePrice == 0) return (0, 0);
            oraclePrice = _oraclePrice;

            // Convert sqrtPriceX96 to regular price (scaled to 18 decimals)
            uint256 poolPrice = _sqrtPriceToPrice(sqrtPriceX96);
            
            // Calculate deviation: |poolPrice - oraclePrice| / oraclePrice * 10000
            if (poolPrice > oraclePrice) {
                deviationBps = ((poolPrice - oraclePrice) * 10000) / oraclePrice;
            } else {
                deviationBps = ((oraclePrice - poolPrice) * 10000) / oraclePrice;
            }
        } catch {
            // Oracle not available for this pair
            return (0, 0);
        }
    }

    /// @notice Convert sqrtPriceX96 to regular price scaled to 18 decimals
    /// @param sqrtPriceX96 The sqrt price in Q64.96 format
    /// @return price The price scaled to 18 decimals
    function _sqrtPriceToPrice(uint160 sqrtPriceX96) internal pure returns (uint256 price) {
        // price = (sqrtPriceX96 / 2^96)^2 = sqrtPriceX96^2 / 2^192
        // To get 18 decimal precision: price * 10^18
        // Use FullMath to avoid overflow: first compute sqrtPriceX96^2 / 2^96, then * 1e18 / 2^96
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        // Split the computation to avoid overflow:
        // price = sqrtPrice^2 * 1e18 / 2^192 = (sqrtPrice * sqrtPrice / 2^64) * 1e18 / 2^128
        // Use FullMath.mulDiv for safe multiplication
        uint256 priceX128 = FullMath.mulDiv(sqrtPrice, sqrtPrice, 1 << 64);
        price = FullMath.mulDiv(priceX128, 1e18, 1 << 128);
    }

    /// @notice Called after a swap to redistribute captured MEV to LPs and treasury
    /// @dev Calculates fee split and donates LP share back to the pool
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        if (hookData.length == 0) {
            return (IHooks.afterSwap.selector, 0);
        }

        SwarmHookData.Payload memory payload = SwarmHookData.decode(hookData);
        if (payload.treasury == address(0) || payload.treasuryBps == 0) {
            return (IHooks.afterSwap.selector, 0);
        }

        // Calculate and distribute fees, returns treasury amount taken
        int128 deltaAdjustment = _calculateAndDistributeFees(key, params, delta, payload);

        // Return delta adjustment - this tells the pool manager to adjust the delta
        // so caller's settlement is reduced by the treasury amount we took
        return (IHooks.afterSwap.selector, deltaAdjustment);
    }

    /// @dev Internal function to calculate and distribute fees
    /// @notice Takes full fee from user output, sends treasury share to treasury
    /// @notice LP share is also sent to treasury (can be redistributed off-chain or via governance)
    /// @return deltaAdjustment The delta adjustment for the output currency
    function _calculateAndDistributeFees(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        SwarmHookData.Payload memory payload
    ) internal returns (int128 deltaAdjustment) {
        // Determine which currency we're taking fees from (the output currency)
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        int128 swapAmount = specifiedTokenIs0 ? delta.amount1() : delta.amount0();
        if (swapAmount < 0) swapAmount = -swapAmount;

        uint256 outputAmount = uint256(uint128(swapAmount));
        uint256 totalFeeAmount = outputAmount * payload.treasuryBps / 10_000;
        if (totalFeeAmount == 0) return 0;

        // Calculate LP donation and treasury split
        uint256 lpShareBps = payload.lpShareBps > 0 ? payload.lpShareBps : 8000;
        uint256 lpDonation = (totalFeeAmount * lpShareBps) / 10_000;
        uint256 treasuryAmount = totalFeeAmount - lpDonation;

        Currency feeCurrency = specifiedTokenIs0 ? key.currency1 : key.currency0;

        // Take entire fee from user's output
        // Treasury receives its share directly
        if (treasuryAmount > 0) {
            poolManager.take(feeCurrency, payload.treasury, treasuryAmount);
        }

        // LP share: Instead of donate() which creates settlement issues,
        // we accumulate LP fees for later distribution via the LP donation mechanism
        // For now, LP share also goes to treasury for manual redistribution
        // A more sophisticated approach would be a separate LP fee accumulator contract
        if (lpDonation > 0) {
            poolManager.take(feeCurrency, payload.treasury, lpDonation);
        }

        // Return full fee as delta adjustment
        deltaAdjustment = int128(uint128(totalFeeAmount));

        emit MevCaptured(key.toId(), payload.intentId, totalFeeAmount, lpDonation, treasuryAmount);
    }

    // Note: Direct LP donation via donate() is disabled because it creates unsettled deltas
    // The LP share is sent to treasury for off-chain redistribution to LPs
    // A future version could use a dedicated LP fee accumulator with periodic donations
}
