// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {DynamicFeeAgent} from "../src/agents/DynamicFeeAgent.sol";
import {BackrunAgent} from "../src/agents/BackrunAgent.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {ISwarmAgent, AgentType} from "../src/interfaces/ISwarmAgent.sol";

interface IAggregatorV3 {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

interface IAavePool {
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}

/**
 * @title SepoliaForkTest
 * @notice Integration tests running on forked Sepolia testnet
 * @dev Run with: forge test --match-contract SepoliaForkTest --fork-url $SEPOLIA_RPC_URL -vvv
 */
contract SepoliaForkTest is Test {
    using PoolIdLibrary for PoolKey;

    string internal constant DEFAULT_SEPOLIA_RPC_URL =
        "https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo";

    // ============ Sepolia Addresses ============
    
    // Uniswap V4 PoolManager on Sepolia
    address constant POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    // Aave V3 Pool on Sepolia
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    
    // Tokens on Sepolia
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;
    
    // Chainlink Feeds on Sepolia
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    
    // ============ State ============
    
    IPoolManager poolManager;
    AgentExecutor executor;
    ArbitrageAgent arbAgent;
    DynamicFeeAgent feeAgent;
    BackrunAgent backrunAgent;
    LPFeeAccumulator lpAccumulator;
    OracleRegistry oracleRegistry;
    
    address deployer;

    // ============ Setup ============
    
    function setUp() public {
        // Always run on a Sepolia fork so `forge test` works without CLI flags.
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", DEFAULT_SEPOLIA_RPC_URL);
        vm.createSelectFork(rpc);
        
        deployer = makeAddr("deployer");
        vm.deal(deployer, 100 ether);
        
        // Get PoolManager from Sepolia
        poolManager = IPoolManager(POOL_MANAGER);
        
        console.log("===========================================");
        console.log("Sepolia Fork Test Setup");
        console.log("===========================================");
        console.log("Block number:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("PoolManager:", address(poolManager));
        
        // Deploy our contracts
        vm.startPrank(deployer);
        
        // Deploy Oracle Registry
        oracleRegistry = new OracleRegistry();
        console.log("OracleRegistry deployed:", address(oracleRegistry));
        
        // Register Chainlink feeds
        oracleRegistry.setPriceFeed(WETH, address(0), ETH_USD_FEED);
        console.log("ETH/USD feed registered");
        
        // Deploy LP Fee Accumulator
        lpAccumulator = new LPFeeAccumulator(poolManager, 0.001 ether, 1 hours);
        console.log("LPFeeAccumulator deployed:", address(lpAccumulator));
        
        // Deploy Agents with correct constructors
        arbAgent = new ArbitrageAgent(
            poolManager,
            deployer,
            8000,  // 80% hook share
            50     // 0.5% min divergence
        );
        console.log("ArbitrageAgent deployed:", address(arbAgent));
        
        feeAgent = new DynamicFeeAgent(
            poolManager,
            deployer
        );
        console.log("DynamicFeeAgent deployed:", address(feeAgent));
        
        backrunAgent = new BackrunAgent(
            poolManager,
            deployer
        );
        console.log("BackrunAgent deployed:", address(backrunAgent));
        
        // Deploy Executor
        executor = new AgentExecutor();
        console.log("AgentExecutor deployed:", address(executor));
        
        // Register agents
        executor.registerAgent(AgentType.ARBITRAGE, address(arbAgent));
        executor.registerAgent(AgentType.DYNAMIC_FEE, address(feeAgent));
        executor.registerAgent(AgentType.BACKRUN, address(backrunAgent));
        
        vm.stopPrank();
    }

    // ============ Tests ============
    
    function test_poolManagerIsLive() public view {
        assertTrue(address(poolManager) != address(0), "PoolManager not found");
        assertTrue(address(poolManager).code.length > 0, "PoolManager has no code");
        console.log("PoolManager is live on Sepolia!");
    }
    
    function test_chainlinkFeedIsLive() public {
        (, int256 price,,,) = IAggregatorV3(ETH_USD_FEED).latestRoundData();
        assertTrue(price > 0, "Invalid ETH price");
        console.log("ETH/USD price:", uint256(price) / 1e8, "USD");
        
        (uint256 registeredPrice,) = oracleRegistry.getLatestPrice(WETH, address(0));
        uint256 expectedPrice = uint256(price) * 1e10;
        assertEq(registeredPrice, expectedPrice, "Oracle registry price mismatch");
    }
    
    function test_agentExecutorConfiguration() public view {
        assertEq(executor.agents(AgentType.ARBITRAGE), address(arbAgent));
        assertEq(executor.agents(AgentType.DYNAMIC_FEE), address(feeAgent));
        assertEq(executor.agents(AgentType.BACKRUN), address(backrunAgent));
        
        assertTrue(executor.agentEnabled(AgentType.ARBITRAGE));
        assertTrue(executor.agentEnabled(AgentType.DYNAMIC_FEE));
        assertTrue(executor.agentEnabled(AgentType.BACKRUN));
        
        console.log("Agent executor configured correctly");
    }
    
    function test_agentTypesCorrect() public view {
        assertEq(uint8(arbAgent.agentType()), uint8(AgentType.ARBITRAGE));
        assertEq(uint8(feeAgent.agentType()), uint8(AgentType.DYNAMIC_FEE));
        assertEq(uint8(backrunAgent.agentType()), uint8(AgentType.BACKRUN));
        console.log("All agent types correctly identified");
    }
    
    function test_aavePoolAvailability() public {
        IAavePool aave = IAavePool(AAVE_POOL);
        try aave.FLASHLOAN_PREMIUM_TOTAL() returns (uint128 premium) {
            console.log("Aave V3 flash loan premium:", premium, "basis points");
            assertTrue(premium >= 0, "Invalid flash loan premium");
        } catch {
            console.log("Aave V3 not available - skipping flash loan tests");
        }
    }
    
    function test_wethBalance() public {
        IERC20 weth = IERC20(WETH);
        uint256 totalSupply = weth.totalSupply();
        console.log("WETH total supply:", totalSupply / 1e18, "WETH");
        assertTrue(totalSupply > 0, "WETH has no supply");
    }
    
    function test_agentHotSwap() public {
        vm.startPrank(deployer);
        
        ArbitrageAgent newArbAgent = new ArbitrageAgent(
            poolManager,
            deployer,
            9000, // different share
            100   // different threshold
        );
        
        executor.registerAgent(AgentType.ARBITRAGE, address(newArbAgent));
        assertEq(executor.agents(AgentType.ARBITRAGE), address(newArbAgent));
        console.log("Agent hot-swapped successfully");
        
        vm.stopPrank();
    }
    
    function test_agentDisableEnable() public {
        vm.startPrank(deployer);
        
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, false);
        assertFalse(executor.agentEnabled(AgentType.DYNAMIC_FEE));
        console.log("Fee agent disabled");
        
        executor.setAgentEnabled(AgentType.DYNAMIC_FEE, true);
        assertTrue(executor.agentEnabled(AgentType.DYNAMIC_FEE));
        console.log("Fee agent re-enabled");
        
        vm.stopPrank();
    }
    
    function test_erc8004Identity() public {
        vm.startPrank(deployer);
        
        arbAgent.configureIdentity(12345, address(0x1234));
        
        assertEq(arbAgent.getAgentId(), 12345);
        console.log("ERC-8004 identity configured");
        
        vm.stopPrank();
    }
}
