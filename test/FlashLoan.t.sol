// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

import {FlashLoanBackrunner} from "../src/backrun/FlashLoanBackrunner.sol";
import {LPFeeAccumulator} from "../src/LPFeeAccumulator.sol";

import {TestERC20} from "./utils/TestERC20.sol";

/// @title FlashLoanTest
/// @notice Tests for FlashLoanBackrunner functionality
contract FlashLoanTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    FlashLoanBackrunner public backrunner;
    LPFeeAccumulator public lpAccumulator;
    
    // Mock Aave pool for testing
    address public mockAavePool;
    
    address public keeper = makeAddr("keeper");
    address public owner = makeAddr("owner");
    
    IPoolManager public poolManager;

    function setUp() public {
        // Fork Sepolia for real pool manager
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            // Skip test if no RPC URL
            vm.skip(true);
            return;
        }
        
        vm.createSelectFork(rpc);
        
        address poolManagerAddr = vm.envOr("POOL_MANAGER", address(0));
        if (poolManagerAddr == address(0)) {
            vm.skip(true);
            return;
        }
        poolManager = IPoolManager(poolManagerAddr);
        
        // Deploy mock Aave pool
        mockAavePool = makeAddr("mockAave");
        
        // Deploy backrunner with mock Aave
        vm.prank(owner);
        backrunner = new FlashLoanBackrunner(poolManager, mockAavePool);
    }

    function testDeployment() public view {
        assertEq(address(backrunner.poolManager()), address(poolManager));
        assertEq(address(backrunner.aavePool()), mockAavePool);
        assertTrue(backrunner.authorizedKeepers(owner));
    }

    function testAuthorizeKeeper() public {
        assertFalse(backrunner.authorizedKeepers(keeper));
        
        vm.prank(owner);
        backrunner.setKeeperAuthorization(keeper, true);
        
        assertTrue(backrunner.authorizedKeepers(keeper));
    }

    function testUnauthorizedKeeperCannotExecute() public {
        // Create a mock pool key
        PoolKey memory mockKey = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        PoolId poolId = mockKey.toId();
        
        // Record a backrun opportunity (anyone can record for testing)
        backrunner.recordBackrunOpportunity(
            mockKey,
            2000e18,  // target price
            1900e18,  // current price
            1 ether,  // backrun amount
            true      // zeroForOne
        );
        
        // Unauthorized keeper should fail
        vm.prank(keeper);
        vm.expectRevert(FlashLoanBackrunner.UnauthorizedKeeper.selector);
        backrunner.executeBackrun(poolId, 0);
    }

    function testRecordBackrunOpportunity() public {
        PoolKey memory mockKey = PoolKey({
            currency0: Currency.wrap(address(0x1)),
            currency1: Currency.wrap(address(0x2)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        
        PoolId poolId = mockKey.toId();
        
        // Record opportunity
        backrunner.recordBackrunOpportunity(
            mockKey,
            2000e18,
            1900e18,
            1 ether,
            true
        );
        
        // Check it was recorded
        (
            ,
            uint256 targetPrice,
            uint256 currentPrice,
            uint256 backrunAmount,
            bool zeroForOne,
            ,
            bool executed
        ) = backrunner.pendingBackruns(poolId);
        
        assertEq(targetPrice, 2000e18);
        assertEq(currentPrice, 1900e18);
        assertEq(backrunAmount, 1 ether);
        assertTrue(zeroForOne);
        assertFalse(executed);
    }
}
