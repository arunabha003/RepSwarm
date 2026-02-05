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
}

interface IWETH9Like is IERC20Like {
    function deposit() external payable;
}

/// @title E2EMainnetTest
/// @notice Mainnet-fork E2E suite.
/// @dev Disabled by default to keep `forge test` stable in CI/sandbox environments.
///      Enable with `RUN_MAINNET_E2E=true forge test --match-contract E2EMainnetTest -vv`.
contract E2EMainnetTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    string internal constant MAINNET_RPC_URL = "https://eth-mainnet.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo";

    // Uniswap v4 PoolManager on mainnet.
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Mainnet token addresses.
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Chainlink ETH/USD feed (used as WETH/DAI proxy: DAI ~= USD).
    address internal constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    bool internal skipAll;

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

    function setUp() public {
        bool run = vm.envOr("RUN_MAINNET_E2E", false);
        if (!run) {
            skipAll = true;
            return;
        }

        vm.createSelectFork(MAINNET_RPC_URL);

        // Hardcode mainnet PoolManager so the test doesn't accidentally pick up a Sepolia `POOL_MANAGER`
        // env var (common when running fork tests locally).
        poolManager = IPoolManager(POOL_MANAGER);
        require(address(poolManager).code.length > 0, "PoolManager not deployed");

        oracleRegistry = new OracleRegistry();
        oracleRegistry.setPriceFeed(WETH, DAI, ETH_USD_FEED);

        lpAccumulator = new LPFeeAccumulator(poolManager, 1, 0);

        executor = new AgentExecutor();
        arbAgent = new ArbitrageAgent(poolManager, address(this), 8000, 50);
        feeAgent = new DynamicFeeAgent(poolManager, address(this));
        backrunAgent = new BackrunAgent(poolManager, address(this));

        hook = _deployHook();

        // Use chain-aware default Aave pool inside FlashLoanBackrunner.
        flashBackrunner = new FlashLoanBackrunner(poolManager, address(0));

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
        flashBackrunner.setRepayPoolKey(hookPoolId, repayPoolKey);

        _fundActor(alice, 200 ether, 200_000 ether);
        _fundActor(bob, 200 ether, 200_000 ether);
        _fundActor(keeper, 1 ether, 0);
    }

    function test_E2E_CoordinatorFlow_TakesMevFee_ToTreasuryAndLPs() public {
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        SwarmCoordinator coordinator = new SwarmCoordinator(poolManager, treasury, address(0), address(0));
        coordinator.registerAgent(routeAgent, 123, true);

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: hookPoolKey.currency0,
            fee: hookPoolKey.fee,
            tickSpacing: hookPoolKey.tickSpacing,
            hooks: hookPoolKey.hooks,
            hookData: ""
        });

        bytes[] memory candidates = new bytes[](1);
        candidates[0] = abi.encode(path);

        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: hookPoolKey.currency1,
            currencyOut: hookPoolKey.currency0,
            amountIn: 10_000 ether,
            amountOutMin: 0,
            deadline: 0,
            mevFeeBps: 30, // 0.30%
            treasuryBps: 200,
            lpShareBps: 8000
        });

        vm.startPrank(alice);
        IERC20Like(DAI).approve(address(coordinator), type(uint256).max);

        uint256 treasuryWethBefore = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        uint256 intentId = coordinator.createIntent(params, candidates);
        vm.stopPrank();

        vm.prank(routeAgent);
        coordinator.submitProposal(intentId, 0, 0, "");

        vm.prank(alice);
        coordinator.executeIntent(intentId);

        uint256 treasuryWethAfter = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        assertTrue(treasuryWethAfter > treasuryWethBefore, "treasury should receive MEV fee share");
        assertTrue(accWethAfter > accWethBefore, "accumulator should record LP share of MEV fee");
    }

    function test_E2E_DirectSwap_HookData_TakesMevFee() public {
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        bytes memory hookData = abi.encode(uint256(1), uint256(123), treasury, uint16(200), uint24(3000), uint16(8000));

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
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        arbAgent.setConfig(8000, 5_000, 5_000);
        _swapExactIn(bob, hookPoolKey, true, 5 ether, "");
        arbAgent.setConfig(8000, 50, 5_000);

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(hookPoolId);
        uint256 poolPrice = HookLib.sqrtPriceToPrice(sqrtPriceX96);
        (uint256 oraclePrice,) = oracleRegistry.getLatestPrice(WETH, DAI);
        uint256 oracleConfidence = (oraclePrice * 50) / 10_000;

        SwapParams memory probeParams = SwapParams({
            zeroForOne: false, amountSpecified: -int256(1_000 ether), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
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

        uint256 treasuryDaiBefore = IERC20Like(DAI).balanceOf(treasury);
        uint256 accDaiBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(DAI));

        bytes memory hookData = abi.encode(0, 0, treasury, uint16(1_000), uint24(0), uint16(8_000));

        _swapExactIn(alice, hookPoolKey, false, 1_000 ether, hookData);

        uint256 treasuryDaiAfter = IERC20Like(DAI).balanceOf(treasury);
        uint256 accDaiAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(DAI));

        assertTrue(treasuryDaiAfter > treasuryDaiBefore, "treasury should receive share of captured amount");
        assertTrue(accDaiAfter > accDaiBefore, "accumulator should receive LP share of captured amount");
    }

    function test_E2E_DynamicFeeOverride_EmitsEvent() public {
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        _swapExactIn(bob, hookPoolKey, true, 5 ether, "");

        vm.expectEmit(true, false, false, false, address(hook));
        emit FeeOverrideApplied(hookPoolId, 0);

        _swapExactIn(alice, hookPoolKey, false, 100 ether, "");
    }

    function test_E2E_BackrunFlow_RecordedAndExecutable_CapitalMode() public {
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, false);

        _swapExactIn(bob, hookPoolKey, false, 1_000 ether, "");

        (,,, uint256 backrunAmount, bool backrunZeroForOne,,, bool executed) =
            flashBackrunner.pendingBackruns(hookPoolId);

        assertTrue(backrunAmount > 0, "backrun amount should be recorded");
        assertFalse(executed, "opportunity should be pending");

        address tokenIn = backrunZeroForOne ? WETH : DAI;

        uint256 keeperTokenBefore = IERC20Like(tokenIn).balanceOf(keeper);
        uint256 accTokenBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(tokenIn));

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
    }

    function test_E2E_BackrunFlow_FlashLoanExecutes_ProfitDistributed() public {
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        // Ensure arbitrage capture doesn't interfere; we want a clean divergence-driven backrun.
        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, false);

        // Create divergence (DAI -> WETH) so the backrun borrows WETH on mainnet Aave.
        _swapExactIn(bob, hookPoolKey, false, 1_000 ether, "");

        (,,, uint256 backrunAmount, bool backrunZeroForOne,,, bool executed) =
            flashBackrunner.pendingBackruns(hookPoolId);

        assertTrue(backrunAmount > 0, "backrun amount should be recorded");
        assertFalse(executed, "opportunity should be pending");
        assertTrue(backrunZeroForOne, "expected to borrow WETH (currency0)");

        uint256 keeperWethBefore = IERC20Like(WETH).balanceOf(keeper);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        // Execute with a smaller amount than the recorded opportunity.
        uint256 amountIn = backrunAmount;
        if (amountIn > 0.1 ether) amountIn = 0.1 ether;
        vm.prank(keeper);
        flashBackrunner.executeBackrunPartial(hookPoolId, amountIn, 0);

        uint256 keeperWethAfter = IERC20Like(WETH).balanceOf(keeper);
        uint256 accWethAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        assertTrue(keeperWethAfter > keeperWethBefore, "keeper should earn profit share");
        assertTrue(accWethAfter > accWethBefore, "LP accumulator should receive share of profit");
    }

    function test_E2E_MalformedHookData_IsIgnored_NoMevFeeTaken() public {
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, false);

        bytes memory malformed = hex"01";

        uint256 treasuryWethBefore = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        _swapExactIn(alice, hookPoolKey, false, 100 ether, malformed);

        uint256 treasuryWethAfter = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethAfter = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        assertEq(treasuryWethAfter, treasuryWethBefore, "treasury should not receive MEV fee for malformed hookData");
        assertEq(accWethAfter, accWethBefore, "accumulator should not receive MEV fee for malformed hookData");
    }

    function test_E2E_ComposedCaptureAndMevFee_HappyPath() public {
        if (skipAll) vm.skip(true, "set RUN_MAINNET_E2E=true to run");

        executor.setAgentEnabled(AgentType.ARBITRAGE, false);
        _swapExactIn(bob, hookPoolKey, true, 5 ether, "");
        executor.setAgentEnabled(AgentType.ARBITRAGE, true);

        bytes memory hookData = abi.encode(uint256(1), uint256(123), treasury, uint16(200), uint24(3000), uint16(8000));

        uint256 treasuryDaiBefore = IERC20Like(DAI).balanceOf(treasury);
        uint256 accDaiBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(DAI));
        uint256 treasuryWethBefore = IERC20Like(WETH).balanceOf(treasury);
        uint256 accWethBefore = lpAccumulator.accumulatedFees(hookPoolId, Currency.wrap(WETH));

        _swapExactIn(alice, hookPoolKey, false, 1_000 ether, hookData);

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
        bytes memory creationCode = type(SwarmHook).creationCode;
        bytes memory constructorArgs = abi.encode(poolManager, address(this));

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, creationCode, constructorArgs);

        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "Hook deployment failed");

        address deployedAddress = address(bytes20(returnData));
        require(deployedAddress == hookAddress, "Hook address mismatch");

        deployed = SwarmHook(payable(deployedAddress));
    }

    function _initPoolsAndLiquidity() internal {
        (uint256 oraclePrice,) = oracleRegistry.getLatestPrice(WETH, DAI);
        require(oraclePrice > 0, "oracle price unavailable");

        (Currency currency0, Currency currency1) = _sortCurrencies(Currency.wrap(WETH), Currency.wrap(DAI));

        hookPoolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        hookPoolId = hookPoolKey.toId();

        repayPoolKey = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0))
        });
        repayPoolId = repayPoolKey.toId();

        uint160 sqrtPriceX96 = HookLib.priceToSqrtPrice(oraclePrice);
        poolManager.initialize(hookPoolKey, sqrtPriceX96);
        poolManager.initialize(repayPoolKey, sqrtPriceX96);

        (, int24 tick,,) = poolManager.getSlot0(hookPoolId);
        int24 tickLower = _floorTick(_clampTick(tick - 60_000), hookPoolKey.tickSpacing);
        int24 tickUpper = _floorTick(_clampTick(tick + 60_000), hookPoolKey.tickSpacing);

        vm.deal(address(this), 2_000 ether);
        IWETH9Like(WETH).deposit{value: 1_000 ether}();
        deal(DAI, address(this), 5_000_000 ether);

        IERC20Like(WETH).approve(address(liquidityRouter), type(uint256).max);
        IERC20Like(DAI).approve(address(liquidityRouter), type(uint256).max);

        liquidityRouter.modifyLiquidity(
            hookPoolKey,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 100 ether, salt: bytes32(uint256(1))
            }),
            ""
        );

        liquidityRouter.modifyLiquidity(
            repayPoolKey,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: 300 ether, salt: bytes32(uint256(2))
            }),
            ""
        );

        lpAccumulator.registerPoolKey(hookPoolKey);
        lpAccumulator.registerPoolKey(repayPoolKey);

        require(poolManager.getLiquidity(hookPoolId) > 0, "hook pool has no liquidity");
        require(poolManager.getLiquidity(repayPoolId) > 0, "repay pool has no liquidity");
    }

    function _fundActor(address who, uint256 wethAmount, uint256 daiAmount) internal {
        IERC20Like(WETH).transfer(who, wethAmount);
        if (daiAmount > 0) IERC20Like(DAI).transfer(who, daiAmount);

        vm.startPrank(who);
        IERC20Like(WETH).approve(address(swapRouter), type(uint256).max);
        IERC20Like(DAI).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    function _swapExactIn(address trader, PoolKey memory key, bool zeroForOne, uint256 amountIn, bytes memory hookData)
        internal
        returns (BalanceDelta delta)
    {
        vm.startPrank(trader);
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

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
        if (tick < 0) return tick - (spacing + rem);
        return tick - rem;
    }

    function _clampTick(int24 tick) internal pure returns (int24) {
        if (tick < TickMath.MIN_TICK) return TickMath.MIN_TICK;
        if (tick > TickMath.MAX_TICK) return TickMath.MAX_TICK;
        return tick;
    }
}
