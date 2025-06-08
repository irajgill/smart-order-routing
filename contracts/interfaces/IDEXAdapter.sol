// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IDEXAdapter {
    /**
     * Execute a swap through the DEX
     * tokenIn Input token address
     * tokenOut Output token address
     * amountIn Amount of input tokens
     * minAmountOut Minimum amount of output tokens
     * swapData Additional data for the swap (path, fees, etc.)
     * @return amountOut Actual amount of output tokens received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata swapData
    ) external returns (uint256 amountOut);

    /**
     * Get a quote for a potential swap
     * tokenIn Input token address
     * tokenOut Output token address
     * amountIn Amount of input tokens
     * swapData Additional data for the quote
     * @return amountOut Expected output amount
     * @return gasEstimate Estimated gas cost for the swap
     */
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata swapData
    ) external returns (uint256 amountOut, uint256 gasEstimate);

    /**
     * Get the name of the DEX
     * @return name Human-readable name of the DEX
     */
    function getDEXName() external view returns (string memory name);

    /**
     * Get supported fee tiers for this DEX
     * @return fees Array of supported fee tiers in basis points
     */
    function getSupportedFeeTiers() external view returns (uint256[] memory fees);
}
