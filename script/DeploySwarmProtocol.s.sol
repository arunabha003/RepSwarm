// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

import {SwarmHook} from "../src/hooks/SwarmHook.sol";
import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {DynamicFeeAgent} from "../src/agents/DynamicFeeAgent.sol";
import {BackrunAgent} from "../src/agents/BackrunAgent.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {ISwarmAgent, AgentType} from "../src/interfaces/ISwarmAgent.sol";

/// @title DeploySwarmProtocol
/// @notice Deploys the complete agent-driven Swarm protocol
/// @dev New architecture: Hook -> AgentExecutor -> Agents
contract DeploySwarmProtocol is Script {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // ============ Sepolia Addresses ============
    
    address constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address constant ERC8004_IDENTITY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant ERC8004_REPUTATION = 0x8004B663056A597Dffe9eCcC1965A193B7388713;

    // Deployed contracts
    SwarmHook public hook;
    AgentExecutor public agentExecutor;
    ArbitrageAgent public arbitrageAgent;
    DynamicFeeAgent public dynamicFeeAgent;
    BackrunAgent public backrunAgent;
    LPFeeAccumulator public lpFeeAccumulator;
    OracleRegistry public oracleRegistry;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Swarm Protocol Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Pool Manager:", POOL_MANAGER);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Oracle Registry
        console.log("\n1. Deploying Oracle Registry...");
        oracleRegistry = new OracleRegistry();
        console.log("   Oracle Registry:", address(oracleRegistry));

        // 2. Deploy LP Fee Accumulator
        console.log("\n2. Deploying LP Fee Accumulator...");
        lpFeeAccumulator = new LPFeeAccumulator(
            IPoolManager(POOL_MANAGER),
            0.001 ether,  // Min donation threshold
            1 hours       // Min donation interval
        );
        console.log("   LP Fee Accumulator:", address(lpFeeAccumulator));

        // 3. Deploy Agent Executor
        console.log("\n3. Deploying Agent Executor...");
        agentExecutor = new AgentExecutor();
        console.log("   Agent Executor:", address(agentExecutor));

        // 4. Deploy Hook with mined address
        console.log("\n4. Mining hook address...");
        hook = _deployHook(deployer);
        console.log("   SwarmHook:", address(hook));

        // 5. Deploy Agents
        console.log("\n5. Deploying Agents...");
        
        // Arbitrage Agent
        arbitrageAgent = new ArbitrageAgent(
            IPoolManager(POOL_MANAGER),
            deployer,
            8000,   // 80% hook share
            50      // 0.5% min divergence
        );
        console.log("   Arbitrage Agent:", address(arbitrageAgent));

        // Dynamic Fee Agent
        dynamicFeeAgent = new DynamicFeeAgent(
            IPoolManager(POOL_MANAGER),
            deployer
        );
        console.log("   Dynamic Fee Agent:", address(dynamicFeeAgent));

        // Backrun Agent
        backrunAgent = new BackrunAgent(
            IPoolManager(POOL_MANAGER),
            deployer
        );
        console.log("   Backrun Agent:", address(backrunAgent));

        // 6. Configure Agent Executor
        console.log("\n6. Configuring Agent Executor...");
        
        // Register agents
        agentExecutor.registerAgent(AgentType.ARBITRAGE, address(arbitrageAgent));
        agentExecutor.registerAgent(AgentType.DYNAMIC_FEE, address(dynamicFeeAgent));
        agentExecutor.registerAgent(AgentType.BACKRUN, address(backrunAgent));
        
        // Authorize hook to call executor
        agentExecutor.authorizeHook(address(hook), true);
        
        console.log("   Agents registered and hook authorized");

        // 7. Configure Hook
        console.log("\n7. Configuring Hook...");
        hook.setAgentExecutor(address(agentExecutor));
        hook.setOracleRegistry(address(oracleRegistry));
        hook.setLPFeeAccumulator(address(lpFeeAccumulator));
        console.log("   Hook configured");

        // 8. Configure Agents
        console.log("\n8. Configuring Agents...");
        
        // Authorize executor to call agents
        arbitrageAgent.authorizeCaller(address(agentExecutor), true);
        dynamicFeeAgent.authorizeCaller(address(agentExecutor), true);
        backrunAgent.authorizeCaller(address(agentExecutor), true);
        
        // Set LP accumulator in backrun agent
        backrunAgent.setLPFeeAccumulator(address(lpFeeAccumulator));
        
        // Authorize hook in LP accumulator
        lpFeeAccumulator.setHookAuthorization(address(hook), true);
        
        console.log("   Agents configured");

        vm.stopBroadcast();

        // Print summary
        _printSummary();
    }

    function _deployHook(address deployer) internal returns (SwarmHook) {
        // Define required hook permissions
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        // Mine for address with correct flags
        bytes memory creationCode = type(SwarmHook).creationCode;
        bytes memory constructorArgs = abi.encode(POOL_MANAGER, deployer);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );

        console.log("   Mined hook address:", hookAddress);

        // Deploy with salt
        SwarmHook deployedHook = new SwarmHook{salt: salt}(
            IPoolManager(POOL_MANAGER),
            deployer
        );

        require(address(deployedHook) == hookAddress, "Hook address mismatch");
        
        return deployedHook;
    }

    function _printSummary() internal view {
        console.log("\n========================================");
        console.log("       DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("");
        console.log("Core Contracts:");
        console.log("  SwarmHook:         ", address(hook));
        console.log("  AgentExecutor:     ", address(agentExecutor));
        console.log("  LPFeeAccumulator:  ", address(lpFeeAccumulator));
        console.log("  OracleRegistry:    ", address(oracleRegistry));
        console.log("");
        console.log("Agents:");
        console.log("  ArbitrageAgent:    ", address(arbitrageAgent));
        console.log("  DynamicFeeAgent:   ", address(dynamicFeeAgent));
        console.log("  BackrunAgent:      ", address(backrunAgent));
        console.log("");
        console.log("ERC-8004 (Sepolia):");
        console.log("  Identity Registry: ", ERC8004_IDENTITY);
        console.log("  Reputation Registry:", ERC8004_REPUTATION);
        console.log("");
        console.log("========================================");
        console.log("");
        console.log("To switch agents:");
        console.log("  agentExecutor.registerAgent(AgentType.ARBITRAGE, newAgentAddress)");
        console.log("");
    }
}
