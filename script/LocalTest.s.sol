// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {MevRouterHook} from "../src/hooks/MevRouterHook.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {ISwarmCoordinator} from "../src/interfaces/ISwarmCoordinator.sol";
import {SwarmHookData} from "../src/libraries/SwarmHookData.sol";
import {SwarmTypes} from "../src/libraries/SwarmTypes.sol";

/**
 * @title LocalTest
 * @notice Script for manual testing on Anvil fork
 * @dev Use this script for step-by-step manual testing
 */
contract LocalTest is Script {
    // Deployed contract addresses (update after deployment)
    address public oracleRegistry;
    address payable public coordinator;
    address public hook;
    address public mevAgent;
    address public slippageAgent;
    
    // Test tokens
    address constant WETH = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    // Pool Manager
    address constant POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;
    
    function setUp() public {
        // Load deployed addresses from env (set these after deployment)
        oracleRegistry = vm.envOr("ORACLE_REGISTRY", address(0));
        coordinator = payable(vm.envOr("COORDINATOR", address(0)));
        hook = vm.envOr("HOOK", address(0));
        mevAgent = vm.envOr("MEV_AGENT", address(0));
        slippageAgent = vm.envOr("SLIPPAGE_AGENT", address(0));
    }
    
    /// @notice Create a test intent
    function createTestIntent() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        
        // Encode a candidate path as bytes (PoolKey + zeroForOne)
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(WETH),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });
        
        bytes[] memory candidatePaths = new bytes[](1);
        candidatePaths[0] = abi.encode(poolKey, true); // zeroForOne = true
        
        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: Currency.wrap(USDC),
            currencyOut: Currency.wrap(WETH),
            amountIn: 1000000, // 1 USDC (6 decimals)
            amountOutMin: 0,   // No minimum for testing
            deadline: uint64(block.timestamp + 3600),
            mevFeeBps: 100,    // 1% MEV fee
            treasuryBps: 50,   // 0.5% treasury fee
            lpShareBps: 8000   // 80% of fee to LPs
        });
        
        uint256 intentId = SwarmCoordinator(coordinator).createIntent(params, candidatePaths);
        
        console.log("Created intent:", intentId);
        vm.stopBroadcast();
    }
    
    /// @notice Query oracle price
    function getOraclePrice(address token) external view {
        // Get price against USD (quote = address(0))
        (uint256 price, ) = OracleRegistry(oracleRegistry).getLatestPrice(token, address(0));
        console.log("Token:", token);
        console.log("Price (18 decimals):", price);
    }
    
    /// @notice Check ETH price from Chainlink directly
    function checkEthPrice() external view {
        address ethUsdFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        
        // Call latestRoundData()
        (bool success, bytes memory data) = ethUsdFeed.staticcall(
            abi.encodeWithSignature("latestRoundData()")
        );
        
        if (success) {
            (,int256 answer,,,) = abi.decode(data, (uint80, int256, uint256, uint256, uint80));
            console.log("ETH/USD Price (8 decimals):", uint256(answer));
            console.log("ETH/USD Price (human):", uint256(answer) / 1e8);
        } else {
            console.log("Failed to query ETH price");
        }
    }
    
    /// @notice Register a new agent
    function registerAgent(address agent) external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        
        SwarmCoordinator(coordinator).registerAgent(agent, 1, true);
        console.log("Registered agent:", agent);
        
        vm.stopBroadcast();
    }
    
    /// @notice Print deployment status
    function printStatus() external view {
        console.log("=== Deployment Status ===");
        console.log("OracleRegistry:", oracleRegistry);
        console.log("SwarmCoordinator:", coordinator);
        console.log("MevRouterHook:", hook);
        console.log("MevHunterAgent:", mevAgent);
        console.log("SlippagePredictorAgent:", slippageAgent);
        console.log("PoolManager:", POOL_MANAGER);
    }
}
