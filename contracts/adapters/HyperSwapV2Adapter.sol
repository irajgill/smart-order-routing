// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDEXAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IHyperSwapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);

    function factory() external pure returns (address);
    
    function WETH() external pure returns (address);
}

interface IHyperSwapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IHyperSwapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract HyperSwapV2Adapter is IDEXAdapter {
    using SafeERC20 for IERC20;
    
    IHyperSwapV2Router public immutable router;
    IHyperSwapV2Factory public immutable factory;
    
    uint256 private constant FEE_RATE = 300; // 0.3%
    
    constructor(address _router) {
        router = IHyperSwapV2Router(_router);
        factory = IHyperSwapV2Factory(router.factory());
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata swapData
    ) external override returns (uint256 amountOut) {
        address[] memory path;
        
        if (swapData.length > 0) {
            path = abi.decode(swapData, (address[]));
        } else {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        }
        
        require(path[0] == tokenIn && path[path.length - 1] == tokenOut, "HyperSwapV2: Invalid path");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        uint[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            msg.sender,
            block.timestamp + 300
        );

        return amounts[amounts.length - 1];
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata swapData
    ) external view override returns (uint256 amountOut, uint256 gasEstimate) {
        address[] memory path;
        
        if (swapData.length > 0) {
            path = abi.decode(swapData, (address[]));
        } else {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        }
        
        try router.getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
            return (amounts[amounts.length - 1], 150000);
        } catch {
            return (0, 150000);
        }
    }

    function getDEXName() external pure override returns (string memory) {
        return "HyperSwap V2";
    }
    
    function getSupportedFeeTiers() external pure override returns (uint256[] memory) {
        uint256[] memory fees = new uint256[](1);
        fees[0] = FEE_RATE;
        return fees;
    }

    function getPairLiquidity(address tokenA, address tokenB) external view returns (uint256 liquidity) {
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) return 0;
        
        (uint112 reserve0, uint112 reserve1,) = IHyperSwapV2Pair(pair).getReserves();
        address token0 = IHyperSwapV2Pair(pair).token0();
        
        if (token0 == tokenA) {
            liquidity = uint256(reserve0);
        } else {
            liquidity = uint256(reserve1);
        }
    }

    function calculatePriceImpact(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 priceImpact) {
        address pair = factory.getPair(tokenIn, tokenOut);
        if (pair == address(0)) return 10000; // 100% if no pair
        
        (uint112 reserve0, uint112 reserve1,) = IHyperSwapV2Pair(pair).getReserves();
        address token0 = IHyperSwapV2Pair(pair).token0();
        
        uint256 reserveIn = token0 == tokenIn ? uint256(reserve0) : uint256(reserve1);
        
        if (reserveIn == 0) return 10000;
        
        // Price impact = (amountIn / reserveIn) * 10000
        priceImpact = (amountIn * 10000) / reserveIn;
        return priceImpact > 10000 ? 10000 : priceImpact;
    }
}
