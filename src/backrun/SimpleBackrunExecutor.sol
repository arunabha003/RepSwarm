// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// @title SimpleBackrunExecutor
/// @notice Executes MEV backruns using contract-held capital (simpler than flash loans)
/// @dev Suitable for testing and lower capital operations
contract SimpleBackrunExecutor is IUnlockCallback, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    // ============ Constants ============
    
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant BASIS_POINTS = 10000;

    // ============ State Variables ============
    
    IPoolManager public immutable poolManager;
    
    /// @notice Authorized bots/keepers
    mapping(address => bool) public keepers;
    
    /// @notice Capital deposited per token
    mapping(address => uint256) public capitalDeposited;
    
    /// @notice Total profits earned per pool
    mapping(PoolId => uint256) public poolProfits;
    
    /// @notice Treasury for accumulated profits
    address public treasury;
    
    /// @notice Profit share to keeper (rest to treasury)
    uint256 public keeperShareBps = 2000; // 20%

    // ============ Events ============
    
    event CapitalDeposited(address indexed token, uint256 amount, address depositor);
    event CapitalWithdrawn(address indexed token, uint256 amount, address recipient);
    event BackrunExecuted(
        PoolId indexed poolId, 
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut, 
        uint256 profit,
        address keeper
    );
    event KeeperUpdated(address indexed keeper, bool active);
    event TreasuryUpdated(address indexed newTreasury);

    // ============ Errors ============
    
    error NotKeeper();
    error InsufficientCapital();
    error UnprofitableBackrun();
    error InvalidAmount();

    // ============ Constructor ============
    
    constructor(IPoolManager _poolManager, address _treasury) Ownable(msg.sender) {
        poolManager = _poolManager;
        treasury = _treasury != address(0) ? _treasury : msg.sender;
        keepers[msg.sender] = true;
    }

    // ============ Modifiers ============
    
    modifier onlyKeeper() {
        if (!keepers[msg.sender]) revert NotKeeper();
        _;
    }

    // ============ Capital Management ============
    
    /// @notice Deposit capital for backrun operations
    function depositCapital(address token, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        capitalDeposited[token] += amount;
        
        emit CapitalDeposited(token, amount, msg.sender);
    }
    
    /// @notice Withdraw capital (owner only)
    function withdrawCapital(address token, uint256 amount) external onlyOwner {
        if (amount > capitalDeposited[token]) revert InsufficientCapital();
        
        capitalDeposited[token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit CapitalWithdrawn(token, amount, msg.sender);
    }

    // ============ Backrun Execution ============
    
    /// @notice Execute an atomic backrun swap
    /// @param key The pool to backrun
    /// @param zeroForOne Direction of the backrun
    /// @param amountIn Amount to swap
    /// @param minAmountOut Minimum output for profitability
    function executeBackrun(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minAmountOut
    ) external onlyKeeper nonReentrant returns (uint256 profit) {
        // Check we have enough capital
        address inputToken = zeroForOne 
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        
        if (capitalDeposited[inputToken] < amountIn) revert InsufficientCapital();
        
        // Execute swap and get result
        bytes memory result = poolManager.unlock(
            abi.encode(key, zeroForOne, amountIn, minAmountOut, msg.sender)
        );
        
        (uint256 actualOut, uint256 actualProfit) = abi.decode(result, (uint256, uint256));
        
        emit BackrunExecuted(
            key.toId(),
            zeroForOne,
            amountIn,
            actualOut,
            actualProfit,
            msg.sender
        );
        
        return actualProfit;
    }
    
    /// @notice Execute round-trip arbitrage
    /// @dev Swaps A->B->A to capture price discrepancy
    function executeArbitrage(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minProfit
    ) external onlyKeeper nonReentrant returns (uint256 profit) {
        // Get input token
        address inputToken = zeroForOne 
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        
        if (capitalDeposited[inputToken] < amountIn) revert InsufficientCapital();
        
        // Execute round-trip arbitrage
        bytes memory result = poolManager.unlock(
            abi.encode(
                key,
                zeroForOne,
                amountIn,
                true, // isArbitrage
                minProfit,
                msg.sender
            )
        );
        
        profit = abi.decode(result, (uint256));
        
        if (profit < minProfit) revert UnprofitableBackrun();
        
        // Update capital tracking
        capitalDeposited[inputToken] += profit;
        poolProfits[key.toId()] += profit;
    }

    // ============ IUnlockCallback ============
    
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only PoolManager");
        
        // Decode based on data length to determine operation type
        if (data.length > 192) {
            // Arbitrage operation (has 6 params)
            return _executeArbitrageCallback(data);
        } else {
            // Simple backrun (has 5 params)
            return _executeBackrunCallback(data);
        }
    }
    
    function _executeBackrunCallback(bytes calldata data) internal returns (bytes memory) {
        (
            PoolKey memory key,
            bool zeroForOne,
            uint256 amountIn,
            uint256 minAmountOut,
            address keeper
        ) = abi.decode(data, (PoolKey, bool, uint256, uint256, address));
        
        // Execute the swap
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne 
                ? TickMath.MIN_SQRT_PRICE + 1 
                : TickMath.MAX_SQRT_PRICE - 1
        });
        
        BalanceDelta delta = poolManager.swap(key, params, "");
        
        // Get actual output
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        uint256 amountOut = outputDelta < 0 ? uint256(uint128(-outputDelta)) : 0;
        
        if (amountOut < minAmountOut) revert UnprofitableBackrun();
        
        // Settle the swap
        _settle(key, delta, zeroForOne);
        
        // Calculate profit for keeper reward
        uint256 profit = amountOut > amountIn ? amountOut - amountIn : 0;
        
        return abi.encode(amountOut, profit);
    }
    
    function _executeArbitrageCallback(bytes calldata data) internal returns (bytes memory) {
        (
            PoolKey memory key,
            bool zeroForOne,
            uint256 amountIn,
            bool isArbitrage,
            uint256 minProfit,
            address keeper
        ) = abi.decode(data, (PoolKey, bool, uint256, bool, uint256, address));
        
        require(isArbitrage, "Invalid call");
        
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
        
        // First swap: input -> intermediate
        SwapParams memory params1 = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne 
                ? TickMath.MIN_SQRT_PRICE + 1 
                : TickMath.MAX_SQRT_PRICE - 1
        });
        
        BalanceDelta delta1 = poolManager.swap(key, params1, "");
        
        // Get intermediate amount
        int128 interDelta = zeroForOne ? delta1.amount1() : delta1.amount0();
        uint256 intermediateAmount = interDelta < 0 ? uint256(uint128(-interDelta)) : 0;
        
        // Second swap: intermediate -> back to input (opposite direction)
        SwapParams memory params2 = SwapParams({
            zeroForOne: !zeroForOne,
            amountSpecified: -int256(intermediateAmount),
            sqrtPriceLimitX96: !zeroForOne 
                ? TickMath.MIN_SQRT_PRICE + 1 
                : TickMath.MAX_SQRT_PRICE - 1
        });
        
        BalanceDelta delta2 = poolManager.swap(key, params2, "");
        
        // Get final amount back
        int128 finalDelta = !zeroForOne ? delta2.amount1() : delta2.amount0();
        uint256 finalAmount = finalDelta < 0 ? uint256(uint128(-finalDelta)) : 0;
        
        // Calculate profit
        if (finalAmount <= amountIn) revert UnprofitableBackrun();
        uint256 profit = finalAmount - amountIn;
        
        if (profit < minProfit) revert UnprofitableBackrun();
        
        // Settle both deltas
        // Combined delta for input currency: delta1.input + delta2.output
        // Combined delta for output currency: delta1.output + delta2.input (should net to ~0)
        
        // Pay input for first swap
        _payToken(inputCurrency, uint256(int256(zeroForOne ? delta1.amount0() : delta1.amount1())));
        
        // Take output from first swap - this becomes input for second swap
        // Actually, we need to handle this more carefully
        // Let's settle each swap separately
        
        _settle(key, delta1, zeroForOne);
        _settle(key, delta2, !zeroForOne);
        
        // Distribute profit
        _distributeProfit(inputCurrency, profit, keeper);
        
        return abi.encode(profit);
    }
    
    function _settle(
        PoolKey memory key,
        BalanceDelta delta,
        bool zeroForOne
    ) internal {
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
        
        int128 inputAmount = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputAmount = zeroForOne ? delta.amount1() : delta.amount0();
        
        // Pay input (positive means we owe)
        if (inputAmount > 0) {
            _payToken(inputCurrency, uint128(inputAmount));
        }
        
        // Take output (negative means we're owed)
        if (outputAmount < 0) {
            poolManager.take(outputCurrency, address(this), uint128(-outputAmount));
        }
    }
    
    function _payToken(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
    
    function _distributeProfit(
        Currency currency,
        uint256 profit,
        address keeper
    ) internal {
        if (profit == 0) return;
        
        address token = Currency.unwrap(currency);
        
        // Keeper share
        uint256 keeperAmount = profit * keeperShareBps / BASIS_POINTS;
        if (keeperAmount > 0 && !currency.isAddressZero()) {
            IERC20(token).safeTransfer(keeper, keeperAmount);
        }
        
        // Treasury share (rest)
        uint256 treasuryAmount = profit - keeperAmount;
        if (treasuryAmount > 0 && !currency.isAddressZero()) {
            IERC20(token).safeTransfer(treasury, treasuryAmount);
        }
    }

    // ============ View Functions ============
    
    /// @notice Get available capital for a token
    function getAvailableCapital(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
    
    /// @notice Estimate backrun profitability
    function estimateProfit(
        PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn
    ) external view returns (uint256 estimatedProfit, bool isProfitable) {
        // Get current pool state
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        
        // Simplified estimation - in production would use more sophisticated model
        uint256 currentPrice = _sqrtPriceToPrice(sqrtPriceX96);
        
        // Estimate output based on current price
        uint256 estimatedOut;
        if (zeroForOne) {
            estimatedOut = amountIn * currentPrice / PRICE_PRECISION;
        } else {
            estimatedOut = amountIn * PRICE_PRECISION / currentPrice;
        }
        
        // Account for ~0.3% swap fee
        estimatedOut = estimatedOut * 997 / 1000;
        
        if (estimatedOut > amountIn) {
            estimatedProfit = estimatedOut - amountIn;
            isProfitable = true;
        }
    }
    
    function _sqrtPriceToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        return (sqrtPrice * sqrtPrice * PRICE_PRECISION) >> 192;
    }

    // ============ Admin Functions ============
    
    function setKeeper(address keeper, bool active) external onlyOwner {
        keepers[keeper] = active;
        emit KeeperUpdated(keeper, active);
    }
    
    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }
    
    function setKeeperShare(uint256 newShareBps) external onlyOwner {
        require(newShareBps <= 5000, "Max 50%");
        keeperShareBps = newShareBps;
    }
    
    /// @notice Emergency token recovery
    function emergencyRecover(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    receive() external payable {}
}
