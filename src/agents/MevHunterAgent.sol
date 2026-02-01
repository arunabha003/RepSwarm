// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SwarmAgentBase} from "./SwarmAgentBase.sol";
import {ISwarmCoordinator} from "../interfaces/ISwarmCoordinator.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract MevHunterAgent is SwarmAgentBase {
    uint256 private constant LIQUIDITY_WEIGHT = 1e12;

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
            (, uint24 lpFee, uint128 liquidity) = _poolMetrics(path[i], current);
            int256 feeComponent = int256(uint256(lpFee));
            int256 liquidityComponent = int256(uint256(liquidity) / LIQUIDITY_WEIGHT);
            score += feeComponent - liquidityComponent;
            current = path[i].intermediateCurrency;
        }

        return score;
    }
}
