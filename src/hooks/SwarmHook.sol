// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

import {AgentExecutor} from "../agents/AgentExecutor.sol";
import {ISwarmAgent, SwapContext, AgentType} from "../interfaces/ISwarmAgent.sol";
import {IOracleRegistry} from "../interfaces/IChainlinkOracle.sol";
import {LPFeeAccumulator} from "../LPFeeAccumulator.sol";

/// @title SwarmHook
/// @notice Thin hook that ONLY delegates to agents via AgentExecutor
/// @dev All logic lives in agents - this hook just orchestrates
/// @dev Admin can hot-swap agents without redeploying
contract SwarmHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // ============ Constants ============

    /// @notice Price precision
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @notice Maximum dynamic fee (1%)
    uint24 public constant MAX_DYNAMIC_FEE = 10000;

    // ============ State Variables ============

    /// @notice Agent executor - routes calls to appropriate agents
    AgentExecutor public agentExecutor;

    /// @notice Oracle registry for price feeds
    IOracleRegistry public oracleRegistry;

    /// @notice LP Fee accumulator
    LPFeeAccumulator public lpFeeAccumulator;

    /// @notice Contract owner
    address public immutable owner;

    /// @notice Accumulated tokens per pool (for tracking)
    mapping(PoolId => mapping(Currency => uint256)) public accumulatedTokens;

    // ============ Events ============

    event AgentExecutorSet(address executor);
    event OracleRegistrySet(address registry);
    event LPFeeAccumulatorSet(address accumulator);
    event ArbitrageCaptured(
        PoolId indexed poolId,
        Currency indexed currency,
        uint256 amount
    );
    event FeeOverrideApplied(PoolId indexed poolId, uint24 fee);
    event BackrunOpportunityRecorded(PoolId indexed poolId, uint256 amount);

    // ============ Errors ============

    error NotOwner();
    error NoAgentExecutor();
    error InvalidAddress();

    // ============ Modifiers ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ============ Constructor ============

    constructor(
        IPoolManager _poolManager,
        address _owner
    ) BaseHook(_poolManager) {
        owner = _owner;
    }

    // ============ Hook Permissions ============

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Core Hook Functions ============

    /// @notice Called before a swap - delegates to agents for decision
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Skip exact output swaps for simplicity
        if (params.amountSpecified >= 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // If no executor, pass through
        if (address(agentExecutor) == address(0)) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Build context for agents
        SwapContext memory context = _buildContext(key, params);

        // Delegate to agent executor
        AgentExecutor.BeforeSwapResult memory result = agentExecutor.processBeforeSwap(context);

        // Handle arbitrage capture
        if (result.shouldCapture && result.captureAmount > 0) {
            return _executeCapture(key, params, result.captureAmount);
        }

        // Handle fee override
        if (result.useOverrideFee && result.overrideFee > 0) {
            uint24 fee = result.overrideFee;
            if (fee > MAX_DYNAMIC_FEE) fee = MAX_DYNAMIC_FEE;
            
            emit FeeOverrideApplied(key.toId(), fee);
            
            uint24 overrideFee = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, overrideFee);
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @notice Called after a swap - delegates to agents for backrun analysis
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, int128) {
        // If no executor, pass through
        if (address(agentExecutor) == address(0)) {
            return (IHooks.afterSwap.selector, 0);
        }

        // Build context
        SwapContext memory context = _buildContext(key, params);

        // Get new pool price after swap
        uint160 sqrtPriceX96 = _getSqrtPrice(key);
        uint256 newPoolPrice = _sqrtPriceToPrice(sqrtPriceX96);

        // Delegate to agent executor for backrun analysis
        AgentExecutor.AfterSwapResult memory result = agentExecutor.processAfterSwap(
            context,
            newPoolPrice
        );

        if (result.shouldBackrun && result.backrunAmount > 0) {
            emit BackrunOpportunityRecorded(key.toId(), result.backrunAmount);
        }

        return (IHooks.afterSwap.selector, 0);
    }

    // ============ Internal Functions ============

    /// @notice Build swap context for agents
    function _buildContext(
        PoolKey calldata key,
        SwapParams calldata params
    ) internal view returns (SwapContext memory context) {
        PoolId poolId = key.toId();
        
        // Get pool state
        uint160 sqrtPriceX96 = _getSqrtPrice(key);
        uint128 liquidity = _getLiquidity(key);
        uint256 poolPrice = _sqrtPriceToPrice(sqrtPriceX96);

        // Get oracle price
        (uint256 oraclePrice, uint256 oracleConfidence) = _getOraclePrice(key);

        context = SwapContext({
            poolKey: key,
            poolId: poolId,
            params: params,
            poolPrice: poolPrice,
            oraclePrice: oraclePrice,
            oracleConfidence: oracleConfidence,
            liquidity: liquidity,
            hookData: ""
        });
    }

    /// @notice Execute arbitrage capture
    function _executeCapture(
        PoolKey calldata key,
        SwapParams calldata params,
        uint256 captureAmount
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        PoolId poolId = key.toId();

        // Take from pool
        poolManager.take(inputCurrency, address(this), captureAmount);
        accumulatedTokens[poolId][inputCurrency] += captureAmount;

        // Send to LP accumulator if configured
        if (address(lpFeeAccumulator) != address(0)) {
            _sendToAccumulator(poolId, inputCurrency, captureAmount);
        }

        emit ArbitrageCaptured(poolId, inputCurrency, captureAmount);

        // Create delta
        BeforeSwapDelta delta = params.zeroForOne
            ? toBeforeSwapDelta(int128(int256(captureAmount)), 0)
            : toBeforeSwapDelta(0, int128(int256(captureAmount)));

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    /// @notice Send captured tokens to LP accumulator
    function _sendToAccumulator(
        PoolId poolId,
        Currency currency,
        uint256 amount
    ) internal {
        if (currency.isAddressZero()) {
            (bool success,) = address(lpFeeAccumulator).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20Minimal(Currency.unwrap(currency)).transfer(
                address(lpFeeAccumulator),
                amount
            );
        }
        lpFeeAccumulator.accumulateFees(poolId, currency, amount);
    }

    /// @notice Get oracle price for pool
    function _getOraclePrice(
        PoolKey calldata key
    ) internal view returns (uint256 price, uint256 confidence) {
        if (address(oracleRegistry) == address(0)) {
            return (0, 0);
        }

        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);

        try oracleRegistry.getLatestPrice(token0, token1) returns (uint256 _price, uint256) {
            price = _price;
            confidence = _price * 50 / 10000; // 0.5% default confidence
        } catch {
            return (0, 0);
        }
    }

    /// @notice Get pool sqrt price
    function _getSqrtPrice(PoolKey calldata key) internal view returns (uint160) {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        return sqrtPriceX96;
    }

    /// @notice Get pool liquidity
    function _getLiquidity(PoolKey calldata key) internal view returns (uint128) {
        PoolId poolId = key.toId();
        return poolManager.getLiquidity(poolId);
    }

    /// @notice Convert sqrt price to regular price
    function _sqrtPriceToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        return (sqrtPrice * sqrtPrice * PRICE_PRECISION) >> 192;
    }

    // ============ Admin Functions ============

    /// @notice Set the agent executor
    function setAgentExecutor(address _executor) external onlyOwner {
        if (_executor == address(0)) revert InvalidAddress();
        agentExecutor = AgentExecutor(_executor);
        emit AgentExecutorSet(_executor);
    }

    /// @notice Set the oracle registry
    function setOracleRegistry(address _registry) external onlyOwner {
        oracleRegistry = IOracleRegistry(_registry);
        emit OracleRegistrySet(_registry);
    }

    /// @notice Set the LP fee accumulator
    function setLPFeeAccumulator(address _accumulator) external onlyOwner {
        if (_accumulator == address(0)) revert InvalidAddress();
        lpFeeAccumulator = LPFeeAccumulator(payable(_accumulator));
        emit LPFeeAccumulatorSet(_accumulator);
    }

    // ============ View Functions ============

    /// @notice Get accumulated tokens for a pool
    function getAccumulatedTokens(
        PoolId poolId,
        Currency currency
    ) external view returns (uint256) {
        return accumulatedTokens[poolId][currency];
    }

    /// @notice Get current agents
    function getAgents() external view returns (address[5] memory) {
        if (address(agentExecutor) == address(0)) {
            return [address(0), address(0), address(0), address(0), address(0)];
        }
        return agentExecutor.getAllAgents();
    }

    // ============ Receive ETH ============

    receive() external payable {}
}
