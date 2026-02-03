// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {MevRouterHookV2} from "../src/hooks/MevRouterHookV2.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";
import {FlashLoanBackrunner} from "../src/backrun/FlashLoanBackrunner.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {SwarmAgentRegistry} from "../src/erc8004/SwarmAgentRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {FeeOptimizerAgent} from "../src/agents/FeeOptimizerAgent.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ISwarmCoordinator} from "../src/interfaces/ISwarmCoordinator.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ERC8004Integration} from "../src/erc8004/ERC8004Integration.sol";

/// @title DeployAnvilFork
/// @notice Deploy all contracts to Anvil forked Sepolia for frontend testing
/// @dev Run: anvil --fork-url $SEPOLIA_RPC_URL
/// @dev Then: forge script script/DeployAnvilFork.s.sol:DeployAnvilFork --rpc-url http://127.0.0.1:8545 --broadcast
contract DeployAnvilFork is Script {
    // ============ Sepolia Live Addresses ============
    
    // Uniswap v4 PoolManager on Sepolia
    address constant SEPOLIA_POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    // ERC-8004 Official Sepolia Addresses
    address constant ERC8004_IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address constant ERC8004_REPUTATION_REGISTRY = 0x8004B663056A597Dffe9eCcC1965A193B7388713;
    
    // Aave V3 Pool on Sepolia
    address constant AAVE_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    
    // Chainlink Sepolia Price Feeds
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant LINK_USD_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    
    // Common Sepolia Tokens
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;
    
    // CREATE2 Deployer (standard)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // ============ Deployed Contracts ============
    
    OracleRegistry public oracleRegistry;
    LPFeeAccumulator public lpAccumulator;
    MevRouterHookV2 public hook;
    SwarmCoordinator public coordinator;
    FlashLoanBackrunner public backrunner;
    SwarmAgentRegistry public agentRegistry;
    FeeOptimizerAgent public feeAgent;
    SlippagePredictorAgent public slippageAgent;
    MevHunterAgent public mevAgent;

    function run() external {
        // Anvil default private key (DON'T USE IN PRODUCTION!)
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================================");
        console.log("   MULTI-AGENT TRADE ROUTER SWARM - ANVIL FORK DEPLOY   ");
        console.log("========================================================");
        console.log("");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // ================================================================
        // STEP 1: Deploy Oracle Registry with Chainlink feeds
        // ================================================================
        console.log("--- Step 1: Oracle Registry ---");
        oracleRegistry = new OracleRegistry();
        console.log("OracleRegistry:", address(oracleRegistry));
        
        // Configure Chainlink price feeds (these exist on Sepolia)
        oracleRegistry.setPriceFeed(WETH, address(0), ETH_USD_FEED);  // WETH/USD
        oracleRegistry.setPriceFeed(address(0), address(0), ETH_USD_FEED); // ETH/USD
        oracleRegistry.setPriceFeed(USDC, address(0), USDC_USD_FEED); // USDC/USD
        console.log("  -> Chainlink feeds configured");
        console.log("");
        
        // ================================================================
        // STEP 2: Deploy LP Fee Accumulator
        // ================================================================
        console.log("--- Step 2: LP Fee Accumulator ---");
        lpAccumulator = new LPFeeAccumulator(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            0.001 ether,  // Min donation threshold (lower for testing)
            5 minutes     // Min interval (shorter for testing)
        );
        console.log("LPFeeAccumulator:", address(lpAccumulator));
        console.log("");
        
        // ================================================================
        // STEP 3: Deploy MevRouterHookV2 with CREATE2 for valid hook address
        // ================================================================
        console.log("--- Step 3: MevRouterHookV2 ---");
        
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
        
        // Find valid hook address
        (address hookAddress, bytes32 salt) = _findHookAddress(
            CREATE2_DEPLOYER,
            hookFlags,
            type(MevRouterHookV2).creationCode,
            hookConstructorArgs
        );
        
        console.log("  Hook target address:", hookAddress);
        
        // Deploy using CREATE2
        bytes memory deploymentData = abi.encodePacked(type(MevRouterHookV2).creationCode, hookConstructorArgs);
        bytes memory callData = abi.encodePacked(salt, deploymentData);
        
        (bool success, bytes memory returnData) = CREATE2_DEPLOYER.call(callData);
        require(success && returnData.length == 20, "Hook deployment failed");
        
        address deployedHook = address(bytes20(returnData));
        require(deployedHook == hookAddress, "Hook address mismatch");
        
        hook = MevRouterHookV2(payable(deployedHook));
        console.log("MevRouterHookV2:", address(hook));
        
        // Link hook to LP accumulator
        hook.setLPFeeAccumulator(address(lpAccumulator));
        lpAccumulator.setHookAuthorization(address(hook), true);
        console.log("  -> Linked to LP accumulator");
        console.log("");
        
        // ================================================================
        // STEP 4: Deploy SwarmCoordinator with ERC-8004 integration
        // ================================================================
        console.log("--- Step 4: SwarmCoordinator ---");
        coordinator = new SwarmCoordinator(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            deployer,  // treasury
            ERC8004_IDENTITY_REGISTRY,
            ERC8004_REPUTATION_REGISTRY
        );
        console.log("SwarmCoordinator:", address(coordinator));
        
        // Configure reputation
        coordinator.setReputationConfig(
            ERC8004_REPUTATION_REGISTRY,
            "swarm-routing",
            "",
            int256(-5e18)  // Allow any reputation for testing
        );
        console.log("  -> ERC-8004 reputation configured");
        console.log("");
        
        // ================================================================
        // STEP 5: Deploy FlashLoan Backrunner
        // ================================================================
        console.log("--- Step 5: FlashLoanBackrunner ---");
        backrunner = new FlashLoanBackrunner(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            AAVE_POOL_SEPOLIA
        );
        console.log("FlashLoanBackrunner:", address(backrunner));
        
        // Link to LP accumulator
        backrunner.setLPFeeAccumulator(address(lpAccumulator));
        console.log("  -> Linked to LP accumulator");
        console.log("");
        
        // ================================================================
        // STEP 6: Deploy SwarmAgentRegistry (ERC-8004)
        // ================================================================
        console.log("--- Step 6: SwarmAgentRegistry ---");
        agentRegistry = new SwarmAgentRegistry(
            ERC8004_IDENTITY_REGISTRY,
            ERC8004_REPUTATION_REGISTRY
        );
        console.log("SwarmAgentRegistry:", address(agentRegistry));
        
        // Authorize coordinator as feedback client
        agentRegistry.setFeedbackClientAuthorization(address(coordinator), true);
        console.log("  -> Coordinator authorized for feedback");
        console.log("");
        
        // ================================================================
        // STEP 7: Deploy Agents
        // ================================================================
        console.log("--- Step 7: Agents ---");
        
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
        console.log("");
        
        // ================================================================
        // STEP 8: Register Agents in Coordinator
        // ================================================================
        console.log("--- Step 8: Agent Registration ---");
        
        // Register with placeholder IDs (in production, use ERC-8004 IDs)
        coordinator.registerAgent(address(feeAgent), 1, true);
        coordinator.registerAgent(address(slippageAgent), 2, true);
        coordinator.registerAgent(address(mevAgent), 3, true);
        
        console.log("  -> FeeOptimizer registered (ID: 1)");
        console.log("  -> SlippagePredictor registered (ID: 2)");
        console.log("  -> MevHunter registered (ID: 3)");
        console.log("");
        
        vm.stopBroadcast();
        
        // ================================================================
        // OUTPUT: Frontend Configuration
        // ================================================================
        console.log("========================================================");
        console.log("   DEPLOYMENT COMPLETE - COPY TO FRONTEND CONFIG        ");
        console.log("========================================================");
        console.log("");
        _outputFrontendConfig();
        console.log("");
        _outputTestInstructions();
    }
    
    function _outputFrontendConfig() internal view {
        console.log("// Add to frontend/src/config/web3.ts");
        console.log("export const ANVIL_CONTRACTS = {");
        console.log("  poolManager: '%s',", SEPOLIA_POOL_MANAGER);
        console.log("  mevRouterHook: '%s',", address(hook));
        console.log("  lpFeeAccumulator: '%s',", address(lpAccumulator));
        console.log("  swarmCoordinator: '%s',", address(coordinator));
        console.log("  flashLoanBackrunner: '%s',", address(backrunner));
        console.log("  agentRegistry: '%s',", address(agentRegistry));
        console.log("  oracleRegistry: '%s',", address(oracleRegistry));
        console.log("  // Agents");
        console.log("  feeOptimizerAgent: '%s',", address(feeAgent));
        console.log("  slippagePredictorAgent: '%s',", address(slippageAgent));
        console.log("  mevHunterAgent: '%s',", address(mevAgent));
        console.log("  // ERC-8004 (live Sepolia)");
        console.log("  erc8004IdentityRegistry: '%s',", ERC8004_IDENTITY_REGISTRY);
        console.log("  erc8004ReputationRegistry: '%s',", ERC8004_REPUTATION_REGISTRY);
        console.log("};");
    }
    
    function _outputTestInstructions() internal pure {
        console.log("========================================================");
        console.log("   TESTING INSTRUCTIONS                                  ");
        console.log("========================================================");
        console.log("");
        console.log("1. Keep Anvil running: anvil --fork-url $SEPOLIA_RPC_URL");
        console.log("2. Update frontend/src/config/web3.ts with addresses above");
        console.log("3. Start frontend: cd frontend && npm run dev");
        console.log("4. Connect wallet to localhost:8545 (Anvil)");
        console.log("5. Use test tokens from Sepolia faucets");
        console.log("");
        console.log("See FORKED_TESTING.md for detailed instructions");
    }
    
    function _findHookAddress(
        address deployer,
        uint160 flags,
        bytes memory creationCode,
        bytes memory constructorArgs
    ) internal pure returns (address hookAddress, bytes32 salt) {
        bytes memory deploymentData = abi.encodePacked(creationCode, constructorArgs);
        bytes32 initCodeHash = keccak256(deploymentData);
        
        for (uint256 i = 0; i < 100000; i++) {
            salt = bytes32(i);
            hookAddress = _computeCreate2Address(deployer, salt, initCodeHash);
            
            if (_hasCorrectFlags(hookAddress, flags)) {
                return (hookAddress, salt);
            }
        }
        revert("Could not find valid hook address");
    }
    
    function _computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            initCodeHash
        )))));
    }
    
    function _hasCorrectFlags(address hookAddress, uint160 flags) internal pure returns (bool) {
        uint160 addressFlags = uint160(hookAddress) & 0xFFFF;
        return (addressFlags & flags) == flags;
    }
}
