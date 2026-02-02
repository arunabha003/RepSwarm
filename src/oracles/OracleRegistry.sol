// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {AggregatorV3Interface, IOracleRegistry} from "../interfaces/IChainlinkOracle.sol";

/// @title OracleRegistry
/// @notice Registry for Chainlink price feeds used by the MEV detection system
/// @dev Maps token pairs to Chainlink aggregator addresses
contract OracleRegistry is IOracleRegistry, Ownable {
    /// @notice Mapping from hash(base, quote) to price feed address
    mapping(bytes32 => address) public priceFeeds;

    /// @notice Maximum staleness for price data (default 1 hour)
    uint256 public maxStaleness = 1 hours;

    /// @notice Emitted when a price feed is set
    event PriceFeedSet(address indexed base, address indexed quote, address feed);

    /// @notice Emitted when max staleness is updated
    event MaxStalenessUpdated(uint256 oldValue, uint256 newValue);

    error StalePrice(uint256 updatedAt, uint256 maxAge);
    error InvalidPrice(int256 price);
    error FeedNotFound(address base, address quote);
    error ZeroAddress();

    constructor() Ownable(msg.sender) {}

    /// @notice Set a price feed for a token pair
    /// @param base The base token address
    /// @param quote The quote token address
    /// @param feed The Chainlink aggregator address
    function setPriceFeed(address base, address quote, address feed) external onlyOwner {
        if (feed == address(0)) revert ZeroAddress();
        bytes32 key = _getPairKey(base, quote);
        priceFeeds[key] = feed;
        emit PriceFeedSet(base, quote, feed);
    }

    /// @notice Set multiple price feeds at once
    /// @param bases Array of base token addresses
    /// @param quotes Array of quote token addresses
    /// @param feeds Array of Chainlink aggregator addresses
    function setPriceFeeds(
        address[] calldata bases,
        address[] calldata quotes,
        address[] calldata feeds
    ) external onlyOwner {
        require(bases.length == quotes.length && quotes.length == feeds.length, "Length mismatch");
        for (uint256 i = 0; i < bases.length; i++) {
            if (feeds[i] == address(0)) revert ZeroAddress();
            bytes32 key = _getPairKey(bases[i], quotes[i]);
            priceFeeds[key] = feeds[i];
            emit PriceFeedSet(bases[i], quotes[i], feeds[i]);
        }
    }

    /// @notice Update the maximum staleness threshold
    /// @param newMaxStaleness New staleness threshold in seconds
    function setMaxStaleness(uint256 newMaxStaleness) external onlyOwner {
        emit MaxStalenessUpdated(maxStaleness, newMaxStaleness);
        maxStaleness = newMaxStaleness;
    }

    /// @inheritdoc IOracleRegistry
    function getPriceFeed(address base, address quote) external view override returns (address feed) {
        bytes32 key = _getPairKey(base, quote);
        feed = priceFeeds[key];
        if (feed == address(0)) {
            // Try reverse pair
            key = _getPairKey(quote, base);
            feed = priceFeeds[key];
        }
    }

    /// @inheritdoc IOracleRegistry
    function getLatestPrice(address base, address quote) external view override returns (uint256 price, uint256 updatedAt) {
        (address feed, bool inverted) = _getFeedWithDirection(base, quote);
        if (feed == address(0)) revert FeedNotFound(base, quote);

        AggregatorV3Interface aggregator = AggregatorV3Interface(feed);
        (, int256 answer, , uint256 updatedAtRaw, ) = aggregator.latestRoundData();

        if (answer <= 0) revert InvalidPrice(answer);
        if (block.timestamp - updatedAtRaw > maxStaleness) revert StalePrice(updatedAtRaw, maxStaleness);

        uint8 decimals = aggregator.decimals();
        updatedAt = updatedAtRaw;

        // Normalize to 18 decimals
        if (inverted) {
            // If we have quote/base feed but need base/quote, invert
            price = (10 ** (18 + decimals)) / uint256(answer);
        } else {
            if (decimals < 18) {
                price = uint256(answer) * (10 ** (18 - decimals));
            } else if (decimals > 18) {
                price = uint256(answer) / (10 ** (decimals - 18));
            } else {
                price = uint256(answer);
            }
        }
    }

    /// @notice Check if a price feed exists for a pair
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return exists True if a feed exists (in either direction)
    function hasPriceFeed(address base, address quote) external view returns (bool exists) {
        (address feed, ) = _getFeedWithDirection(base, quote);
        exists = feed != address(0);
    }

    /// @dev Get the feed address and whether it needs to be inverted
    function _getFeedWithDirection(address base, address quote) internal view returns (address feed, bool inverted) {
        bytes32 key = _getPairKey(base, quote);
        feed = priceFeeds[key];
        if (feed != address(0)) {
            return (feed, false);
        }
        // Try reverse pair
        key = _getPairKey(quote, base);
        feed = priceFeeds[key];
        if (feed != address(0)) {
            return (feed, true);
        }
        return (address(0), false);
    }

    /// @dev Generate a unique key for a token pair
    function _getPairKey(address base, address quote) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(base, quote));
    }
}
