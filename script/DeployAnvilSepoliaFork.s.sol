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
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
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

interface IWETH9Like {
    function deposit() external payable;
}

interface IAavePoolSupplyLike {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
}

/// @notice Deploy + configure Swarm on a local Anvil that is FORKING Sepolia state.
/// @dev This script is designed for: `anvil --fork-url <sepolia rpc> --chain-id 31337 --auto-impersonate`
/// @dev It deploys protocol contracts AND creates a local WETH/DAI pool (hooked + repay pool) with liquidity.
contract DeployAnvilSepoliaFork is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    // Sepolia v4 PoolManager
    address internal constant POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Aave v3 Pool (Sepolia)
    address internal constant AAVE_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;

    // Tokens (Sepolia Aave market assets)
    // WETH used by Aave on Sepolia (so flashloans borrow the same asset we trade)
    address internal constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address internal constant DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;

    // Chainlink ETH/USD feed (Sepolia) used as WETH/DAI proxy
    address internal constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    // ERC-8004 (Sepolia) – pass explicitly because local chainid=31337 won't auto-select
    address internal constant ERC8004_IDENTITY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address internal constant ERC8004_REPUTATION = 0x8004B663056A597Dffe9eCcC1965A193B7388713;

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
    SwarmAgentRegistry public swarmAgentRegistry;
    SimpleRouteAgent public simpleRouteAgent;
    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public liquidityRouter;

    PoolKey public hookPoolKey;
    PoolId public hookPoolId;
    PoolKey public repayPoolKey;
    PoolId public repayPoolId;

    // ERC-8004 identity IDs (for hook agents)
    uint256 public arbAgentId;
    uint256 public feeAgentId;
    uint256 public backrunAgentId;
    uint256 public simpleRouteAgentErc8004Id;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DeployAnvilSepoliaFork ===");
        console.log("Deployer:");
        console.log(deployer);
        console.log("PoolManager:");
        console.log(POOL_MANAGER);

        vm.startBroadcast(deployerPrivateKey);

        // 1) Oracle registry + feed
        oracleRegistry = new OracleRegistry();
        oracleRegistry.setPriceFeed(WETH, DAI, ETH_USD_FEED);

        // 2) Accumulator tuned for local demo (donate immediately)
        lpFeeAccumulator = new LPFeeAccumulator(IPoolManager(POOL_MANAGER), 1, 0);

        // 3) Executor + agents
        agentExecutor = new AgentExecutor();
        arbitrageAgent = new ArbitrageAgent(IPoolManager(POOL_MANAGER), deployer, 8000, 50);
        dynamicFeeAgent = new DynamicFeeAgent(IPoolManager(POOL_MANAGER), deployer);
        backrunAgent = new BackrunAgent(IPoolManager(POOL_MANAGER), deployer);

        // 4) Hook (CREATE2 deployer to ensure flag bits)
        hook = _deployHook(deployer);

        // 5) Backrunner (explicit Aave pool because chainid=31337)
        flashBackrunner = new FlashLoanBackrunner(IPoolManager(POOL_MANAGER), AAVE_POOL_SEPOLIA);

        // 6) Coordinator (explicit ERC-8004 addresses because chainid=31337)
        coordinator = new SwarmCoordinator(IPoolManager(POOL_MANAGER), deployer, ERC8004_IDENTITY, ERC8004_REPUTATION);
        simpleRouteAgent = new SimpleRouteAgent(address(coordinator), deployer);
        coordinator.registerAgent(address(simpleRouteAgent), vm.envOr("SIMPLE_ROUTE_AGENT_ID", uint256(1)), true);

        // 7) Wire executor + hook
        agentExecutor.registerAgent(AgentType.ARBITRAGE, address(arbitrageAgent));
        agentExecutor.registerAgent(AgentType.DYNAMIC_FEE, address(dynamicFeeAgent));
        agentExecutor.registerAgent(AgentType.BACKRUN, address(backrunAgent));
        agentExecutor.authorizeHook(address(hook), true);
        if (vm.envOr("ENABLE_ONCHAIN_SCORING", true)) {
            agentExecutor.setOnchainScoringConfig(
                ERC8004_REPUTATION,
                "swarm-hook",
                "hook-agents",
                int128(int256(1e18)),
                int128(int256(-1e18)),
                true
            );
        }

        hook.setAgentExecutor(address(agentExecutor));
        hook.setOracleRegistry(address(oracleRegistry));
        hook.setLPFeeAccumulator(address(lpFeeAccumulator));
        hook.setBackrunRecorder(address(flashBackrunner));

        // On Anvil forks Chainlink feed timestamps are stale, so extend the window.
        oracleRegistry.setMaxStaleness(365 days);

        // 8) Authorizations
        arbitrageAgent.authorizeCaller(address(agentExecutor), true);
        dynamicFeeAgent.authorizeCaller(address(agentExecutor), true);
        backrunAgent.authorizeCaller(address(agentExecutor), true);
        arbitrageAgent.authorizeCaller(address(hook), true);
        dynamicFeeAgent.authorizeCaller(address(hook), true);
        backrunAgent.authorizeCaller(address(hook), true);

        backrunAgent.setLPFeeAccumulator(address(lpFeeAccumulator));
        backrunAgent.setFlashBackrunner(address(flashBackrunner));
        backrunAgent.setMaxFlashLoanAmount(0.1 ether);

        lpFeeAccumulator.setHookAuthorization(address(hook), true);
        lpFeeAccumulator.setHookAuthorization(address(flashBackrunner), true);

        flashBackrunner.setLPFeeAccumulator(address(lpFeeAccumulator));
        flashBackrunner.setRecorderAuthorization(address(hook), true);
        flashBackrunner.setForwarderAuthorization(address(backrunAgent), true);
        flashBackrunner.setKeeperAuthorization(deployer, true);
        flashBackrunExecutorAgent =
            new FlashBackrunExecutorAgent(address(flashBackrunner), deployer, 0.05 ether, 0);
        flashBackrunner.setForwarderAuthorization(address(flashBackrunExecutorAgent), true);
        flashBackrunner.setKeeperAuthorization(address(flashBackrunExecutorAgent), true);

        // 9) Routers for liquidity bootstrap on local fork
        swapRouter = new PoolSwapTest(IPoolManager(POOL_MANAGER));
        liquidityRouter = new PoolModifyLiquidityTest(IPoolManager(POOL_MANAGER));

        // 10) Create pools + add liquidity
        _initPoolsAndLiquidity(deployer);
        flashBackrunner.setRepayPoolKey(hookPoolId, repayPoolKey);

        // 11) Optional: register hook agents on ERC-8004 and bind their IDs into the agent contracts.
        // Enable/disable via: `REGISTER_ERC8004_HOOK_AGENTS=true/false` (default: true)
        if (vm.envOr("REGISTER_ERC8004_HOOK_AGENTS", true)) {
            _registerHookAgentsOnERC8004();
        }

        vm.stopBroadcast();

        _printSummary(deployer);
    }

    function _deployHook(address owner) internal returns (SwarmHook deployed) {
        bytes memory creationCode = type(SwarmHook).creationCode;
        bytes memory constructorArgs = abi.encode(IPoolManager(POOL_MANAGER), owner);

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, creationCode, constructorArgs);

        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);

        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "Hook deployment failed");

        address deployedAddress = address(bytes20(returnData));
        require(deployedAddress == hookAddress, "Hook address mismatch");

        deployed = SwarmHook(payable(deployedAddress));
    }

    function _initPoolsAndLiquidity(address deployer) internal {
        IPoolManager pm = IPoolManager(POOL_MANAGER);

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
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        repayPoolId = repayPoolKey.toId();

        uint160 sqrtPriceX96 = HookLib.priceToSqrtPrice(oraclePrice);

        // Only initialize pools that don't already exist (avoids PoolAlreadyInitialized revert on re-deploy)
        {
            (uint160 existing,,,) = pm.getSlot0(hookPoolId);
            if (existing == 0) pm.initialize(hookPoolKey, sqrtPriceX96);
        }
        {
            (uint160 existing,,,) = pm.getSlot0(repayPoolId);
            if (existing == 0) pm.initialize(repayPoolKey, sqrtPriceX96);
        }

        (, int24 tick,,) = pm.getSlot0(hookPoolId);
        int24 tickLower = _floorTick(_clampTick(tick - 60_000), hookPoolKey.tickSpacing);
        int24 tickUpper = _floorTick(_clampTick(tick + 60_000), hookPoolKey.tickSpacing);

        // Funds: WETH via deposit, DAI must be pre-funded on the fork (see docs).
        uint256 daiNeed = 5_000_000 ether;
        uint256 wethNeed = 1_000 ether;

        require(IERC20(DAI).balanceOf(deployer) >= daiNeed, "fund deployer with DAI first");

        // Ensure deployer has WETH.
        IWETH9Like(WETH).deposit{value: wethNeed}();

        // Optional: seed Aave liquidity on the local fork so flashloans can always execute.
        // This is "best effort" (won't revert the whole deployment if Aave rejects supply).
        // Enable via: `SEED_AAVE_LIQUIDITY=true`
        if (vm.envOr("SEED_AAVE_LIQUIDITY", false)) {
            _seedAaveLiquidityBestEffort(deployer);
        }

        IERC20(WETH).approve(address(liquidityRouter), type(uint256).max);
        IERC20(DAI).approve(address(liquidityRouter), type(uint256).max);

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

        lpFeeAccumulator.registerPoolKey(hookPoolKey);
        lpFeeAccumulator.registerPoolKey(repayPoolKey);

        require(pm.getLiquidity(hookPoolId) > 0, "hook pool has no liquidity");
        require(pm.getLiquidity(repayPoolId) > 0, "repay pool has no liquidity");
    }

    function _seedAaveLiquidityBestEffort(address deployer) internal {
        // Keep these modest to avoid hitting supply caps or rate-limits on Sepolia.
        // WETH is seeded by default. DAI seeding is opt-in because stable reserves can be paused/frozen.
        uint256 wethSupply = vm.envOr("AAVE_WETH_SUPPLY", uint256(10 ether));
        bool seedDai = vm.envOr("SEED_AAVE_DAI", false);
        uint256 daiSupply = seedDai ? vm.envOr("AAVE_DAI_SUPPLY", uint256(100_000 ether)) : 0;
        bool strict = vm.envOr("SEED_AAVE_STRICT", false);

        if (wethSupply > 0) {
            if (IERC20(WETH).balanceOf(deployer) >= wethSupply) {
                IERC20(WETH).approve(AAVE_POOL_SEPOLIA, wethSupply);
                (bool ok,) = AAVE_POOL_SEPOLIA.call(
                    abi.encodeWithSelector(IAavePoolSupplyLike.supply.selector, WETH, wethSupply, deployer, 0)
                );
                if (!ok) {
                    if (strict) revert("Aave supply(WETH) failed on this fork");
                    console.log("WARN: Aave supply(WETH) failed on this fork");
                }
            } else if (strict) {
                revert("insufficient WETH for Aave seeding");
            } else {
                console.log("WARN: skipping Aave WETH supply (insufficient WETH)");
            }
        }

        if (daiSupply > 0) {
            if (IERC20(DAI).balanceOf(deployer) >= daiSupply) {
                IERC20(DAI).approve(AAVE_POOL_SEPOLIA, daiSupply);
                (bool ok,) = AAVE_POOL_SEPOLIA.call(
                    abi.encodeWithSelector(IAavePoolSupplyLike.supply.selector, DAI, daiSupply, deployer, 0)
                );
                if (!ok) {
                    if (strict) revert("Aave supply(DAI) failed on this fork");
                    console.log("WARN: Aave supply(DAI) failed on this fork");
                }
            } else if (strict) {
                revert("insufficient DAI for Aave seeding");
            } else {
                console.log("WARN: skipping Aave DAI supply (insufficient DAI)");
            }
        }
    }

    function _registerHookAgentsOnERC8004() internal {
        // Deploy a tiny helper registry that owns the ERC-8004 identity NFTs it mints.
        // The deployer (EOA) remains the owner of the hook-agent contracts; we only set the agentId + identityRegistry
        // fields on those contracts so they become "ERC-8004-aware".
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

    function _printSummary(address deployer) internal view {
        console.log("\n========================================");
        console.log("           LOCAL DEPLOY SUMMARY         ");
        console.log("========================================");
        console.log("Deployer:");
        console.log(deployer);
        console.log("");
        console.log("SwarmHook:");
        console.log(address(hook));
        console.log("AgentExecutor:");
        console.log(address(agentExecutor));
        console.log("SwarmCoordinator:");
        console.log(address(coordinator));
        console.log("LPFeeAccumulator:");
        console.log(address(lpFeeAccumulator));
        console.log("OracleRegistry:");
        console.log(address(oracleRegistry));
        console.log("FlashLoanBackrunner:");
        console.log(address(flashBackrunner));
        console.log("FlashBackrunExecutorAgent:");
        console.log(address(flashBackrunExecutorAgent));
        console.log("SimpleRouteAgent:");
        console.log(address(simpleRouteAgent));
        console.log("SwarmAgentRegistry (ERC-8004):");
        console.log(address(swarmAgentRegistry));
        console.log("");
        console.log("Hook Agents:");
        console.log("  ArbitrageAgent:");
        console.log(address(arbitrageAgent));
        console.log("  ArbitrageAgent ERC-8004 ID:");
        console.log(arbAgentId);
        console.log("  DynamicFeeAgent:");
        console.log(address(dynamicFeeAgent));
        console.log("  DynamicFeeAgent ERC-8004 ID:");
        console.log(feeAgentId);
        console.log("  BackrunAgent:");
        console.log(address(backrunAgent));
        console.log("  BackrunAgent ERC-8004 ID:");
        console.log(backrunAgentId);
        console.log("  SimpleRouteAgent ERC-8004 ID:");
        console.log(simpleRouteAgentErc8004Id);
        console.log("");
        console.log("Hook Pool:");
        console.log("  poolId:");
        console.logBytes32(PoolId.unwrap(hookPoolId));
        console.log("  currency0:");
        console.log(Currency.unwrap(hookPoolKey.currency0));
        console.log("  currency1:");
        console.log(Currency.unwrap(hookPoolKey.currency1));
        console.log("  fee:");
        console.log(uint256(hookPoolKey.fee));
        console.log("  tickSpacing:");
        console.log(int256(hookPoolKey.tickSpacing));
        console.log("  hooks:");
        console.log(address(hookPoolKey.hooks));
        console.log("");
        console.log("========================================");
        console.log("");
        console.log("Frontend .env:");
        console.log("  VITE_READ_RPC_URL=http://127.0.0.1:8545");
        console.log("  VITE_COORDINATOR=<above>");
        console.log("  VITE_AGENT_EXECUTOR=<above>");
        console.log("  VITE_LP_ACCUMULATOR=<above>");
        console.log("  VITE_FLASH_BACKRUNNER=<above>");
        console.log("  VITE_FLASH_BACKRUN_EXECUTOR_AGENT=<above>");
        console.log("  VITE_SIMPLE_ROUTE_AGENT=<above>");
        console.log("  VITE_SWARM_AGENT_REGISTRY=<above>");
        console.log("  VITE_ORACLE_REGISTRY=<above>");
        console.log("  VITE_POOL_MANAGER:");
        console.log(POOL_MANAGER);
        console.log("  VITE_POOL_CURRENCY_IN:");
        console.log(Currency.unwrap(hookPoolKey.currency1)); // DAI
        console.log("  VITE_POOL_CURRENCY_OUT:");
        console.log(Currency.unwrap(hookPoolKey.currency0)); // WETH
        console.log("  VITE_POOL_FEE:");
        console.log(uint256(hookPoolKey.fee));
        console.log("  VITE_POOL_TICK_SPACING:");
        console.log(int256(hookPoolKey.tickSpacing));
        console.log("  VITE_POOL_HOOKS:");
        console.log(address(hookPoolKey.hooks));
        console.log("");
    }
}
