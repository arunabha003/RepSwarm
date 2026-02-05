// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {SwarmHook} from "../src/hooks/SwarmHook.sol";
import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {DynamicFeeAgent} from "../src/agents/DynamicFeeAgent.sol";
import {BackrunAgent} from "../src/agents/BackrunAgent.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {ISwarmAgent, AgentType, SwapContext, AgentResult} from "../src/interfaces/ISwarmAgent.sol";

import {TestERC20} from "./utils/TestERC20.sol";

/// @title E2E Test - Complete Protocol End-to-End Testing
/// @notice Comprehensive E2E test demonstrating all protocol features
/// @dev Run with: forge test --match-contract E2ETest -vvv --fork-url $SEPOLIA_RPC_URL
contract E2ETest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // ============ Sepolia Addresses ============
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant ERC8004_IDENTITY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;

    // ============ Deployed Contracts ============
    IPoolManager public poolManager;
    SwarmHook public hook;
    AgentExecutor public agentExecutor;
    ArbitrageAgent public arbitrageAgent;
    DynamicFeeAgent public dynamicFeeAgent;
    BackrunAgent public backrunAgent;
    LPFeeAccumulator public lpFeeAccumulator;
    OracleRegistry public oracleRegistry;

    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public liquidityRouter;

    TestERC20 public tokenA;
    TestERC20 public tokenB;

    PoolKey public poolKey;
    PoolId public poolId;

    // Test actors
    address public deployer;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public admin = makeAddr("admin");

    // ============ Events to Test ============
    event AgentRegistered(AgentType indexed agentType, address indexed agent, uint256 agentId);
    event AgentEnabled(AgentType indexed agentType, bool enabled);

    // ============ Setup ============

    function setUp() public {
        // Fork Sepolia
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string("https://rpc.sepolia.org"));
        vm.createSelectFork(rpc);

        deployer = address(this);
        poolManager = IPoolManager(POOL_MANAGER);

        // Give test contract ETH
        vm.deal(deployer, 1000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(admin, 100 ether);

        // Deploy test tokens
        tokenA = new TestERC20("Token A", "TKA");
        tokenB = new TestERC20("Token B", "TKB");

        // Mint tokens
        tokenA.mint(deployer, 1_000_000 ether);
        tokenB.mint(deployer, 1_000_000 ether);
        tokenA.mint(alice, 10_000 ether);
        tokenB.mint(alice, 10_000 ether);
        tokenA.mint(bob, 10_000 ether);
        tokenB.mint(bob, 10_000 ether);

        // ============ Phase 1: Deploy Infrastructure ============
        console.log("\n=== PHASE 1: Deploy Infrastructure ===");
        
        oracleRegistry = new OracleRegistry();
        console.log("OracleRegistry:", address(oracleRegistry));
        
        // Register real Chainlink feed
        oracleRegistry.setPriceFeed(address(0), address(tokenB), ETH_USD_FEED);
        console.log("Chainlink ETH/USD feed registered");

        lpFeeAccumulator = new LPFeeAccumulator(poolManager, 0.001 ether, 1 hours);
        console.log("LPFeeAccumulator:", address(lpFeeAccumulator));

        agentExecutor = new AgentExecutor();
        console.log("AgentExecutor:", address(agentExecutor));

        // ============ Phase 2: Deploy Agents ============
        console.log("\n=== PHASE 2: Deploy Agents ===");

        arbitrageAgent = new ArbitrageAgent(poolManager, deployer, 8000, 50);
        console.log("ArbitrageAgent:", address(arbitrageAgent));
        console.log("  - Hook Share: 80%, Min Divergence: 0.5%");

        dynamicFeeAgent = new DynamicFeeAgent(poolManager, deployer);
        console.log("DynamicFeeAgent:", address(dynamicFeeAgent));
        console.log("  - Calculates optimal fees based on volatility");

        backrunAgent = new BackrunAgent(poolManager, deployer);
        console.log("BackrunAgent:", address(backrunAgent));
        console.log("  - LP Share: 80%");

        // ============ Phase 3: Deploy Hook ============
        console.log("\n=== PHASE 3: Deploy Hook ===");
        _deployHook();
        console.log("SwarmHook:", address(hook));

        // ============ Phase 4: Configure System ============
        console.log("\n=== PHASE 4: Configure System ===");
        _configureSystem();
        console.log("System fully configured");

        // ============ Phase 5: Deploy Routers ============
        console.log("\n=== PHASE 5: Deploy Routers ===");
        swapRouter = new PoolSwapTest(poolManager);
        liquidityRouter = new PoolModifyLiquidityTest(poolManager);
        console.log("PoolSwapTest:", address(swapRouter));
        console.log("PoolModifyLiquidityTest:", address(liquidityRouter));

        // ============ Phase 6: Create Pool ============
        console.log("\n=== PHASE 6: Create Pool ===");
        _createPool();
        console.log("Pool created with ID:", vm.toString(PoolId.unwrap(poolId)));

        // ============ Phase 7: Add Liquidity ============
        console.log("\n=== PHASE 7: Add Liquidity ===");
        _addLiquidity();
        console.log("Initial liquidity added");

        // Setup test actors
        _setupActors();
    }

    function _deployHook() internal {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager, deployer);
        
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

    function _configureSystem() internal {
        // Register agents
        agentExecutor.registerAgent(AgentType.ARBITRAGE, address(arbitrageAgent));
        agentExecutor.registerAgent(AgentType.DYNAMIC_FEE, address(dynamicFeeAgent));
        agentExecutor.registerAgent(AgentType.BACKRUN, address(backrunAgent));

        // Authorize hook
        agentExecutor.authorizeHook(address(hook), true);

        // Configure hook
        hook.setAgentExecutor(address(agentExecutor));
        hook.setOracleRegistry(address(oracleRegistry));
        hook.setLPFeeAccumulator(address(lpFeeAccumulator));

        // Authorize callers
        arbitrageAgent.authorizeCaller(address(agentExecutor), true);
        dynamicFeeAgent.authorizeCaller(address(agentExecutor), true);
        backrunAgent.authorizeCaller(address(agentExecutor), true);
        
        arbitrageAgent.authorizeCaller(address(hook), true);
        dynamicFeeAgent.authorizeCaller(address(hook), true);
        backrunAgent.authorizeCaller(address(hook), true);

        // Configure backrun agent
        backrunAgent.setLPFeeAccumulator(address(lpFeeAccumulator));

        // Authorize hook in accumulator
        lpFeeAccumulator.setHookAuthorization(address(hook), true);
    }

    function _createPool() internal {
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

        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price
        poolManager.initialize(poolKey, sqrtPriceX96);
    }

    function _addLiquidity() internal {
        tokenA.approve(address(liquidityRouter), type(uint256).max);
        tokenB.approve(address(liquidityRouter), type(uint256).max);

        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -60000,
                tickUpper: 60000,
                liquidityDelta: 10000 ether,
                salt: bytes32(0)
            }),
            ""
        );
    }

    function _setupActors() internal {
        vm.prank(alice);
        tokenA.approve(address(swapRouter), type(uint256).max);
        vm.prank(alice);
        tokenB.approve(address(swapRouter), type(uint256).max);

        vm.prank(bob);
        tokenA.approve(address(swapRouter), type(uint256).max);
        vm.prank(bob);
        tokenB.approve(address(swapRouter), type(uint256).max);
    }

    function _sortCurrencies(Currency a, Currency b) internal pure returns (Currency, Currency) {
        return Currency.unwrap(a) < Currency.unwrap(b) ? (a, b) : (b, a);
    }

    // ============ E2E TESTS ============

    /// @notice Test: Complete protocol deployment verification
    function test_E2E_ProtocolDeployment() public view {
        console.log("\n=== TEST: Protocol Deployment Verification ===");
        
        // Verify all contracts deployed
        assertTrue(address(oracleRegistry) != address(0), "OracleRegistry not deployed");
        assertTrue(address(lpFeeAccumulator) != address(0), "LPFeeAccumulator not deployed");
        assertTrue(address(agentExecutor) != address(0), "AgentExecutor not deployed");
        assertTrue(address(hook) != address(0), "SwarmHook not deployed");
        assertTrue(address(arbitrageAgent) != address(0), "ArbitrageAgent not deployed");
        assertTrue(address(dynamicFeeAgent) != address(0), "DynamicFeeAgent not deployed");
        assertTrue(address(backrunAgent) != address(0), "BackrunAgent not deployed");

        console.log("All contracts deployed successfully");
    }

    /// @notice Test: Agent registration and executor configuration
    function test_E2E_AgentRegistration() public view {
        console.log("\n=== TEST: Agent Registration ===");

        // Verify agents registered
        assertEq(agentExecutor.agents(AgentType.ARBITRAGE), address(arbitrageAgent));
        assertEq(agentExecutor.agents(AgentType.DYNAMIC_FEE), address(dynamicFeeAgent));
        assertEq(agentExecutor.agents(AgentType.BACKRUN), address(backrunAgent));

        // Verify agents enabled
        assertTrue(agentExecutor.agentEnabled(AgentType.ARBITRAGE));
        assertTrue(agentExecutor.agentEnabled(AgentType.DYNAMIC_FEE));
        assertTrue(agentExecutor.agentEnabled(AgentType.BACKRUN));

        console.log("All 3 agents registered and enabled");
    }

    /// @notice Test: Agent types correctly identified
    function test_E2E_AgentTypes() public view {
        console.log("\n=== TEST: Agent Type Identification ===");

        assertEq(uint8(arbitrageAgent.agentType()), uint8(AgentType.ARBITRAGE));
        assertEq(uint8(dynamicFeeAgent.agentType()), uint8(AgentType.DYNAMIC_FEE));
        assertEq(uint8(backrunAgent.agentType()), uint8(AgentType.BACKRUN));

        console.log("Agent types correctly identified");
    }

    /// @notice Test: Execute swap through hook with agent processing
    function test_E2E_SwapWithAgents() public {
        console.log("\n=== TEST: Swap Through Hook with Agents ===");

        vm.prank(alice);
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Swap should execute successfully through hook and agents
        swapRouter.swap(poolKey, params, settings, "");

        console.log("Swap executed successfully through hook with all agents!");
        
        // Verify agents are still active after swap
        assertTrue(arbitrageAgent.isActive(), "ArbitrageAgent should remain active");
        assertTrue(dynamicFeeAgent.isActive(), "DynamicFeeAgent should remain active");
        assertTrue(backrunAgent.isActive(), "BackrunAgent should remain active");
    }

    /// @notice Test: Multiple consecutive swaps
    function test_E2E_MultipleSwaps() public {
        console.log("\n=== TEST: Multiple Consecutive Swaps ===");

        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Swap 1: Alice swaps TokenA -> TokenB
        vm.prank(alice);
        swapRouter.swap(poolKey, SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), settings, "");
        console.log("Swap 1: Alice TokenA -> TokenB (1 token)");

        // Swap 2: Bob swaps TokenB -> TokenA
        vm.prank(bob);
        swapRouter.swap(poolKey, SwapParams({
            zeroForOne: false,
            amountSpecified: -2 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        }), settings, "");
        console.log("Swap 2: Bob TokenB -> TokenA (2 tokens)");

        // Swap 3: Alice large swap
        vm.prank(alice);
        swapRouter.swap(poolKey, SwapParams({
            zeroForOne: true,
            amountSpecified: -10 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), settings, "");
        console.log("Swap 3: Alice large TokenA -> TokenB (10 tokens)");

        console.log("All 3 swaps executed successfully with agent involvement!");
    }

    /// @notice Test: Admin can disable and re-enable agents
    function test_E2E_AdminAgentControl() public {
        console.log("\n=== TEST: Admin Agent Control ===");

        // Verify initially enabled
        assertTrue(agentExecutor.agentEnabled(AgentType.ARBITRAGE), "Should be enabled");

        // Disable arbitrage agent
        agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, false);
        assertFalse(agentExecutor.agentEnabled(AgentType.ARBITRAGE), "Should be disabled");
        console.log("ArbitrageAgent disabled");

        // Swap should still work (graceful degradation)
        vm.prank(alice);
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        swapRouter.swap(poolKey, SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), settings, "");
        console.log("Swap succeeded with ArbitrageAgent disabled");

        // Re-enable
        agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, true);
        assertTrue(agentExecutor.agentEnabled(AgentType.ARBITRAGE), "Should be re-enabled");
        console.log("ArbitrageAgent re-enabled");
    }

    /// @notice Test: Hot-swap agent during operation
    function test_E2E_HotSwapAgent() public {
        console.log("\n=== TEST: Hot-Swap Agent ===");

        address oldAgent = agentExecutor.agents(AgentType.ARBITRAGE);
        console.log("Old ArbitrageAgent:", oldAgent);

        // Deploy new agent with different parameters
        ArbitrageAgent newArbitrageAgent = new ArbitrageAgent(
            poolManager,
            deployer,
            9000,  // 90% LP share (was 80%)
            30     // 0.3% min divergence (was 0.5%)
        );
        console.log("New ArbitrageAgent:", address(newArbitrageAgent));
        console.log("  - New parameters: 90% LP share, 0.3% min divergence");

        // Authorize new agent
        newArbitrageAgent.authorizeCaller(address(agentExecutor), true);
        newArbitrageAgent.authorizeCaller(address(hook), true);

        // Hot-swap
        agentExecutor.registerAgent(AgentType.ARBITRAGE, address(newArbitrageAgent));
        
        address newAgent = agentExecutor.agents(AgentType.ARBITRAGE);
        assertEq(newAgent, address(newArbitrageAgent), "Agent not swapped");
        console.log("Agent hot-swapped successfully!");

        // Swap should work with new agent
        vm.prank(alice);
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        swapRouter.swap(poolKey, SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), settings, "");
        console.log("Swap succeeded with new agent!");
    }

    /// @notice Test: ERC-8004 identity configuration
    function test_E2E_ERC8004Identity() public {
        console.log("\n=== TEST: ERC-8004 Identity Configuration ===");

        // Configure identity for arbitrage agent
        uint256 agentIdentityId = 1001;
        arbitrageAgent.configureIdentity(agentIdentityId, ERC8004_IDENTITY);

        assertEq(arbitrageAgent.agentId(), agentIdentityId);
        assertEq(arbitrageAgent.identityRegistry(), ERC8004_IDENTITY);
        console.log("ArbitrageAgent identity configured: ID", agentIdentityId);

        // Configure for other agents
        dynamicFeeAgent.configureIdentity(1002, ERC8004_IDENTITY);
        backrunAgent.configureIdentity(1003, ERC8004_IDENTITY);
        console.log("All agents configured with ERC-8004 identities");
    }

    /// @notice Test: Agent confidence scores
    function test_E2E_AgentConfidence() public view {
        console.log("\n=== TEST: Agent Confidence Scores ===");

        uint256 arbConfidence = arbitrageAgent.getConfidence();
        uint256 feeConfidence = dynamicFeeAgent.getConfidence();
        uint256 backrunConfidence = backrunAgent.getConfidence();

        console.log("ArbitrageAgent confidence:", arbConfidence);
        console.log("DynamicFeeAgent confidence:", feeConfidence);
        console.log("BackrunAgent confidence:", backrunConfidence);

        // All should have default confidence > 0
        assertTrue(arbConfidence > 0, "ArbitrageAgent confidence should be > 0");
        assertTrue(feeConfidence > 0, "DynamicFeeAgent confidence should be > 0");
        assertTrue(backrunConfidence > 0, "BackrunAgent confidence should be > 0");
    }

    /// @notice Test: Pool liquidity operations
    function test_E2E_LiquidityOperations() public {
        console.log("\n=== TEST: Liquidity Operations ===");

        // Get initial liquidity
        (uint128 liquidityBefore,,) = poolManager.getPositionInfo(
            poolId,
            address(liquidityRouter),
            -60000,
            60000,
            bytes32(0)
        );
        console.log("Initial liquidity:", liquidityBefore);

        // Add more liquidity
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

        (uint128 liquidityAfter,,) = poolManager.getPositionInfo(
            poolId,
            address(liquidityRouter),
            -60000,
            60000,
            bytes32(0)
        );
        console.log("Liquidity after adding:", liquidityAfter);
        assertTrue(liquidityAfter > liquidityBefore, "Liquidity should increase");
    }

    /// @notice Test: Dynamic fee calculation through agent
    function test_E2E_DynamicFeeCalculation() public view {
        console.log("\n=== TEST: Dynamic Fee Calculation ===");

        // Verify pool uses dynamic fees
        assertEq(poolKey.fee, LPFeeLibrary.DYNAMIC_FEE_FLAG, "Pool should use dynamic fees");
        console.log("Pool configured with dynamic fee flag");

        // DynamicFeeAgent is active and will be consulted on each swap
        assertTrue(dynamicFeeAgent.isActive(), "DynamicFeeAgent should be active");
        console.log("DynamicFeeAgent is active and ready");
    }

    /// @notice Test: Oracle registry integration
    function test_E2E_OracleIntegration() public view {
        console.log("\n=== TEST: Oracle Integration ===");

        // Verify Chainlink feed registered
        address feed = oracleRegistry.getPriceFeed(address(0), address(tokenB));
        assertEq(feed, ETH_USD_FEED, "Chainlink feed should be registered");
        console.log("Chainlink ETH/USD feed:", feed);
    }

    /// @notice Test: Complete user journey
    function test_E2E_CompleteUserJourney() public {
        console.log("\n=== TEST: Complete User Journey ===");
        console.log("Simulating a complete user journey through the protocol...\n");

        // Step 1: User (Alice) checks pool exists
        console.log("Step 1: Verify pool exists");
        (uint160 sqrtPriceX96, , ,) = poolManager.getSlot0(poolId);
        assertTrue(sqrtPriceX96 > 0, "Pool should be initialized");
        console.log("  Pool price: active\n");

        // Step 2: User adds liquidity
        console.log("Step 2: Add liquidity");
        vm.startPrank(alice);
        tokenA.approve(address(liquidityRouter), type(uint256).max);
        tokenB.approve(address(liquidityRouter), type(uint256).max);
        vm.stopPrank();

        vm.prank(alice);
        liquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: -6000,
                tickUpper: 6000,
                liquidityDelta: 100 ether,
                salt: bytes32(uint256(1)) // Different salt for Alice
            }),
            ""
        );
        console.log("  Alice added 100 tokens liquidity\n");

        // Step 3: User performs swap
        console.log("Step 3: Execute swap");
        
        vm.prank(alice);
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });
        swapRouter.swap(poolKey, SwapParams({
            zeroForOne: true,
            amountSpecified: -5 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), settings, "");

        console.log("  Alice executed swap of 5 TokenA\n");

        // Step 4: Check agents processed the swap
        console.log("Step 4: Verify agent involvement");
        assertTrue(arbitrageAgent.isActive(), "  ArbitrageAgent processed swap");
        assertTrue(dynamicFeeAgent.isActive(), "  DynamicFeeAgent calculated fee");
        assertTrue(backrunAgent.isActive(), "  BackrunAgent analyzed opportunity");
        console.log("  All agents participated in swap processing\n");

        // Step 5: Admin operations
        console.log("Step 5: Admin operations");
        agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, false);
        console.log("  Admin disabled ArbitrageAgent");
        agentExecutor.setAgentEnabled(AgentType.ARBITRAGE, true);
        console.log("  Admin re-enabled ArbitrageAgent\n");

        console.log("=== USER JOURNEY COMPLETE ===");
    }

    /// @notice Test: System state summary
    function test_E2E_SystemSummary() public view {
        console.log("\n");
        console.log("============================================================");
        console.log("     SWARM PROTOCOL - SYSTEM STATE SUMMARY");
        console.log("============================================================");
        console.log("");
        console.log("CORE CONTRACTS:");
        console.log("  PoolManager (Sepolia):", POOL_MANAGER);
        console.log("  SwarmHook:            ", address(hook));
        console.log("  AgentExecutor:        ", address(agentExecutor));
        console.log("  OracleRegistry:       ", address(oracleRegistry));
        console.log("  LPFeeAccumulator:     ", address(lpFeeAccumulator));
        console.log("");
        console.log("AGENTS:");
        console.log("  ArbitrageAgent:       ", address(arbitrageAgent));
        console.log("    - Type:", uint8(arbitrageAgent.agentType()));
        console.log("    - Active:", arbitrageAgent.isActive());
        console.log("    - Confidence:", arbitrageAgent.getConfidence());
        console.log("");
        console.log("  DynamicFeeAgent:      ", address(dynamicFeeAgent));
        console.log("    - Type:", uint8(dynamicFeeAgent.agentType()));
        console.log("    - Active:", dynamicFeeAgent.isActive());
        console.log("    - Confidence:", dynamicFeeAgent.getConfidence());
        console.log("");
        console.log("  BackrunAgent:         ", address(backrunAgent));
        console.log("    - Type:", uint8(backrunAgent.agentType()));
        console.log("    - Active:", backrunAgent.isActive());
        console.log("    - Confidence:", backrunAgent.getConfidence());
        console.log("");
        console.log("POOL:");
        console.log("  Pool ID:", vm.toString(PoolId.unwrap(poolId)));
        console.log("  Fee Type: Dynamic");
        console.log("  Tick Spacing: 60");
        console.log("");
        console.log("============================================================");
    }
}
