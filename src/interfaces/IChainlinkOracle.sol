// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Chainlink Aggregator V3 Interface
/// @notice Interface for Chainlink price feeds
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title Oracle Registry Interface
/// @notice Interface for managing multiple price feed oracles
interface IOracleRegistry {
    /// @notice Get the price feed for a token pair
    /// @param base The base token address (e.g., WETH)
    /// @param quote The quote token address (e.g., USDC)
    /// @return feed The Chainlink aggregator address for the pair
    function getPriceFeed(address base, address quote) external view returns (address feed);

    /// @notice Get the latest price from a feed
    /// @param base The base token address
    /// @param quote The quote token address
    /// @return price The price scaled to 18 decimals
    /// @return updatedAt Timestamp of last update
    function getLatestPrice(address base, address quote) external view returns (uint256 price, uint256 updatedAt);
}
