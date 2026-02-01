// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

interface ISwarmCoordinator {
    struct IntentView {
        address requester;
        Currency currencyIn;
        Currency currencyOut;
        uint128 amountIn;
        uint128 amountOutMin;
        uint64 deadline;
        uint16 mevFeeBps;
        uint16 treasuryBps;
        bool executed;
    }

    function getIntent(uint256 intentId) external view returns (IntentView memory);
    function getCandidateCount(uint256 intentId) external view returns (uint256);
    function getCandidatePath(uint256 intentId, uint256 candidateId) external view returns (bytes memory);
    function submitProposal(uint256 intentId, uint256 candidateId, int256 score, bytes calldata data) external;
}
