// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISOR {
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address recipient;
        uint256 deadline;
        bool useGasOptimization;
    }

    struct RouteStep {
        address dexAdapter;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        bytes swapData;
        uint256 minAmountOut;
    }

    struct SplitRoute {
        RouteStep[] steps;
        uint256 percentage;
        uint256 expectedOutput;
        uint256 gasEstimate;
    }

    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 gasUsed,
        uint256 splits
    );

    event RouteOptimized(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 expectedSavings,
        uint256 routeCount
    );

    /**
     * Execute optimal swap across multiple DEX protocols
     * Swap parameters including tokens, amounts, and preferences
     * @return amountOut The amount of output tokens received
     */
    function executeOptimalSwap(SwapParams calldata params) external payable returns (uint256 amountOut);
    
    /**
     * Get quote for potential swap without execution
     * tokenIn Input token address
     * tokenOut Output token address
     * amountIn Amount of input tokens
     * @return amountOut Expected output amount
     * @return gasEstimate Estimated gas cost
     * @return routes Array of split routes
     */
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (
        uint256 amountOut,
        uint256 gasEstimate,
        SplitRoute[] memory routes
    );

    /**
     *  Check if a token is supported by the router
     * token Token address to check
     * @return supported True if token is supported
     */
    function supportedTokens(address token) external view returns (bool supported);

    /**
     * Get the current platform fee in basis points
     * @return fee Platform fee in basis points (100 = 1%)
     */
    function platformFee() external view returns (uint256 fee);

    /**
     * Get the maximum allowed slippage in basis points
     * @return slippage Maximum slippage in basis points
     */
    function maxSlippageBps() external view returns (uint256 slippage);
}
