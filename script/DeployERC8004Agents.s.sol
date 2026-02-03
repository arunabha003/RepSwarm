// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {SwarmAgentRegistry} from "../src/erc8004/SwarmAgentRegistry.sol";
import {FeeOptimizerAgent} from "../src/agents/FeeOptimizerAgent.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ISwarmCoordinator} from "../src/interfaces/ISwarmCoordinator.sol";
import {ERC8004Integration} from "../src/erc8004/ERC8004Integration.sol";

/// @title DeployERC8004Agents
/// @notice Deploys Swarm agents and registers them on ERC-8004
/// @dev Run with: forge script script/DeployERC8004Agents.s.sol:DeployERC8004Agents --rpc-url $SEPOLIA_RPC_URL --broadcast
contract DeployERC8004Agents is Script {
    // ============ Sepolia Constants ============
    
    address constant SEPOLIA_POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    // Chainlink Price Feeds (Sepolia)
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    
    // Tokens
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    // ============ Deployed Contracts ============
    
    SwarmAgentRegistry public agentRegistry;
    SwarmCoordinator public coordinator;
    OracleRegistry public oracleRegistry;
    
    FeeOptimizerAgent public feeAgent;
    MevHunterAgent public mevAgent;
    SlippagePredictorAgent public slippageAgent;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== ERC-8004 Agent Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("");
        console.log("ERC-8004 Identity Registry:", ERC8004Integration.SEPOLIA_IDENTITY_REGISTRY);
        console.log("ERC-8004 Reputation Registry:", ERC8004Integration.SEPOLIA_REPUTATION_REGISTRY);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ Step 1: Deploy Oracle Registry ============
        console.log("\n=== Step 1: Oracle Registry ===");
        oracleRegistry = new OracleRegistry();
        console.log("OracleRegistry:", address(oracleRegistry));
        
        // Configure price feeds
        oracleRegistry.setPriceFeed(WETH, address(0), ETH_USD_FEED);
        oracleRegistry.setPriceFeed(address(0), address(0), ETH_USD_FEED);
        console.log("Price feeds configured");
        
        // ============ Step 2: Deploy SwarmCoordinator ============
        console.log("\n=== Step 2: SwarmCoordinator ===");
        coordinator = new SwarmCoordinator(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            deployer, // treasury
            address(0), // Use default Sepolia Identity Registry
            address(0)  // Use default Sepolia Reputation Registry
        );
        console.log("SwarmCoordinator:", address(coordinator));
        
        // ============ Step 3: Deploy SwarmAgentRegistry ============
        console.log("\n=== Step 3: SwarmAgentRegistry ===");
        agentRegistry = new SwarmAgentRegistry(
            address(0), // Use default Sepolia Identity Registry
            address(0)  // Use default Sepolia Reputation Registry
        );
        console.log("SwarmAgentRegistry:", address(agentRegistry));
        
        // Authorize coordinator to give feedback
        agentRegistry.setFeedbackClientAuthorization(address(coordinator), true);
        console.log("Coordinator authorized for feedback");
        
        // ============ Step 4: Deploy Agents ============
        console.log("\n=== Step 4: Deploy Agents ===");
        
        // Fee Optimizer Agent
        feeAgent = new FeeOptimizerAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER)
        );
        console.log("FeeOptimizerAgent:", address(feeAgent));
        
        // MEV Hunter Agent
        mevAgent = new MevHunterAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER),
            IOracleRegistry(address(oracleRegistry))
        );
        console.log("MevHunterAgent:", address(mevAgent));
        
        // Slippage Predictor Agent
        slippageAgent = new SlippagePredictorAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER)
        );
        console.log("SlippagePredictorAgent:", address(slippageAgent));
        
        // ============ Step 5: Register Agents on ERC-8004 ============
        console.log("\n=== Step 5: Register on ERC-8004 ===");
        
        uint256 feeAgentId = agentRegistry.registerAgent(
            address(feeAgent),
            "Swarm Fee Optimizer",
            "Optimizes swap fees by analyzing pool fee structures",
            "fee-optimizer",
            "1.0.0"
        );
        console.log("FeeOptimizerAgent registered with ID:", feeAgentId);
        
        uint256 mevAgentId = agentRegistry.registerAgent(
            address(mevAgent),
            "Swarm MEV Hunter",
            "Detects MEV opportunities using oracle price comparison",
            "mev-hunter",
            "1.0.0"
        );
        console.log("MevHunterAgent registered with ID:", mevAgentId);
        
        uint256 slippageAgentId = agentRegistry.registerAgent(
            address(slippageAgent),
            "Swarm Slippage Predictor",
            "Predicts swap slippage using SwapMath simulation",
            "slippage-predictor",
            "1.0.0"
        );
        console.log("SlippagePredictorAgent registered with ID:", slippageAgentId);
        
        // ============ Step 6: Configure Agents with ERC-8004 ============
        console.log("\n=== Step 6: Configure Agent Reputation ===");
        
        feeAgent.configureReputation(feeAgentId, address(0));
        console.log("FeeOptimizerAgent reputation configured");
        
        mevAgent.configureReputation(mevAgentId, address(0));
        console.log("MevHunterAgent reputation configured");
        
        slippageAgent.configureReputation(slippageAgentId, address(0));
        console.log("SlippagePredictorAgent reputation configured");
        
        // ============ Step 7: Register Agents in Coordinator ============
        console.log("\n=== Step 7: Register in Coordinator ===");
        
        coordinator.registerAgent(address(feeAgent), feeAgentId, true);
        console.log("FeeOptimizerAgent registered in coordinator");
        
        coordinator.registerAgent(address(mevAgent), mevAgentId, true);
        console.log("MevHunterAgent registered in coordinator");
        
        coordinator.registerAgent(address(slippageAgent), slippageAgentId, true);
        console.log("SlippagePredictorAgent registered in coordinator");
        
        vm.stopBroadcast();
        
        // ============ Summary ============
        console.log("\n=== Deployment Summary ===");
        console.log("OracleRegistry:", address(oracleRegistry));
        console.log("SwarmCoordinator:", address(coordinator));
        console.log("SwarmAgentRegistry:", address(agentRegistry));
        console.log("");
        console.log("Agents:");
        console.log("  FeeOptimizerAgent:", address(feeAgent), "ID:", feeAgentId);
        console.log("  MevHunterAgent:", address(mevAgent), "ID:", mevAgentId);
        console.log("  SlippagePredictorAgent:", address(slippageAgent), "ID:", slippageAgentId);
        console.log("");
        console.log("View agents on 8004scan: https://8004scan.io/");
    }
}

/// @title RegisterExistingAgents
/// @notice Register existing agent contracts on ERC-8004
contract RegisterExistingAgents is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Set these to your deployed contract addresses
        address agentRegistryAddr = vm.envAddress("AGENT_REGISTRY");
        address feeAgentAddr = vm.envAddress("FEE_AGENT");
        address mevAgentAddr = vm.envAddress("MEV_AGENT");
        address slippageAgentAddr = vm.envAddress("SLIPPAGE_AGENT");
        
        vm.startBroadcast(deployerPrivateKey);
        
        SwarmAgentRegistry registry = SwarmAgentRegistry(agentRegistryAddr);
        
        if (feeAgentAddr != address(0)) {
            uint256 id = registry.registerAgent(
                feeAgentAddr,
                "Swarm Fee Optimizer",
                "Optimizes swap fees",
                "fee-optimizer",
                "1.0.0"
            );
            console.log("FeeAgent registered:", id);
        }
        
        if (mevAgentAddr != address(0)) {
            uint256 id = registry.registerAgent(
                mevAgentAddr,
                "Swarm MEV Hunter",
                "Detects MEV opportunities",
                "mev-hunter",
                "1.0.0"
            );
            console.log("MevAgent registered:", id);
        }
        
        if (slippageAgentAddr != address(0)) {
            uint256 id = registry.registerAgent(
                slippageAgentAddr,
                "Swarm Slippage Predictor",
                "Predicts swap slippage",
                "slippage-predictor",
                "1.0.0"
            );
            console.log("SlippageAgent registered:", id);
        }
        
        vm.stopBroadcast();
    }
}
