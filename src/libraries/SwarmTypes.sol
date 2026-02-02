// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

library SwarmTypes {
    struct IntentParams {
        Currency currencyIn;
        Currency currencyOut;
        uint128 amountIn;
        uint128 amountOutMin;
        uint64 deadline;
        uint16 mevFeeBps;
        uint16 treasuryBps;
        uint16 lpShareBps; // Percentage of captured MEV to donate to LPs (basis points, e.g., 8000 = 80%)
    }

    struct Intent {
        address requester;
        Currency currencyIn;
        Currency currencyOut;
        uint128 amountIn;
        uint128 amountOutMin;
        uint64 deadline;
        uint16 mevFeeBps;
        uint16 treasuryBps;
        uint16 lpShareBps;
        bool executed;
    }

    struct Proposal {
        uint256 agentId;
        uint256 candidateId;
        int256 score;
        bytes data;
        uint64 timestamp;
    }
}
