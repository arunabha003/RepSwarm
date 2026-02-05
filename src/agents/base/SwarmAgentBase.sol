// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {ISwarmAgent, AgentType, SwapContext, AgentResult} from "../../interfaces/ISwarmAgent.sol";

/// @title SwarmAgentBase
/// @notice Base implementation for all Swarm agents - ERC-8004 compatible
/// @dev All agents inherit from this to get standard functionality
abstract contract SwarmAgentBase is ISwarmAgent, Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // ============ State Variables ============

    /// @notice Uniswap v4 PoolManager
    IPoolManager public immutable poolManager;

    /// @notice ERC-8004 agent identity ID
    uint256 public agentId;

    /// @notice ERC-8004 Identity Registry address
    address public identityRegistry;

    /// @notice Whether agent is active
    bool public active;

    /// @notice Agent confidence score (0-100)
    uint8 public confidence;

    /// @notice Authorized callers (executor, hooks)
    mapping(address => bool) public authorizedCallers;

    // ============ Events ============

    event AgentActivated(bool active);
    event IdentityConfigured(uint256 agentId, address identityRegistry);
    event CallerAuthorized(address caller, bool authorized);
    event ConfidenceUpdated(uint8 oldConfidence, uint8 newConfidence);

    // ============ Errors ============

    error NotAuthorizedCaller();
    error AgentNotActive();

    // ============ Modifiers ============

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert NotAuthorizedCaller();
        }
        _;
    }

    modifier whenActive() {
        if (!active) revert AgentNotActive();
        _;
    }

    // ============ Constructor ============

    constructor(IPoolManager _poolManager, address _owner) Ownable(_owner) {
        poolManager = _poolManager;
        active = true;
        confidence = 80; // Default confidence
    }

    // ============ ISwarmAgent Implementation ============

    /// @inheritdoc ISwarmAgent
    function getAgentId() external view override returns (uint256) {
        return agentId;
    }

    /// @inheritdoc ISwarmAgent
    function isActive() external view override returns (bool) {
        return active;
    }

    /// @inheritdoc ISwarmAgent
    function getConfidence() external view override returns (uint8) {
        return confidence;
    }

    /// @inheritdoc ISwarmAgent
    function execute(SwapContext calldata context)
        external
        virtual
        override
        onlyAuthorized
        whenActive
        returns (AgentResult memory result)
    {
        return _execute(context);
    }

    /// @inheritdoc ISwarmAgent
    function getRecommendation(SwapContext calldata context)
        external
        view
        virtual
        override
        returns (AgentResult memory result)
    {
        return _getRecommendation(context);
    }

    // ============ Abstract Functions ============

    /// @notice Internal execute implementation - override in child contracts
    function _execute(SwapContext calldata context) internal virtual returns (AgentResult memory);

    /// @notice Internal view recommendation - override in child contracts
    function _getRecommendation(SwapContext calldata context) internal view virtual returns (AgentResult memory);

    // ============ Admin Functions ============

    /// @notice Configure ERC-8004 identity
    /// @param _agentId The ERC-8004 identity token ID
    /// @param _identityRegistry The identity registry address
    function configureIdentity(uint256 _agentId, address _identityRegistry) external onlyOwner {
        agentId = _agentId;
        identityRegistry = _identityRegistry;
        emit IdentityConfigured(_agentId, _identityRegistry);
    }

    /// @notice Set agent active status
    /// @param _active Whether agent is active
    function setActive(bool _active) external onlyOwner {
        active = _active;
        emit AgentActivated(_active);
    }

    /// @notice Set agent confidence
    /// @param _confidence Confidence score (0-100)
    function setConfidence(uint8 _confidence) external onlyOwner {
        require(_confidence <= 100, "Invalid confidence");
        uint8 oldConfidence = confidence;
        confidence = _confidence;
        emit ConfidenceUpdated(oldConfidence, _confidence);
    }

    /// @notice Authorize a caller (executor, hook)
    /// @param caller The caller address
    /// @param authorized Whether to authorize
    function authorizeCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
        emit CallerAuthorized(caller, authorized);
    }

    // ============ View Helpers ============

    /// @notice Get pool liquidity
    function _getLiquidity(PoolKey calldata key) internal view returns (uint128) {
        PoolId poolId = key.toId();
        return poolManager.getLiquidity(poolId);
    }

    /// @notice Get pool sqrt price
    function _getSqrtPrice(PoolKey calldata key) internal view returns (uint160) {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        return sqrtPriceX96;
    }
}
