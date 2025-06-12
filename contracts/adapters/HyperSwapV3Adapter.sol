// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDEXAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IHyperSwapV3Router {
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

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface IHyperSwapV3Quoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);

    function quoteExactInput(bytes memory path, uint256 amountIn) external returns (uint256 amountOut);
}

interface IHyperSwapV3Pool {
    function liquidity() external view returns (uint128);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

interface IHyperSwapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract HyperSwapV3Adapter is IDEXAdapter {
    using SafeERC20 for IERC20;

    IHyperSwapV3Router public immutable router;
    IHyperSwapV3Quoter public immutable quoter;
    IHyperSwapV3Factory public immutable factory;

    uint24[] public supportedFees = [100, 500, 3000, 10000]; // 0.01%, 0.05%, 0.3%, 1%

    constructor(address _router, address _quoter) {
        router = IHyperSwapV3Router(_router);
        quoter = IHyperSwapV3Quoter(_quoter);
        // In production, get factory from router
        factory = IHyperSwapV3Factory(_quoter); // Using quoter address as mock factory
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, bytes calldata swapData)
        external
        override
        returns (uint256 amountOut)
    {
        uint24 fee = 500; // Default 0.05%

        if (swapData.length > 0) {
            if (swapData.length == 3) {
                fee = abi.decode(swapData, (uint24));
            } else {
                // Multi-hop path
                return _executeMultiHopSwap(tokenIn, tokenOut, amountIn, minAmountOut, swapData);
            }
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        IHyperSwapV3Router.ExactInputSingleParams memory params = IHyperSwapV3Router.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        return router.exactInputSingle(params);
    }

    function getQuote(address tokenIn, address tokenOut, uint256 amountIn, bytes calldata swapData)
        external
        override
        returns (uint256 amountOut, uint256 gasEstimate)
    {
        if (swapData.length > 3) {
            // Multi-hop path
            try quoter.quoteExactInput(swapData, amountIn) returns (uint256 output) {
                return (output, 250000); // Higher gas for multi-hop
            } catch {
                return (0, 250000);
            }
        }

        uint24 fee = 500; // Default 0.05%
        if (swapData.length == 3) {
            fee = abi.decode(swapData, (uint24));
        }

        // Find best fee tier if not specified
        if (swapData.length == 0) {
            (amountOut, fee) = _findBestFeeTier(tokenIn, tokenOut, amountIn);
            return (amountOut, 180000);
        }

        try quoter.quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, 0) returns (uint256 output) {
            return (output, 180000);
        } catch {
            return (0, 180000);
        }
    }

    function getDEXName() external pure override returns (string memory) {
        return "HyperSwap V3";
    }

    function getSupportedFeeTiers() external view override returns (uint256[] memory) {
        uint256[] memory fees = new uint256[](supportedFees.length);
        for (uint256 i = 0; i < supportedFees.length; i++) {
            fees[i] = supportedFees[i];
        }
        return fees;
    }

    function _executeMultiHopSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata path
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        IHyperSwapV3Router.ExactInputParams memory params = IHyperSwapV3Router.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut
        });

        return router.exactInput(params);
    }

    function _findBestFeeTier(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 bestOutput, uint24 bestFee)
    {
        bestOutput = 0;
        bestFee = 500;

        for (uint256 i = 0; i < supportedFees.length; i++) {
            try quoter.quoteExactInputSingle(tokenIn, tokenOut, supportedFees[i], amountIn, 0) returns (uint256 output)
            {
                if (output > bestOutput) {
                    bestOutput = output;
                    bestFee = supportedFees[i];
                }
            } catch {
                continue;
            }
        }
    }

    function getPoolLiquidity(address tokenA, address, /*tokenB*/ uint24 fee)
        external
        view
        returns (uint128 liquidity)
    {
        address pool = factory.getPool(tokenA, tokenA, fee);
        if (pool == address(0)) return 0;

        return IHyperSwapV3Pool(pool).liquidity();
    }

    function getPoolPrice(address tokenA, address, /*tokenB*/ uint24 fee)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick)
    {
        address pool = factory.getPool(tokenA, tokenA, fee);
        if (pool == address(0)) return (0, 0);

        (sqrtPriceX96, tick,,,,,) = IHyperSwapV3Pool(pool).slot0();
    }

    function calculateConcentratedLiquidityImpact(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee)
        external
        view
        returns (uint256 priceImpact)
    {
        uint128 liquidity = this.getPoolLiquidity(tokenIn, tokenIn, fee);
        if (liquidity == 0) return 10000; // 100% impact

        // Simplified calculation for concentrated liquidity impact
        uint256 liquidityRatio = (amountIn * 10000) / uint256(liquidity);

        // Adjust for fee tier - lower fees typically have tighter ranges
        uint256 feeMultiplier = fee < 500 ? 150 : fee < 3000 ? 100 : 50;
        priceImpact = (liquidityRatio * feeMultiplier) / 100;

        return priceImpact > 10000 ? 10000 : priceImpact;
    }
}
