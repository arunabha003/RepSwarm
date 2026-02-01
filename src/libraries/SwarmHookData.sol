// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SwarmHookData {
    struct Payload {
        uint256 intentId;
        uint256 agentId;
        address treasury;
        uint16 treasuryBps;
        uint24 mevFee;
    }

    function encode(Payload memory payload) internal pure returns (bytes memory) {
        return abi.encode(payload);
    }

    function decode(bytes calldata data) internal pure returns (Payload memory) {
        return abi.decode(data, (Payload));
    }
}
