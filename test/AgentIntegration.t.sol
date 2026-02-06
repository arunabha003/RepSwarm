// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {ISwarmAgent, IBackrunAgent, AgentType, SwapContext, AgentResult} from "../src/interfaces/ISwarmAgent.sol";
import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {DynamicFeeAgent} from "../src/agents/DynamicFeeAgent.sol";
import {BackrunAgent} from "../src/agents/BackrunAgent.sol";

/// @title AgentIntegrationTest
/// @notice Tests for the new agent-driven architecture
/// @dev Tests AgentExecutor routing and individual agent behavior
contract AgentIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Core contracts
    AgentExecutor public executor;
    ArbitrageAgent public arbAgent;
    DynamicFeeAgent public feeAgent;
    BackrunAgent public backrunAgent;

    // Mock addresses
    address public mockPoolManager = makeAddr("poolManager");
    address public mockHook = makeAddr("hook");
    address public admin;

    // Test pool
    PoolKey public testPoolKey;
    PoolId public testPoolId;

    function setUp() public {
        admin = address(this);

        // Deploy executor
        executor = new AgentExecutor();

        // Deploy agents with proper constructors
        arbAgent = new ArbitrageAgent(
            IPoolManager(mockPoolManager),
            admin,
            8000, // 80% hook share
            50 // 0.5% min divergence
        );

        feeAgent = new DynamicFeeAgent(IPoolManager(mockPoolManager), admin);

        backrunAgent = new BackrunAgent(IPoolManager(mockPoolManager), admin);

        // Register agents with executor
        executor.registerAgent(AgentType.ARBITRAGE, address(arbAgent));
        executor.registerAgent(AgentType.DYNAMIC_FEE, address(feeAgent));
        executor.registerAgent(AgentType.BACKRUN, address(backrunAgent));

        // Authorize executor to call agents
        arbAgent.authorizeCaller(address(executor), true);
        feeAgent.authorizeCaller(address(executor), true);
        backrunAgent.authorizeCaller(address(executor), true);

        // Create test pool key
        testPoolKey = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(mockHook)
        });
        testPoolId = testPoolKey.toId();
    }

    // ============ Agent Registration Tests ============

    function test_AgentRegistration() public view {
        // Verify all agents are registered
        assertEq(executor.agents(AgentType.ARBITRAGE), address(arbAgent));
        assertEq(executor.agents(AgentType.DYNAMIC_FEE), address(feeAgent));
        assertEq(executor.agents(AgentType.BACKRUN), address(backrunAgent));

        // Verify all enabled by default
        assertTrue(executor.agentEnabled(AgentType.ARBITRAGE));
        assertTrue(executor.agentEnabled(AgentType.DYNAMIC_FEE));
        assertTrue(executor.agentEnabled(AgentType.BACKRUN));
    }

    function test_AgentTypeIdentification() public view {
        assertEq(uint8(arbAgent.agentType()), uint8(AgentType.ARBITRAGE));
        assertEq(uint8(feeAgent.agentType()), uint8(AgentType.DYNAMIC_FEE));
        assertEq(uint8(backrunAgent.agentType()), uint8(AgentType.BACKRUN));
    }

    function test_AdminCanDisableAgent() public {
        // Disable arbitrage agent
        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        assertFalse(executor.agentEnabled(AgentType.ARBITRAGE));

        // Re-enable
        executor.setAgentEnabled(AgentType.ARBITRAGE, true);
        assertTrue(executor.agentEnabled(AgentType.ARBITRAGE));
    }

    function test_AdminCanSwapAgent() public {
        // Deploy new arbitrage agent
        ArbitrageAgent newArbAgent = new ArbitrageAgent(
            IPoolManager(mockPoolManager),
            admin,
            9000, // different params
            100
        );

        // Swap agent
        executor.registerAgent(AgentType.ARBITRAGE, address(newArbAgent));

        assertEq(executor.agents(AgentType.ARBITRAGE), address(newArbAgent));
    }

    function test_NonOwnerCannotRegisterAgent() public {
        address notOwner = makeAddr("notOwner");

        ArbitrageAgent newAgent = new ArbitrageAgent(IPoolManager(mockPoolManager), notOwner, 8000, 50);

        vm.prank(notOwner);
        vm.expectRevert();
        executor.registerAgent(AgentType.ARBITRAGE, address(newAgent));
    }

    // ============ Agent Activation Tests ============

    function test_AgentActivation() public {
        // All agents start active
        assertTrue(arbAgent.isActive());
        assertTrue(feeAgent.isActive());
        assertTrue(backrunAgent.isActive());

        // Deactivate an agent
        arbAgent.setActive(false);
        assertFalse(arbAgent.isActive());

        // Reactivate
        arbAgent.setActive(true);
        assertTrue(arbAgent.isActive());
    }

    // ============ ERC-8004 Compatibility Tests ============

    function test_AgentCanConfigureIdentity() public {
        uint256 erc8004Id = 12345;
        address identityRegistry = makeAddr("identityRegistry");

        arbAgent.configureIdentity(erc8004Id, identityRegistry);

        // Check via getAgentId
        assertEq(arbAgent.getAgentId(), erc8004Id);
    }

    function test_AgentSupportsISwarmAgentInterface() public view {
        // All agents implement ISwarmAgent
        assertTrue(arbAgent.agentType() == AgentType.ARBITRAGE);
        assertTrue(feeAgent.agentType() == AgentType.DYNAMIC_FEE);
        assertTrue(backrunAgent.agentType() == AgentType.BACKRUN);
    }

    function test_AgentHasConfidence() public view {
        // All agents have default confidence
        assertTrue(arbAgent.getConfidence() > 0);
        assertTrue(feeAgent.getConfidence() > 0);
        assertTrue(backrunAgent.getConfidence() > 0);
    }

    function test_BackrunDirection_FollowsPriceRelation_WhenPoolBelowOracle() public view {
        SwapParams memory params = SwapParams({zeroForOne: false, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: 0});
        SwapContext memory context = SwapContext({
            poolKey: testPoolKey,
            poolId: testPoolId,
            params: params,
            poolPrice: 900e18,
            oraclePrice: 1000e18,
            oracleConfidence: 0,
            liquidity: 1_000_000 ether,
            hookData: ""
        });

        IBackrunAgent.BackrunOpportunity memory opp = backrunAgent.analyzeBackrun(context, 900e18);
        assertTrue(opp.shouldBackrun, "should detect divergence");
        assertTrue(!opp.zeroForOne, "when pool below oracle, direction must be oneForZero");
        assertTrue(opp.backrunAmount > 0, "backrun amount should be positive");
    }

    function test_BackrunDirection_FollowsPriceRelation_WhenPoolAboveOracle() public view {
        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: -int256(1 ether), sqrtPriceLimitX96: 0});
        SwapContext memory context = SwapContext({
            poolKey: testPoolKey,
            poolId: testPoolId,
            params: params,
            poolPrice: 1100e18,
            oraclePrice: 1000e18,
            oracleConfidence: 0,
            liquidity: 1_000_000 ether,
            hookData: ""
        });

        IBackrunAgent.BackrunOpportunity memory opp = backrunAgent.analyzeBackrun(context, 1100e18);
        assertTrue(opp.shouldBackrun, "should detect divergence");
        assertTrue(opp.zeroForOne, "when pool above oracle, direction must be zeroForOne");
        assertTrue(opp.backrunAmount > 0, "backrun amount should be positive");
    }
}
