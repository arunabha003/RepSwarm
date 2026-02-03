// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";

import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {SwarmTypes} from "../src/libraries/SwarmTypes.sol";

/// @title CreateIntent
/// @notice CLI helper to create swap intents
contract CreateIntent is Script {
    function run() external {
        // Load parameters from environment
        address coordinatorAddr = vm.envAddress("COORDINATOR");
        address tokenIn = vm.envAddress("TOKEN_IN");
        address tokenOut = vm.envAddress("TOKEN_OUT");
        uint128 amountIn = uint128(vm.envUint("AMOUNT_IN"));
        uint128 minOut = uint128(vm.envOr("MIN_OUT", uint256(0)));
        uint16 mevFeeBps = uint16(vm.envOr("MEV_FEE_BPS", uint256(100)));
        uint16 treasuryBps = uint16(vm.envOr("TREASURY_BPS", uint256(50)));
        uint16 lpShareBps = uint16(vm.envOr("LP_SHARE_BPS", uint256(8000)));
        
        // Path parameters
        address hookAddr = vm.envAddress("HOOK");
        uint24 fee = uint24(vm.envOr("POOL_FEE", uint256(3000)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        
        console2.log("=== Creating Swap Intent ===");
        console2.log("Coordinator:", coordinatorAddr);
        console2.log("Token In:", tokenIn);
        console2.log("Token Out:", tokenOut);
        console2.log("Amount In:", amountIn);
        console2.log("Min Out:", minOut);
        console2.log("MEV Fee:", mevFeeBps, "bps");
        console2.log("Treasury:", treasuryBps, "bps");
        console2.log("LP Share:", lpShareBps, "bps");
        
        vm.startBroadcast(deployerKey);
        
        SwarmCoordinator coordinator = SwarmCoordinator(payable(coordinatorAddr));
        
        // Build intent params
        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: Currency.wrap(tokenIn),
            currencyOut: Currency.wrap(tokenOut),
            amountIn: amountIn,
            amountOutMin: minOut,
            deadline: 0, // No deadline
            mevFeeBps: mevFeeBps,
            treasuryBps: treasuryBps,
            lpShareBps: lpShareBps
        });
        
        // Build path - single hop direct swap
        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(tokenOut),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddr),
            hookData: bytes("")
        });
        
        // Encode path for storage
        bytes[] memory candidatePaths = new bytes[](1);
        candidatePaths[0] = abi.encode(path);
        
        // Create intent
        uint256 intentId = coordinator.createIntent(params, candidatePaths);
        
        console2.log("\n=== Intent Created ===");
        console2.log("Intent ID:", intentId);
        
        vm.stopBroadcast();
    }
}

/// @title SubmitProposal
/// @notice CLI helper for agents to submit proposals
contract SubmitProposal is Script {
    function run() external {
        address coordinatorAddr = vm.envAddress("COORDINATOR");
        uint256 intentId = vm.envUint("INTENT_ID");
        uint256 candidateId = vm.envOr("CANDIDATE_ID", uint256(0));
        int256 score = int256(vm.envOr("SCORE", uint256(100)));
        
        uint256 agentKey = vm.envUint("AGENT_KEY");
        address agent = vm.addr(agentKey);
        
        console2.log("=== Submitting Proposal ===");
        console2.log("Agent:", agent);
        console2.log("Intent ID:", intentId);
        console2.log("Candidate ID:", candidateId);
        console2.log("Score:", score);
        
        vm.startBroadcast(agentKey);
        
        SwarmCoordinator coordinator = SwarmCoordinator(payable(coordinatorAddr));
        coordinator.submitProposal(intentId, candidateId, score, bytes(""));
        
        console2.log("\n=== Proposal Submitted ===");
        
        vm.stopBroadcast();
    }
}

/// @title ExecuteIntent
/// @notice CLI helper to execute swap intents
contract ExecuteIntent is Script {
    function run() external {
        address coordinatorAddr = vm.envAddress("COORDINATOR");
        uint256 intentId = vm.envUint("INTENT_ID");
        
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        
        console2.log("=== Executing Intent ===");
        console2.log("Intent ID:", intentId);
        
        vm.startBroadcast(deployerKey);
        
        SwarmCoordinator coordinator = SwarmCoordinator(payable(coordinatorAddr));
        
        // Execute the intent
        coordinator.executeIntent{value: 0}(intentId);
        
        console2.log("\n=== Intent Executed ===");
        
        vm.stopBroadcast();
    }
}
