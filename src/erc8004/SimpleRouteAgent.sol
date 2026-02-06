// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {IRouteAgent} from "../interfaces/IRouteAgent.sol";
import {ISwarmCoordinator} from "../interfaces/ISwarmCoordinator.sol";

/// @title SimpleRouteAgent
/// @notice Minimal on-chain route agent that submits proposals to SwarmCoordinator.
/// @dev This removes manual UI proposal submission, but still requires a transaction trigger.
contract SimpleRouteAgent is Ownable, IRouteAgent {
    ISwarmCoordinator public coordinator;

    /// @notice Optional ERC-8004 identity metadata for operator visibility.
    uint256 public agentId;
    address public identityRegistry;

    uint256 public defaultCandidateId;
    int256 public defaultScore;
    bytes public defaultData = "0x";

    event CoordinatorUpdated(address indexed coordinator);
    event IdentityConfigured(uint256 indexed agentId, address indexed identityRegistry);
    event DefaultProposalUpdated(uint256 candidateId, int256 score, bytes data);
    event ProposalSent(uint256 indexed intentId, uint256 indexed candidateId, int256 score, bytes data);

    error InvalidCoordinator();
    error NoCandidates();
    error InvalidCandidate(uint256 candidateId);

    constructor(address _coordinator, address _owner) Ownable(_owner) {
        if (_coordinator == address(0)) revert InvalidCoordinator();
        coordinator = ISwarmCoordinator(_coordinator);
    }

    function setCoordinator(address _coordinator) external onlyOwner {
        if (_coordinator == address(0)) revert InvalidCoordinator();
        coordinator = ISwarmCoordinator(_coordinator);
        emit CoordinatorUpdated(_coordinator);
    }

    function configureIdentity(uint256 _agentId, address _identityRegistry) external onlyOwner {
        agentId = _agentId;
        identityRegistry = _identityRegistry;
        emit IdentityConfigured(_agentId, _identityRegistry);
    }

    function setDefaultProposal(uint256 candidateId, int256 score, bytes calldata data) external onlyOwner {
        defaultCandidateId = candidateId;
        defaultScore = score;
        defaultData = data;
        emit DefaultProposalUpdated(candidateId, score, data);
    }

    /// @notice Submit proposal using configured defaults.
    /// @dev Anyone can trigger this tx; coordinator still validates this contract as the proposing agent.
    function propose(uint256 intentId) external returns (uint256 candidateId, int256 score) {
        (candidateId, score) = _submit(intentId, defaultCandidateId, defaultScore, defaultData);
    }

    /// @notice Submit proposal with explicit values.
    function proposeWith(uint256 intentId, uint256 candidateId, int256 score, bytes calldata data)
        external
        returns (uint256, int256)
    {
        return _submit(intentId, candidateId, score, data);
    }

    function _submit(uint256 intentId, uint256 candidateId, int256 score, bytes memory data)
        internal
        returns (uint256, int256)
    {
        uint256 candidateCount = coordinator.getCandidateCount(intentId);
        if (candidateCount == 0) revert NoCandidates();
        if (candidateId >= candidateCount) revert InvalidCandidate(candidateId);

        coordinator.submitProposal(intentId, candidateId, score, data);
        emit ProposalSent(intentId, candidateId, score, data);
        return (candidateId, score);
    }
}
