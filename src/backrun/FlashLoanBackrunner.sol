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
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {LPFeeAccumulator} from "../LPFeeAccumulator.sol";

/// @title IFlashLoanSimpleReceiver
/// @notice Aave V3 Flash Loan interface
interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/// @title IPool (Aave V3)
/// @notice Minimal interface for Aave V3 Pool
interface IAavePool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
    
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}

/// @title FlashLoanBackrunner
/// @notice Executes MEV backruns using Aave V3 flash loans for capital efficiency
/// @dev Captures arbitrage between pool price and oracle price after large swaps
/// @dev Profits are distributed to LPs via LPFeeAccumulator
contract FlashLoanBackrunner is IFlashLoanSimpleReceiver, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    // ============ Constants ============
    
    /// @notice Aave V3 Pool on Sepolia
    address public constant AAVE_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    
    /// @notice Minimum profit threshold in basis points (0.1%)
    uint256 public constant MIN_PROFIT_BPS = 10;
    
    /// @notice Maximum slippage for backrun swaps (1%)
    uint256 public constant MAX_SLIPPAGE_BPS = 100;
    
    /// @notice Basis points scale
    uint256 public constant BASIS_POINTS = 10000;
    
    /// @notice Price precision
    uint256 public constant PRICE_PRECISION = 1e18;

    // ============ State Variables ============
    
    /// @notice The Uniswap v4 PoolManager
    IPoolManager public immutable poolManager;
    
    /// @notice The LP Fee Accumulator for profit distribution
    LPFeeAccumulator public lpFeeAccumulator;
    
    /// @notice Aave V3 Pool
    IAavePool public aavePool;
    
    /// @notice Authorized keepers who can trigger backruns
    mapping(address => bool) public authorizedKeepers;
    
    /// @notice Pending backrun opportunities per pool
    mapping(PoolId => BackrunOpportunity) public pendingBackruns;
    
    /// @notice Total profits captured per pool
    mapping(PoolId => uint256) public totalProfits;

    // ============ Structs ============
    
    struct BackrunOpportunity {
        PoolKey poolKey;
        uint256 targetPrice;      // Price we want to restore to
        uint256 currentPrice;     // Price after the large swap
        uint256 backrunAmount;    // Calculated optimal backrun amount
        bool zeroForOne;          // Direction of backrun
        uint64 timestamp;         // When opportunity was detected
        bool executed;
    }
    
    struct FlashLoanParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint256 minProfit;
        address profitRecipient;
    }

    // ============ Events ============
    
    event BackrunOpportunityDetected(
        PoolId indexed poolId,
        uint256 targetPrice,
        uint256 currentPrice,
        uint256 backrunAmount,
        bool zeroForOne
    );
    
    event BackrunExecuted(
        PoolId indexed poolId,
        uint256 flashLoanAmount,
        uint256 profit,
        uint256 lpShare,
        address keeper
    );
    
    event KeeperAuthorized(address indexed keeper, bool authorized);
    event LPAccumulatorUpdated(address indexed accumulator);
    event AavePoolUpdated(address indexed pool);
    event EmergencyWithdraw(address indexed token, uint256 amount);

    // ============ Errors ============
    
    error UnauthorizedKeeper();
    error NoOpportunity();
    error OpportunityExpired();
    error InsufficientProfit();
    error FlashLoanFailed();
    error InvalidInitiator();
    error SwapFailed();

    // ============ Constructor ============
    
    constructor(
        IPoolManager _poolManager,
        address _aavePool
    ) Ownable(msg.sender) {
        poolManager = _poolManager;
        aavePool = IAavePool(_aavePool != address(0) ? _aavePool : AAVE_POOL_SEPOLIA);
        
        // Owner is authorized by default
        authorizedKeepers[msg.sender] = true;
    }

    // ============ Modifiers ============
    
    modifier onlyKeeper() {
        if (!authorizedKeepers[msg.sender]) revert UnauthorizedKeeper();
        _;
    }

    // ============ External Functions ============
    
    /// @notice Record a backrun opportunity detected by the hook
    /// @dev Called by MevRouterHookV2 after detecting price deviation
    function recordBackrunOpportunity(
        PoolKey calldata poolKey,
        uint256 targetPrice,
        uint256 currentPrice,
        uint256 backrunAmount,
        bool zeroForOne
    ) external {
        // Only authorized contracts can record opportunities
        // In production, this would be restricted to the hook
        
        PoolId poolId = poolKey.toId();
        
        pendingBackruns[poolId] = BackrunOpportunity({
            poolKey: poolKey,
            targetPrice: targetPrice,
            currentPrice: currentPrice,
            backrunAmount: backrunAmount,
            zeroForOne: zeroForOne,
            timestamp: uint64(block.timestamp),
            executed: false
        });
        
        emit BackrunOpportunityDetected(poolId, targetPrice, currentPrice, backrunAmount, zeroForOne);
    }
    
    /// @notice Execute a pending backrun using flash loan
    /// @param poolId The pool to backrun
    /// @param minProfit Minimum acceptable profit
    function executeBackrun(
        PoolId poolId,
        uint256 minProfit
    ) external onlyKeeper nonReentrant {
        BackrunOpportunity storage opp = pendingBackruns[poolId];
        
        if (opp.backrunAmount == 0) revert NoOpportunity();
        if (opp.executed) revert NoOpportunity();
        if (block.timestamp > opp.timestamp + 2) revert OpportunityExpired(); // Max 2 blocks old
        
        // Mark as executed to prevent reentrancy
        opp.executed = true;
        
        // Determine which token to borrow
        address borrowToken = opp.zeroForOne 
            ? Currency.unwrap(opp.poolKey.currency0)
            : Currency.unwrap(opp.poolKey.currency1);
        
        // Handle native ETH
        if (borrowToken == address(0)) {
            // For ETH, we'd need WETH - skip for now
            revert SwapFailed();
        }
        
        // Encode flash loan params
        bytes memory params = abi.encode(FlashLoanParams({
            poolKey: opp.poolKey,
            zeroForOne: opp.zeroForOne,
            minProfit: minProfit,
            profitRecipient: msg.sender
        }));
        
        // Execute flash loan
        aavePool.flashLoanSimple(
            address(this),
            borrowToken,
            opp.backrunAmount,
            params,
            0 // referral code
        );
    }
    
    /// @notice Aave flash loan callback
    /// @dev Executes the backrun swap and repays the loan
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // Verify caller is Aave pool
        if (msg.sender != address(aavePool)) revert FlashLoanFailed();
        if (initiator != address(this)) revert InvalidInitiator();
        
        // Decode params
        FlashLoanParams memory flashParams = abi.decode(params, (FlashLoanParams));
        
        // Execute the backrun swap
        uint256 amountOut = _executeBackrunSwap(
            flashParams.poolKey,
            flashParams.zeroForOne,
            amount
        );
        
        // Calculate profit
        uint256 totalOwed = amount + premium;
        
        // If we swapped token0 -> token1, we need to swap back
        // This is a round-trip arbitrage
        uint256 amountBack = _executeReverseSwap(
            flashParams.poolKey,
            !flashParams.zeroForOne,
            amountOut
        );
        
        // Check profitability
        if (amountBack < totalOwed + flashParams.minProfit) {
            revert InsufficientProfit();
        }
        
        uint256 profit = amountBack - totalOwed;
        
        // Approve repayment to Aave
        IERC20(asset).approve(address(aavePool), totalOwed);
        
        // Distribute profit
        _distributeProfit(flashParams.poolKey, asset, profit, flashParams.profitRecipient);
        
        emit BackrunExecuted(
            flashParams.poolKey.toId(),
            amount,
            profit,
            profit * 80 / 100, // 80% to LPs
            flashParams.profitRecipient
        );
        
        return true;
    }
    
    /// @notice Check if a backrun opportunity is profitable
    /// @param poolId The pool to check
    /// @return profitable Whether execution would be profitable
    /// @return estimatedProfit Estimated profit amount
    function checkProfitability(PoolId poolId) external view returns (
        bool profitable,
        uint256 estimatedProfit
    ) {
        BackrunOpportunity storage opp = pendingBackruns[poolId];
        
        if (opp.backrunAmount == 0 || opp.executed) {
            return (false, 0);
        }
        
        // Get current pool state
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint256 currentPrice = _sqrtPriceToPrice(sqrtPriceX96);
        
        // Check if price has moved back already
        if (opp.zeroForOne) {
            // We want price to go up (closer to target)
            if (currentPrice >= opp.targetPrice) {
                return (false, 0);
            }
        } else {
            // We want price to go down
            if (currentPrice <= opp.targetPrice) {
                return (false, 0);
            }
        }
        
        // Estimate profit (simplified - actual would need more precise calculation)
        uint256 priceDiff;
        if (currentPrice > opp.targetPrice) {
            priceDiff = currentPrice - opp.targetPrice;
        } else {
            priceDiff = opp.targetPrice - currentPrice;
        }
        
        // Flash loan premium (typically 0.05% on Aave V3)
        uint128 flashPremium = aavePool.FLASHLOAN_PREMIUM_TOTAL();
        uint256 loanCost = opp.backrunAmount * flashPremium / 10000;
        
        estimatedProfit = opp.backrunAmount * priceDiff / PRICE_PRECISION;
        
        if (estimatedProfit > loanCost) {
            profitable = true;
            estimatedProfit = estimatedProfit - loanCost;
        }
    }

    // ============ Internal Functions ============
    
    /// @notice Execute the backrun swap on Uniswap v4
    function _executeBackrunSwap(
        PoolKey memory key,
        bool zeroForOne,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Approve pool manager
        address tokenIn = zeroForOne 
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        
        IERC20(tokenIn).approve(address(poolManager), amountIn);
        
        // Execute swap via unlock callback
        bytes memory result = poolManager.unlock(
            abi.encode(key, zeroForOne, amountIn, true) // true = first swap
        );
        
        amountOut = abi.decode(result, (uint256));
    }
    
    /// @notice Execute reverse swap to complete the round trip
    function _executeReverseSwap(
        PoolKey memory key,
        bool zeroForOne,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        address tokenIn = zeroForOne 
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        
        IERC20(tokenIn).approve(address(poolManager), amountIn);
        
        bytes memory result = poolManager.unlock(
            abi.encode(key, zeroForOne, amountIn, false) // false = reverse swap
        );
        
        amountOut = abi.decode(result, (uint256));
    }
    
    /// @notice Unlock callback for executing swaps
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only pool manager");
        
        (PoolKey memory key, bool zeroForOne, uint256 amountIn, bool isFirstSwap) = 
            abi.decode(data, (PoolKey, bool, uint256, bool));
        
        // Build swap params
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn), // Exact input
            sqrtPriceLimitX96: zeroForOne 
                ? TickMath.MIN_SQRT_PRICE + 1 
                : TickMath.MAX_SQRT_PRICE - 1
        });
        
        // Execute swap
        BalanceDelta delta = poolManager.swap(key, params, "");
        
        // Settle the swap
        _settleDelta(key, delta, zeroForOne);
        
        // Calculate output
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        uint256 amountOut = outputDelta < 0 ? uint256(uint128(-outputDelta)) : uint256(uint128(outputDelta));
        
        return abi.encode(amountOut);
    }
    
    /// @notice Settle swap delta with pool manager
    function _settleDelta(
        PoolKey memory key,
        BalanceDelta delta,
        bool zeroForOne
    ) internal {
        // Settle input (positive delta = we owe)
        Currency inputCurrency = zeroForOne ? key.currency0 : key.currency1;
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
        
        int128 inputDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        
        // Pay input if we owe
        if (inputDelta > 0) {
            _pay(inputCurrency, uint128(inputDelta));
        }
        
        // Take output if owed to us
        if (outputDelta < 0) {
            poolManager.take(outputCurrency, address(this), uint128(-outputDelta));
        }
    }
    
    /// @notice Pay currency to pool manager
    function _pay(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
    
    /// @notice Distribute profits to LPs and keeper
    function _distributeProfit(
        PoolKey memory key,
        address profitToken,
        uint256 profit,
        address keeper
    ) internal {
        // 80% to LPs, 20% to keeper
        uint256 lpShare = profit * 80 / 100;
        uint256 keeperShare = profit - lpShare;
        
        // Send LP share to accumulator if configured
        if (address(lpFeeAccumulator) != address(0) && lpShare > 0) {
            IERC20(profitToken).safeTransfer(address(lpFeeAccumulator), lpShare);
            
            // Notify accumulator
            Currency currency = Currency.wrap(profitToken);
            lpFeeAccumulator.accumulateFees(key.toId(), currency, lpShare);
        } else {
            // Fallback: send to keeper
            keeperShare += lpShare;
        }
        
        // Send keeper share
        if (keeperShare > 0) {
            IERC20(profitToken).safeTransfer(keeper, keeperShare);
        }
        
        // Track total profits
        totalProfits[key.toId()] += profit;
    }
    
    /// @notice Convert sqrt price to regular price
    function _sqrtPriceToPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 sqrtPrice = uint256(sqrtPriceX96);
        return (sqrtPrice * sqrtPrice * PRICE_PRECISION) >> 192;
    }

    // ============ Admin Functions ============
    
    /// @notice Set LP fee accumulator
    function setLPFeeAccumulator(address _accumulator) external onlyOwner {
        lpFeeAccumulator = LPFeeAccumulator(payable(_accumulator));
        emit LPAccumulatorUpdated(_accumulator);
    }
    
    /// @notice Set Aave pool address
    function setAavePool(address _pool) external onlyOwner {
        aavePool = IAavePool(_pool);
        emit AavePoolUpdated(_pool);
    }
    
    /// @notice Authorize/revoke keeper
    function setKeeperAuthorization(address keeper, bool authorized) external onlyOwner {
        authorizedKeepers[keeper] = authorized;
        emit KeeperAuthorized(keeper, authorized);
    }
    
    /// @notice Emergency withdraw stuck tokens
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
        emit EmergencyWithdraw(token, amount);
    }
    
    /// @notice Get pending backrun info
    function getPendingBackrun(PoolId poolId) external view returns (
        uint256 targetPrice,
        uint256 currentPrice,
        uint256 backrunAmount,
        bool zeroForOne,
        uint64 timestamp,
        bool executed
    ) {
        BackrunOpportunity storage opp = pendingBackruns[poolId];
        return (
            opp.targetPrice,
            opp.currentPrice,
            opp.backrunAmount,
            opp.zeroForOne,
            opp.timestamp,
            opp.executed
        );
    }

    // ============ Receive ETH ============
    receive() external payable {}
}
