// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {MevRouterHook} from "../src/hooks/MevRouterHook.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ISwarmCoordinator} from "../src/interfaces/ISwarmCoordinator.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

/**
 * @title Deploy
 * @notice Deployment script for Multi-Agent Trade Router Swarm
 * @dev Run with: forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast
 */
contract Deploy is Script {
    // Sepolia addresses
    address constant SEPOLIA_POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    // CREATE2 Deployer Proxy (used by forge script --broadcast)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Chainlink Sepolia Price Feeds
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant USDC_USD_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant LINK_USD_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF;
    address constant BTC_USD_FEED = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    
    // Common Sepolia tokens
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy Oracle Registry
        OracleRegistry oracleRegistry = new OracleRegistry();
        console.log("OracleRegistry deployed at:", address(oracleRegistry));
        
        // 2. Configure Chainlink feeds (base -> quote pairs)
        oracleRegistry.setPriceFeed(WETH, address(0), ETH_USD_FEED);
        oracleRegistry.setPriceFeed(address(0), address(0), ETH_USD_FEED);
        oracleRegistry.setPriceFeed(USDC, address(0), USDC_USD_FEED);
        console.log("Chainlink feeds configured");
        
        // 3. Deploy Swarm Coordinator
        SwarmCoordinator coordinator = new SwarmCoordinator(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            deployer,
            address(0),
            address(0)
        );
        console.log("SwarmCoordinator deployed at:", address(coordinator));
        
        // 4. Deploy Hook with proper flags using CREATE2
        // Required flags: BEFORE_SWAP | AFTER_SWAP | AFTER_SWAP_RETURNS_DELTA
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        
        bytes memory constructorArgs = abi.encode(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            IOracleRegistry(address(oracleRegistry))
        );
        
        // Find valid salt for hook address
        // Use CREATE2_DEPLOYER as the deployer when using forge script --broadcast
        (address hookAddress, bytes32 salt) = _findHookAddress(
            CREATE2_DEPLOYER,
            flags,
            type(MevRouterHook).creationCode,
            constructorArgs
        );
        console.log("Hook address found:", hookAddress);
        console.log("Using salt:", vm.toString(salt));
        
        // Deploy hook with computed salt
        MevRouterHook hook = new MevRouterHook{salt: salt}(
            IPoolManager(SEPOLIA_POOL_MANAGER),
            IOracleRegistry(address(oracleRegistry))
        );
        require(address(hook) == hookAddress, "Hook address mismatch!");
        console.log("MevRouterHook deployed at:", address(hook));
        
        // 5. Deploy Agents
        MevHunterAgent mevAgent = new MevHunterAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER),
            IOracleRegistry(address(oracleRegistry))
        );
        SlippagePredictorAgent slippageAgent = new SlippagePredictorAgent(
            ISwarmCoordinator(address(coordinator)),
            IPoolManager(SEPOLIA_POOL_MANAGER)
        );
        console.log("MevHunterAgent deployed at:", address(mevAgent));
        console.log("SlippagePredictorAgent deployed at:", address(slippageAgent));
        
        // 6. Register agents
        coordinator.registerAgent(address(mevAgent), 1, true);
        coordinator.registerAgent(address(slippageAgent), 2, true);
        console.log("Agents registered");
        
        vm.stopBroadcast();
        
        // Output deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("OracleRegistry:", address(oracleRegistry));
        console.log("SwarmCoordinator:", address(coordinator));
        console.log("MevRouterHook:", address(hook));
        console.log("MevHunterAgent:", address(mevAgent));
        console.log("SlippagePredictorAgent:", address(slippageAgent));
    }
    
    /// @notice Find a salt that produces a hook address with the required flags
    /// @dev Mirrors the HookMiner.find logic for use in scripts
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
            
            // Check if the address has the correct flags
            if (_hasCorrectFlags(hookAddress, flags)) {
                return (hookAddress, salt);
            }
            saltCounter++;
        }
        revert("Could not find valid hook address");
    }
    
    /// @notice Compute CREATE2 address
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
    
    /// @notice Check if address has correct hook flags
    function _hasCorrectFlags(address hookAddress, uint160 flags) internal pure returns (bool) {
        // The lower 14 bits of the address must match the flags
        return uint160(hookAddress) & Hooks.ALL_HOOK_MASK == flags & Hooks.ALL_HOOK_MASK;
    }
}
