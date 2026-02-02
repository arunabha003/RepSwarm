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

abstract contract SwarmAgentBase is IRouteAgent {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    error NoCandidates();

    ISwarmCoordinator public immutable coordinator;
    IPoolManager public immutable poolManager;

    constructor(ISwarmCoordinator coordinator_, IPoolManager poolManager_) {
        coordinator = coordinator_;
        poolManager = poolManager_;
    }

    function propose(uint256 intentId) external override returns (uint256 candidateId, int256 score) {
        ISwarmCoordinator.IntentView memory intent = coordinator.getIntent(intentId);
        uint256 candidateCount = coordinator.getCandidateCount(intentId);
        if (candidateCount == 0) revert NoCandidates();

        bool hasBest;
        int256 bestScore;

        for (uint256 i = 0; i < candidateCount; i++) {
            PathKey[] memory path = _loadPath(intentId, i);
            int256 candidateScore = _score(intent, path);
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
