// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

/// @title IERC8004IdentityRegistry
/// @notice Interface for ERC-8004 Identity Registry on Sepolia
/// @dev Official Sepolia address: 0x8004A818BFB912233c491871b3d84c89A494BD9e
interface IERC8004IdentityRegistry is IERC721 {
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    /// @notice Register a new agent identity
    function register() external returns (uint256 agentId);
    
    /// @notice Register with URI
    function register(string memory agentURI) external returns (uint256 agentId);
    
    /// @notice Register with URI and metadata
    function register(string memory agentURI, MetadataEntry[] memory metadata) external returns (uint256 agentId);

    /// @notice Get metadata for an agent
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);
    
    /// @notice Set metadata for an agent
    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external;

    /// @notice Get the agent's designated wallet
    function getAgentWallet(uint256 agentId) external view returns (address);

    /// @notice Check if spender is authorized or owner of the agent
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);

    /// @notice Update agent URI
    function setAgentURI(uint256 agentId, string calldata newURI) external;
}

/// @title IERC8004ReputationRegistry
/// @notice Interface for ERC-8004 Reputation Registry on Sepolia
/// @dev Official Sepolia address: 0x8004B663056A597Dffe9eCcC1965A193B7388713
interface IERC8004ReputationRegistry {
    /// @notice Give feedback to an agent
    /// @param agentId The agent's identity ID
    /// @param value Feedback value (can be negative)
    /// @param valueDecimals Decimals for the value (max 18)
    /// @param tag1 Primary tag for categorization
    /// @param tag2 Secondary tag for categorization
    /// @param endpoint Endpoint identifier (optional)
    /// @param feedbackURI URI to detailed feedback (optional)
    /// @param feedbackHash Hash of feedback content (optional)
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;

    /// @notice Revoke previously given feedback
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;

    /// @notice Append a response to feedback
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external;

    /// @notice Get the last feedback index for an agent from a client
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64);

    /// @notice Read specific feedback
    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked);

    /// @notice Get a summary of an agent's reputation
    /// @param agentId The agent's identity ID
    /// @param clientAddresses List of clients to aggregate feedback from
    /// @param tag1 Filter by primary tag (empty string for all)
    /// @param tag2 Filter by secondary tag (empty string for all)
    /// @return count Number of feedbacks
    /// @return summaryValue Average value
    /// @return summaryValueDecimals Decimals for the summary value
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);

    /// @notice Read all feedback for an agent
    function readAllFeedback(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    ) external view returns (
        address[] memory clients,
        uint64[] memory feedbackIndexes,
        int128[] memory values,
        uint8[] memory valueDecimals,
        string[] memory tag1s,
        string[] memory tag2s,
        bool[] memory revokedStatuses
    );

    /// @notice Get all clients who have given feedback to an agent
    function getClients(uint256 agentId) external view returns (address[] memory);
}

/// @title ERC8004Integration
/// @notice Helper library for ERC-8004 integration
/// @dev Provides constants and utilities for working with ERC-8004 registries
library ERC8004Integration {
    // ============ Official Sepolia Addresses ============
    
    /// @notice ERC-8004 Identity Registry on Sepolia
    address public constant SEPOLIA_IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    
    /// @notice ERC-8004 Reputation Registry on Sepolia
    address public constant SEPOLIA_REPUTATION_REGISTRY = 0x8004B663056A597Dffe9eCcC1965A193B7388713;

    // ============ Official Mainnet Addresses ============
    
    /// @notice ERC-8004 Identity Registry on Mainnet
    address public constant MAINNET_IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    
    /// @notice ERC-8004 Reputation Registry on Mainnet
    address public constant MAINNET_REPUTATION_REGISTRY = 0x8004BAa17C55a88189AE136b182e5fdA19dE9b63;

    // ============ Swarm-specific Constants ============
    
    /// @notice Tag for Swarm trade routing feedback
    string public constant TAG_SWARM_ROUTING = "swarm-routing";
    
    /// @notice Tag for MEV protection feedback
    string public constant TAG_MEV_PROTECTION = "mev-protection";
    
    /// @notice Tag for fee optimization feedback
    string public constant TAG_FEE_OPTIMIZATION = "fee-optimization";
    
    /// @notice Tag for slippage prediction feedback
    string public constant TAG_SLIPPAGE_PREDICTION = "slippage-prediction";

    // ============ Reputation Scaling ============
    
    /// @notice Reputation is in WAD format (18 decimals)
    uint8 public constant REPUTATION_DECIMALS = 18;
    
    /// @notice Minimum reputation for a new agent (neutral)
    int128 public constant MIN_NEW_AGENT_REPUTATION = 0;
    
    /// @notice Excellent reputation threshold (+5 in WAD)
    int128 public constant EXCELLENT_REPUTATION_WAD = 5e18;
    
    /// @notice Good reputation threshold (+2 in WAD)
    int128 public constant GOOD_REPUTATION_WAD = 2e18;
    
    /// @notice Poor reputation threshold (-1 in WAD)
    int128 public constant POOR_REPUTATION_WAD = -1e18;

    // ============ Feedback Values ============
    
    /// @notice Feedback for successful swap execution (+1 WAD)
    int128 public constant FEEDBACK_SUCCESS = 1e18;
    
    /// @notice Feedback for excellent MEV protection (+2 WAD)
    int128 public constant FEEDBACK_EXCELLENT_MEV_PROTECTION = 2e18;
    
    /// @notice Feedback for poor slippage prediction (-1 WAD)
    int128 public constant FEEDBACK_POOR_PREDICTION = -1e18;
    
    /// @notice Feedback for failed execution (-2 WAD)
    int128 public constant FEEDBACK_FAILED = -2e18;

    // ============ Helper Functions ============

    /// @notice Normalize reputation value to WAD (18 decimals)
    /// @param value The reputation value
    /// @param decimals The decimals of the value
    /// @return Normalized value in WAD
    function normalizeToWad(int128 value, uint8 decimals) internal pure returns (int256) {
        if (decimals == 18) return int256(value);
        if (decimals > 18) {
            uint256 shift = 10 ** uint256(decimals - 18);
            return int256(value) / int256(shift);
        }
        uint256 factor = 10 ** uint256(18 - decimals);
        return int256(value) * int256(factor);
    }

    /// @notice Calculate reputation weight for scoring (0.5x to 2x multiplier)
    /// @param reputationWad Reputation in WAD format
    /// @return weight Multiplier in WAD (1e18 = 1x)
    function calculateReputationWeight(int256 reputationWad) internal pure returns (uint256 weight) {
        // Map reputation from [-5, +5] WAD to weight [0.5x, 2x]
        // reputation = -5 -> weight = 0.5
        // reputation = 0 -> weight = 1.0
        // reputation = +5 -> weight = 2.0
        
        if (reputationWad <= -5e18) return 0.5e18;
        if (reputationWad >= 5e18) return 2e18;
        
        // Linear interpolation: weight = 1 + (reputation / 10)
        // reputation = -5 -> 1 + (-0.5) = 0.5
        // reputation = 0 -> 1 + 0 = 1.0
        // reputation = +5 -> 1 + 0.5 = 1.5 (we add extra 0.5 for positive)
        
        if (reputationWad >= 0) {
            // Positive: weight = 1 + (reputation / 5) * 0.5, max 2.0
            uint256 bonus = uint256(reputationWad) / 10; // reputation/5 * 0.5 = reputation/10
            return 1e18 + bonus;
        } else {
            // Negative: weight = 1 - (|reputation| / 10), min 0.5
            uint256 penalty = uint256(-reputationWad) / 10;
            if (penalty >= 0.5e18) return 0.5e18;
            return 1e18 - penalty;
        }
    }

    /// @notice Check if agent meets minimum reputation requirements
    /// @param reputationWad Reputation in WAD format
    /// @param minReputationWad Minimum required reputation
    /// @return True if agent meets requirements
    function meetsReputationRequirement(
        int256 reputationWad,
        int256 minReputationWad
    ) internal pure returns (bool) {
        return reputationWad >= minReputationWad;
    }

    /// @notice Get reputation tier (0 = unrated, 1 = poor, 2 = neutral, 3 = good, 4 = excellent)
    /// @param reputationWad Reputation in WAD format
    /// @return tier The reputation tier
    function getReputationTier(int256 reputationWad) internal pure returns (uint8 tier) {
        if (reputationWad >= int256(EXCELLENT_REPUTATION_WAD)) return 4;
        if (reputationWad >= int256(GOOD_REPUTATION_WAD)) return 3;
        if (reputationWad >= int256(MIN_NEW_AGENT_REPUTATION)) return 2;
        if (reputationWad >= int256(POOR_REPUTATION_WAD)) return 1;
        return 0;
    }
}
