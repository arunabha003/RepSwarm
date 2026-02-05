// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {AgentExecutor} from "../src/agents/AgentExecutor.sol";
import {AgentType, SwapContext, AgentResult, IArbitrageAgent} from "../src/interfaces/ISwarmAgent.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract RevertingArbAgent is IArbitrageAgent {
    function agentType() external pure returns (AgentType) {
        return AgentType.ARBITRAGE;
    }

    function getAgentId() external pure returns (uint256) {
        return 1;
    }

    function execute(SwapContext calldata) external pure returns (AgentResult memory) {
        revert("revert execute");
    }

    function getRecommendation(SwapContext calldata) external pure returns (AgentResult memory result) {
        result.agentType = AgentType.ARBITRAGE;
    }

    function isActive() external pure returns (bool) {
        return true;
    }

    function getConfidence() external pure returns (uint8) {
        return 80;
    }

    function analyzeArbitrage(SwapContext calldata) external pure returns (ArbitrageResult memory) {
        revert("revert analyze");
    }
}

contract BackupArbAgent is IArbitrageAgent {
    function agentType() external pure returns (AgentType) {
        return AgentType.ARBITRAGE;
    }

    function getAgentId() external pure returns (uint256) {
        return 2;
    }

    function execute(SwapContext calldata) external pure returns (AgentResult memory result) {
        result.agentType = AgentType.ARBITRAGE;
        result.shouldAct = true;
        result.value = 123;
        result.success = true;
    }

    function getRecommendation(SwapContext calldata) external pure returns (AgentResult memory result) {
        result.agentType = AgentType.ARBITRAGE;
        result.shouldAct = true;
        result.value = 123;
        result.success = true;
    }

    function isActive() external pure returns (bool) {
        return true;
    }

    function getConfidence() external pure returns (uint8) {
        return 80;
    }

    function analyzeArbitrage(SwapContext calldata) external pure returns (ArbitrageResult memory r) {
        r.shouldCapture = true;
        r.hookShare = 123;
        r.arbitrageAmount = 123;
        r.divergenceBps = 100;
    }
}

contract AgentExecutorFailoverTest is Test {
    AgentExecutor internal executor;

    function setUp() public {
        executor = new AgentExecutor();
        executor.authorizeHook(address(this), true);
    }

    function test_Failover_PrimaryReverts_BackupCaptures() public {
        RevertingArbAgent primary = new RevertingArbAgent();
        BackupArbAgent backup = new BackupArbAgent();

        executor.registerAgent(AgentType.ARBITRAGE, address(primary));
        executor.setBackupAgent(AgentType.ARBITRAGE, address(backup));

        // Minimal context; backup agent ignores it.
        PoolKey memory key;
        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: -int256(1), sqrtPriceLimitX96: 0});
        SwapContext memory ctx = SwapContext({
            poolKey: key,
            poolId: PoolId.wrap(bytes32(uint256(1))),
            params: params,
            poolPrice: 0,
            oraclePrice: 0,
            oracleConfidence: 0,
            liquidity: 0,
            hookData: ""
        });

        AgentExecutor.BeforeSwapResult memory r = executor.processBeforeSwap(ctx);
        assertTrue(r.shouldCapture, "should capture via backup");
        assertEq(r.captureAmount, 123, "capture amount should come from backup");
    }
}
