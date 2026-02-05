// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IERC8004IdentityRegistry, IERC8004ReputationRegistry, ERC8004Integration} from "./ERC8004Integration.sol";

/// @title SwarmAgentRegistry
/// @notice Manages Swarm agent registration on ERC-8004
/// @dev Creates and tracks ERC-8004 agent identities for the Swarm protocol
contract SwarmAgentRegistry is Ownable, ReentrancyGuard {
    using ERC8004Integration for int128;
    using ERC8004Integration for int256;

    // ============ State Variables ============

    /// @notice ERC-8004 Identity Registry
    IERC8004IdentityRegistry public identityRegistry;

    /// @notice ERC-8004 Reputation Registry
    IERC8004ReputationRegistry public reputationRegistry;

    /// @notice Mapping from agent contract address to their ERC-8004 agent ID
    mapping(address => uint256) public agentIdentities;

    /// @notice Mapping from agent ID to agent contract address
    mapping(uint256 => address) public agentContracts;

    /// @notice Agent metadata
    struct AgentMetadata {
        string name;
        string description;
        string agentType; // "fee-optimizer", "mev-hunter", "slippage-predictor"
        string version;
        uint256 registeredAt;
        bool active;
    }

    /// @notice Metadata for each agent
    mapping(address => AgentMetadata) public agentMetadata;

    /// @notice List of all registered agent addresses
    address[] public registeredAgents;

    /// @notice Clients authorized to give feedback (usually the SwarmCoordinator)
    mapping(address => bool) public authorizedFeedbackClients;

    // ============ Events ============

    event AgentRegistered(address indexed agentContract, uint256 indexed agentId, string name, string agentType);

    event AgentDeactivated(address indexed agentContract, uint256 indexed agentId);
    event AgentReactivated(address indexed agentContract, uint256 indexed agentId);
    event FeedbackClientAuthorized(address indexed client, bool authorized);
    event RegistryUpdated(address identityRegistry, address reputationRegistry);

    // ============ Errors ============

    error AgentAlreadyRegistered(address agent);
    error AgentNotRegistered(address agent);
    error InvalidAgentType();
    error UnauthorizedFeedbackClient();
    error ZeroAddress();

    // ============ Constructor ============

    constructor(address _identityRegistry, address _reputationRegistry) Ownable(msg.sender) {
        if (_identityRegistry != address(0)) {
            identityRegistry = IERC8004IdentityRegistry(_identityRegistry);
            reputationRegistry = IERC8004ReputationRegistry(_reputationRegistry);
            return;
        }

        // Default registries by chain.
        if (block.chainid == 1) {
            identityRegistry = IERC8004IdentityRegistry(ERC8004Integration.MAINNET_IDENTITY_REGISTRY);
            reputationRegistry = IERC8004ReputationRegistry(ERC8004Integration.MAINNET_REPUTATION_REGISTRY);
        } else if (block.chainid == 11155111) {
            identityRegistry = IERC8004IdentityRegistry(ERC8004Integration.SEPOLIA_IDENTITY_REGISTRY);
            reputationRegistry = IERC8004ReputationRegistry(ERC8004Integration.SEPOLIA_REPUTATION_REGISTRY);
        } else {
            // For other chains, force explicit configuration.
            revert ZeroAddress();
        }
    }

    // ============ Agent Registration ============

    /// @notice Register a new agent on ERC-8004
    /// @param agentContract The agent contract address
    /// @param name Human-readable name
    /// @param description Description of the agent
    /// @param agentType Type of agent ("fee-optimizer", "mev-hunter", "slippage-predictor")
    /// @param version Version string
    /// @return agentId The ERC-8004 agent ID
    function registerAgent(
        address agentContract,
        string calldata name,
        string calldata description,
        string calldata agentType,
        string calldata version
    ) external onlyOwner nonReentrant returns (uint256 agentId) {
        if (agentContract == address(0)) revert ZeroAddress();
        if (agentIdentities[agentContract] != 0) revert AgentAlreadyRegistered(agentContract);

        // Validate agent type
        if (!_isValidAgentType(agentType)) revert InvalidAgentType();

        // Build agent URI (could be IPFS or data URI in production)
        string memory agentURI = _buildAgentURI(name, description, agentType, version, agentContract);

        // Build metadata entries
        IERC8004IdentityRegistry.MetadataEntry[] memory metadata = new IERC8004IdentityRegistry.MetadataEntry[](4);
        metadata[0] =
            IERC8004IdentityRegistry.MetadataEntry({metadataKey: "agentType", metadataValue: bytes(agentType)});
        metadata[1] =
            IERC8004IdentityRegistry.MetadataEntry({metadataKey: "protocol", metadataValue: bytes("swarm-mev-router")});
        metadata[2] = IERC8004IdentityRegistry.MetadataEntry({metadataKey: "version", metadataValue: bytes(version)});
        metadata[3] = IERC8004IdentityRegistry.MetadataEntry({
            metadataKey: "contractAddress", metadataValue: abi.encodePacked(agentContract)
        });

        // Register on ERC-8004 Identity Registry
        agentId = identityRegistry.register(agentURI, metadata);

        // Store mapping
        agentIdentities[agentContract] = agentId;
        agentContracts[agentId] = agentContract;
        registeredAgents.push(agentContract);

        // Store metadata
        agentMetadata[agentContract] = AgentMetadata({
            name: name,
            description: description,
            agentType: agentType,
            version: version,
            registeredAt: block.timestamp,
            active: true
        });

        emit AgentRegistered(agentContract, agentId, name, agentType);
    }

    /// @notice Register an existing ERC-8004 agent ID
    /// @dev Use this if agent was registered directly on ERC-8004
    function linkExistingAgent(
        address agentContract,
        uint256 agentId,
        string calldata name,
        string calldata description,
        string calldata agentType,
        string calldata version
    ) external onlyOwner {
        if (agentContract == address(0)) revert ZeroAddress();
        if (agentIdentities[agentContract] != 0) revert AgentAlreadyRegistered(agentContract);

        // Verify this contract is authorized for the agent ID
        require(identityRegistry.isAuthorizedOrOwner(address(this), agentId), "Not authorized for agent");

        agentIdentities[agentContract] = agentId;
        agentContracts[agentId] = agentContract;
        registeredAgents.push(agentContract);

        agentMetadata[agentContract] = AgentMetadata({
            name: name,
            description: description,
            agentType: agentType,
            version: version,
            registeredAt: block.timestamp,
            active: true
        });

        emit AgentRegistered(agentContract, agentId, name, agentType);
    }

    // ============ Agent Status Management ============

    /// @notice Deactivate an agent
    function deactivateAgent(address agentContract) external onlyOwner {
        if (agentIdentities[agentContract] == 0) revert AgentNotRegistered(agentContract);
        agentMetadata[agentContract].active = false;
        emit AgentDeactivated(agentContract, agentIdentities[agentContract]);
    }

    /// @notice Reactivate an agent
    function reactivateAgent(address agentContract) external onlyOwner {
        if (agentIdentities[agentContract] == 0) revert AgentNotRegistered(agentContract);
        agentMetadata[agentContract].active = true;
        emit AgentReactivated(agentContract, agentIdentities[agentContract]);
    }

    // ============ Reputation Integration ============

    /// @notice Give feedback to an agent (callable by authorized clients like SwarmCoordinator)
    /// @param agentContract The agent contract address
    /// @param value Feedback value in WAD (can be negative)
    /// @param tag Feedback category tag
    function giveFeedback(address agentContract, int128 value, string calldata tag) external {
        if (!authorizedFeedbackClients[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedFeedbackClient();
        }

        uint256 agentId = agentIdentities[agentContract];
        if (agentId == 0) revert AgentNotRegistered(agentContract);

        reputationRegistry.giveFeedback(
            agentId,
            value,
            ERC8004Integration.REPUTATION_DECIMALS,
            ERC8004Integration.TAG_SWARM_ROUTING,
            tag,
            "", // endpoint
            "", // feedbackURI
            bytes32(0) // feedbackHash
        );
    }

    /// @notice Get an agent's reputation summary
    /// @param agentContract The agent contract address
    /// @return count Number of feedbacks
    /// @return reputationWad Average reputation in WAD
    /// @return tier Reputation tier (0-4)
    function getAgentReputation(address agentContract)
        external
        view
        returns (uint64 count, int256 reputationWad, uint8 tier)
    {
        uint256 agentId = agentIdentities[agentContract];
        if (agentId == 0) return (0, 0, 0);

        // Get all clients who have given feedback
        address[] memory clients = reputationRegistry.getClients(agentId);
        if (clients.length == 0) return (0, 0, 2); // Neutral tier for new agents

        (uint64 feedbackCount, int128 summaryValue, uint8 decimals) =
            reputationRegistry.getSummary(agentId, clients, ERC8004Integration.TAG_SWARM_ROUTING, "");

        reputationWad = ERC8004Integration.normalizeToWad(summaryValue, decimals);
        tier = ERC8004Integration.getReputationTier(reputationWad);
        count = feedbackCount;
    }

    /// @notice Calculate reputation weight for scoring
    /// @param agentContract The agent contract address
    /// @return weight Multiplier in WAD (0.5e18 to 2e18)
    function getReputationWeight(address agentContract) external view returns (uint256 weight) {
        uint256 agentId = agentIdentities[agentContract];
        if (agentId == 0) return 1e18; // Neutral weight for unregistered

        address[] memory clients = reputationRegistry.getClients(agentId);
        if (clients.length == 0) return 1e18; // Neutral weight for new agents

        (uint64 count, int128 summaryValue, uint8 decimals) =
            reputationRegistry.getSummary(agentId, clients, ERC8004Integration.TAG_SWARM_ROUTING, "");

        if (count == 0) return 1e18;

        int256 reputationWad = ERC8004Integration.normalizeToWad(summaryValue, decimals);
        return ERC8004Integration.calculateReputationWeight(reputationWad);
    }

    // ============ Authorization ============

    /// @notice Authorize a client to give feedback
    function setFeedbackClientAuthorization(address client, bool authorized) external onlyOwner {
        authorizedFeedbackClients[client] = authorized;
        emit FeedbackClientAuthorized(client, authorized);
    }

    // ============ Configuration ============

    /// @notice Update registry addresses
    function setRegistries(address _identityRegistry, address _reputationRegistry) external onlyOwner {
        if (_identityRegistry != address(0)) {
            identityRegistry = IERC8004IdentityRegistry(_identityRegistry);
        }
        if (_reputationRegistry != address(0)) {
            reputationRegistry = IERC8004ReputationRegistry(_reputationRegistry);
        }
        emit RegistryUpdated(address(identityRegistry), address(reputationRegistry));
    }

    // ============ View Functions ============

    /// @notice Get all registered agents
    function getAllAgents() external view returns (address[] memory) {
        return registeredAgents;
    }

    /// @notice Get active agents only
    function getActiveAgents() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < registeredAgents.length; i++) {
            if (agentMetadata[registeredAgents[i]].active) {
                activeCount++;
            }
        }

        address[] memory active = new address[](activeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < registeredAgents.length; i++) {
            if (agentMetadata[registeredAgents[i]].active) {
                active[j++] = registeredAgents[i];
            }
        }
        return active;
    }

    /// @notice Check if an agent is registered and active
    function isAgentActive(address agentContract) external view returns (bool) {
        return agentIdentities[agentContract] != 0 && agentMetadata[agentContract].active;
    }

    // ============ Internal Functions ============

    function _isValidAgentType(string calldata agentType) internal pure returns (bool) {
        bytes32 typeHash = keccak256(bytes(agentType));
        return (typeHash == keccak256("fee-optimizer") || typeHash == keccak256("mev-hunter")
                || typeHash == keccak256("slippage-predictor") || typeHash == keccak256("generic"));
    }

    function _buildAgentURI(
        string memory name,
        string memory description,
        string memory agentType,
        string memory version,
        address agentContract
    ) internal pure returns (string memory) {
        // In production, this would return an IPFS URI or similar
        // For now, we return a data URI placeholder
        return string(
            abi.encodePacked(
                "data:application/json,{",
                '"name":"',
                name,
                '",',
                '"description":"',
                description,
                '",',
                '"agentType":"',
                agentType,
                '",',
                '"version":"',
                version,
                '",',
                '"contract":"',
                _addressToString(agentContract),
                '"',
                "}"
            )
        );
    }

    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}
