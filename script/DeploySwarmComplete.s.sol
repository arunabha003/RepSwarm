// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {MevRouterHookV2} from "../src/hooks/MevRouterHookV2.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {FeeOptimizerAgent} from "../src/agents/FeeOptimizerAgent.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ISwarmCoordinator} from "../src/interfaces/ISwarmCoordinator.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @title DeploySwarmComplete
/// @notice Complete production deployment of Multi-Agent Trade Router Swarm
/// @dev Deploys all components including ERC-8004 integration
/// @dev Run with: forge script script/DeploySwarmComplete.s.sol:DeploySwarmComplete --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
contract DeploySwarmComplete is Script {
    // ============ Sepolia Constants ============
    
    address constant SEPOLIA_POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Chainlink Sepolia Price Feeds
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant LINK_USD_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    address constant BTC_USD_FEED = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    
    // Common Sepolia tokens  
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    // ============ Deployed Addresses ============
    
    OracleRegistry public oracleRegistry;
    LPFeeAccumulator public lpAccumulator;
    MevRouterHookV2 public hook;
    SwarmCoordinator public coordinator;
    FeeOptimizerAgent public feeAgent;
    SlippagePredictorAgent public slippageAgent;
    MevHunterAgent public mevAgent;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Multi-Agent Trade Router Swarm - Complete Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ============ Step 1: Deploy Oracle Registry ============
        console.log("\n=== Step 1: Oracle Registry ===");
        oracleRegistry = new OracleRegistry();
        console.log("OracleRegistry:", address(oracleRegistry));
        
        // Configure Chainlink feeds
        oracleRegistry.setPriceFeed(WETH, address(0), ETH_USD_FEED);
        oracleRegistry.setPriceFeed(address(0), address(0), ETH_USD_FEED);
        oracleRegistry.setPriceFeed(USDC, address(0), USDC_USD_FEED);
        console.log("Chainlink feeds configured");
        
        // ============ Step 2: Deploy LP Fee Accumulator ============
        console.log("\n=== Step 2: LP Fee Accumulator ===");
        lpAccumulator = new LPFeeAccumulator(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            0.01 ether, // Min donation threshold: 0.01 ETH worth
            1 hours // Min donation interval
        );
        console.log("LPFeeAccumulator:", address(lpAccumulator));
        
        // ============ Step 3: Deploy MevRouterHookV2 ============
        console.log("\n=== Step 3: MevRouterHookV2 ===");
        
        uint160 hookFlags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        bytes memory hookConstructorArgs = abi.encode(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            IOracleRegistry(address(oracleRegistry)),
            deployer
        );
        
        (address hookAddress, bytes32 salt) = _findHookAddress(
            CREATE2_DEPLOYER,
            hookFlags,
            type(MevRouterHookV2).creationCode,
            hookConstructorArgs
        );
        
        console.log("Hook address found:", hookAddress);
        console.log("Using salt:", vm.toString(salt));
        
        // Deploy using CREATE2
        bytes memory deploymentData = abi.encodePacked(type(MevRouterHookV2).creationCode, hookConstructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);
        
        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success, "Hook deployment failed");
        require(returnData.length == 20, "Invalid return data");
        
        address deployedHook = address(bytes20(returnData));
        require(deployedHook == hookAddress, "Hook address mismatch");
        
        hook = MevRouterHookV2(payable(deployedHook));
        console.log("MevRouterHookV2:", address(hook));
        
        // Configure hook with LP accumulator
        hook.setLPFeeAccumulator(address(lpAccumulator));
        console.log("Hook linked to LP accumulator");
        
        // Authorize hook in LP accumulator
        lpAccumulator.setHookAuthorization(address(hook), true);
        console.log("Hook authorized in LP accumulator");
        
        // ============ Step 4: Deploy SwarmCoordinator ============
        console.log("\n=== Step 4: SwarmCoordinator ===");
        
        // Get ERC-8004 registry addresses from environment if available
        address identityRegistry = vm.envOr("IDENTITY_REGISTRY", address(0));
        address reputationRegistry = vm.envOr("REPUTATION_REGISTRY", address(0));
        
        coordinator = new SwarmCoordinator(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            deployer, // treasury
            identityRegistry,
            reputationRegistry
        );
        console.log("SwarmCoordinator:", address(coordinator));
        
        // Configure reputation if registries are set
        if (identityRegistry != address(0) && reputationRegistry != address(0)) {
            // Set reputation config for agent gating
            coordinator.setReputationConfig(
                reputationRegistry,
                "routing",
                "mev",
                int256(0.5e18) // Minimum 0.5 reputation score required
            );
            console.log("Reputation config set");
            
            // Set reputation clients (the coordinator itself as a client)
            address[] memory clients = new address[](1);
            clients[0] = address(coordinator);
            coordinator.setReputationClients(clients);
            console.log("Reputation clients set");
        } else {
            console.log("WARNING: ERC-8004 registries not configured");
            console.log("Run DeployERC8004 first, then update coordinator");
        }
        
        // ============ Step 5: Deploy Agents ============
        console.log("\n=== Step 5: Deploy Agents ===");
        
        feeAgent = new FeeOptimizerAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER)
        );
        console.log("FeeOptimizerAgent:", address(feeAgent));
        
        slippageAgent = new SlippagePredictorAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER)
        );
        console.log("SlippagePredictorAgent:", address(slippageAgent));
        
        mevAgent = new MevHunterAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER),
            IOracleRegistry(address(oracleRegistry))
        );
        console.log("MevHunterAgent:", address(mevAgent));
        
        // ============ Step 6: Register Agents ============
        console.log("\n=== Step 6: Register Agents ===");
        
        // Note: Agent IDs should match ERC-8004 identity NFT IDs
        // For now, use sequential IDs (update after ERC-8004 deployment)
        uint256 feeAgentId = vm.envOr("FEE_OPTIMIZER_AGENT_ID", uint256(1));
        uint256 slippageAgentId = vm.envOr("SLIPPAGE_PREDICTOR_AGENT_ID", uint256(2));
        uint256 mevAgentId = vm.envOr("MEV_HUNTER_AGENT_ID", uint256(3));
        
        coordinator.registerAgent(address(feeAgent), feeAgentId, true);
        console.log("FeeOptimizer registered with ID:", feeAgentId);
        
        coordinator.registerAgent(address(slippageAgent), slippageAgentId, true);
        console.log("SlippagePredictor registered with ID:", slippageAgentId);
        
        coordinator.registerAgent(address(mevAgent), mevAgentId, true);
        console.log("MevHunter registered with ID:", mevAgentId);
        
        vm.stopBroadcast();
        
        // ============ Deployment Summary ============
        _printDeploymentSummary(identityRegistry, reputationRegistry);
    }
    
    function _findHookAddress(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);
        
        uint256 saltCounter = 0;
        while (saltCounter < 100000) {
            salt = bytes32(saltCounter);
            hookAddress = _computeCreate2Address(deployer, salt, bytecodeHash);
            
            if (_hasCorrectFlags(hookAddress, flags)) {
                return (hookAddress, salt);
            }
            saltCounter++;
        }
        revert("Could not find valid hook address");
    }
    
    function _computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            bytecodeHash
        )))));
    }
    
    function _hasCorrectFlags(address hookAddress, uint160 flags) internal pure returns (bool) {
        return uint160(hookAddress) & 0xFFFF == flags;
    }
    
    function _printDeploymentSummary(address identityRegistry, address reputationRegistry) internal view {
        console.log("\n========================================");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("========================================");
        console.log("\n--- Core Infrastructure ---");
        console.log("OracleRegistry:", address(oracleRegistry));
        console.log("LPFeeAccumulator:", address(lpAccumulator));
        console.log("MevRouterHookV2:", address(hook));
        console.log("SwarmCoordinator:", address(coordinator));
        
        console.log("\n--- Agents ---");
        console.log("FeeOptimizerAgent:", address(feeAgent));
        console.log("SlippagePredictorAgent:", address(slippageAgent));
        console.log("MevHunterAgent:", address(mevAgent));
        
        console.log("\n--- ERC-8004 Status ---");
        if (identityRegistry != address(0)) {
            console.log("IdentityRegistry:", identityRegistry);
            console.log("ReputationRegistry:", reputationRegistry);
            console.log("Status: CONFIGURED");
        } else {
            console.log("Status: NOT CONFIGURED");
            console.log("Action: Run DeployERC8004 and update coordinator");
        }
        
        console.log("\n--- Next Steps ---");
        console.log("1. Deploy ERC-8004 registries (if not done): forge script script/DeployERC8004.s.sol");
        console.log("2. Register agents with ERC-8004: forge script script/DeployERC8004.s.sol:SetupSwarmAgents");
        console.log("3. Update coordinator with registry addresses");
        console.log("4. Initialize pools with hook");
        console.log("5. Add liquidity to pools");
        console.log("========================================");
    }
}

/// @title ConfigureERC8004Integration
/// @notice Updates SwarmCoordinator with ERC-8004 registry addresses after deployment
contract ConfigureERC8004Integration is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        address coordinatorAddr = vm.envAddress("SWARM_COORDINATOR");
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");
        address reputationRegistry = vm.envAddress("REPUTATION_REGISTRY");
        
        console.log("=== Configuring ERC-8004 Integration ===");
        console.log("SwarmCoordinator:", coordinatorAddr);
        console.log("IdentityRegistry:", identityRegistry);
        console.log("ReputationRegistry:", reputationRegistry);
        
        SwarmCoordinator coordinator = SwarmCoordinator(payable(coordinatorAddr));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Set identity registry
        coordinator.setIdentityRegistry(identityRegistry);
        console.log("Identity registry set");
        
        // Set reputation config
        coordinator.setReputationConfig(
            reputationRegistry,
            "routing",
            "mev",
            int256(0.5e18) // Minimum 0.5 WAD reputation
        );
        console.log("Reputation config set");
        
        // Set reputation clients
        address[] memory clients = new address[](1);
        clients[0] = coordinatorAddr;
        coordinator.setReputationClients(clients);
        console.log("Reputation clients set");
        
        vm.stopBroadcast();
        
        console.log("\n=== ERC-8004 Integration Complete ===");
        console.log("Agents must now have valid identity NFTs and reputation scores to propose routes");
    }
}
