// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {SwarmTypes} from "../src/libraries/SwarmTypes.sol";
import {SwarmHookData} from "../src/libraries/SwarmHookData.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";
import {IOracleRegistry, AggregatorV3Interface} from "../src/interfaces/IChainlinkOracle.sol";

/// @title SwarmUnitTest
/// @notice Unit tests for Swarm protocol libraries and components
contract SwarmUnitTest is Test {
    OracleRegistry oracleRegistry;

    address tokenA = address(0x1111);
    address tokenB = address(0x2222);

    function setUp() public {
        oracleRegistry = new OracleRegistry();
    }

    // ============ SwarmHookData Tests ============

    function test_hookDataEncodeAndDecode() public pure {
        SwarmHookData.Payload memory original = SwarmHookData.Payload({
            intentId: 42,
            agentId: 1,
            treasury: address(0xBEEF),
            treasuryBps: 200, // 2%
            mevFee: 500, // 0.5%
            lpShareBps: 8000 // 80%
        });

        bytes memory encoded = SwarmHookData.encode(original);
        SwarmHookData.Payload memory decoded = SwarmHookData.decodeMemory(encoded);

        assertEq(decoded.intentId, original.intentId);
        assertEq(decoded.agentId, original.agentId);
        assertEq(decoded.treasury, original.treasury);
        assertEq(decoded.treasuryBps, original.treasuryBps);
        assertEq(decoded.mevFee, original.mevFee);
        assertEq(decoded.lpShareBps, original.lpShareBps);
    }

    function test_hookDataFuzz(
        uint256 intentId,
        uint24 mevFee,
        address treasury,
        uint16 treasuryBps,
        uint16 lpShareBps
    ) public pure {
        SwarmHookData.Payload memory original = SwarmHookData.Payload({
            intentId: intentId,
            agentId: 1,
            treasury: treasury,
            treasuryBps: treasuryBps,
            mevFee: mevFee,
            lpShareBps: lpShareBps
        });

        bytes memory encoded = SwarmHookData.encode(original);
        SwarmHookData.Payload memory decoded = SwarmHookData.decodeMemory(encoded);

        assertEq(decoded.intentId, original.intentId);
        assertEq(decoded.mevFee, original.mevFee);
        assertEq(decoded.treasury, original.treasury);
        assertEq(decoded.treasuryBps, original.treasuryBps);
        assertEq(decoded.lpShareBps, original.lpShareBps);
    }

    // ============ OracleRegistry Tests ============

    function test_oracleRegistry_setPriceFeed() public {
        address mockFeed = address(0x3333);
        
        oracleRegistry.setPriceFeed(tokenA, tokenB, mockFeed);
        
        address retrievedFeed = oracleRegistry.getPriceFeed(tokenA, tokenB);
        assertEq(retrievedFeed, mockFeed);
    }

    function test_oracleRegistry_setPriceFeed_reverseQuery() public {
        address mockFeed = address(0x3333);
        
        // Set feed for A->B
        oracleRegistry.setPriceFeed(tokenA, tokenB, mockFeed);
        
        // Should also be queryable via B->A (reverse lookup)
        address retrievedFeed = oracleRegistry.getPriceFeed(tokenB, tokenA);
        assertEq(retrievedFeed, mockFeed);
    }

    function test_oracleRegistry_setMultiplePriceFeeds() public {
        address feedAB = address(0x3333);
        address feedAC = address(0x4444);
        address tokenC = address(0x5555);

        address[] memory bases = new address[](2);
        address[] memory quotes = new address[](2);
        address[] memory feeds = new address[](2);

        bases[0] = tokenA;
        quotes[0] = tokenB;
        feeds[0] = feedAB;

        bases[1] = tokenA;
        quotes[1] = tokenC;
        feeds[1] = feedAC;

        oracleRegistry.setPriceFeeds(bases, quotes, feeds);

        assertEq(oracleRegistry.getPriceFeed(tokenA, tokenB), feedAB);
        assertEq(oracleRegistry.getPriceFeed(tokenA, tokenC), feedAC);
    }

    function test_oracleRegistry_hasPriceFeed() public {
        assertFalse(oracleRegistry.hasPriceFeed(tokenA, tokenB));

        oracleRegistry.setPriceFeed(tokenA, tokenB, address(0x3333));

        assertTrue(oracleRegistry.hasPriceFeed(tokenA, tokenB));
        assertTrue(oracleRegistry.hasPriceFeed(tokenB, tokenA)); // Reverse lookup
    }

    function test_oracleRegistry_setMaxStaleness() public {
        uint256 defaultStaleness = oracleRegistry.maxStaleness();
        assertEq(defaultStaleness, 1 hours);

        oracleRegistry.setMaxStaleness(30 minutes);
        assertEq(oracleRegistry.maxStaleness(), 30 minutes);
    }

    function test_oracleRegistry_onlyOwnerCanSetFeed() public {
        address attacker = address(0xBAD);
        
        vm.prank(attacker);
        vm.expectRevert();
        oracleRegistry.setPriceFeed(tokenA, tokenB, address(0x3333));
    }

    function test_oracleRegistry_cannotSetZeroAddressFeed() public {
        vm.expectRevert(OracleRegistry.ZeroAddress.selector);
        oracleRegistry.setPriceFeed(tokenA, tokenB, address(0));
    }

    // ============ SwarmTypes Tests ============

    function test_intentParams_struct() public pure {
        SwarmTypes.IntentParams memory params = SwarmTypes.IntentParams({
            currencyIn: Currency.wrap(address(0x1)),
            currencyOut: Currency.wrap(address(0x2)),
            amountIn: 1e18,
            amountOutMin: 9e17,
            deadline: 1000,
            mevFeeBps: 30,
            treasuryBps: 200,
            lpShareBps: 8000
        });

        assertEq(params.amountIn, 1e18);
        assertEq(params.mevFeeBps, 30);
        assertEq(params.lpShareBps, 8000);
    }
}

// Import Currency from v4-core for tests
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
