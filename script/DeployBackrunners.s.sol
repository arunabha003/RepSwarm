// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {SimpleBackrunExecutor} from "../src/backrun/SimpleBackrunExecutor.sol";
import {FlashLoanBackrunner} from "../src/backrun/FlashLoanBackrunner.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {MevRouterHookV2} from "../src/hooks/MevRouterHookV2.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";

/// @title DeployBackrunners
/// @notice Deploy and configure backrun executors on Sepolia fork
contract DeployBackrunners is Script {
    // ============ Sepolia Addresses ============
    
    // Uniswap V4 on Sepolia (placeholder - replace with actual)
    address constant POOL_MANAGER_SEPOLIA = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    // Aave V3 on Sepolia
    address constant AAVE_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    
    // WETH on Sepolia
    address constant WETH_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    
    // USDC on Sepolia (Aave faucet version)
    address constant USDC_SEPOLIA = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    
    // DAI on Sepolia
    address constant DAI_SEPOLIA = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("===========================================");
        console.log("Deploying Backrun Infrastructure on Sepolia");
        console.log("===========================================");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Simple Backrun Executor
        console.log("\n1. Deploying SimpleBackrunExecutor...");
        SimpleBackrunExecutor simpleExecutor = new SimpleBackrunExecutor(
            IPoolManager(POOL_MANAGER_SEPOLIA),
            deployer // Treasury
        );
        console.log("   SimpleBackrunExecutor:", address(simpleExecutor));
        
        // 2. Deploy Flash Loan Backrunner
        console.log("\n2. Deploying FlashLoanBackrunner...");
        FlashLoanBackrunner flashBackrunner = new FlashLoanBackrunner(
            IPoolManager(POOL_MANAGER_SEPOLIA),
            AAVE_POOL_SEPOLIA
        );
        console.log("   FlashLoanBackrunner:", address(flashBackrunner));
        
        // 3. Deploy LP Fee Accumulator
        console.log("\n3. Deploying LPFeeAccumulator...");
        LPFeeAccumulator accumulator = new LPFeeAccumulator(
            IPoolManager(POOL_MANAGER_SEPOLIA),
            0.001 ether, // Min donation threshold
            1 hours      // Min donation interval
        );
        console.log("   LPFeeAccumulator:", address(accumulator));
        
        // 4. Connect components
        console.log("\n4. Configuring connections...");
        flashBackrunner.setLPFeeAccumulator(address(accumulator));
        console.log("   FlashBackrunner -> LPAccumulator connected");
        
        vm.stopBroadcast();
        
        // Print summary
        console.log("\n===========================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("===========================================");
        console.log("SimpleBackrunExecutor:", address(simpleExecutor));
        console.log("FlashLoanBackrunner:", address(flashBackrunner));
        console.log("LPFeeAccumulator:", address(accumulator));
        console.log("\nNext steps:");
        console.log("1. Deposit capital to SimpleBackrunExecutor");
        console.log("2. Add keepers to both executors");
        console.log("3. Connect to MevRouterHookV2");
    }
}

/// @title TestBackrunOnFork
/// @notice Test backrun execution on forked Sepolia
contract TestBackrunOnFork is Script {
    function run() external {
        // This would be run with: forge script --fork-url $SEPOLIA_RPC
        console.log("Testing backrun on Sepolia fork...");
        console.log("Block number:", block.number);
        console.log("Timestamp:", block.timestamp);
        
        // Test Aave flash loan availability
        IAavePool aave = IAavePool(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951);
        
        try aave.FLASHLOAN_PREMIUM_TOTAL() returns (uint128 premium) {
            console.log("Aave flash loan premium:", premium, "bps");
        } catch {
            console.log("Aave pool not available on this network");
        }
    }
}

interface IAavePool {
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}
