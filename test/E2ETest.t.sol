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
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";

import {SwarmHook} from "../src/hooks/SwarmHook.sol";
import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {DynamicFeeAgent} from "../src/agents/DynamicFeeAgent.sol";
import {BackrunAgent} from "../src/agents/BackrunAgent.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {FlashLoanBackrunner} from "../src/backrun/FlashLoanBackrunner.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {SwarmTypes} from "../src/libraries/SwarmTypes.sol";
import {HookLib} from "../src/libraries/HookLib.sol";

import {AgentType, SwapContext} from "../src/interfaces/ISwarmAgent.sol";
import {IArbitrageAgent} from "../src/interfaces/ISwarmAgent.sol";

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IWETH9Like is IERC20Like {
    function deposit() external payable;
}

/// @title E2ETest
/// @notice Fork-based E2E tests that exercise the full on-chain protocol wiring.
/// @dev Runs on a Sepolia fork (Alchemy URL provided by user).
contract E2ETest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    string internal constant DEFAULT_SEPOLIA_RPC_URL =
        "https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo";

    address internal constant DEFAULT_POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Sepolia token addresses (commonly used test deployments).
    address internal constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address internal constant DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;

    // Chainlink ETH/USD feed (used as WETH/DAI proxy: DAI ~= USD).
    address internal constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    IPoolManager internal poolManager;

    SwarmHook internal hook;
    AgentExecutor internal executor;
    ArbitrageAgent internal arbAgent;
    DynamicFeeAgent internal feeAgent;
    BackrunAgent internal backrunAgent;
    OracleRegistry internal oracleRegistry;
    LPFeeAccumulator internal lpAccumulator;
    FlashLoanBackrunner internal flashBackrunner;

    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal liquidityRouter;

    // Two pools using the same pair:
    // 1) Hooked pool: dynamic fees + SwarmHook
    // 2) Repay pool: vanilla pool used by FlashLoanBackrunner to swap back into the borrowed asset
    PoolKey internal hookPoolKey;
    PoolId internal hookPoolId;
    PoolKey internal repayPoolKey;
    PoolId internal repayPoolId;

    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");
    address internal routeAgent = makeAddr("routeAgent");

    event FeeOverrideApplied(PoolId indexed poolId, uint24 fee);
    event BackrunOpportunityRecorded(PoolId indexed poolId, uint256 amount);

    function setUp() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", DEFAULT_SEPOLIA_RPC_URL);
        vm.createSelectFork(rpc);

        poolManager = IPoolManager(vm.envOr("POOL_MANAGER", DEFAULT_POOL_MANAGER));

        // Deploy protocol contracts
        oracleRegistry = new OracleRegistry();
        oracleRegistry.setPriceFeed(WETH, DAI, ETH_USD_FEED);

        // Low thresholds to allow immediate donation in tests
        lpAccumulator = new LPFeeAccumulator(poolManager, 1, 0);

        executor = new AgentExecutor();
        arbAgent = new ArbitrageAgent(poolManager, address(this), 8000, 50);
        feeAgent = new DynamicFeeAgent(poolManager, address(this));
        backrunAgent = new BackrunAgent(poolManager, address(this));

        hook = _deployHook();

        flashBackrunner = new FlashLoanBackrunner(poolManager, address(0));

        // Wire everything together
        executor.registerAgent(AgentType.ARBITRAGE, address(arbAgent));
        executor.registerAgent(AgentType.DYNAMIC_FEE, address(feeAgent));
        executor.registerAgent(AgentType.BACKRUN, address(backrunAgent));
        executor.authorizeHook(address(hook), true);

        hook.setAgentExecutor(address(executor));
        hook.setOracleRegistry(address(oracleRegistry));
        hook.setLPFeeAccumulator(address(lpAccumulator));
        hook.setBackrunRecorder(address(flashBackrunner));

        arbAgent.authorizeCaller(address(executor), true);
        feeAgent.authorizeCaller(address(executor), true);
        backrunAgent.authorizeCaller(address(executor), true);
        arbAgent.authorizeCaller(address(hook), true);
        feeAgent.authorizeCaller(address(hook), true);
        backrunAgent.authorizeCaller(address(hook), true);

        backrunAgent.setLPFeeAccumulator(address(lpAccumulator));
        backrunAgent.setFlashBackrunner(address(flashBackrunner));

        lpAccumulator.setHookAuthorization(address(hook), true);
        lpAccumulator.setHookAuthorization(address(flashBackrunner), true);

        flashBackrunner.setLPFeeAccumulator(address(lpAccumulator));
        flashBackrunner.setRecorderAuthorization(address(hook), true);
        flashBackrunner.setForwarderAuthorization(address(backrunAgent), true);
        flashBackrunner.setKeeperAuthorization(keeper, true);

        swapRouter = new PoolSwapTest(poolManager);
        liquidityRouter = new PoolModifyLiquidityTest(poolManager);

        _initPoolsAndLiquidity();

        // Configure repay pool for the hooked pool backruns
        flashBackrunner.setRepayPoolKey(hookPoolId, repayPoolKey);

        // Fund actors
        _fundActor(alice, 200 ether, 200_000 ether); // WETH, DAI
        _fundActor(bob, 200 ether, 200_000 ether);
        _fundActor(keeper, 200 ether, 200_000 ether);
    }

    // ============ E2E Tests ============

    function test_E2E_CoordinatorFlow_TakesMevFee_ToTreasuryAndLPs() public {
        SwarmCoordinator coordinator = new SwarmCoordinator(poolManager, treasury, address(0), address(0));

        // Register a route agent identity (EOA works for test; production would be an agent contract).
        coordinator.registerAgent(routeAgent, 123, true);

        // Create 1-hop path through our hooked pool.
        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: hookPoolKey.currency0, // WETH (output)
            fee: hookPoolKey.fee,
            tickSpacing: hookPoolKey.tickSpacing,
            hooks: hookPoolKey.hooks,
            hookData: ""
        });

        bytes[] memory candidates = new bytes[](1);
        candidates[0] = abi.encode(path);

        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: hookPoolKey.currency1, // DAI
            currencyOut: hookPoolKey.currency0, // WETH
            amountIn: 10_000 ether,
            amountOutMin: 0,
            deadline: 0,
            mevFeeBps: 30, // 0.30%
            treasuryBps: 200, // 2% of the MEV fee goes to treasury
            lpShareBps: 8000 // 80% of MEV fee to LPs (rest to treasury/remainder)
        });

        // Alice approves coordinator to pull DAI.
        vm.startPrank(alice);
        IERC20Like(DAI).approve(address(coordinator), type(uint256).max);

        uint256 treasuryWethBefore = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        uint256 intentId = coordinator.createIntent(params, candidates);

        vm.stopPrank();

        // Route agent submits proposal (required by coordinator selection).
        vm.prank(routeAgent);
        coordinator.submitProposal(intentId, 0, 0, "");

        // Execute intent (swap goes through hook with hookData set by coordinator).
        vm.prank(alice);
        coordinator.executeIntent(intentId);

        uint256 treasuryWethAfter = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        assertTrue(treasuryWethAfter > treasuryWethBefore, "treasury should receive MEV fee share");
        assertTrue(accWethAfter > accWethBefore, "accumulator should record LP share of MEV fee");
    }

    function test_E2E_DirectSwap_HookData_TakesMevFee() public {
        bytes memory hookData = abi.encode(
            uint256(1), // intentId
            uint256(123), // agentId
            treasury,
            uint16(200), // treasuryBps
            uint24(3000), // mevFee = 0.30%
            uint16(8000) // lpShareBps
        );

        uint256 treasuryWethBefore = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        uint256 aliceWethBefore = IERC20Like(WETH).balanceOf(alice);
        _swapExactIn(alice, hookPoolKey, false, 100 ether, hookData); // DAI -> WETH
        uint256 aliceWethAfter = IERC20Like(WETH).balanceOf(alice);
        assertTrue(aliceWethAfter > aliceWethBefore, "alice should receive WETH");

        uint256 treasuryWethAfter = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        assertTrue(treasuryWethAfter > treasuryWethBefore, "treasury should receive MEV fee share");
        assertTrue(accWethAfter > accWethBefore, "accumulator should record LP share of MEV fee");
    }

    function test_E2E_ArbitrageCapture_SendsToAccumulatorAndTreasury() public {
        // Make pool diverge first (without capture) so the next swap triggers capture deterministically.
        arbAgent.setConfig(8000, 5_000, 5_000); // require 50% divergence to disable capture temporarily

        _swapExactIn(bob, hookPoolKey, true, 5 ether, ""); // WETH -> DAI pushes price down

        arbAgent.setConfig(8000, 50, 5_000); // back to 0.5% divergence

        // Sanity: ensure the arb agent would trigger capture for the next swap.
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(hookPoolId);
        uint256 poolPrice = HookLib.sqrtPriceToPrice(sqrtPriceX96);
        (uint256 oraclePrice,) = oracleRegistry.getLatestPrice(WETH, DAI);
        uint256 oracleConfidence = (oraclePrice * 50) / 10_000; // matches hook default (0.5%)

        SwapParams memory probeParams = SwapParams({
            zeroForOne: false, // DAI -> WETH
            amountSpecified: -int256(1_000 ether),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        SwapContext memory probeContext = SwapContext({
            poolKey: hookPoolKey,
            poolId: hookPoolId,
            params: probeParams,
            poolPrice: poolPrice,
            oraclePrice: oraclePrice,
            oracleConfidence: oracleConfidence,
            liquidity: poolManager.getLiquidity(hookPoolId),
            hookData: ""
        });

        IArbitrageAgent.ArbitrageResult memory probe = arbAgent.analyzeArbitrage(probeContext);
        assertTrue(probe.shouldCapture, "arb agent should capture");
        assertTrue(probe.hookShare > 0, "arb agent hookShare should be > 0");

        // A swap now should trigger capture.
        uint256 treasuryDaiBefore = IERC20Like(DAI).balanceOf(treasury);
        uint256 accDaiBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(DAI));

        bytes memory hookData = abi.encode(
            0, // intentId
            0, // agentId
            treasury,
            uint16(1_000), // treasuryBps = 10% of captured amount
            uint24(0), // mevFee (not needed for capture test)
            uint16(8_000) // lpShareBps = 80%
        );

        _swapExactIn(alice, hookPoolKey, false, 1_000 ether, hookData); // DAI -> WETH (capture takes DAI)

        uint256 treasuryDaiAfter = IERC20Like(DAI).balanceOf(treasury);
        uint256 accDaiAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(DAI));
        uint256 hookAccum = hook.getAccumulatedTokens(hookPoolId, Currency.wrap(DAI));

        assertTrue(treasuryDaiAfter > treasuryDaiBefore, "treasury should receive share of captured amount");
        assertTrue(accDaiAfter > accDaiBefore, "accumulator should receive LP share of captured amount");
        assertTrue(hookAccum > 0, "hook should track captured amount");
    }

    function test_E2E_DynamicFeeOverride_EmitsEvent() public {
        // Disable capture so fee override isn't short-circuited by arbitrage priority.
        executor.setAgentEnabled(AgentType.ARBITRAGE, false);

        // Move price away from oracle.
        _swapExactIn(bob, hookPoolKey, true, 5 ether, "");

        // Next swap should apply override fee from DynamicFeeAgent.
        vm.expectEmit(true, false, false, false, address(hook));
        emit FeeOverrideApplied(hookPoolId, 0); // fee value not asserted (depends on agent logic)

        _swapExactIn(alice, hookPoolKey, false, 100 ether, "");
    }

    function test_E2E_BackrunFlow_RecordedAndExecutable_ProfitDistributedAndDonated() public {
        // Ensure arbitrage capture doesn't interfere; we want a clean divergence-driven backrun.
        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, false);

        // Create divergence with a victim swap that pushes hook pool price down.
        // Move price upward (WETH more expensive) so the backrun borrows WETH (Aave has liquidity for WETH on Sepolia).
        _swapExactIn(bob, hookPoolKey, false, 1_000 ether, "");

        // Sanity: ensure we actually diverged from oracle.
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(hookPoolId);
        uint256 poolPrice = HookLib.sqrtPriceToPrice(sqrtPriceX96);
        (uint256 oraclePrice,) = oracleRegistry.getLatestPrice(WETH, DAI);
        assertTrue(poolPrice != oraclePrice, "pool should diverge from oracle");

        (
            ,
            ,
            ,
            uint256 backrunAmount,
            bool backrunZeroForOne,
            ,
            uint64 detectedBlock,
            bool executed
        ) = flashBackrunner.pendingBackruns(hookPoolId);

        assertTrue(backrunAmount > 0, "backrun amount should be recorded");
        assertFalse(executed, "opportunity should be pending");
        assertEq(uint256(detectedBlock), block.number, "should be recorded in the current block");

        address tokenIn = backrunZeroForOne ? WETH : DAI;

        uint256 keeperTokenBefore = IERC20Like(tokenIn).balanceOf(keeper);
        uint256 accTokenBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(tokenIn));

        // Execute backrun as keeper using keeper-provided capital (no external flash loan dependency).
        uint256 amountIn = backrunAmount;
        if (amountIn > 0.1 ether) amountIn = 0.1 ether;
        vm.startPrank(keeper);
        IERC20Like(tokenIn).approve(address(flashBackrunner), type(uint256).max);
        flashBackrunner.executeBackrunWithCapital(hookPoolId, amountIn, 0);
        vm.stopPrank();

        uint256 keeperTokenAfter = IERC20Like(tokenIn).balanceOf(keeper);
        uint256 accTokenAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(tokenIn));

        assertTrue(keeperTokenAfter >= keeperTokenBefore, "keeper should not lose tokenIn");
        assertTrue(accTokenAfter > accTokenBefore, "LP accumulator should receive share of profit");

        // Donate accumulated fees to LPs.
        lpAccumulator.donateToLPs(hookPoolId);

        uint256 accTokenFinal = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(tokenIn));
        assertEq(accTokenFinal, 0, "accumulated fees should be reset after donation");
    }

    function test_E2E_MalformedHookData_IsIgnored_NoMevFeeTaken() public {
        // Ensure capture/fee override doesn't interfere with this test.
        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, false);

        bytes memory malformed = hex"01";

        uint256 treasuryWethBefore = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        _swapExactIn(alice, hookPoolKey, false, 100 ether, malformed); // DAI -> WETH

        uint256 treasuryWethAfter = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        assertEq(treasuryWethAfter, treasuryWethBefore, "treasury should not receive MEV fee for malformed hookData");
        assertEq(accWethAfter, accWethBefore, "accumulator should not receive MEV fee for malformed hookData");
    }

    function test_E2E_ComposedCaptureAndMevFee_HappyPath() public {
        // Create divergence without triggering capture.
        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        _swapExactIn(bob, hookPoolKey, true, 5 ether, ""); // WETH -> DAI pushes price down
        executor.setAgentEnabled(AgentType.ARBITRAGE, true);

        bytes memory hookData = abi.encode(
            uint256(1), // intentId
            uint256(123), // agentId
            treasury,
            uint16(200), // treasuryBps
            uint24(3000), // mevFee = 0.30%
            uint16(8000) // lpShareBps = 80%
        );

        uint256 treasuryDaiBefore = IERC20Like(DAI).balanceOf(treasury);
        uint256 accDaiBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(DAI));
        uint256 treasuryWethBefore = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        // This swap should trigger:
        // - arbitrage capture in `beforeSwap` (takes input=DAI)
        // - MEV fee take in `afterSwap` (takes output=WETH)
        _swapExactIn(alice, hookPoolKey, false, 1_000 ether, hookData); // DAI -> WETH

        uint256 treasuryDaiAfter = IERC20Like(DAI).balanceOf(treasury);
        uint256 accDaiAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(DAI));
        uint256 treasuryWethAfter = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        assertTrue(treasuryDaiAfter > treasuryDaiBefore, "treasury should receive captured DAI share");
        assertTrue(accDaiAfter > accDaiBefore, "accumulator should receive captured DAI share");
        assertTrue(treasuryWethAfter > treasuryWethBefore, "treasury should receive MEV fee share (WETH)");
        assertTrue(accWethAfter > accWethBefore, "accumulator should receive MEV fee share (WETH)");
    }

    // ============ Helpers ============

    function _deployHook() internal returns (SwarmHook deployed) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(poolManager, address(this));
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, flags, type(SwarmHook).creationCode, constructorArgs
        );

        bytes memory deploymentData = abi.encodePacked(type(SwarmHook).creationCode, constructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "Hook deployment failed");

        address deployedAddress = address(bytes20(returnData));
        require(deployedAddress == hookAddress, "Hook address mismatch");

        deployed = SwarmHook(payable(deployedAddress));
    }

    function _initPoolsAndLiquidity() internal {
        // Fetch oracle price (WETH/DAI proxy via ETH/USD feed).
        (uint256 oraclePrice,) = oracleRegistry.getLatestPrice(WETH, DAI);
        require(oraclePrice > 0, "oracle price unavailable");

        (Currency currency0, Currency currency1) = _sortCurrencies(
            Currency.wrap(WETH),
            Currency.wrap(DAI)
        );

        hookPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        hookPoolId = hookPoolKey.toId();

        repayPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        repayPoolId = repayPoolKey.toId();

        uint160 sqrtPriceX96 = HookLib.priceToSqrtPrice(oraclePrice);
        poolManager.initialize(hookPoolKey, sqrtPriceX96);
        poolManager.initialize(repayPoolKey, sqrtPriceX96);

        // Add liquidity around the initialized tick (price ~= 2000 => tick is far from 0).
        (, int24 tick,,) = poolManager.getSlot0(hookPoolId);
        // Use a wide range so moderate test swaps can't exhaust liquidity and drive price to ~0.
        int24 tickLower = _floorTick(_clampTick(tick - 60_000), hookPoolKey.tickSpacing);
        int24 tickUpper = _floorTick(_clampTick(tick + 60_000), hookPoolKey.tickSpacing);

        // Fund this contract to provide liquidity.
        vm.deal(address(this), 2_000 ether);
        IWETH9Like(WETH).deposit{value: 1_000 ether}();
        deal(DAI, address(this), 5_000_000 ether);

        IERC20Like(WETH).approve(address(liquidityRouter), type(uint256).max);
        IERC20Like(DAI).approve(address(liquidityRouter), type(uint256).max);

        // Wide-range liquidity in both pools. Keep it moderate so backrun sizing is manageable.
        liquidityRouter.modifyLiquidity(
            hookPoolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: 100 ether,
                salt: bytes32(uint256(1))
            }),
            ""
        );

        liquidityRouter.modifyLiquidity(
            repayPoolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: 300 ether,
                salt: bytes32(uint256(2))
            }),
            ""
        );

        // Register keys so donation execution has the necessary metadata.
        lpAccumulator.registerPoolKey(hookPoolKey);
        lpAccumulator.registerPoolKey(repayPoolKey);

        require(poolManager.getLiquidity(hookPoolId) > 0, "hook pool has no liquidity");
        require(poolManager.getLiquidity(repayPoolId) > 0, "repay pool has no liquidity");
    }

    function _fundActor(address who, uint256 wethAmount, uint256 daiAmount) internal {
        // Transfer from this contract's balances.
        IERC20Like(WETH).transfer(who, wethAmount);
        IERC20Like(DAI).transfer(who, daiAmount);

        vm.startPrank(who);
        IERC20Like(WETH).approve(address(swapRouter), type(uint256).max);
        IERC20Like(DAI).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    function _swapExactIn(
        address trader,
        PoolKey memory key,
        bool zeroForOne,
        uint256 amountIn,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        vm.startPrank(trader);
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        delta = swapRouter.swap(key, params, settings, hookData);
        vm.stopPrank();
    }

    function _sortCurrencies(Currency a, Currency b) internal pure returns (Currency, Currency) {
        return Currency.unwrap(a) < Currency.unwrap(b) ? (a, b) : (b, a);
    }

    function _floorTick(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 rem = tick % spacing;
        if (rem == 0) return tick;
        // Solidity modulo keeps the sign of the dividend. For negative ticks, round down.
        if (tick < 0) {
            return tick - (spacing + rem);
        }
        return tick - rem;
    }

    function _clampTick(int24 tick) internal pure returns (int24) {
        if (tick < TickMath.MIN_TICK) return TickMath.MIN_TICK;
        if (tick > TickMath.MAX_TICK) return TickMath.MAX_TICK;
        return tick;
    }
}
