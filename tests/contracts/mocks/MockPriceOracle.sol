// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../../contracts/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    mapping(bytes32 => PriceData) private prices;
    mapping(bytes32 => uint256) private lastUpdate;

    function getPrice(address tokenA, address tokenB) external view override returns (PriceData memory) {
        bytes32 key = keccak256(abi.encodePacked(tokenA, tokenB));
        PriceData memory priceData = prices[key];
        
        if (priceData.price == 0) {
            return PriceData({
                price: 1e18,
                timestamp: block.timestamp,
                confidence: 95
            });
        }
        
        return priceData;
    }
    
    function getTWAP(
        address tokenA,
        address tokenB,
        uint256 /*period*/
    ) external view override returns (uint256 price) {
        PriceData memory priceData = this.getPrice(tokenA, tokenB);
        return priceData.price;
    }
    
    function updatePrice(
        address tokenA,
        address tokenB,
        uint256 price
    ) external override {
        bytes32 key = keccak256(abi.encodePacked(tokenA, tokenB));
        prices[key] = PriceData({
            price: price,
            timestamp: block.timestamp,
            confidence: 95
        });
        lastUpdate[key] = block.timestamp;
    }

    function isValidPrice(address tokenA, address tokenB) external view override returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(tokenA, tokenB));
        return prices[key].price > 0;
    }
    
    function getLastUpdateTime(address tokenA, address tokenB) external view override returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(tokenA, tokenB));
        return lastUpdate[key];
    }

    // Add missing implementation
    function getPriceWithBounds(
        address tokenA,
        address tokenB
    ) external view override returns (
        uint256 price,
        uint256 lowerBound,
        uint256 upperBound
    ) {
        PriceData memory priceData = this.getPrice(tokenA, tokenB);
        price = priceData.price;
        lowerBound = (price * 95) / 100; // 5% lower bound
        upperBound = (price * 105) / 100; // 5% upper bound
    }
}
