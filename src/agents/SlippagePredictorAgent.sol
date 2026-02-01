// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SwarmAgentBase} from "./SwarmAgentBase.sol";
import {ISwarmCoordinator} from "../interfaces/ISwarmCoordinator.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract SlippagePredictorAgent is SwarmAgentBase {
    uint256 private constant SCALE = 1e18;

    constructor(ISwarmCoordinator coordinator_, IPoolManager poolManager_) SwarmAgentBase(coordinator_, poolManager_) {}

    function _score(ISwarmCoordinator.IntentView memory intent, PathKey[] memory path)
        internal
        view
        override
        returns (int256)
    {
        Currency current = intent.currencyIn;
        int256 score;

        for (uint256 i = 0; i < path.length; i++) {
            (, , uint128 liquidity) = _poolMetrics(path[i], current);
            uint256 penalty = SCALE / (uint256(liquidity) + 1);
            score += int256(penalty);
            current = path[i].intermediateCurrency;
        }

        return score;
    }
}
