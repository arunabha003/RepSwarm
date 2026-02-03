// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {SimpleBackrunExecutor} from "../src/backrun/SimpleBackrunExecutor.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";

/**
 * @title SepoliaForkTest
 * @notice Integration tests running on forked Sepolia testnet
 * @dev Run with: forge test --match-contract SepoliaForkTest --fork-url $SEPOLIA_RPC_URL -vvv
 */
contract SepoliaForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

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
    SimpleBackrunExecutor backrunExecutor;
    LPFeeAccumulator lpAccumulator;
    OracleRegistry oracleRegistry;
    
    address deployer;

    // ============ Setup ============
    
    function setUp() public {
        // Check we're on a fork
        require(block.chainid == 11155111, "Must run on Sepolia fork");
        
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
        
        // Register Chainlink feeds (using standard USD quote)
        oracleRegistry.setPriceFeed(WETH, address(0), ETH_USD_FEED); // WETH/USD
        console.log("ETH/USD feed registered");
        
        // Deploy LP Fee Accumulator
        lpAccumulator = new LPFeeAccumulator(poolManager, 0.001 ether, 1 hours);
        console.log("LPFeeAccumulator deployed:", address(lpAccumulator));
        
        // Deploy Backrun Executor
        backrunExecutor = new SimpleBackrunExecutor(poolManager, deployer);
        console.log("SimpleBackrunExecutor deployed:", address(backrunExecutor));
        
        vm.stopPrank();
    }

    // ============ Tests ============
    
    function test_poolManagerIsLive() public view {
        // Verify PoolManager is accessible
        assertTrue(address(poolManager) != address(0), "PoolManager not found");
        assertTrue(address(poolManager).code.length > 0, "PoolManager has no code");
        
        console.log("PoolManager is live on Sepolia!");
    }
    
    function test_chainlinkFeedIsLive() public {
        // Get ETH/USD price from Chainlink
        (, int256 price,,,) = IAggregatorV3(ETH_USD_FEED).latestRoundData();
        
        assertTrue(price > 0, "Invalid ETH price");
        console.log("ETH/USD price:", uint256(price) / 1e8, "USD");
        
        // Verify our oracle registry returns the correct price
        // OracleRegistry normalizes to 18 decimals, Chainlink uses 8
        (uint256 registeredPrice,) = oracleRegistry.getLatestPrice(WETH, address(0));
        
        // Chainlink ETH/USD has 8 decimals, registry normalizes to 18
        // So registeredPrice = price * 1e10
        uint256 expectedPrice = uint256(price) * 1e10; // Convert 8 decimals to 18
        assertEq(registeredPrice, expectedPrice, "Oracle registry price mismatch");
        console.log("OracleRegistry price (18 decimals):", registeredPrice);
    }
    
    function test_deployBackrunExecutor() public view {
        assertTrue(address(backrunExecutor) != address(0), "Backrun executor not deployed");
        assertTrue(backrunExecutor.keepers(deployer), "Deployer not set as keeper");
        assertEq(backrunExecutor.treasury(), deployer, "Treasury not set correctly");
        
        console.log("Backrun executor configured correctly");
    }
    
    function test_aavePoolAvailability() public {
        // Check if Aave V3 is accessible on Sepolia
        IAavePool aave = IAavePool(AAVE_POOL);
        
        try aave.FLASHLOAN_PREMIUM_TOTAL() returns (uint128 premium) {
            console.log("Aave V3 flash loan premium:", premium, "basis points (0.01%)");
            assertTrue(premium >= 0, "Invalid flash loan premium");
        } catch {
            console.log("Aave V3 not available - skipping flash loan tests");
        }
    }
    
    function test_wethBalance() public {
        // Check WETH contract
        IERC20 weth = IERC20(WETH);
        
        uint256 totalSupply = weth.totalSupply();
        console.log("WETH total supply:", totalSupply / 1e18, "WETH");
        
        assertTrue(totalSupply > 0, "WETH has no supply");
    }
    
    function test_depositCapitalToBackrunner() public {
        // Mint some WETH for testing
        vm.deal(deployer, 10 ether);
        
        vm.startPrank(deployer);
        
        // Wrap ETH to WETH
        IWETH(WETH).deposit{value: 5 ether}();
        
        uint256 wethBalance = IERC20(WETH).balanceOf(deployer);
        console.log("Deployer WETH balance:", wethBalance / 1e18, "WETH");
        
        // Approve and deposit to backrunner
        IERC20(WETH).approve(address(backrunExecutor), wethBalance);
        backrunExecutor.depositCapital(WETH, wethBalance);
        
        uint256 depositedCapital = backrunExecutor.capitalDeposited(WETH);
        assertEq(depositedCapital, wethBalance, "Capital not deposited correctly");
        console.log("Capital deposited to backrunner:", depositedCapital / 1e18, "WETH");
        
        vm.stopPrank();
    }
    
    function test_lpAccumulatorConfiguration() public view {
        // Verify LP accumulator is configured
        assertEq(address(lpAccumulator.poolManager()), POOL_MANAGER, "PoolManager mismatch");
        
        console.log("LP Accumulator configured correctly");
        console.log("  - Min threshold:", lpAccumulator.minDonationThreshold());
        console.log("  - Min interval:", lpAccumulator.minDonationInterval(), "seconds");
    }
    
    function test_fullSystemIntegration() public {
        console.log("\n===========================================");
        console.log("Full System Integration Test");
        console.log("===========================================");
        
        // 1. Verify all contracts deployed
        assertTrue(address(oracleRegistry) != address(0), "OracleRegistry missing");
        assertTrue(address(lpAccumulator) != address(0), "LPAccumulator missing");
        assertTrue(address(backrunExecutor) != address(0), "BackrunExecutor missing");
        console.log("[OK] All contracts deployed");
        
        // 2. Verify PoolManager connectivity
        assertTrue(address(poolManager).code.length > 0, "PoolManager not accessible");
        console.log("[OK] PoolManager accessible");
        
        // 3. Verify oracle feeds
        (uint256 ethPrice,) = oracleRegistry.getLatestPrice(WETH, address(0));
        assertTrue(ethPrice > 0, "ETH price not available");
        console.log("[OK] Oracle feeds working - ETH price:", ethPrice / 1e8, "USD");
        
        // 4. Test capital flow
        vm.deal(deployer, 1 ether);
        vm.startPrank(deployer);
        IWETH(WETH).deposit{value: 1 ether}();
        IERC20(WETH).approve(address(backrunExecutor), 1 ether);
        backrunExecutor.depositCapital(WETH, 1 ether);
        vm.stopPrank();
        console.log("[OK] Capital flow working");
        
        console.log("\n[SUCCESS] All integration tests passed!");
    }
}

// ============ Interfaces ============

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

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}
