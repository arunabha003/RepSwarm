// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {ISwarmAgent, IArbitrageAgent, IDynamicFeeAgent, IBackrunAgent, AgentType, SwapContext, AgentResult} from "../interfaces/ISwarmAgent.sol";

/// @title AgentExecutor
/// @notice Central hub for agent coordination - routes hook calls to appropriate agents
/// @dev Admin can hot-swap agents without redeploying the hook
/// @dev All agents must implement ISwarmAgent interface (ERC-8004 compatible)
contract AgentExecutor is Ownable {
    using PoolIdLibrary for PoolKey;

    // ============ State Variables ============

    /// @notice Registered agents by type
    mapping(AgentType => address) public agents;

    /// @notice Backup agents for failover
    mapping(AgentType => address) public backupAgents;

    /// @notice Whether each agent type is enabled
    mapping(AgentType => bool) public agentEnabled;

    /// @notice Authorized callers (hooks)
    mapping(address => bool) public authorizedHooks;

    /// @notice Agent execution statistics
    mapping(address => AgentStats) public agentStats;

    // ============ Structs ============

    struct AgentStats {
        uint256 executionCount;
        uint256 successCount;
        uint256 totalValueProcessed;
        uint64 lastExecution;
    }

    struct BeforeSwapResult {
        bool shouldCapture;
        uint256 captureAmount;
        uint24 overrideFee;
        bool useOverrideFee;
    }

    struct AfterSwapResult {
        bool shouldBackrun;
        uint256 backrunAmount;
        uint256 expectedProfit;
        bool zeroForOne;
        uint256 targetPrice;
        uint256 currentPrice;
    }

    // ============ Events ============

    event AgentRegistered(
        AgentType indexed agentType,
        address indexed agent,
        uint256 agentId
    );

    event AgentRemoved(
        AgentType indexed agentType,
        address indexed agent
    );

    event AgentSwitched(
        AgentType indexed agentType,
        address indexed oldAgent,
        address indexed newAgent
    );

    event AgentEnabled(AgentType indexed agentType, bool enabled);

    event HookAuthorized(address indexed hook, bool authorized);

    event AgentExecuted(
        AgentType indexed agentType,
        address indexed agent,
        bool success,
        uint256 value
    );

    // ============ Errors ============

    error NotAuthorizedHook();
    error AgentNotRegistered(AgentType agentType);
    error AgentNotActive();
    error InvalidAgent();
    error AgentTypeMismatch();

    // ============ Modifiers ============

    modifier onlyAuthorizedHook() {
        if (!authorizedHooks[msg.sender]) revert NotAuthorizedHook();
        _;
    }

    // ============ Constructor ============

    constructor() Ownable(msg.sender) {}

    // ============ Hook Interface Functions ============

    /// @notice Process before swap - called by hook
    /// @param context The swap context
    /// @return result Aggregated result from all relevant agents
    function processBeforeSwap(
        SwapContext calldata context
    ) external onlyAuthorizedHook returns (BeforeSwapResult memory result) {
        // 1. Check arbitrage agent
        if (agentEnabled[AgentType.ARBITRAGE]) {
            address arbAgent = agents[AgentType.ARBITRAGE];
            if (arbAgent != address(0)) {
                try IArbitrageAgent(arbAgent).analyzeArbitrage(context) returns (
                    IArbitrageAgent.ArbitrageResult memory arbResult
                ) {
                    if (arbResult.shouldCapture && arbResult.hookShare > 0) {
                        result.shouldCapture = true;
                        result.captureAmount = arbResult.hookShare;
                        _recordExecution(arbAgent, true, arbResult.hookShare);
                        emit AgentExecuted(
                            AgentType.ARBITRAGE,
                            arbAgent,
                            true,
                            arbResult.hookShare
                        );
                        return result; // Arbitrage takes priority
                    }
                } catch {
                    _recordExecution(arbAgent, false, 0);
                    // Try backup agent
                    arbAgent = backupAgents[AgentType.ARBITRAGE];
                    if (arbAgent != address(0)) {
                        try IArbitrageAgent(arbAgent).analyzeArbitrage(context) returns (
                            IArbitrageAgent.ArbitrageResult memory arbResult
                        ) {
                            if (arbResult.shouldCapture && arbResult.hookShare > 0) {
                                result.shouldCapture = true;
                                result.captureAmount = arbResult.hookShare;
                                return result;
                            }
                        } catch {}
                    }
                }
            }
        }

        // 2. Check dynamic fee agent
        if (agentEnabled[AgentType.DYNAMIC_FEE]) {
            address feeAgent = agents[AgentType.DYNAMIC_FEE];
            if (feeAgent != address(0)) {
                try IDynamicFeeAgent(feeAgent).calculateFee(context) returns (
                    IDynamicFeeAgent.FeeResult memory feeResult
                ) {
                    if (feeResult.useOverride && feeResult.recommendedFee > 0) {
                        result.overrideFee = feeResult.recommendedFee;
                        result.useOverrideFee = true;
                        _recordExecution(feeAgent, true, feeResult.recommendedFee);
                        emit AgentExecuted(
                            AgentType.DYNAMIC_FEE,
                            feeAgent,
                            true,
                            feeResult.recommendedFee
                        );
                    }
                } catch {
                    _recordExecution(feeAgent, false, 0);
                }
            }
        }

        return result;
    }

    /// @notice Process after swap - called by hook
    /// @param context The swap context
    /// @param newPoolPrice Pool price after swap
    /// @return result Aggregated result from all relevant agents
    function processAfterSwap(
        SwapContext calldata context,
        uint256 newPoolPrice
    ) external onlyAuthorizedHook returns (AfterSwapResult memory result) {
        // Check backrun agent
        if (agentEnabled[AgentType.BACKRUN]) {
            address backrunAgent = agents[AgentType.BACKRUN];
            if (backrunAgent != address(0)) {
                try IBackrunAgent(backrunAgent).analyzeBackrun(context, newPoolPrice) returns (
                    IBackrunAgent.BackrunOpportunity memory opportunity
                ) {
                    if (opportunity.shouldBackrun && opportunity.backrunAmount > 0) {
                        result.shouldBackrun = true;
                        result.backrunAmount = opportunity.backrunAmount;
                        result.expectedProfit = opportunity.expectedProfit;
                        result.zeroForOne = opportunity.zeroForOne;
                        result.targetPrice = opportunity.targetPrice;
                        result.currentPrice = newPoolPrice;
                        _recordExecution(backrunAgent, true, opportunity.expectedProfit);
                        emit AgentExecuted(
                            AgentType.BACKRUN,
                            backrunAgent,
                            true,
                            opportunity.expectedProfit
                        );
                    }
                } catch {
                    _recordExecution(backrunAgent, false, 0);
                }
            }
        }

        return result;
    }

    /// @notice Get view-only recommendations from all agents
    /// @param context The swap context
    /// @return arbResult Arbitrage analysis (if available)
    /// @return feeResult Fee recommendation (if available)
    function getRecommendations(
        SwapContext calldata context
    ) external view returns (
        IArbitrageAgent.ArbitrageResult memory arbResult,
        IDynamicFeeAgent.FeeResult memory feeResult
    ) {
        // Get arbitrage recommendation
        address arbAgent = agents[AgentType.ARBITRAGE];
        if (arbAgent != address(0) && agentEnabled[AgentType.ARBITRAGE]) {
            try IArbitrageAgent(arbAgent).analyzeArbitrage(context) returns (
                IArbitrageAgent.ArbitrageResult memory result
            ) {
                arbResult = result;
            } catch {}
        }

        // Get fee recommendation
        address feeAgent = agents[AgentType.DYNAMIC_FEE];
        if (feeAgent != address(0) && agentEnabled[AgentType.DYNAMIC_FEE]) {
            try IDynamicFeeAgent(feeAgent).calculateFee(context) returns (
                IDynamicFeeAgent.FeeResult memory result
            ) {
                feeResult = result;
            } catch {}
        }
    }

    // ============ Admin Functions ============

    /// @notice Register a new agent
    /// @param agentType The type of agent
    /// @param agent The agent contract address
    function registerAgent(
        AgentType agentType,
        address agent
    ) external onlyOwner {
        if (agent == address(0)) revert InvalidAgent();
        
        // Verify agent implements correct interface
        AgentType actualType = ISwarmAgent(agent).agentType();
        if (actualType != agentType) revert AgentTypeMismatch();
        
        // Check agent is active
        if (!ISwarmAgent(agent).isActive()) revert AgentNotActive();

        address oldAgent = agents[agentType];
        agents[agentType] = agent;
        agentEnabled[agentType] = true;

        uint256 agentId = ISwarmAgent(agent).getAgentId();

        if (oldAgent != address(0)) {
            emit AgentSwitched(agentType, oldAgent, agent);
        } else {
            emit AgentRegistered(agentType, agent, agentId);
        }
    }

    /// @notice Set backup agent for failover
    /// @param agentType The type of agent
    /// @param agent The backup agent address
    function setBackupAgent(
        AgentType agentType,
        address agent
    ) external onlyOwner {
        if (agent != address(0)) {
            AgentType actualType = ISwarmAgent(agent).agentType();
            if (actualType != agentType) revert AgentTypeMismatch();
        }
        backupAgents[agentType] = agent;
    }

    /// @notice Remove an agent
    /// @param agentType The type of agent to remove
    function removeAgent(AgentType agentType) external onlyOwner {
        address agent = agents[agentType];
        if (agent == address(0)) revert AgentNotRegistered(agentType);
        
        delete agents[agentType];
        agentEnabled[agentType] = false;
        
        emit AgentRemoved(agentType, agent);
    }

    /// @notice Enable/disable an agent type
    /// @param agentType The agent type
    /// @param enabled Whether to enable
    function setAgentEnabled(
        AgentType agentType,
        bool enabled
    ) external onlyOwner {
        agentEnabled[agentType] = enabled;
        emit AgentEnabled(agentType, enabled);
    }

    /// @notice Authorize a hook to call this executor
    /// @param hook The hook address
    /// @param authorized Whether to authorize
    function authorizeHook(address hook, bool authorized) external onlyOwner {
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }

    // ============ View Functions ============

    /// @notice Get agent for a specific type
    /// @param agentType The agent type
    /// @return agent The agent address
    /// @return enabled Whether it's enabled
    /// @return agentId The ERC-8004 ID
    function getAgent(AgentType agentType) external view returns (
        address agent,
        bool enabled,
        uint256 agentId
    ) {
        agent = agents[agentType];
        enabled = agentEnabled[agentType];
        if (agent != address(0)) {
            agentId = ISwarmAgent(agent).getAgentId();
        }
    }

    /// @notice Get all registered agents
    /// @return agentList Array of agent addresses by type
    function getAllAgents() external view returns (address[5] memory agentList) {
        agentList[0] = agents[AgentType.ARBITRAGE];
        agentList[1] = agents[AgentType.DYNAMIC_FEE];
        agentList[2] = agents[AgentType.BACKRUN];
        agentList[3] = agents[AgentType.LIQUIDITY];
        agentList[4] = agents[AgentType.ORACLE];
    }

    /// @notice Get agent statistics
    /// @param agent The agent address
    /// @return stats The agent's execution stats
    function getAgentStats(address agent) external view returns (AgentStats memory stats) {
        return agentStats[agent];
    }

    // ============ Internal Functions ============

    function _recordExecution(address agent, bool success, uint256 value) internal {
        AgentStats storage stats = agentStats[agent];
        stats.executionCount++;
        if (success) {
            stats.successCount++;
            stats.totalValueProcessed += value;
        }
        stats.lastExecution = uint64(block.timestamp);
    }
}
