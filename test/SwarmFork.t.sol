// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

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

import {TestERC20} from "./utils/TestERC20.sol";

contract SwarmForkTest is Test {
    using CurrencyLibrary for Currency;

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

    function test_endToEndIntentSwap() public {
        (Currency currencyIn, Currency currencyOut) = _intentCurrencies();

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: currencyOut,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: poolKey.tickSpacing,
            hooks: poolKey.hooks,
            hookData: ""
        });

        bytes[] memory candidates = new bytes[](1);
        candidates[0] = abi.encode(path);

        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: currencyIn,
            currencyOut: currencyOut,
            amountIn: 1e18,
            amountOutMin: 1,
            deadline: uint64(block.timestamp + 1 hours),
            mevFeeBps: 30,
            treasuryBps: 200,
            lpShareBps: 8000 // 80% to LPs
        });

        uint256 intentId = coordinator.createIntent(params, candidates);

        feeAgent.propose(intentId);
        slippageAgent.propose(intentId);
        mevAgent.propose(intentId);

        _approveCoordinator(currencyIn);
        uint256 treasuryBalanceBefore = currencyOut.balanceOf(TREASURY);
        uint256 outBalanceBefore = currencyOut.balanceOf(address(this));

        coordinator.executeIntent(intentId);

        uint256 outBalanceAfter = currencyOut.balanceOf(address(this));
        uint256 treasuryBalanceAfter = currencyOut.balanceOf(TREASURY);
        assertGt(outBalanceAfter, outBalanceBefore, "User should receive output tokens");
        assertGt(treasuryBalanceAfter, treasuryBalanceBefore, "Treasury should receive fees");

        ISwarmCoordinator.IntentView memory intentView = coordinator.getIntent(intentId);
        assertTrue(intentView.executed, "Intent should be marked executed");
    }

    function test_mevCaptureAndLpDonation() public {
        (Currency currencyIn, Currency currencyOut) = _intentCurrencies();

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: currencyOut,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: poolKey.tickSpacing,
            hooks: poolKey.hooks,
            hookData: ""
        });

        bytes[] memory candidates = new bytes[](1);
        candidates[0] = abi.encode(path);

        // Higher MEV fee and LP share to test redistribution
        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: currencyIn,
            currencyOut: currencyOut,
            amountIn: 1e18,
            amountOutMin: 1,
            deadline: uint64(block.timestamp + 1 hours),
            mevFeeBps: 100, // 1% MEV fee
            treasuryBps: 500, // 5% total fee
            lpShareBps: 8000 // 80% of fees to LPs
        });

        uint256 intentId = coordinator.createIntent(params, candidates);

        feeAgent.propose(intentId);
        
        _approveCoordinator(currencyIn);
        
        // Record balances before
        uint256 treasuryBefore = currencyOut.balanceOf(TREASURY);
        
        coordinator.executeIntent(intentId);
        
        // Treasury should have received 20% of the fee (lpShareBps = 80% to LPs)
        uint256 treasuryAfter = currencyOut.balanceOf(TREASURY);
        assertGt(treasuryAfter, treasuryBefore, "Treasury should receive its share");
    }

    function test_multipleAgentVoting() public {
        (Currency currencyIn, Currency currencyOut) = _intentCurrencies();

        // Create two different path candidates
        PathKey[] memory path1 = new PathKey[](1);
        path1[0] = PathKey({
            intermediateCurrency: currencyOut,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: poolKey.tickSpacing,
            hooks: poolKey.hooks,
            hookData: ""
        });

        bytes[] memory candidates = new bytes[](1);
        candidates[0] = abi.encode(path1);

        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: currencyIn,
            currencyOut: currencyOut,
            amountIn: 1e17, // Smaller amount
            amountOutMin: 1,
            deadline: uint64(block.timestamp + 1 hours),
            mevFeeBps: 50,
            treasuryBps: 100,
            lpShareBps: 7000 // 70% to LPs
        });

        uint256 intentId = coordinator.createIntent(params, candidates);

        // All three agents vote
        feeAgent.propose(intentId);
        slippageAgent.propose(intentId);
        mevAgent.propose(intentId);

        // Verify proposals were recorded
        address[] memory proposalAgents = coordinator.getProposalAgents(intentId);
        assertEq(proposalAgents.length, 3, "Should have 3 proposals");

        _approveCoordinator(currencyIn);
        coordinator.executeIntent(intentId);

        ISwarmCoordinator.IntentView memory intentView = coordinator.getIntent(intentId);
        assertTrue(intentView.executed);
    }

    function _deployHook() internal {
        // Deploy oracle registry first
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
            liquidityDelta: int256(1e18),
            salt: bytes32(0)
        });

        liquidityRouter.modifyLiquidity(poolKey, params, "");
    }

    function _deployAgents() internal {
        feeAgent = new FeeOptimizerAgent(coordinator, poolManager);
        slippageAgent = new SlippagePredictorAgent(coordinator, poolManager);
        mevAgent = new MevHunterAgent(coordinator, poolManager, IOracleRegistry(address(oracleRegistry)));

        coordinator.registerAgent(address(feeAgent), 1, true);
        coordinator.registerAgent(address(slippageAgent), 2, true);
        coordinator.registerAgent(address(mevAgent), 3, true);
    }

    function _approveCoordinator(Currency currencyIn) internal {
        if (Currency.unwrap(currencyIn) == address(tokenA)) {
            tokenA.approve(address(coordinator), type(uint256).max);
        } else {
            tokenB.approve(address(coordinator), type(uint256).max);
        }
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

    function _intentCurrencies() internal view returns (Currency currencyIn, Currency currencyOut) {
        (Currency currency0, Currency currency1) = _sortedCurrencies();
        currencyIn = currency0;
        currencyOut = currency1;
    }

    function _intent(uint256 intentId) internal view returns (SwarmTypes.Intent memory) {
        ISwarmCoordinator.IntentView memory viewIntent = coordinator.getIntent(intentId);
        return SwarmTypes.Intent({
            requester: viewIntent.requester,
            currencyIn: viewIntent.currencyIn,
            currencyOut: viewIntent.currencyOut,
            amountIn: viewIntent.amountIn,
            amountOutMin: viewIntent.amountOutMin,
            deadline: viewIntent.deadline,
            mevFeeBps: viewIntent.mevFeeBps,
            treasuryBps: viewIntent.treasuryBps,
            lpShareBps: viewIntent.lpShareBps,
            executed: viewIntent.executed
        });
    }

}
