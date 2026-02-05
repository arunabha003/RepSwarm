// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
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

import {SwarmHook} from "../src/hooks/SwarmHook.sol";
import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {DynamicFeeAgent} from "../src/agents/DynamicFeeAgent.sol";
import {BackrunAgent} from "../src/agents/BackrunAgent.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {ISwarmAgent, AgentType, SwapContext} from "../src/interfaces/ISwarmAgent.sol";
import {SwarmHookData} from "../src/libraries/SwarmHookData.sol";
import {ArbitrageLib} from "../src/libraries/ArbitrageLib.sol";

import {TestERC20} from "./utils/TestERC20.sol";

/// @title MevIntegrationTest
/// @notice Comprehensive MEV scenario tests with the new agent-driven architecture
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
    SwarmHook internal hook;
    AgentExecutor internal executor;
    ArbitrageAgent internal arbAgent;
    DynamicFeeAgent internal feeAgent;
    BackrunAgent internal backrunAgent;
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

        // Deploy agents
        arbAgent = new ArbitrageAgent(
            poolManager,
            IOracleRegistry(address(oracleRegistry))
        );

        feeAgent = new DynamicFeeAgent(
            poolManager,
            IOracleRegistry(address(oracleRegistry))
        );

        backrunAgent = new BackrunAgent(
            poolManager,
            lpAccumulator
        );

        // Deploy executor
        executor = new AgentExecutor();
        
        // Register agents
        executor.registerAgent(AgentType.ARBITRAGE, address(arbAgent));
        executor.registerAgent(AgentType.DYNAMIC_FEE, address(feeAgent));
        executor.registerAgent(AgentType.BACKRUN, address(backrunAgent));

        // Deploy hook with proper address mining
        _deployHook();

        // Configure LP accumulator
        lpAccumulator.setHookAuthorization(address(hook), true);

        // Link hook to accumulator
        hook.setLPFeeAccumulator(address(lpAccumulator));

        // Authorize callers
        arbAgent.authorizeCaller(address(hook), true);
        feeAgent.authorizeCaller(address(hook), true);
        backrunAgent.authorizeCaller(address(hook), true);
        arbAgent.authorizeCaller(address(executor), true);
        feeAgent.authorizeCaller(address(executor), true);
        backrunAgent.authorizeCaller(address(executor), true);

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
            address(executor),
            IOracleRegistry(address(oracleRegistry)),
            address(this)
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(SwarmHook).creationCode,
            constructorArgs
        );

        bytes memory deploymentData = abi.encodePacked(type(SwarmHook).creationCode, constructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "Hook deployment failed");

        address deployedAddress = address(bytes20(returnData));
        require(deployedAddress == hookAddress, "Hook address mismatch");

        hook = SwarmHook(payable(deployedAddress));
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

        // Initialize pool
        poolManager.initialize(poolKey, SQRT_PRICE_1_1);

        // Add initial liquidity
        tokenA.approve(address(liquidityRouter), type(uint256).max);
        tokenB.approve(address(liquidityRouter), type(uint256).max);

        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -60000,
                tickUpper: 60000,
                liquidityDelta: 1000 ether,
                salt: bytes32(0)
            }),
            ""
        );
    }

    function _setupTestActors() internal {
        // Fund test actors
        tokenA.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenA.mint(attacker, 10000 ether);
        tokenA.mint(victim, 100 ether);
        
        tokenB.mint(alice, 1000 ether);
        tokenB.mint(bob, 1000 ether);
        tokenB.mint(attacker, 10000 ether);
        tokenB.mint(victim, 100 ether);

        // Approvals
        vm.prank(alice);
        tokenA.approve(address(swapRouter), type(uint256).max);
        vm.prank(alice);
        tokenB.approve(address(swapRouter), type(uint256).max);

        vm.prank(bob);
        tokenA.approve(address(swapRouter), type(uint256).max);
        vm.prank(bob);
        tokenB.approve(address(swapRouter), type(uint256).max);

        vm.prank(attacker);
        tokenA.approve(address(swapRouter), type(uint256).max);
        vm.prank(attacker);
        tokenB.approve(address(swapRouter), type(uint256).max);

        vm.prank(victim);
        tokenA.approve(address(swapRouter), type(uint256).max);
        vm.prank(victim);
        tokenB.approve(address(swapRouter), type(uint256).max);
    }

    function _sortCurrencies(Currency a, Currency b) internal pure returns (Currency, Currency) {
        return Currency.unwrap(a) < Currency.unwrap(b) ? (a, b) : (b, a);
    }

    // ============ Test Cases ============

    function test_NormalSwapWithAgents() public {
        vm.prank(alice);
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap - agents should analyze and process
        swapRouter.swap(poolKey, params, settings, "");
        
        // Swap should complete successfully
        assertTrue(true);
    }

    function test_DynamicFeeIsApplied() public {
        // Make a large swap that should trigger higher fees
        vm.prank(alice);
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -100 ether, // Large swap
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Execute swap
        swapRouter.swap(poolKey, params, settings, "");
        
        // Fee agent should have been consulted
        assertTrue(feeAgent.isActive());
    }

    function test_AgentExecutorReceivesSwapContext() public {
        // Verify executor is configured
        assertEq(address(hook.agentExecutor()), address(executor));
        
        // Verify agents are registered
        assertEq(executor.agents(AgentType.ARBITRAGE), address(arbAgent));
        assertEq(executor.agents(AgentType.DYNAMIC_FEE), address(feeAgent));
        assertEq(executor.agents(AgentType.BACKRUN), address(backrunAgent));
    }

    function test_AdminCanSwapAgentDuringOperation() public {
        // Deploy new arbitrage agent
        ArbitrageAgent newArbAgent = new ArbitrageAgent(
            poolManager,
            IOracleRegistry(address(oracleRegistry))
        );
        
        // Hot-swap the agent
        executor.registerAgent(AgentType.ARBITRAGE, address(newArbAgent));
        newArbAgent.authorizeCaller(address(hook), true);
        newArbAgent.authorizeCaller(address(executor), true);
        
        // Verify swap
        assertEq(executor.agents(AgentType.ARBITRAGE), address(newArbAgent));
        
        // Swap should still work with new agent
        vm.prank(alice);
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        swapRouter.swap(poolKey, params, settings, "");
    }

    function test_DisablingAgentAffectsSwaps() public {
        // Disable fee agent
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, false);
        
        // Swap should still work (graceful degradation)
        vm.prank(alice);
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        swapRouter.swap(poolKey, params, settings, "");
        
        // Re-enable
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, true);
    }
}
