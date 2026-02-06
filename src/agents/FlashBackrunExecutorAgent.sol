// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

interface IFlashLoanBackrunnerLike {
    function pendingBackruns(PoolId poolId)
        external
        view
        returns (
            PoolKey memory poolKey,
            uint256 targetPrice,
            uint256 currentPrice,
            uint256 backrunAmount,
            bool zeroForOne,
            uint64 timestamp,
            uint64 blockNumber,
            bool executed
        );

    function executeBackrunPartialFor(PoolId poolId, uint256 flashLoanAmount, uint256 minProfit, address keeper)
        external;
}

/// @title FlashBackrunExecutorAgent
/// @notice Permissionless on-chain agent that executes pending flashloan backruns and forwards bounty to caller.
/// @dev Must be authorized as both forwarder and keeper on FlashLoanBackrunner.
contract FlashBackrunExecutorAgent is Ownable {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    IFlashLoanBackrunnerLike public immutable backrunner;

    /// @notice Max amount to use for each backrun execution (0 = no clamp).
    uint256 public maxFlashloanAmount;

    /// @notice Min profit passed through to FlashLoanBackrunner.
    uint256 public minProfit;

    event ExecutionConfigUpdated(uint256 maxFlashloanAmount, uint256 minProfit);
    event BackrunExecuted(PoolId indexed poolId, address indexed caller, address token, uint256 amountIn, uint256 bounty);

    error InvalidBackrunner();
    error NoOpportunity();
    error InvalidBorrowToken();

    constructor(address _backrunner, address _owner, uint256 _maxFlashloanAmount, uint256 _minProfit)
        Ownable(_owner)
    {
        if (_backrunner == address(0)) revert InvalidBackrunner();
        backrunner = IFlashLoanBackrunnerLike(_backrunner);
        maxFlashloanAmount = _maxFlashloanAmount;
        minProfit = _minProfit;
    }

    function setExecutionConfig(uint256 _maxFlashloanAmount, uint256 _minProfit) external onlyOwner {
        maxFlashloanAmount = _maxFlashloanAmount;
        minProfit = _minProfit;
        emit ExecutionConfigUpdated(_maxFlashloanAmount, _minProfit);
    }

    /// @notice Execute the currently pending backrun for a pool and forward bounty to caller.
    /// @return token Borrow token used for the flashloan.
    /// @return bounty Amount paid to the caller from keeper share.
    function execute(PoolId poolId) external returns (address token, uint256 bounty) {
        (PoolKey memory poolKey,,, uint256 backrunAmount, bool zeroForOne,,, bool executed) =
            backrunner.pendingBackruns(poolId);

        if (backrunAmount == 0 || executed) revert NoOpportunity();

        token = zeroForOne ? Currency.unwrap(poolKey.currency0) : Currency.unwrap(poolKey.currency1);
        if (token == address(0)) revert InvalidBorrowToken();

        uint256 amountIn = backrunAmount;
        if (maxFlashloanAmount != 0 && amountIn > maxFlashloanAmount) {
            amountIn = maxFlashloanAmount;
        }

        uint256 beforeBal = IERC20(token).balanceOf(address(this));
        backrunner.executeBackrunPartialFor(poolId, amountIn, minProfit, address(this));
        uint256 afterBal = IERC20(token).balanceOf(address(this));

        bounty = afterBal - beforeBal;
        if (bounty > 0) {
            IERC20(token).safeTransfer(msg.sender, bounty);
        }

        emit BackrunExecuted(poolId, msg.sender, token, amountIn, bounty);
    }
}
