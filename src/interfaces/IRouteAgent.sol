// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRouteAgent {
    function propose(uint256 intentId) external returns (uint256 candidateId, int256 score);
}
