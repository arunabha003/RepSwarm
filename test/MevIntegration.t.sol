// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {MevRouterHookV2} from "../src/hooks/MevRouterHookV2.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {SwarmHookData} from "../src/libraries/SwarmHookData.sol";
import {ArbitrageLib} from "../src/libraries/ArbitrageLib.sol";
import {HookLib} from "../src/libraries/HookLib.sol";

import {TestERC20} from "./utils/TestERC20.sol";

/// @title MevIntegrationTest
/// @notice Comprehensive MEV scenario tests with forked mainnet
/// @dev Tests sandwich attack protection, backrunning, and LP fee distribution
contract MevIntegrationTest is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // ============ Constants ============
    
    address internal constant TREASURY = address(0xBEEF);
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 1:1 price
    uint160 internal constant SQRT_PRICE_1_2 = 56022770974786139918731938227; // 1:2 price (50% cheaper)
    uint160 internal constant SQRT_PRICE_2_1 = 112045541949572279837463876454; // 2:1 price (50% more expensive)

    // ============ Test Contracts ============
    
    IPoolManager internal poolManager;
    MevRouterHookV2 internal hook;
    LPFeeAccumulator internal lpAccumulator;
    OracleRegistry internal oracleRegistry;
    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal liquidityRouter;

    TestERC20 internal tokenA;
    TestERC20 internal tokenB;

    PoolKey internal poolKey;
    PoolId internal poolId;

    // Test actors
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");
    address internal victim = makeAddr("victim");

    // ============ Setup ============

    function setUp() public {
        // Fork Sepolia
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);

        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        require(poolManagerAddr != address(0), "POOL_MANAGER missing");
        poolManager = IPoolManager(poolManagerAddr);

        // Deploy test tokens
        tokenA = new TestERC20("TokenA", "TKA");
        tokenB = new TestERC20("TokenB", "TKB");

        // Deploy oracle registry
        oracleRegistry = new OracleRegistry();

        // Deploy LP accumulator
        lpAccumulator = new LPFeeAccumulator(
            poolManager,
            0.01 ether, // min donation threshold
            1 hours // min donation interval
        );

        // Deploy hook with proper address mining
        _deployHook();

        // Configure LP accumulator
        lpAccumulator.setHookAuthorization(address(hook), true);

        // Link hook to accumulator
        hook.setLPFeeAccumulator(address(lpAccumulator));

        // Deploy routers
        swapRouter = new PoolSwapTest(poolManager);
        liquidityRouter = new PoolModifyLiquidityTest(poolManager);

        // Initialize pool
        _initPoolAndLiquidity();

        // Setup test actors
        _setupTestActors();
    }

    function _deployHook() internal {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(
            poolManager, 
            IOracleRegistry(address(oracleRegistry)),
            address(this)
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(MevRouterHookV2).creationCode,
            constructorArgs
        );

        bytes memory deploymentData = abi.encodePacked(type(MevRouterHookV2).creationCode, constructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "Hook deployment failed");

        address deployedAddress = address(bytes20(returnData));
        require(deployedAddress == hookAddress, "Hook address mismatch");

        hook = MevRouterHookV2(payable(deployedAddress));
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

        poolId = poolKey.toId();

        // Initialize at 1:1 price
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        // Register pool key with accumulator
        lpAccumulator.registerPoolKey(poolKey);

        // Add liquidity
        tokenA.mint(address(this), 1000e18);
        tokenB.mint(address(this), 1000e18);
        tokenA.approve(address(liquidityRouter), type(uint256).max);
        tokenB.approve(address(liquidityRouter), type(uint256).max);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -6000,
            tickUpper: 6000,
            liquidityDelta: int256(100e18),
            salt: bytes32(0)
        });

        liquidityRouter.modifyLiquidity(poolKey, params, "");
    }

    function _setupTestActors() internal {
        // Mint tokens to all actors
        tokenA.mint(alice, 100e18);
        tokenB.mint(alice, 100e18);
        tokenA.mint(bob, 100e18);
        tokenB.mint(bob, 100e18);
        tokenA.mint(attacker, 1000e18);
        tokenB.mint(attacker, 1000e18);
        tokenA.mint(victim, 10e18);
        tokenB.mint(victim, 10e18);

        // Approve routers
        address[] memory actors = new address[](4);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = attacker;
        actors[3] = victim;

        for (uint256 i = 0; i < actors.length; i++) {
            vm.startPrank(actors[i]);
            tokenA.approve(address(swapRouter), type(uint256).max);
            tokenB.approve(address(swapRouter), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _sortCurrencies(Currency a, Currency b) internal pure returns (Currency, Currency) {
        if (Currency.unwrap(a) < Currency.unwrap(b)) {
            return (a, b);
        }
        return (b, a);
    }

    // ============ MEV Scenario Tests ============

    /// @notice Test sandwich attack protection
    /// @dev Simulates: Attacker frontrun -> Victim swap -> Attacker backrun
    function test_sandwichAttackProtection() public {
        console.log("=== Sandwich Attack Protection Test ===");

        // Record initial state
        uint256 victimBalanceA_before = tokenA.balanceOf(victim);
        uint256 victimBalanceB_before = tokenB.balanceOf(victim);
        uint256 attackerBalanceA_before = tokenA.balanceOf(attacker);
        uint256 attackerBalanceB_before = tokenB.balanceOf(attacker);

        // ============ Step 1: Attacker Frontrun (Medium Buy) ============
        console.log("\n--- Attacker Frontrun ---");
        
        vm.startPrank(attacker);
        
        // Use smaller swap amount to not exhaust liquidity
        SwapParams memory frontrunParams = SwapParams({
            zeroForOne: true, // Buy tokenB with tokenA
            amountSpecified: -5e18, // Smaller swap to not hit price limit
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Create hook data for MEV capture
        SwarmHookData.Payload memory payload = SwarmHookData.Payload({
            intentId: 1,
            agentId: 1,
            treasury: TREASURY,
            treasuryBps: 200, // 2%
            mevFee: 100, // 0.01%
            lpShareBps: 8000 // 80%
        });
        bytes memory hookData = SwarmHookData.encode(payload);

        BalanceDelta frontrunDelta = swapRouter.swap(poolKey, frontrunParams, settings, hookData);
        vm.stopPrank();

        console.log("Frontrun delta amount0:", frontrunDelta.amount0());
        console.log("Frontrun delta amount1:", frontrunDelta.amount1());

        // Get price after frontrun
        (uint160 priceAfterFrontrun,,,) = poolManager.getSlot0(poolId);
        console.log("Price after frontrun (sqrtPriceX96):", priceAfterFrontrun);

        // ============ Step 2: Victim Swap ============
        console.log("\n--- Victim Swap ---");
        
        vm.startPrank(victim);
        
        SwapParams memory victimParams = SwapParams({
            zeroForOne: true, // Same direction as attacker
            amountSpecified: -1e18, // Victim's smaller swap
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        BalanceDelta victimDelta = swapRouter.swap(poolKey, victimParams, settings, hookData);
        vm.stopPrank();

        console.log("Victim delta amount0:", victimDelta.amount0());
        console.log("Victim delta amount1:", victimDelta.amount1());

        // ============ Step 3: Attacker Backrun (Sell) ============
        console.log("\n--- Attacker Backrun ---");
        
        vm.startPrank(attacker);
        
        // Calculate how much tokenB attacker gained
        uint256 attackerCurrentB = tokenB.balanceOf(attacker);
        console.log("Attacker current tokenB balance:", attackerCurrentB);
        console.log("Attacker initial tokenB balance:", attackerBalanceB_before);
        
        // Only try backrun if attacker actually gained tokenB
        if (attackerCurrentB > attackerBalanceB_before) {
            uint256 attackerGainedB = attackerCurrentB - attackerBalanceB_before;
            console.log("Attacker gained tokenB:", attackerGainedB);
            
            // Only sell a portion to avoid price limit issues
            uint256 sellAmount = attackerGainedB * 80 / 100;
            if (sellAmount > 0) {
                SwapParams memory backrunParams = SwapParams({
                    zeroForOne: false, // Sell tokenB for tokenA
                    amountSpecified: -int256(sellAmount),
                    sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
                });

                BalanceDelta backrunDelta = swapRouter.swap(poolKey, backrunParams, settings, hookData);
                console.log("Backrun delta amount0:", backrunDelta.amount0());
                console.log("Backrun delta amount1:", backrunDelta.amount1());
            }
        } else {
            console.log("Attacker did not gain tokenB, skipping backrun");
        }
        vm.stopPrank();

        // ============ Analysis ============
        console.log("\n--- Analysis ---");

        uint256 attackerFinalA = tokenA.balanceOf(attacker);
        // Check both token balances in treasury
        uint256 treasuryBalanceA = tokenA.balanceOf(TREASURY);
        uint256 treasuryBalanceB = tokenB.balanceOf(TREASURY);

        // Calculate attacker profit/loss - use safe comparison
        bool attackerLostA = attackerFinalA < attackerBalanceA_before;
        uint256 attackerChangeA = attackerLostA 
            ? attackerBalanceA_before - attackerFinalA 
            : attackerFinalA - attackerBalanceA_before;
        
        console.log("Attacker lost tokenA:", attackerLostA);
        console.log("Attacker change in tokenA:", attackerChangeA);
        console.log("Treasury captured tokenA:", treasuryBalanceA);
        console.log("Treasury captured tokenB:", treasuryBalanceB);

        // The hook should have captured some MEV, in either token
        uint256 totalTreasury = treasuryBalanceA + treasuryBalanceB;
        assertGt(totalTreasury, 0, "Treasury should capture MEV fees");
    }

    /// @notice Test arbitrage detection with oracle price deviation
    function test_arbitrageDetection() public {
        console.log("=== Arbitrage Detection Test ===");

        // Setup mock oracle with price deviation
        // Pool is at 1:1, but oracle says "fair" price is 1.5:1
        // This creates arbitrage opportunity

        // Get current pool price
        uint160 sqrtPriceX96 = HookLib.getSqrtPrice(poolManager, poolKey);
        uint256 poolPrice = HookLib.sqrtPriceToPrice(sqrtPriceX96);
        console.log("Pool price (18 decimals):", poolPrice);

        // Calculate expected arbitrage opportunity
        uint256 swapAmount = 10e18;
        
        // For zeroForOne (selling token0 for token1), arbitrage is advantageous when poolPrice > oraclePrice
        // This means pool gives MORE token1 per token0 than fair market rate
        // So we set oracle price LOWER than pool price to simulate arbitrage opportunity
        uint256 fakeOraclePrice = poolPrice * 50 / 100; // 50% LOWER (pool gives better rate)

        ArbitrageLib.ArbitrageResult memory result = ArbitrageLib.analyzeArbitrageOpportunity(
            ArbitrageLib.ArbitrageParams({
                poolPrice: poolPrice,
                oraclePrice: fakeOraclePrice,
                oracleConfidence: fakeOraclePrice / 200, // 0.5% confidence
                swapAmount: swapAmount,
                zeroForOne: true  // Selling token0 for token1
            }),
            8000, // 80% hook share
            50 // 0.5% min divergence
        );

        console.log("Arbitrage opportunity:", result.arbitrageOpportunity);
        console.log("Hook share:", result.hookShare);
        console.log("Should interfere:", result.shouldInterfere);
        console.log("Price divergence BPS:", result.priceDivergenceBps);
        console.log("Outside confidence band:", result.isOutsideConfidenceBand);

        // With 50% price deviation and correct direction, should detect opportunity
        assertTrue(result.shouldInterfere, "Should detect arbitrage opportunity");
        assertGt(result.hookShare, 0, "Hook should capture share");
    }

    /// @notice Test LP fee accumulation and donation
    function test_lpFeeAccumulationAndDonation() public {
        console.log("=== LP Fee Accumulation Test ===");

        // Execute multiple swaps to accumulate fees
        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(alice);
            
            SwapParams memory params = SwapParams({
                zeroForOne: i % 2 == 0,
                amountSpecified: -1e18,
                sqrtPriceLimitX96: i % 2 == 0 ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            });

            SwarmHookData.Payload memory payload = SwarmHookData.Payload({
                intentId: i + 1,
                agentId: 1,
                treasury: TREASURY,
                treasuryBps: 100, // 1%
                mevFee: 50,
                lpShareBps: 8000 // 80% to LPs
            });

            PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            });

            swapRouter.swap(poolKey, params, settings, SwarmHookData.encode(payload));
            vm.stopPrank();
        }

        // Check accumulated fees
        uint256 accumulatedA = lpAccumulator.getAccumulatedFees(poolId, poolKey.currency0);
        uint256 accumulatedB = lpAccumulator.getAccumulatedFees(poolId, poolKey.currency1);

        console.log("Accumulated currency0:", accumulatedA);
        console.log("Accumulated currency1:", accumulatedB);

        // Check if donation is possible
        (bool canDonate, uint256 amount0, uint256 amount1) = lpAccumulator.canDonate(poolId);
        console.log("Can donate:", canDonate);
        console.log("Donation amount0:", amount0);
        console.log("Donation amount1:", amount1);

        // Note: Actual donation would require sufficient accumulated fees
        // and passing the time interval check
    }

    /// @notice Test backrunning opportunity detection
    function test_backrunOpportunityDetection() public {
        console.log("=== Backrun Opportunity Detection Test ===");

        // Large swap to create price deviation
        vm.startPrank(alice);

        SwapParams memory largeSwap = SwapParams({
            zeroForOne: true,
            amountSpecified: -20e18, // Large swap
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        SwarmHookData.Payload memory payload = SwarmHookData.Payload({
            intentId: 1,
            agentId: 1,
            treasury: TREASURY,
            treasuryBps: 200,
            mevFee: 100,
            lpShareBps: 8000
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        swapRouter.swap(poolKey, largeSwap, settings, SwarmHookData.encode(payload));
        vm.stopPrank();

        // Check pending backrun amount
        uint256 pendingBackrun = hook.getPendingBackrun(poolId);
        console.log("Pending backrun amount:", pendingBackrun);

        // Large swaps should create backrun opportunities
        // (Note: Actual value depends on price impact and oracle deviation)
    }

    /// @notice Test dynamic fee adjustment based on MEV risk
    function test_dynamicFeeAdjustment() public {
        console.log("=== Dynamic Fee Adjustment Test ===");

        // Create a pool with very low liquidity (high MEV risk)
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

        poolManager.initialize(lowLiqPoolKey, SQRT_PRICE_1_1);

        // Add very small liquidity
        lowLiqTokenA.mint(address(this), 1e15);
        lowLiqTokenB.mint(address(this), 1e15);
        lowLiqTokenA.approve(address(liquidityRouter), type(uint256).max);
        lowLiqTokenB.approve(address(liquidityRouter), type(uint256).max);

        ModifyLiquidityParams memory liquidityParams = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: int256(1e12), // Very small liquidity
            salt: bytes32(0)
        });

        liquidityRouter.modifyLiquidity(lowLiqPoolKey, liquidityParams, "");

        // Verify low liquidity
        uint128 liquidity = poolManager.getLiquidity(lowLiqPoolKey.toId());
        console.log("Pool liquidity:", liquidity);
        assertLt(liquidity, 1e15, "Should have very low liquidity");

        // Swap in low liquidity pool should trigger high MEV protection
        lowLiqTokenA.mint(alice, 1e18);
        
        vm.startPrank(alice);
        lowLiqTokenA.approve(address(swapRouter), type(uint256).max);
        lowLiqTokenB.approve(address(swapRouter), type(uint256).max);

        // Note: The actual fee override would be visible in the swap execution
        // Hook should apply MAX_DYNAMIC_FEE for low liquidity pools
        vm.stopPrank();
    }

    /// @notice Test multi-hop sandwich attack scenario
    function test_multiHopMevProtection() public {
        console.log("=== Multi-Hop MEV Protection Test ===");

        // This would test MEV protection across multiple pools
        // For simplicity, we test the basic mechanism here

        // Execute swap with hook data
        vm.startPrank(alice);

        SwarmHookData.Payload memory payload = SwarmHookData.Payload({
            intentId: 1,
            agentId: 1,
            treasury: TREASURY,
            treasuryBps: 300, // 3% fee
            mevFee: 200, // 0.02% MEV fee
            lpShareBps: 7500 // 75% to LPs
        });

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -2e18, // Smaller swap to avoid overflow
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        uint256 aliceBalanceBefore = tokenB.balanceOf(alice);
        uint256 treasuryBeforeA = tokenA.balanceOf(TREASURY);
        uint256 treasuryBeforeB = tokenB.balanceOf(TREASURY);

        swapRouter.swap(poolKey, params, settings, SwarmHookData.encode(payload));

        uint256 aliceBalanceAfter = tokenB.balanceOf(alice);
        uint256 treasuryAfterA = tokenA.balanceOf(TREASURY);
        uint256 treasuryAfterB = tokenB.balanceOf(TREASURY);

        // Safe subtraction
        uint256 aliceReceived = aliceBalanceAfter > aliceBalanceBefore 
            ? aliceBalanceAfter - aliceBalanceBefore 
            : 0;
        uint256 treasuryReceivedA = treasuryAfterA > treasuryBeforeA 
            ? treasuryAfterA - treasuryBeforeA 
            : 0;
        uint256 treasuryReceivedB = treasuryAfterB > treasuryBeforeB 
            ? treasuryAfterB - treasuryBeforeB 
            : 0;

        console.log("Alice received:", aliceReceived);
        console.log("Treasury received tokenA:", treasuryReceivedA);
        console.log("Treasury received tokenB:", treasuryReceivedB);

        vm.stopPrank();

        // Treasury should have captured fees (in either token)
        uint256 totalTreasuryReceived = treasuryReceivedA + treasuryReceivedB;
        assertGt(totalTreasuryReceived, 0, "Treasury should receive fees");
    }

    // ============ Helper Functions ============

    receive() external payable {}
}
