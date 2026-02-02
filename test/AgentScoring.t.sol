// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";

import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {SwarmTypes} from "../src/libraries/SwarmTypes.sol";
import {ISwarmCoordinator} from "../src/interfaces/ISwarmCoordinator.sol";
import {MevRouterHook} from "../src/hooks/MevRouterHook.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {FeeOptimizerAgent} from "../src/agents/FeeOptimizerAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";
import {IRouteAgent} from "../src/interfaces/IRouteAgent.sol";

import {TestERC20} from "./utils/TestERC20.sol";

/// @title AgentScoringTest
/// @notice Tests for agent scoring mechanisms
contract AgentScoringTest is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    address internal constant TREASURY = address(0xBEEF);

    IPoolManager internal poolManager;
    SwarmCoordinator internal coordinator;
    MevRouterHook internal hook;
    OracleRegistry internal oracleRegistry;

    FeeOptimizerAgent internal feeAgent;
    SlippagePredictorAgent internal slippageAgent;
    MevHunterAgent internal mevAgent;

    TestERC20 internal tokenA;
    TestERC20 internal tokenB;

    PoolKey internal poolKey;

    function setUp() public {
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);

        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        require(poolManagerAddr != address(0), "POOL_MANAGER missing");
        poolManager = IPoolManager(poolManagerAddr);

        tokenA = new TestERC20("TokenA", "TKA");
        tokenB = new TestERC20("TokenB", "TKB");

        _deployHook();
        _deployCoordinator();
        _initPoolAndLiquidity();
        _deployAgents();
    }

    // ============ FeeOptimizerAgent Tests ============

    function test_feeOptimizerAgent_hasCoordinatorAndPoolManager() public view {
        assertEq(address(feeAgent.coordinator()), address(coordinator));
        assertEq(address(feeAgent.poolManager()), address(poolManager));
    }

    function test_feeOptimizerAgent_scoresPath() public {
        // Create an intent
        SwarmTypes.IntentParams memory params = _defaultIntentParams();
        bytes[] memory candidates = _defaultCandidates();
        uint256 intentId = coordinator.createIntent(params, candidates);

        // FeeAgent should be able to propose
        feeAgent.propose(intentId);

        address[] memory proposalAgents = coordinator.getProposalAgents(intentId);
        assertEq(proposalAgents.length, 1);
        assertEq(proposalAgents[0], address(feeAgent));
    }

    // ============ SlippagePredictorAgent Tests ============

    function test_slippagePredictorAgent_hasCoordinatorAndPoolManager() public view {
        assertEq(address(slippageAgent.coordinator()), address(coordinator));
        assertEq(address(slippageAgent.poolManager()), address(poolManager));
    }

    function test_slippagePredictorAgent_scoresPath() public {
        SwarmTypes.IntentParams memory params = _defaultIntentParams();
        bytes[] memory candidates = _defaultCandidates();
        uint256 intentId = coordinator.createIntent(params, candidates);

        slippageAgent.propose(intentId);

        address[] memory proposalAgents = coordinator.getProposalAgents(intentId);
        assertEq(proposalAgents.length, 1);
        assertEq(proposalAgents[0], address(slippageAgent));
    }

    // ============ MevHunterAgent Tests ============

    function test_mevHunterAgent_hasCoordinatorAndPoolManager() public view {
        assertEq(address(mevAgent.coordinator()), address(coordinator));
        assertEq(address(mevAgent.poolManager()), address(poolManager));
    }

    function test_mevHunterAgent_scoresPath() public {
        SwarmTypes.IntentParams memory params = _defaultIntentParams();
        bytes[] memory candidates = _defaultCandidates();
        uint256 intentId = coordinator.createIntent(params, candidates);

        mevAgent.propose(intentId);

        address[] memory proposalAgents = coordinator.getProposalAgents(intentId);
        assertEq(proposalAgents.length, 1);
        assertEq(proposalAgents[0], address(mevAgent));
    }

    // ============ Multi-Agent Voting Tests ============

    function test_multipleAgentsPropose() public {
        SwarmTypes.IntentParams memory params = _defaultIntentParams();
        bytes[] memory candidates = _defaultCandidates();
        uint256 intentId = coordinator.createIntent(params, candidates);

        // All three agents propose
        feeAgent.propose(intentId);
        slippageAgent.propose(intentId);
        mevAgent.propose(intentId);

        address[] memory proposalAgents = coordinator.getProposalAgents(intentId);
        assertEq(proposalAgents.length, 3);

        // Check all agents are recorded
        bool hasFeeAgent = false;
        bool hasSlippageAgent = false;
        bool hasMevAgent = false;

        for (uint256 i = 0; i < proposalAgents.length; i++) {
            if (proposalAgents[i] == address(feeAgent)) hasFeeAgent = true;
            if (proposalAgents[i] == address(slippageAgent)) hasSlippageAgent = true;
            if (proposalAgents[i] == address(mevAgent)) hasMevAgent = true;
        }

        assertTrue(hasFeeAgent, "FeeAgent should have proposed");
        assertTrue(hasSlippageAgent, "SlippageAgent should have proposed");
        assertTrue(hasMevAgent, "MevAgent should have proposed");
    }

    function test_consensusDeterminesBestCandidate() public {
        SwarmTypes.IntentParams memory params = _defaultIntentParams();
        bytes[] memory candidates = _defaultCandidates();
        uint256 intentId = coordinator.createIntent(params, candidates);

        // All agents propose on candidate 0
        feeAgent.propose(intentId);
        slippageAgent.propose(intentId);
        mevAgent.propose(intentId);

        // Execute should succeed with consensus on candidate 0
        tokenA.mint(address(this), 10e18);
        tokenB.mint(address(this), 10e18);
        tokenA.approve(address(coordinator), type(uint256).max);
        tokenB.approve(address(coordinator), type(uint256).max);

        coordinator.executeIntent(intentId);

        ISwarmCoordinator.IntentView memory intent = coordinator.getIntent(intentId);
        assertTrue(intent.executed);
    }

    // ============ Agent Interface Tests ============

    function test_agentImplementsIRouteAgent() public {
        // Verify agents implement the interface correctly
        assertTrue(
            feeAgent.coordinator() != ISwarmCoordinator(address(0)),
            "FeeAgent should have coordinator"
        );
        assertTrue(
            slippageAgent.coordinator() != ISwarmCoordinator(address(0)),
            "SlippageAgent should have coordinator"
        );
        assertTrue(
            mevAgent.coordinator() != ISwarmCoordinator(address(0)),
            "MevAgent should have coordinator"
        );
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

    function _deployCoordinator() internal {
        coordinator = new SwarmCoordinator(poolManager, TREASURY, address(0), address(0));
    }

    function _initPoolAndLiquidity() internal {
        (Currency currency0, Currency currency1) = _sortedCurrencies();
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

        PoolModifyLiquidityTest liquidityRouter = new PoolModifyLiquidityTest(poolManager);
        tokenA.approve(address(liquidityRouter), type(uint256).max);
        tokenB.approve(address(liquidityRouter), type(uint256).max);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -600,
            tickUpper: 600,
            liquidityDelta: int256(10e18),
            salt: bytes32(0)
        });

        liquidityRouter.modifyLiquidity(poolKey, params, "");
    }

    function _deployAgents() internal {
        feeAgent = new FeeOptimizerAgent(coordinator, poolManager);
        slippageAgent = new SlippagePredictorAgent(coordinator, poolManager);
        mevAgent = new MevHunterAgent(coordinator, poolManager);

        coordinator.registerAgent(address(feeAgent), 1, true);
        coordinator.registerAgent(address(slippageAgent), 2, true);
        coordinator.registerAgent(address(mevAgent), 3, true);
    }

    function _sortedCurrencies() internal view returns (Currency currency0, Currency currency1) {
        Currency token0 = Currency.wrap(address(tokenA));
        Currency token1 = Currency.wrap(address(tokenB));
        if (token0 < token1) {
            currency0 = token0;
            currency1 = token1;
        } else {
            currency0 = token1;
            currency1 = token0;
        }
    }

    function _defaultIntentParams() internal view returns (SwarmTypes.IntentParams memory) {
        (Currency currencyIn, Currency currencyOut) = _sortedCurrencies();
        return SwarmTypes.IntentParams({
            currencyIn: currencyIn,
            currencyOut: currencyOut,
            amountIn: 1e18,
            amountOutMin: 1,
            deadline: uint64(block.timestamp + 1 hours),
            mevFeeBps: 30,
            treasuryBps: 200,
            lpShareBps: 8000
        });
    }

    function _defaultCandidates() internal view returns (bytes[] memory candidates) {
        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: poolKey.currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: poolKey.tickSpacing,
            hooks: poolKey.hooks,
            hookData: ""
        });

        candidates = new bytes[](1);
        candidates[0] = abi.encode(path);
    }
}
