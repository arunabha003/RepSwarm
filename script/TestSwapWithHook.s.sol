// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @title TestSwapWithHook
/// @notice Test a swap through the MEV protection hook
contract TestSwapWithHook is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Addresses
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant POOL_SWAP_TEST = 0x9B6b46e2c869aa39918Db7f52f5557FE577B6eEe;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant HOOK = 0xB33ac5E0ebA7d47f3D9cFB78C29519801a7380Cc;

    function run() external {
        uint256 pk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(pk);

        console.log("===========================================");
        console.log("  TESTING SWAP THROUGH MEV HOOK");
        console.log("===========================================");
        console.log("Deployer:", deployer);

        // Pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),  // ETH
            currency1: Currency.wrap(USDC),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(HOOK)
        });

        PoolId poolId = poolKey.toId();
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        // Check pool state before swap
        console.log("");
        console.log("=== Before Swap ===");
        (uint160 sqrtPriceBefore, int24 tickBefore,,) = IPoolManager(POOL_MANAGER).getSlot0(poolId);
        console.log("sqrtPriceX96:", sqrtPriceBefore);
        console.log("Tick:", tickBefore);

        uint256 ethBalanceBefore = deployer.balance;
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(deployer);
        console.log("ETH Balance:", ethBalanceBefore / 1e18);
        console.log("USDC Balance:", usdcBalanceBefore / 1e18);

        vm.startBroadcast(pk);

        // Swap: ETH -> USDC (0.0001 ETH)
        // zeroForOne = true (swapping ETH for USDC)
        // amountSpecified = -0.0001 ETH (negative = exact input)
        // sqrtPriceLimitX96 = MIN_SQRT_PRICE + 1 for zeroForOne
        
        int256 amountToSwap = -0.0001 ether;  // Exact input: 0.0001 ETH
        uint160 sqrtPriceLimit = TickMath.MIN_SQRT_PRICE + 1;  // For zeroForOne
        
        console.log("");
        console.log("=== Executing Swap ===");
        console.log("Swapping:", uint256(-amountToSwap), "wei ETH for USDC");
        console.log("sqrtPriceLimit:", sqrtPriceLimit);

        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: amountToSwap,
            sqrtPriceLimitX96: sqrtPriceLimit
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        try PoolSwapTest(POOL_SWAP_TEST).swap{value: 0.001 ether}(
            poolKey,
            swapParams,
            testSettings,
            ""  // No hookData
        ) returns (BalanceDelta delta) {
            console.log("");
            console.log("[SUCCESS] Swap executed!");
            console.log("Delta amount0 (ETH):", int256(delta.amount0()));
            console.log("Delta amount1 (USDC):", int256(delta.amount1()));
        } catch Error(string memory reason) {
            console.log("[FAILED]:", reason);
        } catch (bytes memory data) {
            console.log("[FAILED] Raw error:");
            console.logBytes(data);
        }

        vm.stopBroadcast();

        // Check pool state after swap
        console.log("");
        console.log("=== After Swap ===");
        (uint160 sqrtPriceAfter, int24 tickAfter,,) = IPoolManager(POOL_MANAGER).getSlot0(poolId);
        console.log("sqrtPriceX96:", sqrtPriceAfter);
        console.log("Tick:", tickAfter);

        uint256 ethBalanceAfter = deployer.balance;
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(deployer);
        console.log("ETH Balance:", ethBalanceAfter / 1e18);
        console.log("USDC Balance:", usdcBalanceAfter / 1e18);

        // Verify hook was called
        console.log("");
        console.log("=== Verification ===");
        if (tickAfter != tickBefore) {
            console.log("[OK] Pool price moved - swap executed through hook!");
        }
        if (usdcBalanceAfter > usdcBalanceBefore) {
            console.log("[OK] Received USDC from swap");
            console.log("USDC received:", (usdcBalanceAfter - usdcBalanceBefore) / 1e18);
        }

        console.log("");
        console.log("===========================================");
        console.log("  TEST COMPLETE");
        console.log("===========================================");
    }
}
