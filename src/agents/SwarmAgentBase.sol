// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwarmCoordinator} from "../interfaces/ISwarmCoordinator.sol";
import {IRouteAgent} from "../interfaces/IRouteAgent.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {IERC8004ReputationRegistry, ERC8004Integration} from "../erc8004/ERC8004Integration.sol";

/// @title SwarmAgentBase
/// @notice Base contract for Swarm routing agents with ERC-8004 reputation integration
/// @dev Agents inherit this to implement specialized scoring logic
abstract contract SwarmAgentBase is IRouteAgent {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error NoCandidates();

    /// @notice The Swarm coordinator contract
    ISwarmCoordinator public immutable coordinator;
    
    /// @notice Uniswap v4 PoolManager
    IPoolManager public immutable poolManager;
    
    /// @notice ERC-8004 Reputation Registry (optional)
    IERC8004ReputationRegistry public reputationRegistry;
    
    /// @notice This agent's ERC-8004 identity ID (0 if not registered)
    uint256 public agentId;
    
    /// @notice Whether to use reputation-weighted scoring
    bool public useReputationWeighting;
    
    /// @notice Cached reputation weight (updated periodically)
    uint256 public cachedReputationWeight;
    
    /// @notice Last time reputation was refreshed
    uint256 public lastReputationRefresh;
    
    /// @notice Reputation refresh interval (default 1 hour)
    uint256 public constant REPUTATION_REFRESH_INTERVAL = 1 hours;

    event ReputationConfigured(uint256 agentId, address reputationRegistry);
    event ReputationWeightUpdated(uint256 oldWeight, uint256 newWeight);

    constructor(ISwarmCoordinator coordinator_, IPoolManager poolManager_) {
        coordinator = coordinator_;
        poolManager = poolManager_;
        cachedReputationWeight = 1e18; // Default neutral weight
    }
    
    /// @notice Configure ERC-8004 reputation integration
    /// @param agentId_ The ERC-8004 agent identity ID
    /// @param reputationRegistry_ The reputation registry address (or address(0) for default Sepolia)
    function configureReputation(uint256 agentId_, address reputationRegistry_) external {
        // In production, add access control here
        agentId = agentId_;
        
        if (reputationRegistry_ == address(0)) {
            reputationRegistry = IERC8004ReputationRegistry(ERC8004Integration.SEPOLIA_REPUTATION_REGISTRY);
        } else {
            reputationRegistry = IERC8004ReputationRegistry(reputationRegistry_);
        }
        
        useReputationWeighting = true;
        _refreshReputationWeight();
        
        emit ReputationConfigured(agentId_, address(reputationRegistry));
    }
    
    /// @notice Refresh the cached reputation weight
    function refreshReputationWeight() external {
        _refreshReputationWeight();
    }
    
    /// @notice Internal function to refresh reputation weight
    function _refreshReputationWeight() internal {
        if (agentId == 0 || address(reputationRegistry) == address(0)) {
            cachedReputationWeight = 1e18;
            return;
        }
        
        uint256 oldWeight = cachedReputationWeight;
        
        try reputationRegistry.getClients(agentId) returns (address[] memory clients) {
            if (clients.length == 0) {
                cachedReputationWeight = 1e18; // Neutral for new agents
            } else {
                try reputationRegistry.getSummary(
                    agentId,
                    clients,
                    ERC8004Integration.TAG_SWARM_ROUTING,
                    ""
                ) returns (uint64 count, int128 summaryValue, uint8 decimals) {
                    if (count > 0) {
                        int256 reputationWad = ERC8004Integration.normalizeToWad(summaryValue, decimals);
                        cachedReputationWeight = ERC8004Integration.calculateReputationWeight(reputationWad);
                    } else {
                        cachedReputationWeight = 1e18;
                    }
                } catch {
                    cachedReputationWeight = 1e18;
                }
            }
        } catch {
            cachedReputationWeight = 1e18;
        }
        
        lastReputationRefresh = block.timestamp;
        
        if (oldWeight != cachedReputationWeight) {
            emit ReputationWeightUpdated(oldWeight, cachedReputationWeight);
        }
    }
    
    /// @notice Get the current reputation weight, refreshing if stale
    function getReputationWeight() public returns (uint256) {
        if (block.timestamp >= lastReputationRefresh + REPUTATION_REFRESH_INTERVAL) {
            _refreshReputationWeight();
        }
        return cachedReputationWeight;
    }
    
    /// @notice Get reputation weight without refreshing (view function)
    function getReputationWeightView() public view returns (uint256) {
        return cachedReputationWeight;
    }

    /// @notice Submit a proposal for an intent
    /// @dev Evaluates all candidate paths and submits the best one
    /// @param intentId The intent to propose for
    /// @return candidateId The selected candidate
    /// @return score The reputation-weighted score
    function propose(uint256 intentId) external override returns (uint256 candidateId, int256 score) {
        ISwarmCoordinator.IntentView memory intent = coordinator.getIntent(intentId);
        uint256 candidateCount = coordinator.getCandidateCount(intentId);
        if (candidateCount == 0) revert NoCandidates();

        bool hasBest;
        int256 bestScore;

        for (uint256 i = 0; i < candidateCount; i++) {
            PathKey[] memory path = _loadPath(intentId, i);
            int256 candidateScore = _score(intent, path);
            
            // Apply reputation weighting if enabled
            if (useReputationWeighting && cachedReputationWeight != 1e18) {
                // Higher reputation = lower (better) weighted score
                // Score * (2 - weight) where weight is 0.5 to 2.0
                // High rep (weight=2.0) -> score * 0 = score unchanged or improved
                // Low rep (weight=0.5) -> score * 1.5 = score penalized
                uint256 weightFactor = 2e18 - cachedReputationWeight;
                if (candidateScore >= 0) {
                    candidateScore = (candidateScore * int256(weightFactor)) / 1e18;
                } else {
                    // For negative scores (better), high rep makes them more negative (even better)
                    candidateScore = (candidateScore * int256(cachedReputationWeight)) / 1e18;
                }
            }
            
            if (!hasBest || candidateScore < bestScore) {
                hasBest = true;
                bestScore = candidateScore;
                candidateId = i;
            }
        }

        if (!hasBest) revert NoCandidates();
        score = bestScore;
        coordinator.submitProposal(intentId, candidateId, score, _proposalData(intent, candidateId, score));
    }

    function _loadPath(uint256 intentId, uint256 candidateId) internal view returns (PathKey[] memory) {
        bytes memory pathData = coordinator.getCandidatePath(intentId, candidateId);
        return abi.decode(pathData, (PathKey[]));
    }

    function _poolMetrics(PathKey memory step, Currency currencyIn)
        internal
        view
        returns (PoolKey memory key, uint24 lpFee, uint128 liquidity)
    {
        // Build pool key from PathKey and currencyIn
        Currency currencyOut = step.intermediateCurrency;
        (Currency currency0, Currency currency1) =
            currencyIn < currencyOut ? (currencyIn, currencyOut) : (currencyOut, currencyIn);
        
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: step.fee,
            tickSpacing: step.tickSpacing,
            hooks: step.hooks
        });
        
        PoolId poolId = key.toId();
        (, , , lpFee) = poolManager.getSlot0(poolId);
        liquidity = poolManager.getLiquidity(poolId);
    }

    function _score(ISwarmCoordinator.IntentView memory intent, PathKey[] memory path)
        internal
        view
        virtual
        returns (int256);

    function _proposalData(ISwarmCoordinator.IntentView memory, uint256, int256)
        internal
        view
        virtual
        returns (bytes memory)
    {
        return "";
    }
}
