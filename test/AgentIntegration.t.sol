// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

import {AgentProposalRegistry} from "../src/agents/AgentProposalRegistry.sol";

/// @title AgentIntegrationTest
/// @notice Tests for REAL agent participation in swap flow
/// @dev This demonstrates that agents actually impact the protocol
contract AgentIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    AgentProposalRegistry public registry;
    
    address public agent1 = makeAddr("agent1");
    address public agent2 = makeAddr("agent2");
    address public agent3 = makeAddr("agent3");
    address public hook = makeAddr("hook");
    
    PoolKey public testPoolKey;
    PoolId public testPoolId;

    function setUp() public {
        // Deploy agent registry
        registry = new AgentProposalRegistry();
        
        // Create a test pool key
        testPoolKey = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hook)
        });
        testPoolId = testPoolKey.toId();
        
        // Authorize hook
        registry.authorizeHook(hook, true);
    }

    function testAgentRegistration() public {
        // Agent registers with ERC-8004 ID
        vm.prank(agent1);
        registry.registerAgent(101); // agentId from ERC-8004
        
        assertEq(registry.registeredAgents(agent1), 101);
        assertEq(registry.agentReputation(agent1), 100); // base reputation
    }

    function testAgentSubmitProposal() public {
        // Register agent
        vm.prank(agent1);
        registry.registerAgent(101);
        
        // Submit proposal for pool
        vm.prank(agent1);
        registry.submitProposal(
            testPoolKey,
            3000,      // 0.30% fee recommendation
            50,        // 50 bps max slippage
            75,        // 75/100 MEV risk score
            80         // 80/100 liquidity score
        );
        
        // Check proposal stored
        (
            uint256 agentId,
            uint24 recommendedFee,
            uint256 maxSlippageBps,
            uint256 mevRiskScore,
            uint256 liquidityScore,
            ,
            bool active
        ) = registry.proposals(testPoolId, agent1);
        
        assertEq(agentId, 101);
        assertEq(recommendedFee, 3000);
        assertEq(maxSlippageBps, 50);
        assertEq(mevRiskScore, 75);
        assertEq(liquidityScore, 80);
        assertTrue(active);
    }

    function testMultipleAgentsConsensus() public {
        // Register 3 agents
        vm.prank(agent1);
        registry.registerAgent(101);
        
        vm.prank(agent2);
        registry.registerAgent(102);
        
        vm.prank(agent3);
        registry.registerAgent(103);
        
        // Each submits different recommendations
        vm.prank(agent1);
        registry.submitProposal(testPoolKey, 2000, 50, 60, 80); // 0.20% fee
        
        vm.prank(agent2);
        registry.submitProposal(testPoolKey, 4000, 50, 80, 70); // 0.40% fee
        
        vm.prank(agent3);
        registry.submitProposal(testPoolKey, 3000, 50, 70, 75); // 0.30% fee
        
        // Check consensus (should be average since all have same reputation)
        AgentProposalRegistry.AggregatedRecommendation memory rec = registry.getRecommendation(testPoolId);
        
        assertEq(rec.agentCount, 3);
        // Average fee: (2000 + 4000 + 3000) / 3 = 3000 (weighted by equal reputation)
        assertEq(rec.consensusFee, 3000);
        // Average MEV risk: (60 + 80 + 70) / 3 = 70
        assertEq(rec.avgMevRisk, 70);
    }

    function testReputationWeightedConsensus() public {
        // Register agents with different reputations
        vm.prank(agent1);
        registry.registerAgent(101);
        
        vm.prank(agent2);
        registry.registerAgent(102);
        
        // Give agent1 higher reputation
        registry.setAgentReputation(agent1, 300); // 3x weight
        registry.setAgentReputation(agent2, 100); // 1x weight
        
        // Agent1 recommends 2000, Agent2 recommends 4000
        vm.prank(agent1);
        registry.submitProposal(testPoolKey, 2000, 50, 60, 80);
        
        vm.prank(agent2);
        registry.submitProposal(testPoolKey, 4000, 50, 80, 70);
        
        // Weighted average: (2000*300 + 4000*100) / (300+100) = 1000000/400 = 2500
        AgentProposalRegistry.AggregatedRecommendation memory rec = registry.getRecommendation(testPoolId);
        assertEq(rec.consensusFee, 2500);
    }

    function testHookQueriesAgentRecommendations() public {
        // Register and submit proposals
        vm.prank(agent1);
        registry.registerAgent(101);
        
        vm.prank(agent1);
        registry.submitProposal(testPoolKey, 3500, 50, 65, 85);
        
        // Hook queries consensus
        (bool hasCoverage, uint256 agentCount) = registry.hasAgentCoverage(testPoolId);
        assertTrue(hasCoverage);
        assertEq(agentCount, 1);
        
        uint24 consensusFee = registry.getAgentConsensusFee(testPoolId);
        assertEq(consensusFee, 3500);
        
        uint256 mevRisk = registry.getAgentMevRisk(testPoolId);
        assertEq(mevRisk, 65);
    }

    function testStaleProposalsIgnored() public {
        // Register and submit
        vm.prank(agent1);
        registry.registerAgent(101);
        
        vm.prank(agent1);
        registry.submitProposal(testPoolKey, 3000, 50, 70, 80);
        
        // Warp time past max proposal age (default 5 minutes)
        vm.warp(block.timestamp + 6 minutes);
        
        // Proposal should be stale
        (bool hasCoverage, ) = registry.hasAgentCoverage(testPoolId);
        assertFalse(hasCoverage);
        
        uint24 consensusFee = registry.getAgentConsensusFee(testPoolId);
        assertEq(consensusFee, 0); // No valid recommendation
    }

    function testUnregisteredAgentCannotPropose() public {
        // Try to submit without registering
        vm.prank(agent1);
        vm.expectRevert(AgentProposalRegistry.NotRegisteredAgent.selector);
        registry.submitProposal(testPoolKey, 3000, 50, 70, 80);
    }

    function testInvalidFeeRejected() public {
        vm.prank(agent1);
        registry.registerAgent(101);
        
        // Try to submit fee > 10%
        vm.prank(agent1);
        vm.expectRevert(AgentProposalRegistry.InvalidFee.selector);
        registry.submitProposal(testPoolKey, 200000, 50, 70, 80); // 20% fee
    }
}
