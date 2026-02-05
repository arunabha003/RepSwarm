// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {ArbitrageAgent} from "../src/agents/ArbitrageAgent.sol";
import {AgentType} from "../src/interfaces/ISwarmAgent.sol";
import {
    IERC8004IdentityRegistry,
    IERC8004ReputationRegistry,
    ERC8004Integration
} from "../src/erc8004/ERC8004Integration.sol";

/// @notice Fork test that verifies AgentExecutor can switch agents based on real ERC-8004 reputation.
contract AgentExecutorReputationSwitchSepoliaTest is Test {
    string internal constant SEPOLIA_RPC_URL = "https://eth-sepolia.g.alchemy.com/v2/KywLaq2zlVzePOhip0BY3U8ztfHkYDmo";

    address internal constant POOL_MANAGER = 0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A;

    function test_SwitchesToBackup_WhenReputationBelowThreshold() public {
        vm.createSelectFork(SEPOLIA_RPC_URL);

        AgentExecutor executor = new AgentExecutor();

        ArbitrageAgent primary = new ArbitrageAgent(IPoolManager(POOL_MANAGER), address(this), 8000, 50);
        ArbitrageAgent backup = new ArbitrageAgent(IPoolManager(POOL_MANAGER), address(this), 8000, 50);

        executor.registerAgent(AgentType.ARBITRAGE, address(primary));
        executor.setBackupAgent(AgentType.ARBITRAGE, address(backup));

        IERC8004IdentityRegistry id = IERC8004IdentityRegistry(ERC8004Integration.SEPOLIA_IDENTITY_REGISTRY);
        IERC8004ReputationRegistry rep = IERC8004ReputationRegistry(ERC8004Integration.SEPOLIA_REPUTATION_REGISTRY);

        address idOwner = makeAddr("idOwner");
        vm.deal(idOwner, 1 ether);
        vm.prank(idOwner);
        uint256 agentId = id.register();

        primary.configureIdentity(agentId, address(id));

        address client = makeAddr("client");
        vm.deal(client, 1 ether);

        address[] memory clients = new address[](1);
        clients[0] = client;

        executor.setReputationSwitchConfig(
            AgentType.ARBITRAGE,
            address(rep),
            "swarm-routing",
            "mev-protection",
            0, // require non-negative reputation
            true
        );
        executor.setReputationSwitchClients(AgentType.ARBITRAGE, clients);

        // Push primary below threshold.
        vm.prank(client);
        rep.giveFeedback(agentId, int128(int256(-1e18)), 18, "swarm-routing", "mev-protection", "", "", bytes32(0));

        bool switched = executor.checkAndSwitchAgentIfBelowThreshold(AgentType.ARBITRAGE);
        assertTrue(switched, "should switch to backup");
        assertEq(executor.agents(AgentType.ARBITRAGE), address(backup), "backup should become active agent");
    }
}

