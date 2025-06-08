// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockDEXRouter {
    using SafeERC20 for IERC20;

    // Mock HyperSwap V2 Router
    function swapExactTokensForTokens(
        uint amountIn,
        uint /*amountOutMin*/,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        require(block.timestamp <= deadline, "Expired");
        
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        // Transfer input tokens
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Calculate output (simulate 0.3% fee)
        uint256 amountOut = (amountIn * 997) / 1000;
        amounts[path.length - 1] = amountOut;
        
        // Transfer output tokens
        IERC20(path[path.length - 1]).safeTransfer(to, amountOut);
    }

    function getAmountsOut(uint amountIn, address[] calldata path)
        external pure returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        // Simulate output calculation
        amounts[path.length - 1] = (amountIn * 997) / 1000;
    }

    function getAmountsOutStable(uint amountIn, address[] calldata path)
        external pure returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        
        // Simulate stable swap with lower fees
        amounts[path.length - 1] = (amountIn * 9999) / 10000;
    }

    // Mock HyperSwap V3 Router
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external returns (uint256 amountOut) {
        require(block.timestamp <= params.deadline, "Expired");
        
        // Transfer input tokens
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        
        // Calculate output based on fee tier
        uint256 feeRate = params.fee;
        amountOut = (params.amountIn * (1000000 - feeRate)) / 1000000;
        
        require(amountOut >= params.amountOutMinimum, "Insufficient output");
        
        // Transfer output tokens
        IERC20(params.tokenOut).safeTransfer(params.recipient, amountOut);
    }

    // Mock quoter
    function quoteExactInputSingle(
        address /*tokenIn*/,
        address /*tokenOut*/,
        uint24 fee,
        uint256 amountIn,
        uint160 /*sqrtPriceLimitX96*/
    ) external pure returns (uint256 amountOut) {
        amountOut = (amountIn * (1000000 - fee)) / 1000000;
    }

    // Mock Laminar Router
    function getOptimalSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external pure returns (uint256 amountOut, bytes memory routeData) {
        amountOut = (amountIn * 9998) / 10000; // 0.02% fee
        routeData = abi.encode("laminar_route");
    }

    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata /*routeData*/
    ) external returns (uint256 amountOut) {
        // Transfer input tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        amountOut = (amountIn * 9998) / 10000;
        require(amountOut >= minAmountOut, "Insufficient output");
        
        // Transfer output tokens
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
}
