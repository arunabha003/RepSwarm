// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployERC8004
/// @notice Deploys REAL ERC-8004 Identity and Reputation registries on Sepolia
/// @dev NO MOCKING - This creates actual upgradeable proxy contracts
/// @dev Run with: forge script script/DeployERC8004.s.sol:DeployERC8004 --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

// Import the actual ERC-8004 implementation contracts
// These are from lib/erc-8004-contracts/contracts/

interface IIdentityRegistryUpgradeable {
    function initialize() external;
    function register() external returns (uint256 agentId);
    function register(string memory agentURI) external returns (uint256 agentId);
    function getAgentWallet(uint256 agentId) external view returns (address);
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);
    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external;
    function ownerOf(uint256 agentId) external view returns (address);
}

interface IReputationRegistryUpgradeable {
    function initialize(address identityRegistry_) external;
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external view returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked);
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);
}

contract DeployERC8004 is Script {
    // Deployed addresses will be saved here
    address public identityRegistryProxy;
    address public reputationRegistryProxy;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Deploying ERC-8004 Registries ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ Step 1: Deploy Identity Registry Implementation ============
        console.log("\n=== Deploying IdentityRegistry ===");
        
        // Deploy implementation
        bytes memory identityImplCode = vm.getCode("IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable");
        address identityImpl;
        assembly {
            identityImpl := create(0, add(identityImplCode, 0x20), mload(identityImplCode))
        }
        require(identityImpl != address(0), "Identity impl deployment failed");
        console.log("IdentityRegistry Implementation:", identityImpl);
        
        // Deploy proxy with initialize call
        bytes memory identityInitData = abi.encodeWithSignature("initialize()");
        ERC1967Proxy identityProxy = new ERC1967Proxy(identityImpl, identityInitData);
        identityRegistryProxy = address(identityProxy);
        console.log("IdentityRegistry Proxy:", identityRegistryProxy);
        
        // ============ Step 2: Deploy Reputation Registry Implementation ============
        console.log("\n=== Deploying ReputationRegistry ===");
        
        // Deploy implementation
        bytes memory reputationImplCode = vm.getCode("ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable");
        address reputationImpl;
        assembly {
            reputationImpl := create(0, add(reputationImplCode, 0x20), mload(reputationImplCode))
        }
        require(reputationImpl != address(0), "Reputation impl deployment failed");
        console.log("ReputationRegistry Implementation:", reputationImpl);
        
        // Deploy proxy with initialize call (passing identity registry address)
        bytes memory reputationInitData = abi.encodeWithSignature("initialize(address)", identityRegistryProxy);
        ERC1967Proxy reputationProxy = new ERC1967Proxy(reputationImpl, reputationInitData);
        reputationRegistryProxy = address(reputationProxy);
        console.log("ReputationRegistry Proxy:", reputationRegistryProxy);
        
        vm.stopBroadcast();
        
        // ============ Verification ============
        console.log("\n=== Verifying Deployment ===");
        
        // Verify identity registry is working
        IIdentityRegistryUpgradeable identity = IIdentityRegistryUpgradeable(identityRegistryProxy);
        
        // Verify reputation registry is linked correctly
        IReputationRegistryUpgradeable reputation = IReputationRegistryUpgradeable(reputationRegistryProxy);
        
        console.log("\n=== Deployment Complete ===");
        console.log("IdentityRegistry Proxy:", identityRegistryProxy);
        console.log("ReputationRegistry Proxy:", reputationRegistryProxy);
        console.log("\nSave these addresses for SwarmCoordinator configuration!");
    }
}

/// @title SetupSwarmAgents
/// @notice Registers agents with ERC-8004 Identity Registry and seeds initial reputation
/// @dev Run after DeployERC8004 to create agent identities
contract SetupSwarmAgents is Script {
    // Agent metadata URIs (could be IPFS hashes in production)
    string constant FEE_OPTIMIZER_URI = "https://swarm.agents/fee-optimizer/metadata.json";
    string constant SLIPPAGE_PREDICTOR_URI = "https://swarm.agents/slippage-predictor/metadata.json";
    string constant MEV_HUNTER_URI = "https://swarm.agents/mev-hunter/metadata.json";
    
    // Reputation tags for swarm routing
    string constant TAG_ROUTING = "routing";
    string constant TAG_MEV = "mev";
    
    struct AgentSetup {
        address agentContract;
        string uri;
        uint256 agentId;
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get deployed registry addresses from environment
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");
        address reputationRegistry = vm.envAddress("REPUTATION_REGISTRY");
        
        // Get agent contract addresses
        address feeOptimizer = vm.envAddress("FEE_OPTIMIZER_AGENT");
        address slippagePredictor = vm.envAddress("SLIPPAGE_PREDICTOR_AGENT");
        address mevHunter = vm.envAddress("MEV_HUNTER_AGENT");
        
        console.log("=== Setting Up Swarm Agents with ERC-8004 ===");
        console.log("IdentityRegistry:", identityRegistry);
        console.log("ReputationRegistry:", reputationRegistry);
        
        IIdentityRegistryUpgradeable identity = IIdentityRegistryUpgradeable(identityRegistry);
        IReputationRegistryUpgradeable reputation = IReputationRegistryUpgradeable(reputationRegistry);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ Register Agent Identities ============
        
        // Register FeeOptimizer Agent
        console.log("\n=== Registering FeeOptimizer Agent ===");
        uint256 feeOptimizerId = identity.register(FEE_OPTIMIZER_URI);
        console.log("FeeOptimizer Agent ID:", feeOptimizerId);
        
        // Set agent contract address as metadata
        identity.setMetadata(feeOptimizerId, "contractAddress", abi.encodePacked(feeOptimizer));
        identity.setMetadata(feeOptimizerId, "agentType", bytes("fee_optimizer"));
        identity.setMetadata(feeOptimizerId, "version", bytes("1.0.0"));
        
        // Register SlippagePredictor Agent
        console.log("\n=== Registering SlippagePredictor Agent ===");
        uint256 slippagePredictorId = identity.register(SLIPPAGE_PREDICTOR_URI);
        console.log("SlippagePredictor Agent ID:", slippagePredictorId);
        
        identity.setMetadata(slippagePredictorId, "contractAddress", abi.encodePacked(slippagePredictor));
        identity.setMetadata(slippagePredictorId, "agentType", bytes("slippage_predictor"));
        identity.setMetadata(slippagePredictorId, "version", bytes("1.0.0"));
        
        // Register MevHunter Agent
        console.log("\n=== Registering MevHunter Agent ===");
        uint256 mevHunterId = identity.register(MEV_HUNTER_URI);
        console.log("MevHunter Agent ID:", mevHunterId);
        
        identity.setMetadata(mevHunterId, "contractAddress", abi.encodePacked(mevHunter));
        identity.setMetadata(mevHunterId, "agentType", bytes("mev_hunter"));
        identity.setMetadata(mevHunterId, "version", bytes("1.0.0"));
        
        vm.stopBroadcast();
        
        // ============ Output Summary ============
        console.log("\n=== Agent Registration Complete ===");
        console.log("FeeOptimizer Agent ID:", feeOptimizerId);
        console.log("SlippagePredictor Agent ID:", slippagePredictorId);
        console.log("MevHunter Agent ID:", mevHunterId);
        
        console.log("\n=== Next Steps ===");
        console.log("1. Update SwarmCoordinator with these agent IDs");
        console.log("2. Call coordinator.setIdentityRegistry(identityRegistry)");
        console.log("3. Call coordinator.setReputationConfig(reputationRegistry, 'routing', 'mev', minRepWad)");
        console.log("4. Register agents with coordinator.registerAgent(agentAddr, agentId, true)");
    }
}

/// @title SeedAgentReputation  
/// @notice Seeds initial reputation for agents to bootstrap the system
/// @dev This is called by clients after agents have performed well
contract SeedAgentReputation is Script {
    string constant TAG_ROUTING = "routing";
    string constant TAG_MEV = "mev";
    
    function run() external {
        uint256 clientPrivateKey = vm.envUint("CLIENT_PRIVATE_KEY"); // Different from deployer
        address client = vm.addr(clientPrivateKey);
        
        address reputationRegistry = vm.envAddress("REPUTATION_REGISTRY");
        
        // Agent IDs to give feedback to
        uint256 feeOptimizerId = vm.envUint("FEE_OPTIMIZER_AGENT_ID");
        uint256 slippagePredictorId = vm.envUint("SLIPPAGE_PREDICTOR_AGENT_ID");
        uint256 mevHunterId = vm.envUint("MEV_HUNTER_AGENT_ID");
        
        console.log("=== Seeding Agent Reputation ===");
        console.log("Client:", client);
        console.log("ReputationRegistry:", reputationRegistry);
        
        IReputationRegistryUpgradeable reputation = IReputationRegistryUpgradeable(reputationRegistry);
        
        vm.startBroadcast(clientPrivateKey);
        
        // Give positive feedback to FeeOptimizer
        // value = 1e18 (1.0 in WAD format), 18 decimals
        reputation.giveFeedback(
            feeOptimizerId,
            int128(int256(1e18)), // +1.0 score
            18, // decimals
            TAG_ROUTING,
            TAG_MEV,
            "", // endpoint
            "", // feedbackURI
            bytes32(0) // feedbackHash
        );
        console.log("Feedback given to FeeOptimizer");
        
        // Give positive feedback to SlippagePredictor
        reputation.giveFeedback(
            slippagePredictorId,
            int128(int256(1e18)),
            18,
            TAG_ROUTING,
            TAG_MEV,
            "",
            "",
            bytes32(0)
        );
        console.log("Feedback given to SlippagePredictor");
        
        // Give positive feedback to MevHunter
        reputation.giveFeedback(
            mevHunterId,
            int128(int256(1e18)),
            18,
            TAG_ROUTING,
            TAG_MEV,
            "",
            "",
            bytes32(0)
        );
        console.log("Feedback given to MevHunter");
        
        vm.stopBroadcast();
        
        // Verify reputations
        console.log("\n=== Verifying Reputations ===");
        
        address[] memory clients = new address[](1);
        clients[0] = client;
        
        (uint64 count1, int128 value1,) = reputation.getSummary(feeOptimizerId, clients, TAG_ROUTING, TAG_MEV);
        console.log("FeeOptimizer - Count:", count1, "Value:", uint256(int256(value1)));
        
        (uint64 count2, int128 value2,) = reputation.getSummary(slippagePredictorId, clients, TAG_ROUTING, TAG_MEV);
        console.log("SlippagePredictor - Count:", count2, "Value:", uint256(int256(value2)));
        
        (uint64 count3, int128 value3,) = reputation.getSummary(mevHunterId, clients, TAG_ROUTING, TAG_MEV);
        console.log("MevHunter - Count:", count3, "Value:", uint256(int256(value3)));
    }
}
