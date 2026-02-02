// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {MevRouterHook} from "../src/hooks/MevRouterHook.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry} from "../src/interfaces/IChainlinkOracle.sol";
import {FeeOptimizerAgent} from "../src/agents/FeeOptimizerAgent.sol";
import {SlippagePredictorAgent} from "../src/agents/SlippagePredictorAgent.sol";
import {MevHunterAgent} from "../src/agents/MevHunterAgent.sol";

contract DeploySwarm is Script {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER");
        address treasury = vm.envAddress("TREASURY");
        address identityRegistry = vm.envAddress("IDENTITY_REGISTRY");
        address reputationRegistry = vm.envAddress("REPUTATION_REGISTRY");

        vm.startBroadcast();

        // Deploy OracleRegistry for Chainlink price feeds
        OracleRegistry oracleRegistry = new OracleRegistry();

        SwarmCoordinator coordinator = new SwarmCoordinator(
            IPoolManager(poolManager),
            treasury,
            identityRegistry,
            reputationRegistry
        );

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory constructorArgs = abi.encode(IPoolManager(poolManager), IOracleRegistry(oracleRegistry));
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(MevRouterHook).creationCode,
            constructorArgs
        );

        MevRouterHook hook = new MevRouterHook{salt: salt}(IPoolManager(poolManager), IOracleRegistry(oracleRegistry));
        require(address(hook) == hookAddress, "hook address mismatch");

        FeeOptimizerAgent feeAgent = new FeeOptimizerAgent(coordinator, IPoolManager(poolManager));
        SlippagePredictorAgent slippageAgent = new SlippagePredictorAgent(coordinator, IPoolManager(poolManager));
        MevHunterAgent mevAgent = new MevHunterAgent(coordinator, IPoolManager(poolManager));

        uint256 feeAgentId = vm.envOr("FEE_AGENT_ID", uint256(0));
        if (feeAgentId != 0) coordinator.registerAgent(address(feeAgent), feeAgentId, true);

        uint256 slippageAgentId = vm.envOr("SLIPPAGE_AGENT_ID", uint256(0));
        if (slippageAgentId != 0) coordinator.registerAgent(address(slippageAgent), slippageAgentId, true);

        uint256 mevAgentId = vm.envOr("MEV_AGENT_ID", uint256(0));
        if (mevAgentId != 0) coordinator.registerAgent(address(mevAgent), mevAgentId, true);

        vm.stopBroadcast();

        console2.log("OracleRegistry", address(oracleRegistry));
        console2.log("SwarmCoordinator", address(coordinator));
        console2.log("MevRouterHook", address(hook));
        console2.log("FeeOptimizerAgent", address(feeAgent));
        console2.log("SlippagePredictorAgent", address(slippageAgent));
        console2.log("MevHunterAgent", address(mevAgent));
    }
}
