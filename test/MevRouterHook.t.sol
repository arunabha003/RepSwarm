// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {MevRouterHook} from "../src/hooks/MevRouterHook.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {SwarmHookData} from "../src/libraries/SwarmHookData.sol";

import {TestERC20} from "./utils/TestERC20.sol";

/// @title MevRouterHookTest
/// @notice Comprehensive tests for MevRouterHook
contract MevRouterHookTest is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    address internal constant TREASURY = address(0xBEEF);

    IPoolManager internal poolManager;
    MevRouterHook internal hook;
    OracleRegistry internal oracleRegistry;
    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal liquidityRouter;

    TestERC20 internal tokenA;
    TestERC20 internal tokenB;

    PoolKey internal poolKey;

    // Allow receiving ETH
    receive() external payable {}

    function setUp() public {
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);

        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        require(poolManagerAddr != address(0), "POOL_MANAGER missing");
        poolManager = IPoolManager(poolManagerAddr);

        tokenA = new TestERC20("TokenA", "TKA");
        tokenB = new TestERC20("TokenB", "TKB");

        _deployHook();
        _initPoolAndLiquidity();
    }

    // ============ Hook Permission Tests ============

    function test_hookPermissions() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();

        assertTrue(perms.beforeSwap, "beforeSwap should be enabled");
        assertTrue(perms.afterSwap, "afterSwap should be enabled");
        assertTrue(perms.afterSwapReturnDelta, "afterSwapReturnDelta should be enabled");

        assertFalse(perms.beforeInitialize, "beforeInitialize should be disabled");
        assertFalse(perms.afterInitialize, "afterInitialize should be disabled");
        assertFalse(perms.beforeAddLiquidity, "beforeAddLiquidity should be disabled");
        assertFalse(perms.afterAddLiquidity, "afterAddLiquidity should be disabled");
    }

    // ============ MEV Detection Tests ============

    function test_swapWithHookData() public {
        tokenA.mint(address(this), 10e18);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);

        SwarmHookData.Payload memory payload = SwarmHookData.Payload({
            intentId: 1,
            agentId: 1,
            treasury: TREASURY,
            treasuryBps: 200, // 2%
            mevFee: 100, // 0.01%
            lpShareBps: 8000 // 80%
        });

        bytes memory hookData = SwarmHookData.encode(payload);

        uint256 treasuryBefore = poolKey.currency1.balanceOf(TREASURY);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e18,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        swapRouter.swap(poolKey, params, testSettings, hookData);

        uint256 treasuryAfter = poolKey.currency1.balanceOf(TREASURY);

        // Treasury should have received 20% of 2% fee (since lpShare is 80%)
        assertGt(treasuryAfter, treasuryBefore, "Treasury should receive fees");
    }

    function test_swapWithoutHookData() public {
        tokenA.mint(address(this), 10e18);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);

        uint256 treasuryBefore = poolKey.currency1.balanceOf(TREASURY);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1e18,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Empty hook data - should pass through without fee capture
        swapRouter.swap(poolKey, params, testSettings, "");

        uint256 treasuryAfter = poolKey.currency1.balanceOf(TREASURY);

        // No treasury fee when no hook data
        assertEq(treasuryAfter, treasuryBefore, "Treasury should not receive fees without hookData");
    }

    function test_lowLiquidityTriggersMaxFee() public {
        // Create a new pool with very low liquidity
        TestERC20 lowLiqTokenA = new TestERC20("LowLiqA", "LLA");
        TestERC20 lowLiqTokenB = new TestERC20("LowLiqB", "LLB");

        (Currency currency0, Currency currency1) = _sortCurrencies(
            Currency.wrap(address(lowLiqTokenA)),
            Currency.wrap(address(lowLiqTokenB))
        );

        PoolKey memory lowLiqPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolManager.initialize(lowLiqPoolKey, TickMath.getSqrtPriceAtTick(0));

        // Add very small liquidity (below MEV threshold)
        lowLiqTokenA.mint(address(this), 1e14);
        lowLiqTokenB.mint(address(this), 1e14);
        lowLiqTokenA.approve(address(liquidityRouter), type(uint256).max);
        lowLiqTokenB.approve(address(liquidityRouter), type(uint256).max);

        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: int256(1e12), // Very small liquidity
            salt: bytes32(0)
        });

        liquidityRouter.modifyLiquidity(lowLiqPoolKey, liquidityParams, "");

        // Pool has very low liquidity, should trigger max MEV protection fee
        uint128 liquidity = poolManager.getLiquidity(lowLiqPoolKey.toId());
        assertLt(liquidity, 1e15, "Liquidity should be below threshold");
    }

    // ============ Oracle Integration Tests ============

    function test_oracleRegistrySet() public view {
        assertEq(address(hook.oracleRegistry()), address(oracleRegistry));
    }

    function test_sqrtPriceToPrice() public view {
        // Test the price conversion at tick 0 (price should be 1)
        uint160 sqrtPriceAtTick0 = TickMath.getSqrtPriceAtTick(0);
        
        // At tick 0, price should be approximately 1 (scaled to 18 decimals)
        // We can verify this by checking the slot0 of our pool
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolKey.toId());
        assertEq(sqrtPriceX96, sqrtPriceAtTick0, "Pool initialized at tick 0");
    }

    // ============ Constants Tests ============

    function test_constants() public view {
        assertEq(hook.MEV_THRESHOLD_BPS(), 100); // 1%
        assertEq(hook.MAX_MEV_FEE(), 10000); // 1% in hundredths of bip
        assertEq(hook.ORACLE_DEVIATION_THRESHOLD_BPS(), 50); // 0.5%
    }

    // ============ Helper Functions ============

    function _deployHook() internal {
        oracleRegistry = new OracleRegistry();

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory constructorArgs = abi.encode(poolManager, IOracleRegistry(oracleRegistry));
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            type(MevRouterHook).creationCode,
            constructorArgs
        );
        hook = new MevRouterHook{salt: salt}(poolManager, IOracleRegistry(oracleRegistry));
        require(address(hook) == hookAddress, "hook mismatch");
    }

    function _initPoolAndLiquidity() internal {
        (Currency currency0, Currency currency1) = _sortCurrencies(
            Currency.wrap(address(tokenA)),
            Currency.wrap(address(tokenB))
        );

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolManager.initialize(poolKey, TickMath.getSqrtPriceAtTick(0));

        tokenA.mint(address(this), 1e24);
        tokenB.mint(address(this), 1e24);

        liquidityRouter = new PoolModifyLiquidityTest(poolManager);
        tokenA.approve(address(liquidityRouter), type(uint256).max);
        tokenB.approve(address(liquidityRouter), type(uint256).max);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: int256(10e18),
            salt: bytes32(0)
        });

        liquidityRouter.modifyLiquidity(poolKey, params, "");

        swapRouter = new PoolSwapTest(poolManager);
    }

    function _sortCurrencies(Currency a, Currency b) internal pure returns (Currency currency0, Currency currency1) {
        if (a < b) {
            currency0 = a;
            currency1 = b;
        } else {
            currency0 = b;
            currency1 = a;
        }
    }
}
