// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {SwarmHook} from "../src/hooks/SwarmHook.sol";
import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {DynamicFeeAgent} from "../src/agents/DynamicFeeAgent.sol";
import {BackrunAgent} from "../src/agents/BackrunAgent.sol";
import {FlashBackrunExecutorAgent} from "../src/agents/FlashBackrunExecutorAgent.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {AgentType} from "../src/interfaces/ISwarmAgent.sol";
import {FlashLoanBackrunner} from "../src/backrun/FlashLoanBackrunner.sol";
import {HookLib} from "../src/libraries/HookLib.sol";
import {SwarmAgentRegistry} from "../src/erc8004/SwarmAgentRegistry.sol";
import {SimpleRouteAgent} from "../src/erc8004/SimpleRouteAgent.sol";

interface IWETHLike {
    function deposit() external payable;
}

interface IERC20MetadataLike {
    function decimals() external view returns (uint8);
}

/// @title DeploySwarmProtocol
/// @notice Deploys and wires the full Swarm protocol on Sepolia.
/// @dev Optional pool bootstrap creates the two required pools:
///      1) Hook pool (dynamic fee + SwarmHook)
///      2) Repay pool (3000 fee + no hook) for flash-loan round-trip repayment
contract DeploySwarmProtocol is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // ============ Sepolia Constants ============

    address internal constant DEFAULT_POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal constant DEFAULT_AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;

    // Aave-market Sepolia assets (18 decimals).
    address internal constant DEFAULT_WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address internal constant DEFAULT_DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;

    // Chainlink ETH/USD (used as WETH/DAI proxy: DAI ~= USD).
    address internal constant DEFAULT_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    address internal constant ERC8004_IDENTITY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address internal constant ERC8004_REPUTATION = 0x8004B663056A597Dffe9eCcC1965A193B7388713;

    uint24 internal constant REPAY_POOL_FEE = 3000;
    int24 internal constant DEFAULT_TICK_SPACING = 60;

    // Deployed contracts
    SwarmHook public hook;
    AgentExecutor public agentExecutor;
    ArbitrageAgent public arbitrageAgent;
    DynamicFeeAgent public dynamicFeeAgent;
    BackrunAgent public backrunAgent;
    FlashLoanBackrunner public flashBackrunner;
    FlashBackrunExecutorAgent public flashBackrunExecutorAgent;
    LPFeeAccumulator public lpFeeAccumulator;
    OracleRegistry public oracleRegistry;
    SwarmCoordinator public coordinator;
    SimpleRouteAgent public simpleRouteAgent;
    SwarmAgentRegistry public swarmAgentRegistry;
    PoolModifyLiquidityTest public liquidityRouter;

    PoolKey public hookPoolKey;
    PoolId public hookPoolId;
    PoolKey public repayPoolKey;
    PoolId public repayPoolId;

    uint256 public arbAgentId;
    uint256 public feeAgentId;
    uint256 public backrunAgentId;
    uint256 public simpleRouteAgentErc8004Id;

    function run() external {
        // Required
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Optional / configurable
        address poolManagerAddr = vm.envOr("POOL_MANAGER", DEFAULT_POOL_MANAGER);
        address treasury = vm.envOr("TREASURY", deployer);
        address wethToken = vm.envOr("WETH_TOKEN", DEFAULT_WETH);
        address stableToken = vm.envOr("STABLE_TOKEN", DEFAULT_DAI);
        address oracleFeed = vm.envOr("ORACLE_FEED", DEFAULT_ETH_USD_FEED);
        address aavePool = vm.envOr("AAVE_POOL", DEFAULT_AAVE_POOL);

        bool bootstrapPools = vm.envOr("BOOTSTRAP_POOLS", true);
        bool registerErc8004Agents = vm.envOr("REGISTER_ERC8004_AGENTS", true);
        bool enableOnchainScoring = vm.envOr("ENABLE_ONCHAIN_SCORING", true);
        bool enforceCoordinatorIdentity = vm.envOr("ENFORCE_COORDINATOR_IDENTITY", false);
        bool enforceCoordinatorReputation = vm.envOr("ENFORCE_COORDINATOR_REPUTATION", false);

        uint256 routeAgentId = vm.envOr("SIMPLE_ROUTE_AGENT_ID", uint256(1));
        uint256 flashExecMaxAmount = vm.envOr("FLASH_EXECUTOR_MAX_FLASHLOAN_AMOUNT", uint256(0.05 ether));
        uint256 flashExecMinProfit = vm.envOr("FLASH_EXECUTOR_MIN_PROFIT", uint256(0));
        uint256 minDonationThreshold = vm.envOr("MIN_DONATION_THRESHOLD", uint256(0.001 ether));
        uint256 minDonationInterval = vm.envOr("MIN_DONATION_INTERVAL", uint256(1 hours));

        // Liquidity bootstrap params
        uint256 wrapWethAmount = vm.envOr("BOOTSTRAP_WRAP_WETH_AMOUNT", uint256(5 ether));
        uint256 stableBootstrapAmount = vm.envOr("BOOTSTRAP_STABLE_AMOUNT", uint256(10_000 ether));
        uint256 hookLiquidityDelta = vm.envOr("HOOK_LIQUIDITY_DELTA", uint256(100 ether));
        uint256 repayLiquidityDelta = vm.envOr("REPAY_LIQUIDITY_DELTA", uint256(300 ether));

        require(poolManagerAddr != address(0), "POOL_MANAGER=0");
        require(treasury != address(0), "TREASURY=0");
        require(wethToken != address(0), "WETH_TOKEN=0");
        require(stableToken != address(0), "STABLE_TOKEN=0");
        require(oracleFeed != address(0), "ORACLE_FEED=0");
        require(aavePool != address(0), "AAVE_POOL=0");
        require(wethToken != stableToken, "WETH_TOKEN==STABLE_TOKEN");

        uint8 wethDecimals = IERC20MetadataLike(wethToken).decimals();
        uint8 stableDecimals = IERC20MetadataLike(stableToken).decimals();
        require(wethDecimals == 18, "WETH decimals must be 18");
        require(stableDecimals == 18, "STABLE decimals must be 18");

        console.log("=== Swarm Protocol Deployment ===");
        console.log("Deployer:");
        console.log(deployer);
        console.log("Pool Manager:");
        console.log(poolManagerAddr);
        console.log("Treasury:");
        console.log(treasury);
        console.log("WETH Token:");
        console.log(wethToken);
        console.log("Stable Token:");
        console.log(stableToken);
        console.log("Oracle Feed:");
        console.log(oracleFeed);
        console.log("Aave Pool:");
        console.log(aavePool);
        console.log("Bootstrap Pools:");
        console.log(bootstrapPools);
        console.log("Register ERC-8004:");
        console.log(registerErc8004Agents);

        vm.startBroadcast(deployerPrivateKey);

        // 1) Deploy oracle registry + feed mapping
        console.log("\n1. Deploying Oracle Registry...");
        oracleRegistry = new OracleRegistry();
        oracleRegistry.setPriceFeed(wethToken, stableToken, oracleFeed);
        console.log("   Oracle Registry:");
        console.log(address(oracleRegistry));

        // 2) Deploy LP fee accumulator
        console.log("\n2. Deploying LP Fee Accumulator...");
        lpFeeAccumulator = new LPFeeAccumulator(IPoolManager(poolManagerAddr), minDonationThreshold, minDonationInterval);
        console.log("   LP Fee Accumulator:");
        console.log(address(lpFeeAccumulator));

        // 3) Deploy agent executor
        console.log("\n3. Deploying Agent Executor...");
        agentExecutor = new AgentExecutor();
        console.log("   Agent Executor:");
        console.log(address(agentExecutor));

        // 4) Deploy hook with mined permissions address bits
        console.log("\n4. Mining hook address...");
        hook = _deployHook(deployer, poolManagerAddr);
        console.log("   SwarmHook:");
        console.log(address(hook));

        // 5) Deploy hook agents + flash backrunner + on-chain backrun executor agent
        console.log("\n5. Deploying Agents...");
        arbitrageAgent = new ArbitrageAgent(IPoolManager(poolManagerAddr), deployer, 8000, 50);
        console.log("   Arbitrage Agent:");
        console.log(address(arbitrageAgent));

        dynamicFeeAgent = new DynamicFeeAgent(IPoolManager(poolManagerAddr), deployer);
        console.log("   Dynamic Fee Agent:");
        console.log(address(dynamicFeeAgent));

        backrunAgent = new BackrunAgent(IPoolManager(poolManagerAddr), deployer);
        console.log("   Backrun Agent:");
        console.log(address(backrunAgent));

        flashBackrunner = new FlashLoanBackrunner(IPoolManager(poolManagerAddr), aavePool);
        console.log("   FlashLoanBackrunner:");
        console.log(address(flashBackrunner));

        flashBackrunExecutorAgent =
            new FlashBackrunExecutorAgent(address(flashBackrunner), deployer, flashExecMaxAmount, flashExecMinProfit);
        console.log("   FlashBackrunExecutorAgent:");
        console.log(address(flashBackrunExecutorAgent));

        // 6) Deploy coordinator + route agent (no off-chain route proposer needed for demo flow)
        console.log("\n6. Deploying Coordinator + Route Agent...");
        coordinator = new SwarmCoordinator(
            IPoolManager(poolManagerAddr),
            treasury,
            ERC8004_IDENTITY,
            ERC8004_REPUTATION
        );
        simpleRouteAgent = new SimpleRouteAgent(address(coordinator), deployer);
        coordinator.registerAgent(address(simpleRouteAgent), routeAgentId, true);
        coordinator.setEnforcement(enforceCoordinatorIdentity, enforceCoordinatorReputation);

        address[] memory repClients = new address[](1);
        repClients[0] = address(coordinator);
        coordinator.setReputationClients(repClients);
        console.log("   SwarmCoordinator:");
        console.log(address(coordinator));
        console.log("   SimpleRouteAgent:");
        console.log(address(simpleRouteAgent));

        // 7) Configure agent executor and hook wiring
        console.log("\n7. Configuring AgentExecutor + Hook...");
        agentExecutor.registerAgent(AgentType.ARBITRAGE, address(arbitrageAgent));
        agentExecutor.registerAgent(AgentType.DYNAMIC_FEE, address(dynamicFeeAgent));
        agentExecutor.registerAgent(AgentType.BACKRUN, address(backrunAgent));

        agentExecutor.setOnchainScoringConfig(
            ERC8004_REPUTATION, "swarm-hook", "hook-agents", int128(int256(1e18)), int128(int256(-1e18)), enableOnchainScoring
        );
        agentExecutor.authorizeHook(address(hook), true);
        hook.setAgentExecutor(address(agentExecutor));
        hook.setOracleRegistry(address(oracleRegistry));
        hook.setLPFeeAccumulator(address(lpFeeAccumulator));
        hook.setBackrunRecorder(address(flashBackrunner));
        console.log("   AgentExecutor + Hook configured");

        // 8) Configure agent-level authorizations
        console.log("\n8. Configuring Agent Authorizations...");
        arbitrageAgent.authorizeCaller(address(agentExecutor), true);
        dynamicFeeAgent.authorizeCaller(address(agentExecutor), true);
        backrunAgent.authorizeCaller(address(agentExecutor), true);

        backrunAgent.setLPFeeAccumulator(address(lpFeeAccumulator));
        backrunAgent.setFlashBackrunner(address(flashBackrunner));
        backrunAgent.setMaxFlashLoanAmount(vm.envOr("BACKRUN_MAX_FLASHLOAN_AMOUNT", uint256(0.1 ether)));

        lpFeeAccumulator.setHookAuthorization(address(hook), true);
        lpFeeAccumulator.setHookAuthorization(address(flashBackrunner), true);

        flashBackrunner.setLPFeeAccumulator(address(lpFeeAccumulator));
        flashBackrunner.setRecorderAuthorization(address(hook), true);
        flashBackrunner.setForwarderAuthorization(address(backrunAgent), true);
        flashBackrunner.setForwarderAuthorization(address(flashBackrunExecutorAgent), true);
        flashBackrunner.setKeeperAuthorization(address(flashBackrunExecutorAgent), true);
        flashBackrunner.setKeeperAuthorization(deployer, true);
        console.log("   Agent auth configured");

        // 9) Optional ERC-8004 registry + identity linking for agents
        if (registerErc8004Agents) {
            console.log("\n9. Registering agents on ERC-8004...");
            _registerAgentsOnERC8004();
        }

        // 10) Optional pool bootstrap and initial liquidity
        if (bootstrapPools) {
            console.log("\n10. Bootstrapping pools + liquidity...");
            _bootstrapPoolsAndLiquidity(
                IPoolManager(poolManagerAddr),
                deployer,
                wethToken,
                stableToken,
                wrapWethAmount,
                stableBootstrapAmount,
                hookLiquidityDelta,
                repayLiquidityDelta
            );
        }

        vm.stopBroadcast();

        _printSummary(
            deployer,
            poolManagerAddr,
            wethToken,
            stableToken,
            oracleFeed,
            bootstrapPools,
            registerErc8004Agents
        );
    }

    function _deployHook(address owner, address poolManagerAddr) internal returns (SwarmHook deployedHook) {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory creationCode = type(SwarmHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(poolManagerAddr), owner);
        (address hookAddress, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, creationCode, constructorArgs);
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "Hook deployment failed");
        address deployedAddress = address(bytes20(returnData));
        require(deployedAddress == hookAddress, "Hook address mismatch");

        console.log("   Mined hook address:");
        console.log(hookAddress);
        return SwarmHook(payable(deployedAddress));
    }

    function _bootstrapPoolsAndLiquidity(
        IPoolManager poolManager,
        address deployer,
        address wethToken,
        address stableToken,
        uint256 wrapWethAmount,
        uint256 stableBootstrapAmount,
        uint256 hookLiquidityDelta,
        uint256 repayLiquidityDelta
    ) internal {
        require(hookLiquidityDelta > 0 && repayLiquidityDelta > 0, "liquidityDelta=0");

        (uint256 oraclePrice,) = oracleRegistry.getLatestPrice(wethToken, stableToken);
        require(oraclePrice > 0, "oracle price unavailable");
        uint160 sqrtPriceX96 = HookLib.priceToSqrtPrice(oraclePrice);

        (Currency c0, Currency c1) = _sortCurrencies(Currency.wrap(wethToken), Currency.wrap(stableToken));

        hookPoolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        hookPoolId = hookPoolKey.toId();

        repayPoolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: REPAY_POOL_FEE,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(address(0))
        });
        repayPoolId = repayPoolKey.toId();

        // Hook pool should be new (hook address is unique by deployment). Revert on failure.
        poolManager.initialize(hookPoolKey, sqrtPriceX96);

        // Repay pool can already exist. If it does, we continue.
        try poolManager.initialize(repayPoolKey, sqrtPriceX96) {} catch {
            console.log("   Repay pool already initialized (continuing)");
        }

        if (wrapWethAmount > 0) {
            IWETHLike(wethToken).deposit{value: wrapWethAmount}();
        }

        require(IERC20(stableToken).balanceOf(deployer) >= stableBootstrapAmount, "insufficient STABLE balance");

        liquidityRouter = new PoolModifyLiquidityTest(poolManager);
        IERC20(wethToken).approve(address(liquidityRouter), type(uint256).max);
        IERC20(stableToken).approve(address(liquidityRouter), type(uint256).max);

        (, int24 tick,,) = poolManager.getSlot0(hookPoolId);
        int24 tickLower = _floorTick(_clampTick(tick - 60_000), DEFAULT_TICK_SPACING);
        int24 tickUpper = _floorTick(_clampTick(tick + 60_000), DEFAULT_TICK_SPACING);

        liquidityRouter.modifyLiquidity(
            hookPoolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(hookLiquidityDelta),
                salt: bytes32(uint256(1))
            }),
            ""
        );

        liquidityRouter.modifyLiquidity(
            repayPoolKey,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(repayLiquidityDelta),
                salt: bytes32(uint256(2))
            }),
            ""
        );

        lpFeeAccumulator.registerPoolKey(hookPoolKey);
        lpFeeAccumulator.registerPoolKey(repayPoolKey);
        flashBackrunner.setRepayPoolKey(hookPoolId, repayPoolKey);

        require(poolManager.getLiquidity(hookPoolId) > 0, "hook pool has no liquidity");
        require(poolManager.getLiquidity(repayPoolId) > 0, "repay pool has no liquidity");
    }

    function _registerAgentsOnERC8004() internal {
        swarmAgentRegistry = new SwarmAgentRegistry(ERC8004_IDENTITY, ERC8004_REPUTATION);

        arbAgentId = swarmAgentRegistry.registerAgent(
            address(arbitrageAgent),
            "Swarm Arbitrage Hook Agent",
            "Captures oracle-divergence MEV and routes share to LPs",
            "generic",
            "1.0.0"
        );
        arbitrageAgent.configureIdentity(arbAgentId, ERC8004_IDENTITY);

        feeAgentId = swarmAgentRegistry.registerAgent(
            address(dynamicFeeAgent),
            "Swarm Dynamic Fee Hook Agent",
            "Recommends v4 dynamic fee overrides based on pool conditions",
            "generic",
            "1.0.0"
        );
        dynamicFeeAgent.configureIdentity(feeAgentId, ERC8004_IDENTITY);

        backrunAgentId = swarmAgentRegistry.registerAgent(
            address(backrunAgent),
            "Swarm Backrun Hook Agent",
            "Detects price dislocations and records backrun opportunities",
            "generic",
            "1.0.0"
        );
        backrunAgent.configureIdentity(backrunAgentId, ERC8004_IDENTITY);

        simpleRouteAgentErc8004Id = swarmAgentRegistry.registerAgent(
            address(simpleRouteAgent),
            "Swarm Simple Route Agent",
            "Submits default coordinator proposals on-chain",
            "generic",
            "1.0.0"
        );
        simpleRouteAgent.configureIdentity(simpleRouteAgentErc8004Id, ERC8004_IDENTITY);
        coordinator.registerAgent(address(simpleRouteAgent), simpleRouteAgentErc8004Id, true);
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

    function _printSummary(
        address deployer,
        address poolManagerAddr,
        address wethToken,
        address stableToken,
        address oracleFeed,
        bool bootstrapPools,
        bool registerErc8004Agents
    ) internal view {
        console.log("\n========================================");
        console.log("       DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("Deployer:");
        console.log(deployer);
        console.log("PoolManager:");
        console.log(poolManagerAddr);
        console.log("WETH Token:");
        console.log(wethToken);
        console.log("Stable Token:");
        console.log(stableToken);
        console.log("Oracle Feed:");
        console.log(oracleFeed);
        console.log("");
        console.log("SwarmHook:");
        console.log(address(hook));
        console.log("AgentExecutor:");
        console.log(address(agentExecutor));
        console.log("SwarmCoordinator:");
        console.log(address(coordinator));
        console.log("SimpleRouteAgent:");
        console.log(address(simpleRouteAgent));
        console.log("LPFeeAccumulator:");
        console.log(address(lpFeeAccumulator));
        console.log("OracleRegistry:");
        console.log(address(oracleRegistry));
        console.log("FlashLoanBackrunner:");
        console.log(address(flashBackrunner));
        console.log("FlashBackrunExecutorAgent:");
        console.log(address(flashBackrunExecutorAgent));
        console.log("ArbitrageAgent:");
        console.log(address(arbitrageAgent));
        console.log("DynamicFeeAgent:");
        console.log(address(dynamicFeeAgent));
        console.log("BackrunAgent:");
        console.log(address(backrunAgent));
        if (registerErc8004Agents) {
            console.log("SwarmAgentRegistry:");
            console.log(address(swarmAgentRegistry));
            console.log("ArbitrageAgent ERC-8004 ID:");
            console.log(arbAgentId);
            console.log("DynamicFeeAgent ERC-8004 ID:");
            console.log(feeAgentId);
            console.log("BackrunAgent ERC-8004 ID:");
            console.log(backrunAgentId);
            console.log("SimpleRouteAgent ERC-8004 ID:");
            console.log(simpleRouteAgentErc8004Id);
        }
        if (bootstrapPools) {
            console.log("Hook Pool ID:");
            console.logBytes32(PoolId.unwrap(hookPoolId));
            console.log("Repay Pool ID:");
            console.logBytes32(PoolId.unwrap(repayPoolId));
            console.log("Hook Pool Fee:");
            console.log(uint256(hookPoolKey.fee));
            console.log("Hook Pool Tick Spacing:");
            console.log(int256(hookPoolKey.tickSpacing));
            console.log("Hook Pool Hooks:");
            console.log(address(hookPoolKey.hooks));
            console.log("Repay Pool Fee:");
            console.log(uint256(repayPoolKey.fee));
            console.log("Repay Pool Tick Spacing:");
            console.log(int256(repayPoolKey.tickSpacing));
            console.log("Repay Pool Hooks:");
            console.log(address(repayPoolKey.hooks));
        }
        console.log("========================================");
    }
}
