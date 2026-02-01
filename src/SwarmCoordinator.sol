// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey, PathKeyLibrary} from "v4-periphery/src/libraries/PathKey.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {V4Router} from "v4-periphery/src/V4Router.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {ReentrancyLock} from "v4-periphery/src/base/ReentrancyLock.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

import {SwarmTypes} from "./libraries/SwarmTypes.sol";
import {SwarmHookData} from "./libraries/SwarmHookData.sol";
import {ISwarmCoordinator} from "./interfaces/ISwarmCoordinator.sol";

interface IIdentityRegistry {
    function getAgentWallet(uint256 agentId) external view returns (address);
}

interface IReputationRegistry {
    function getSummary(uint256 agentId, address[] calldata clientAddresses, string calldata tag1, string calldata tag2)
        external
        view
        returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);
}

contract SwarmCoordinator is V4Router, ReentrancyLock, Ownable, ISwarmCoordinator {
    using PathKeyLibrary for PathKey;

    error DeadlinePassed(uint256 deadline);
    error IntentAlreadyExecuted(uint256 intentId);
    error NoCandidates();
    error InvalidCandidate(uint256 candidateId);
    error InvalidBps(uint256 value);
    error NoProposals(uint256 intentId);
    error UnauthorizedAgent(address agent);
    error ReputationTooLow(int128 value, uint8 decimals);
    error InvalidPath();

    struct AgentConfig {
        uint256 agentId;
        bool active;
    }

    uint256 public nextIntentId;

    mapping(uint256 => SwarmTypes.Intent) private intents;
    mapping(uint256 => bytes[]) private intentCandidates;
    mapping(uint256 => mapping(address => SwarmTypes.Proposal)) private proposals;
    mapping(uint256 => address[]) private proposalAgents;
    mapping(uint256 => mapping(address => bool)) private hasProposed;

    mapping(address => AgentConfig) public agents;

    address public treasury;
    address public identityRegistry;
    address public reputationRegistry;
    string public reputationTag1;
    string public reputationTag2;
    address[] public reputationClients;
    int256 public minReputationWad;

    event IntentCreated(uint256 indexed intentId, address indexed requester, uint256 candidateCount);
    event ProposalSubmitted(
        uint256 indexed intentId,
        address indexed agent,
        uint256 indexed agentId,
        uint256 candidateId,
        int256 score
    );
    event IntentExecuted(uint256 indexed intentId, address indexed executor, uint256 candidateId);
    event AgentRegistered(address indexed agent, uint256 indexed agentId, bool active);
    event ReputationConfigUpdated(address registry, string tag1, string tag2, int256 minReputationWad);
    event ReputationClientsUpdated(uint256 count);
    event TreasuryUpdated(address treasury);

    constructor(
        IPoolManager poolManager,
        address treasury_,
        address identityRegistry_,
        address reputationRegistry_
    ) V4Router(poolManager) Ownable(msg.sender) {
        treasury = treasury_;
        identityRegistry = identityRegistry_;
        reputationRegistry = reputationRegistry_;
    }

    receive() external payable {}

    function setTreasury(address treasury_) external onlyOwner {
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setReputationConfig(
        address reputationRegistry_,
        string calldata tag1,
        string calldata tag2,
        int256 minReputationWad_
    ) external onlyOwner {
        reputationRegistry = reputationRegistry_;
        reputationTag1 = tag1;
        reputationTag2 = tag2;
        minReputationWad = minReputationWad_;
        emit ReputationConfigUpdated(reputationRegistry_, tag1, tag2, minReputationWad_);
    }

    function setReputationClients(address[] calldata clients) external onlyOwner {
        delete reputationClients;
        for (uint256 i = 0; i < clients.length; i++) {
            reputationClients.push(clients[i]);
        }
        emit ReputationClientsUpdated(clients.length);
    }

    function setIdentityRegistry(address identityRegistry_) external onlyOwner {
        identityRegistry = identityRegistry_;
    }

    function registerAgent(address agent, uint256 agentId, bool active) external onlyOwner {
        agents[agent] = AgentConfig({agentId: agentId, active: active});
        emit AgentRegistered(agent, agentId, active);
    }

    function createIntent(SwarmTypes.IntentParams calldata params, bytes[] calldata candidatePaths)
        external
        returns (uint256 intentId)
    {
        if (params.deadline != 0 && block.timestamp > params.deadline) {
            revert DeadlinePassed(params.deadline);
        }
        if (candidatePaths.length == 0) revert NoCandidates();
        if (params.treasuryBps > 10_000) revert InvalidBps(params.treasuryBps);
        if (params.mevFeeBps > 10_000) revert InvalidBps(params.mevFeeBps);

        intentId = nextIntentId++;
        intents[intentId] = SwarmTypes.Intent({
            requester: msg.sender,
            currencyIn: params.currencyIn,
            currencyOut: params.currencyOut,
            amountIn: params.amountIn,
            amountOutMin: params.amountOutMin,
            deadline: params.deadline,
            mevFeeBps: params.mevFeeBps,
            treasuryBps: params.treasuryBps,
            executed: false
        });

        for (uint256 i = 0; i < candidatePaths.length; i++) {
            intentCandidates[intentId].push(candidatePaths[i]);
        }

        emit IntentCreated(intentId, msg.sender, candidatePaths.length);
    }

    function submitProposal(uint256 intentId, uint256 candidateId, int256 score, bytes calldata data)
        external
        override
    {
        SwarmTypes.Intent storage intent = intents[intentId];
        if (intent.executed) revert IntentAlreadyExecuted(intentId);
        if (intent.deadline != 0 && block.timestamp > intent.deadline) revert DeadlinePassed(intent.deadline);
        if (candidateId >= intentCandidates[intentId].length) revert InvalidCandidate(candidateId);

        AgentConfig memory config = agents[msg.sender];
        if (!config.active || config.agentId == 0) revert UnauthorizedAgent(msg.sender);
        _requireIdentity(msg.sender, config.agentId);
        _requireReputation(config.agentId);

        if (!hasProposed[intentId][msg.sender]) {
            proposalAgents[intentId].push(msg.sender);
            hasProposed[intentId][msg.sender] = true;
        }

        proposals[intentId][msg.sender] = SwarmTypes.Proposal({
            agentId: config.agentId,
            candidateId: candidateId,
            score: score,
            data: data,
            timestamp: uint64(block.timestamp)
        });

        emit ProposalSubmitted(intentId, msg.sender, config.agentId, candidateId, score);
    }

    function executeIntent(uint256 intentId) external payable isNotLocked {
        SwarmTypes.Intent storage intent = intents[intentId];
        if (intent.executed) revert IntentAlreadyExecuted(intentId);
        if (intent.deadline != 0 && block.timestamp > intent.deadline) revert DeadlinePassed(intent.deadline);

        (uint256 candidateId, uint256 agentId) = _selectBestCandidate(intentId);
        bytes memory pathData = intentCandidates[intentId][candidateId];
        PathKey[] memory path = abi.decode(pathData, (PathKey[]));
        if (path.length == 0) revert InvalidPath();

        _validatePath(intent.currencyIn, intent.currencyOut, path);

        uint24 mevFee = uint24(uint256(intent.mevFeeBps) * 100);
        SwarmHookData.Payload memory payload = SwarmHookData.Payload({
            intentId: intentId,
            agentId: agentId,
            treasury: treasury,
            treasuryBps: intent.treasuryBps,
            mevFee: mevFee
        });

        for (uint256 i = 0; i < path.length; i++) {
            path[i].hookData = SwarmHookData.encode(payload);
        }

        bytes memory actions = abi.encodePacked(
            bytes1(uint8(Actions.SWAP_EXACT_IN)),
            bytes1(uint8(Actions.SETTLE)),
            bytes1(uint8(Actions.TAKE))
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: intent.currencyIn,
                path: path,
                maxHopSlippage: new uint256[](0),
                amountIn: intent.amountIn,
                amountOutMinimum: intent.amountOutMin
            })
        );
        params[1] = abi.encode(intent.currencyIn, uint256(ActionConstants.OPEN_DELTA), true);
        params[2] = abi.encode(intent.currencyOut, ActionConstants.MSG_SENDER, uint256(ActionConstants.OPEN_DELTA));

        _executeActions(abi.encode(actions, params));

        intent.executed = true;
        emit IntentExecuted(intentId, msg.sender, candidateId);
    }

    function getIntent(uint256 intentId) external view override returns (IntentView memory) {
        SwarmTypes.Intent storage intent = intents[intentId];
        return IntentView({
            requester: intent.requester,
            currencyIn: intent.currencyIn,
            currencyOut: intent.currencyOut,
            amountIn: intent.amountIn,
            amountOutMin: intent.amountOutMin,
            deadline: intent.deadline,
            mevFeeBps: intent.mevFeeBps,
            treasuryBps: intent.treasuryBps,
            executed: intent.executed
        });
    }

    function getCandidateCount(uint256 intentId) external view override returns (uint256) {
        return intentCandidates[intentId].length;
    }

    function getCandidatePath(uint256 intentId, uint256 candidateId) external view override returns (bytes memory) {
        return intentCandidates[intentId][candidateId];
    }

    function getProposal(uint256 intentId, address agent) external view returns (SwarmTypes.Proposal memory) {
        return proposals[intentId][agent];
    }

    function getProposalAgents(uint256 intentId) external view returns (address[] memory) {
        return proposalAgents[intentId];
    }

    function msgSender() public view override returns (address) {
        return _getLocker();
    }

    function _pay(Currency currency, address payer, uint256 amount) internal override {
        if (amount == 0) return;
        if (payer == address(this)) {
            currency.transfer(address(poolManager), amount);
        } else {
            IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
        }
    }

    function _selectBestCandidate(uint256 intentId) internal view returns (uint256 bestCandidate, uint256 agentId) {
        address[] memory agentsList = proposalAgents[intentId];
        if (agentsList.length == 0) revert NoProposals(intentId);

        uint256 candidateCount = intentCandidates[intentId].length;
        if (candidateCount == 0) revert NoCandidates();

        bool hasBest;
        int256 bestScore;

        for (uint256 candidateId = 0; candidateId < candidateCount; candidateId++) {
            int256 totalScore;
            uint256 votes;
            uint256 firstAgentId;
            for (uint256 i = 0; i < agentsList.length; i++) {
                SwarmTypes.Proposal storage proposal = proposals[intentId][agentsList[i]];
                if (proposal.candidateId != candidateId) continue;
                totalScore += proposal.score;
                votes++;
                if (firstAgentId == 0) firstAgentId = proposal.agentId;
            }
            if (votes == 0) continue;
            int256 avgScore = totalScore / int256(votes);
            if (!hasBest || avgScore < bestScore) {
                hasBest = true;
                bestScore = avgScore;
                bestCandidate = candidateId;
                agentId = firstAgentId;
            }
        }

        if (!hasBest) revert NoProposals(intentId);
    }

    function _validatePath(Currency currencyIn, Currency currencyOut, PathKey[] memory path) internal pure {
        Currency current = currencyIn;
        for (uint256 i = 0; i < path.length; i++) {
            PathKey memory step = path[i];
            step.getPoolAndSwapDirection(current);
            current = step.intermediateCurrency;
        }
        if (current != currencyOut) revert InvalidPath();
    }

    function _requireIdentity(address agent, uint256 agentId) internal view {
        if (identityRegistry == address(0)) return;
        address wallet = IIdentityRegistry(identityRegistry).getAgentWallet(agentId);
        if (wallet != agent) revert UnauthorizedAgent(agent);
    }

    function _requireReputation(uint256 agentId) internal view {
        if (reputationRegistry == address(0)) return;
        if (reputationClients.length == 0) return;
        (uint64 count, int128 value, uint8 decimals) =
            IReputationRegistry(reputationRegistry).getSummary(agentId, reputationClients, reputationTag1, reputationTag2);
        if (count == 0) revert ReputationTooLow(0, 0);

        int256 normalized = _normalize(value, decimals);
        if (normalized < minReputationWad) revert ReputationTooLow(value, decimals);
    }

    function _normalize(int128 value, uint8 decimals) internal pure returns (int256) {
        if (decimals == 18) return int256(value);
        if (decimals > 18) {
            uint256 shift = 10 ** uint256(decimals - 18);
            return int256(value) / int256(shift);
        }
        uint256 factor = 10 ** uint256(18 - decimals);
        return int256(value) * int256(factor);
    }
}
