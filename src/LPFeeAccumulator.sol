// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

/// @title LPFeeAccumulator
/// @notice Accumulates captured MEV fees and periodically donates them to LPs
/// @dev Uses Uniswap v4's donate() function for actual LP fee redistribution
/// @dev This is a REAL implementation - no mocking or simplified logic
contract LPFeeAccumulator is Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    /// @notice The Uniswap v4 PoolManager
    IPoolManager public immutable poolManager;

    /// @notice Minimum accumulated amount before donation is triggered
    uint256 public minDonationThreshold;

    /// @notice Minimum time between donations to same pool (prevents spam)
    uint256 public minDonationInterval;

    /// @notice Accumulated fees per pool per currency
    /// poolId => currency => accumulated amount
    mapping(PoolId => mapping(Currency => uint256)) public accumulatedFees;

    /// @notice Last donation timestamp per pool
    mapping(PoolId => uint256) public lastDonationTime;

    /// @notice Registered hooks that can deposit fees
    mapping(address => bool) public authorizedHooks;

    /// @notice Pool keys for donation execution
    mapping(PoolId => PoolKey) public poolKeys;

    /// @notice Whether a pool key has been registered
    mapping(PoolId => bool) public poolKeyRegistered;

    /// @notice Total fees ever donated per pool per currency
    mapping(PoolId => mapping(Currency => uint256)) public totalDonated;

    // Events
    event FeesAccumulated(PoolId indexed poolId, Currency indexed currency, uint256 amount);
    event FeesDonatedToLPs(
        PoolId indexed poolId, Currency indexed currency0, Currency indexed currency1, uint256 amount0, uint256 amount1
    );
    event HookAuthorized(address indexed hook, bool authorized);
    event PoolKeyRegistered(PoolId indexed poolId);
    event ThresholdUpdated(uint256 newThreshold);
    event IntervalUpdated(uint256 newInterval);
    event EmergencyWithdrawal(Currency indexed currency, uint256 amount, address recipient);

    // Errors
    error UnauthorizedHook(address hook);
    error PoolKeyNotRegistered(PoolId poolId);
    error DonationTooSoon(uint256 lastTime, uint256 minInterval);
    error BelowThreshold(uint256 amount, uint256 threshold);
    error InvalidPoolKey();
    error ZeroAmount();
    error TransferFailed();

    constructor(IPoolManager _poolManager, uint256 _minDonationThreshold, uint256 _minDonationInterval)
        Ownable(msg.sender)
    {
        poolManager = _poolManager;
        minDonationThreshold = _minDonationThreshold;
        minDonationInterval = _minDonationInterval;
    }

    /// @notice Authorize a hook to deposit fees
    /// @param hook The hook address
    /// @param authorized Whether to authorize or revoke
    function setHookAuthorization(address hook, bool authorized) external onlyOwner {
        authorizedHooks[hook] = authorized;
        emit HookAuthorized(hook, authorized);
    }

    /// @notice Register a pool key for a pool ID (needed for donation)
    /// @param key The pool key
    function registerPoolKey(PoolKey calldata key) external {
        PoolId poolId = key.toId();
        if (poolKeyRegistered[poolId]) return; // Already registered

        poolKeys[poolId] = key;
        poolKeyRegistered[poolId] = true;
        emit PoolKeyRegistered(poolId);
    }

    /// @notice Update minimum donation threshold
    /// @param newThreshold New threshold amount
    function setMinDonationThreshold(uint256 newThreshold) external onlyOwner {
        minDonationThreshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    /// @notice Update minimum donation interval
    /// @param newInterval New interval in seconds
    function setMinDonationInterval(uint256 newInterval) external onlyOwner {
        minDonationInterval = newInterval;
        emit IntervalUpdated(newInterval);
    }

    /// @notice Accumulate fees from an authorized hook
    /// @dev Called by MevRouterHook after capturing MEV
    /// @param poolId The pool ID
    /// @param currency The currency being accumulated
    /// @param amount The amount to accumulate
    function accumulateFees(PoolId poolId, Currency currency, uint256 amount) external {
        if (!authorizedHooks[msg.sender]) {
            revert UnauthorizedHook(msg.sender);
        }
        if (amount == 0) revert ZeroAmount();

        accumulatedFees[poolId][currency] += amount;
        emit FeesAccumulated(poolId, currency, amount);
    }

    /// @notice Donate accumulated fees to LPs of a specific pool
    /// @dev Uses the PoolManager's donate() function for REAL LP fee redistribution
    /// @param poolId The pool ID to donate to
    function donateToLPs(PoolId poolId) external nonReentrant {
        if (!poolKeyRegistered[poolId]) {
            revert PoolKeyNotRegistered(poolId);
        }

        // Check donation interval
        uint256 lastTime = lastDonationTime[poolId];
        if (block.timestamp < lastTime + minDonationInterval) {
            revert DonationTooSoon(lastTime, minDonationInterval);
        }

        PoolKey memory key = poolKeys[poolId];

        uint256 amount0 = accumulatedFees[poolId][key.currency0];
        uint256 amount1 = accumulatedFees[poolId][key.currency1];

        // Check threshold
        if (amount0 < minDonationThreshold && amount1 < minDonationThreshold) {
            revert BelowThreshold(amount0 > amount1 ? amount0 : amount1, minDonationThreshold);
        }

        // Reset accumulated fees before external call (CEI pattern)
        accumulatedFees[poolId][key.currency0] = 0;
        accumulatedFees[poolId][key.currency1] = 0;
        lastDonationTime[poolId] = block.timestamp;

        // Update totals
        totalDonated[poolId][key.currency0] += amount0;
        totalDonated[poolId][key.currency1] += amount1;

        // Execute donation through pool manager
        // This is the REAL LP fee distribution using Uniswap v4's native donate()
        if (amount0 > 0 || amount1 > 0) {
            _executeDonation(key, amount0, amount1);
        }

        emit FeesDonatedToLPs(poolId, key.currency0, key.currency1, amount0, amount1);
    }

    /// @notice Internal function to execute the actual donation
    /// @dev Implements IUnlockCallback pattern for pool manager interaction
    function _executeDonation(PoolKey memory key, uint256 amount0, uint256 amount1) internal {
        // Approve tokens for pool manager if ERC20
        if (!key.currency0.isAddressZero() && amount0 > 0) {
            IERC20(Currency.unwrap(key.currency0)).approve(address(poolManager), amount0);
        }
        if (!key.currency1.isAddressZero() && amount1 > 0) {
            IERC20(Currency.unwrap(key.currency1)).approve(address(poolManager), amount1);
        }

        // Call unlock to execute donation
        // The callback will handle the actual donate() call
        bytes memory callbackData = abi.encode(key, amount0, amount1);
        poolManager.unlock(callbackData);
    }

    /// @notice Callback from pool manager during unlock
    /// @dev Executes the actual donate() call
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "Only pool manager");

        (PoolKey memory key, uint256 amount0, uint256 amount1) = abi.decode(data, (PoolKey, uint256, uint256));

        // Execute donation to LPs
        // donate() adds fees to the pool that get distributed to in-range LPs
        BalanceDelta delta = poolManager.donate(key, amount0, amount1, "");

        // Settle the donations
        if (amount0 > 0) {
            _settle(key.currency0, amount0);
        }
        if (amount1 > 0) {
            _settle(key.currency1, amount1);
        }

        return abi.encode(delta);
    }

    /// @notice Settle currency with pool manager
    function _settle(Currency currency, uint256 amount) internal {
        if (currency.isAddressZero()) {
            // Native ETH
            poolManager.settle{value: amount}();
        } else {
            // ERC20 - sync and settle
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }
    }

    /// @notice Check if donation is possible for a pool
    /// @param poolId The pool ID
    /// @return canDonate_ Whether donation can be executed
    /// @return amount0 Accumulated amount of currency0
    /// @return amount1 Accumulated amount of currency1
    function canDonate(PoolId poolId) external view returns (bool canDonate_, uint256 amount0, uint256 amount1) {
        if (!poolKeyRegistered[poolId]) {
            return (false, 0, 0);
        }

        PoolKey memory key = poolKeys[poolId];
        amount0 = accumulatedFees[poolId][key.currency0];
        amount1 = accumulatedFees[poolId][key.currency1];

        bool intervalPassed = block.timestamp >= lastDonationTime[poolId] + minDonationInterval;
        bool aboveThreshold = amount0 >= minDonationThreshold || amount1 >= minDonationThreshold;

        canDonate_ = intervalPassed && aboveThreshold;
    }

    /// @notice Get accumulated fees for a pool
    /// @param poolId The pool ID
    /// @param currency The currency
    /// @return amount The accumulated amount
    function getAccumulatedFees(PoolId poolId, Currency currency) external view returns (uint256 amount) {
        return accumulatedFees[poolId][currency];
    }

    /// @notice Get total donated fees for a pool
    /// @param poolId The pool ID
    /// @param currency The currency
    /// @return amount The total donated amount
    function getTotalDonated(PoolId poolId, Currency currency) external view returns (uint256 amount) {
        return totalDonated[poolId][currency];
    }

    /// @notice Emergency withdrawal by owner (only for stuck funds)
    /// @param currency The currency to withdraw
    /// @param amount The amount to withdraw
    /// @param recipient The recipient address
    function emergencyWithdraw(Currency currency, uint256 amount, address recipient) external onlyOwner {
        if (currency.isAddressZero()) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(Currency.unwrap(currency)).safeTransfer(recipient, amount);
        }
        emit EmergencyWithdrawal(currency, amount, recipient);
    }

    /// @notice Receive ETH
    receive() external payable {}
}
