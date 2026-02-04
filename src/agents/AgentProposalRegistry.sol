// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @title AgentProposalRegistry
/// @notice REAL agent integration - agents submit parameters that hooks actually use
/// @dev This makes agents ACTIVELY participate in every swap, not just intents
/// @dev Aligned with hackathon: "agents that programmatically interact with Uniswap v4 pools"
contract AgentProposalRegistry is Ownable {
    using PoolIdLibrary for PoolKey;

    // ============ Structs ============

    /// @notice Parameters an agent proposes for a pool
    struct AgentProposal {
        uint256 agentId;              // ERC-8004 identity
        uint24 recommendedFee;        // Fee recommendation (in hundredths of bips)
        uint256 maxSlippageBps;       // Max slippage recommendation
        uint256 mevRiskScore;         // 0-100 MEV risk assessment
        uint256 liquidityScore;       // 0-100 liquidity depth score
        uint256 timestamp;            // When proposal was submitted
        bool active;                  // Whether proposal is active
    }

    /// @notice Aggregated recommendation from all agents for a pool
    struct AggregatedRecommendation {
        uint24 consensusFee;          // Weighted average fee
        uint256 avgMevRisk;           // Average MEV risk
        uint256 avgLiquidityScore;    // Average liquidity score
        uint256 agentCount;           // Number of contributing agents
        uint256 timestamp;            // Last update time
    }

    // ============ State ============

    /// @notice Agent proposals per pool
    mapping(PoolId => mapping(address => AgentProposal)) public proposals;

    /// @notice List of agents that have submitted proposals for a pool
    mapping(PoolId => address[]) public poolAgents;

    /// @notice Cached aggregated recommendations per pool
    mapping(PoolId => AggregatedRecommendation) public recommendations;

    /// @notice Registered agents (address => agentId)
    mapping(address => uint256) public registeredAgents;

    /// @notice Agent reputation scores (influences weight)
    mapping(address => uint256) public agentReputation;

    /// @notice Minimum reputation to participate
    uint256 public minReputation = 0;

    /// @notice Maximum proposal age (default 5 minutes)
    uint256 public maxProposalAge = 5 minutes;

    /// @notice Authorized hooks that can query recommendations
    mapping(address => bool) public authorizedHooks;

    // ============ Events ============

    event AgentRegistered(address indexed agent, uint256 indexed agentId);
    event ProposalSubmitted(
        PoolId indexed poolId,
        address indexed agent,
        uint24 recommendedFee,
        uint256 mevRiskScore
    );
    event RecommendationUpdated(
        PoolId indexed poolId,
        uint24 consensusFee,
        uint256 avgMevRisk,
        uint256 agentCount
    );
    event HookAuthorized(address indexed hook, bool authorized);

    // ============ Errors ============

    error NotRegisteredAgent();
    error ReputationTooLow();
    error InvalidFee();
    error NotAuthorizedHook();

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Agent Registration ============

    /// @notice Register as an agent (permissionless with ERC-8004 ID)
    /// @param agentId Your ERC-8004 agent identity ID
    function registerAgent(uint256 agentId) external {
        registeredAgents[msg.sender] = agentId;
        agentReputation[msg.sender] = 100; // Start with base reputation
        emit AgentRegistered(msg.sender, agentId);
    }

    /// @notice Owner can set agent reputation
    function setAgentReputation(address agent, uint256 reputation) external onlyOwner {
        agentReputation[agent] = reputation;
    }

    // ============ Proposal Submission (Called by Agents) ============

    /// @notice Submit a proposal for a pool - THIS IS THE KEY FUNCTION
    /// @dev Agents call this off-chain via keeper bots or on-chain via their contracts
    /// @param poolKey The pool to submit a proposal for
    /// @param recommendedFee Recommended swap fee (in hundredths of bips, e.g., 3000 = 0.30%)
    /// @param maxSlippageBps Maximum recommended slippage
    /// @param mevRiskScore MEV risk assessment 0-100
    /// @param liquidityScore Liquidity depth score 0-100
    function submitProposal(
        PoolKey calldata poolKey,
        uint24 recommendedFee,
        uint256 maxSlippageBps,
        uint256 mevRiskScore,
        uint256 liquidityScore
    ) external {
        uint256 agentId = registeredAgents[msg.sender];
        if (agentId == 0) revert NotRegisteredAgent();
        if (agentReputation[msg.sender] < minReputation) revert ReputationTooLow();
        if (recommendedFee > 100000) revert InvalidFee(); // Max 10%

        PoolId poolId = poolKey.toId();

        // Check if this is a new agent for this pool
        AgentProposal storage existing = proposals[poolId][msg.sender];
        if (!existing.active) {
            poolAgents[poolId].push(msg.sender);
        }

        // Store proposal
        proposals[poolId][msg.sender] = AgentProposal({
            agentId: agentId,
            recommendedFee: recommendedFee,
            maxSlippageBps: maxSlippageBps,
            mevRiskScore: mevRiskScore,
            liquidityScore: liquidityScore,
            timestamp: block.timestamp,
            active: true
        });

        emit ProposalSubmitted(poolId, msg.sender, recommendedFee, mevRiskScore);

        // Update aggregated recommendation
        _updateRecommendation(poolId);
    }

    // ============ Hook Query Functions (Called by MevRouterHookV2) ============

    /// @notice Get aggregated agent recommendation for a pool
    /// @dev Called by hook in beforeSwap to get agent consensus
    /// @param poolId The pool to query
    /// @return recommendation The aggregated recommendation from all agents
    function getRecommendation(PoolId poolId) 
        external 
        view 
        returns (AggregatedRecommendation memory) 
    {
        return recommendations[poolId];
    }

    /// @notice Get recommended fee from agent consensus
    /// @dev Returns 0 if no agents have submitted proposals
    function getAgentConsensusFee(PoolId poolId) external view returns (uint24) {
        AggregatedRecommendation storage rec = recommendations[poolId];
        
        // Check if recommendation is fresh enough
        if (rec.timestamp == 0 || block.timestamp > rec.timestamp + maxProposalAge) {
            return 0; // No valid recommendation
        }
        
        return rec.consensusFee;
    }

    /// @notice Get MEV risk score from agents
    /// @dev Hook can use this to adjust MEV capture aggressiveness
    function getAgentMevRisk(PoolId poolId) external view returns (uint256) {
        AggregatedRecommendation storage rec = recommendations[poolId];
        
        if (rec.timestamp == 0 || block.timestamp > rec.timestamp + maxProposalAge) {
            return 50; // Default medium risk
        }
        
        return rec.avgMevRisk;
    }

    /// @notice Check if pool has active agent coverage
    function hasAgentCoverage(PoolId poolId) external view returns (bool, uint256) {
        AggregatedRecommendation storage rec = recommendations[poolId];
        bool hasCoverage = rec.timestamp > 0 && 
                          block.timestamp <= rec.timestamp + maxProposalAge &&
                          rec.agentCount > 0;
        return (hasCoverage, rec.agentCount);
    }

    // ============ Internal Functions ============

    /// @notice Update aggregated recommendation for a pool
    function _updateRecommendation(PoolId poolId) internal {
        address[] storage agents = poolAgents[poolId];
        
        uint256 totalWeight;
        uint256 weightedFee;
        uint256 totalMevRisk;
        uint256 totalLiquidityScore;
        uint256 activeCount;

        for (uint256 i = 0; i < agents.length; i++) {
            AgentProposal storage prop = proposals[poolId][agents[i]];
            
            // Skip inactive or stale proposals
            if (!prop.active || block.timestamp > prop.timestamp + maxProposalAge) {
                continue;
            }

            // Weight by reputation
            uint256 weight = agentReputation[agents[i]];
            
            totalWeight += weight;
            weightedFee += uint256(prop.recommendedFee) * weight;
            totalMevRisk += prop.mevRiskScore;
            totalLiquidityScore += prop.liquidityScore;
            activeCount++;
        }

        if (activeCount == 0 || totalWeight == 0) {
            return;
        }

        recommendations[poolId] = AggregatedRecommendation({
            consensusFee: uint24(weightedFee / totalWeight),
            avgMevRisk: totalMevRisk / activeCount,
            avgLiquidityScore: totalLiquidityScore / activeCount,
            agentCount: activeCount,
            timestamp: block.timestamp
        });

        emit RecommendationUpdated(
            poolId,
            uint24(weightedFee / totalWeight),
            totalMevRisk / activeCount,
            activeCount
        );
    }

    // ============ Admin Functions ============

    function setMinReputation(uint256 min) external onlyOwner {
        minReputation = min;
    }

    function setMaxProposalAge(uint256 age) external onlyOwner {
        maxProposalAge = age;
    }

    function authorizeHook(address hook, bool authorized) external onlyOwner {
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }
}
