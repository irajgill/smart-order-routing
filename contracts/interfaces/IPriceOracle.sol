// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPriceOracle {
    struct PriceData {
        uint256 price;      // Price with 18 decimals
        uint256 timestamp;  // Last update timestamp
        uint256 confidence; // Confidence level (0-100)
    }

    event PriceUpdated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    );

    event OracleSourceAdded(
        address indexed source,
        string name,
        uint256 weight
    );

    
    function getPrice(address tokenA, address tokenB) external view returns (PriceData memory priceData);
    
    /**
     *Get time-weighted average price over a period
     * tokenA First token address
     * tokenB Second token address
     * period Time period in seconds
     * @return price TWAP price with 18 decimals
     */
    function getTWAP(
        address tokenA,
        address tokenB,
        uint256 period
    ) external view returns (uint256 price);
    
    /**
     * date price data (restricted to authorized sources)
     * tokenA First token address
     * tokenB Second token address
     * price New price with 18 decimals
     */
    function updatePrice(
        address tokenA,
        address tokenB,
        uint256 price
    ) external;

    /**
     * Check if price data is valid and recent
     * tokenA First token address
     * tokenB Second token address
     * @return valid True if price is valid
     */
    function isValidPrice(address tokenA, address tokenB) external view returns (bool valid);
    
    /**
     * Get the timestamp of the last price update
     * tokenA First token address
     * tokenB Second token address
     * @return timestamp Last update timestamp
     */
    function getLastUpdateTime(address tokenA, address tokenB) external view returns (uint256 timestamp);

    /**
     * Get price with deviation bounds
     * tokenA First token address
     * tokenB Second token address
     * @return price Current price
     * @return lowerBound Lower confidence bound
     * @return upperBound Upper confidence bound
     */
    function getPriceWithBounds(
        address tokenA,
        address tokenB
    ) external view returns (
        uint256 price,
        uint256 lowerBound,
        uint256 upperBound
    );
}
