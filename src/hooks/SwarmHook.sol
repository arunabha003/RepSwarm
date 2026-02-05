// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
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
import {SwarmHookData} from "../libraries/SwarmHookData.sol";
import {HookLib} from "../libraries/HookLib.sol";

interface IBackrunRecorder {
    function recordBackrunOpportunity(
        PoolKey calldata poolKey,
        uint256 targetPrice,
        uint256 currentPrice,
        uint256 backrunAmount,
        bool zeroForOne
    ) external;
}

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

    /// @notice Optional backrun recorder/executor (e.g., flash-loan backrunner keeper contract)
    address public backrunRecorder;

    /// @notice Contract owner
    address public immutable owner;

    /// @notice Accumulated tokens per pool (for tracking)
    mapping(PoolId => mapping(Currency => uint256)) public accumulatedTokens;

    /// @notice Track whether we've registered this pool key in the accumulator
    mapping(PoolId => bool) public accumulatorPoolKeyRegistered;

    // ============ Events ============

    event AgentExecutorSet(address executor);
    event OracleRegistrySet(address registry);
    event LPFeeAccumulatorSet(address accumulator);
    event BackrunRecorderSet(address recorder);
    event ArbitrageCaptured(PoolId indexed poolId, Currency indexed currency, uint256 amount);
    event FeeOverrideApplied(PoolId indexed poolId, uint24 fee);
    event BackrunOpportunityRecorded(PoolId indexed poolId, uint256 amount);
    event MevFeeTaken(PoolId indexed poolId, Currency indexed currency, uint256 amount, address treasury);

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

    constructor(IPoolManager _poolManager, address _owner) BaseHook(_poolManager) {
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
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Core Hook Functions ============

    /// @notice Called before a swap - delegates to agents for decision
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Skip exact output swaps for simplicity
        if (params.amountSpecified >= 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // If no executor, pass through
        if (address(agentExecutor) == address(0)) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        _maybeRegisterPoolKey(key);

        // Build context for agents
        SwapContext memory context = _buildContext(key, params, hookData);

        // Delegate to agent executor
        AgentExecutor.BeforeSwapResult memory result = agentExecutor.processBeforeSwap(context);

        // Handle arbitrage capture
        if (result.shouldCapture && result.captureAmount > 0) {
            return _executeCapture(key, params, result.captureAmount, hookData);
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
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // If no executor, pass through
        if (address(agentExecutor) == address(0)) {
            return (IHooks.afterSwap.selector, 0);
        }

        _maybeRegisterPoolKey(key);

        // Build context
        SwapContext memory context = _buildContext(key, params, hookData);

        // Get new pool price after swap
        uint160 sqrtPriceX96 = _getSqrtPrice(key);
        uint256 newPoolPrice = _sqrtPriceToPrice(sqrtPriceX96);

        // Delegate to agent executor for backrun analysis
        AgentExecutor.AfterSwapResult memory result = agentExecutor.processAfterSwap(context, newPoolPrice);

        if (result.shouldBackrun && result.backrunAmount > 0) {
            emit BackrunOpportunityRecorded(key.toId(), result.backrunAmount);
            if (backrunRecorder != address(0)) {
                // Record opportunity for off-chain keeper execution (or on-chain executor).
                IBackrunRecorder(backrunRecorder)
                    .recordBackrunOpportunity(
                        key, result.targetPrice, result.currentPrice, result.backrunAmount, result.zeroForOne
                    );
            }
        }

        int128 hookDeltaUnspecified = _takeMevFeeAfterSwap(key, params, delta, hookData);

        return (IHooks.afterSwap.selector, hookDeltaUnspecified);
    }

    // ============ Internal Functions ============

    /// @notice Build swap context for agents
    function _buildContext(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        view
        returns (SwapContext memory context)
    {
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
            hookData: hookData
        });
    }

    /// @notice Execute arbitrage capture
    function _executeCapture(
        PoolKey calldata key,
        SwapParams calldata params,
        uint256 captureAmount,
        bytes calldata hookData
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        Currency inputCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        PoolId poolId = key.toId();

        // Take from pool
        poolManager.take(inputCurrency, address(this), captureAmount);
        accumulatedTokens[poolId][inputCurrency] += captureAmount;

        (bool hasPayload, SwarmHookData.Payload memory payload) = _decodeHookData(hookData);

        // Distribute captured value using payload (if present). Default: all to LP accumulator.
        uint256 treasuryAmount = 0;
        uint256 lpAmount = captureAmount;
        address treasury = address(0);

        if (hasPayload) {
            treasury = payload.treasury;
            if (payload.treasuryBps > 0 && treasury != address(0)) {
                treasuryAmount = (captureAmount * uint256(payload.treasuryBps)) / 10_000;
            }

            if (payload.lpShareBps > 0) {
                lpAmount = (captureAmount * uint256(payload.lpShareBps)) / 10_000;
            } else {
                // If lpShareBps is unset, default the remainder (after treasury) to LPs.
                lpAmount = captureAmount - treasuryAmount;
            }
        }

        // Clamp so we never exceed captured amount; route any remainder to LPs.
        if (treasuryAmount > captureAmount) treasuryAmount = captureAmount;
        if (lpAmount + treasuryAmount > captureAmount) {
            lpAmount = captureAmount - treasuryAmount;
        } else {
            lpAmount += (captureAmount - treasuryAmount - lpAmount);
        }

        if (treasuryAmount > 0 && treasury != address(0)) {
            _sendToTreasury(inputCurrency, treasury, treasuryAmount);
        }

        // Send to LP accumulator if configured; otherwise leave in hook contract.
        if (lpAmount > 0 && address(lpFeeAccumulator) != address(0)) {
            _sendToAccumulator(poolId, inputCurrency, lpAmount);
        }

        emit ArbitrageCaptured(poolId, inputCurrency, captureAmount);

        // Charge the swapper by shrinking the amount that is actually swapped (exact input only).
        // The hook has already `take`n `captureAmount` of the input currency from the manager, and
        // this delta ensures the manager nets the swapper's original `amountSpecified` such that:
        // - `captureAmount` is diverted to the hook
        // - the remainder is swapped as usual
        BeforeSwapDelta delta = toBeforeSwapDelta(int128(int256(captureAmount)), 0);

        return (IHooks.beforeSwap.selector, delta, 0);
    }

    /// @notice Send captured tokens to LP accumulator
    function _sendToAccumulator(PoolId poolId, Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            (bool success,) = address(lpFeeAccumulator).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20Minimal(Currency.unwrap(currency)).transfer(address(lpFeeAccumulator), amount);
        }
        lpFeeAccumulator.accumulateFees(poolId, currency, amount);
    }

    function _sendToTreasury(Currency currency, address treasury, uint256 amount) internal {
        if (amount == 0) return;

        if (currency.isAddressZero()) {
            (bool success,) = treasury.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20Minimal(Currency.unwrap(currency)).transfer(treasury, amount);
        }
    }

    function _decodeHookData(bytes calldata hookData)
        internal
        pure
        returns (bool hasPayload, SwarmHookData.Payload memory payload)
    {
        if (hookData.length == 0) return (false, payload);
        // SwarmHookData.Payload is fully static => ABI-encoded length is fixed at 6 * 32 bytes.
        if (hookData.length != 192) return (false, payload);
        payload = abi.decode(hookData, (SwarmHookData.Payload));
        return (true, payload);
    }

    function _maybeRegisterPoolKey(PoolKey calldata key) internal {
        if (address(lpFeeAccumulator) == address(0)) return;

        PoolId poolId = key.toId();
        if (accumulatorPoolKeyRegistered[poolId]) return;

        // Best-effort: accumulator ignores duplicates; if this reverts, we don't want to brick swaps.
        try lpFeeAccumulator.registerPoolKey(key) {
            accumulatorPoolKeyRegistered[poolId] = true;
        } catch {}
    }

    /// @notice Collect a MEV fee in the unspecified currency (exact-input swaps only) using
    /// Uniswap v4's `afterSwapReturnDelta` accounting pattern.
    /// @dev Returns the hook delta for the unspecified currency.
    function _takeMevFeeAfterSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal returns (int128 hookDeltaUnspecified) {
        (bool hasPayload, SwarmHookData.Payload memory payload) = _decodeHookData(hookData);
        if (!hasPayload) return 0;

        // `mevFee` is in Uniswap units (fee / 1e6). Example: 3000 = 0.30%.
        uint24 mevFee = payload.mevFee;
        if (mevFee == 0) return 0;

        // Only support exact input swaps (same as `_beforeSwap`).
        if (params.amountSpecified >= 0) return 0;

        PoolId poolId = key.toId();
        bool outputIsToken0 = params.zeroForOne ? false : true;
        int256 outputAmount = outputIsToken0 ? delta.amount0() : delta.amount1();
        if (outputAmount <= 0) return 0;

        uint256 amountOut = uint256(outputAmount);
        uint256 feeAmount = (amountOut * uint256(mevFee)) / 1_000_000;
        if (feeAmount == 0) return 0;

        require(feeAmount <= ((uint256(1) << 127) - 1), "fee too large");

        Currency feeCurrency = outputIsToken0 ? key.currency0 : key.currency1;

        // Pull the fee to the hook; returning `hookDeltaUnspecified` reduces the output to the user.
        poolManager.take(feeCurrency, address(this), feeAmount);

        uint256 treasuryAmount = 0;
        if (payload.treasury != address(0) && payload.treasuryBps > 0) {
            treasuryAmount = (feeAmount * uint256(payload.treasuryBps)) / 10_000;
        }

        uint256 lpAmount = feeAmount - treasuryAmount;

        if (treasuryAmount > 0 && payload.treasury != address(0)) {
            _sendToTreasury(feeCurrency, payload.treasury, treasuryAmount);
        }

        if (lpAmount > 0 && address(lpFeeAccumulator) != address(0)) {
            _sendToAccumulator(poolId, feeCurrency, lpAmount);
        } else if (lpAmount > 0 && payload.treasury != address(0)) {
            _sendToTreasury(feeCurrency, payload.treasury, lpAmount);
        }

        emit MevFeeTaken(poolId, feeCurrency, feeAmount, payload.treasury);
        hookDeltaUnspecified = int128(int256(feeAmount));
    }

    /// @notice Get oracle price for pool
    function _getOraclePrice(PoolKey calldata key) internal view returns (uint256 price, uint256 confidence) {
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
        return HookLib.sqrtPriceToPrice(sqrtPriceX96);
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

    /// @notice Set optional backrun recorder contract
    function setBackrunRecorder(address _recorder) external onlyOwner {
        backrunRecorder = _recorder;
        emit BackrunRecorderSet(_recorder);
    }

    // ============ View Functions ============

    /// @notice Get accumulated tokens for a pool
    function getAccumulatedTokens(PoolId poolId, Currency currency) external view returns (uint256) {
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
