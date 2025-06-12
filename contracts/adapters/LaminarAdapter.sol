// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDEXAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ILaminarRouter {
    struct RouteInfo {
        address[] path;
        address[] adapters;
        uint256[] fees;
        bytes[] swapData;
    }

    function getOptimalSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, bytes memory routeData);

    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external returns (uint256 amountOut);

    
    function getAggregatedLiquidity(
        address tokenA,
        address tokenB
    ) external returns (uint256 totalLiquidity, uint256 hyperEVMLiquidity, uint256 hyperCoreLiquidity, address[] memory sources);

    function getCrossLayerRoutes(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (RouteInfo[] memory routes);
}

interface ILaminarHyperCoreAdapter {
    function getHyperCorePrice(
        address tokenA,
        address tokenB,
        uint256 amount
    ) external view returns (uint256 price, uint256 liquidity);

    function executeHyperCoreSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);
}

interface ILaminarBridge {
    function bridgeToHyperCore(
        address token,
        uint256 amount,
        bytes calldata swapData
    ) external returns (bytes32 bridgeId);

    function bridgeFromHyperCore(
        address token,
        uint256 amount,
        address recipient
    ) external returns (uint256 amountReceived);
}

contract LaminarAdapter is IDEXAdapter {
    using SafeERC20 for IERC20;
    
    ILaminarRouter public immutable laminarRouter;
    ILaminarHyperCoreAdapter public immutable hyperCoreAdapter;
    ILaminarBridge public immutable bridge;
    
    uint256 private constant BASE_FEE_RATE = 10; // 0.01%
    uint256 private constant CROSS_LAYER_FEE = 20; // 0.02% for cross-layer
    
    mapping(address => mapping(address => uint256)) public pairLiquidity;
    mapping(address => bool) public supportedHyperCoreTokens;
    
    event CrossLayerSwap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        string layer
    );

    event LiquidityAggregated(
        address indexed tokenA,
        address indexed tokenB,
        uint256 totalLiquidity,
        uint256 sources
    );

    constructor(address _laminarRouter) {
        laminarRouter = ILaminarRouter(_laminarRouter);
        hyperCoreAdapter = ILaminarHyperCoreAdapter(_laminarRouter);
        bridge = ILaminarBridge(_laminarRouter);
        
        supportedHyperCoreTokens[0x2222222222222222222222222222222222222222] = true; // HYPE
        supportedHyperCoreTokens[0x1111111111111111111111111111111111111111] = true; // USDC
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata swapData
    ) external override returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(laminarRouter), amountIn);
        
        if (_shouldUseCrossLayer(tokenIn, tokenOut, amountIn)) {
            return _executeCrossLayerSwap(tokenIn, tokenOut, amountIn, minAmountOut, swapData);
        }
        
        return laminarRouter.executeSwap(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut,
            swapData
        );
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata /* swapData */
    ) external view override returns (uint256 amountOut, uint256 gasEstimate) {
        try laminarRouter.getOptimalSwap(tokenIn, tokenOut, amountIn) 
        returns (uint256 optimal, bytes memory) {
            
            if (_shouldUseCrossLayer(tokenIn, tokenOut, amountIn)) {
                uint256 crossLayerOutput = _getCrossLayerQuote(tokenIn, tokenOut, amountIn);
                if (crossLayerOutput > optimal) {
                    return (crossLayerOutput, 200000);
                }
            }
            
            return (optimal, 120000);
        } catch {
            return (0, 120000);
        }
    }

    function getDEXName() external pure override returns (string memory) {
        return "Laminar";
    }
    
    function getSupportedFeeTiers() external pure override returns (uint256[] memory) {
        uint256[] memory fees = new uint256[](2);
        fees[0] = BASE_FEE_RATE;
        fees[1] = CROSS_LAYER_FEE;
        return fees;
    }

    function _executeCrossLayerSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata swapData
    ) internal returns (uint256 amountOut) {
        (uint256 hyperCorePrice,) = hyperCoreAdapter.getHyperCorePrice(tokenIn, tokenOut, amountIn);
        (uint256 hyperEVMPrice,) = laminarRouter.getOptimalSwap(tokenIn, tokenOut, amountIn);
        
        if (hyperCorePrice > hyperEVMPrice) {
            amountOut = _executeOnHyperCore(tokenIn, tokenOut, amountIn, minAmountOut);
            emit CrossLayerSwap(tokenIn, tokenOut, amountIn, amountOut, "HyperCore");
        } else {
            amountOut = laminarRouter.executeSwap(tokenIn, tokenOut, amountIn, minAmountOut, swapData);
            emit CrossLayerSwap(tokenIn, tokenOut, amountIn, amountOut, "HyperEVM");
        }
        
        return amountOut;
    }

    function _executeOnHyperCore(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        if (!supportedHyperCoreTokens[tokenIn]) {
            revert("Token not supported on HyperCore");
        }
        
        amountOut = hyperCoreAdapter.executeHyperCoreSwap(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );
        
        if (!supportedHyperCoreTokens[tokenOut]) {
            amountOut = bridge.bridgeFromHyperCore(tokenOut, amountOut, msg.sender);
        }
        
        return amountOut;
    }

    function _shouldUseCrossLayer(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (bool) {
        if (amountIn < 10000 * 10**18) return false;
        
        try hyperCoreAdapter.getHyperCorePrice(tokenIn, tokenOut, amountIn) 
        returns (uint256 corePrice, uint256) {
            try laminarRouter.getOptimalSwap(tokenIn, tokenOut, amountIn) 
            returns (uint256 evmPrice, bytes memory) {
                uint256 priceDiff = corePrice > evmPrice ? 
                    ((corePrice - evmPrice) * 10000) / evmPrice :
                    ((evmPrice - corePrice) * 10000) / corePrice;
                
                return priceDiff > 50;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function _getCrossLayerQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256) {
        try hyperCoreAdapter.getHyperCorePrice(tokenIn, tokenOut, amountIn) 
        returns (uint256 corePrice, uint256) {
            try laminarRouter.getOptimalSwap(tokenIn, tokenOut, amountIn) 
            returns (uint256 evmPrice, bytes memory) {
                return corePrice > evmPrice ? corePrice : evmPrice;
            } catch {
                return corePrice;
            }
        } catch {
            return 0;
        }
    }


    function getAggregatedLiquidity(
        address tokenA,
        address tokenB
    ) external returns (
        uint256 totalLiquidity,
        uint256 hyperEVMLiquidity,
        uint256 hyperCoreLiquidity,
        address[] memory sources
    ) {
        
        (uint256 _totalLiquidity, uint256 _hyperEVMLiquidity, uint256 _hyperCoreLiquidity, address[] memory _sources) = laminarRouter.getAggregatedLiquidity(tokenA, tokenB);
        
        
        totalLiquidity = _totalLiquidity;
        hyperEVMLiquidity = _hyperEVMLiquidity;
        hyperCoreLiquidity = _hyperCoreLiquidity;
        sources = _sources;
        
        emit LiquidityAggregated(tokenA, tokenB, totalLiquidity, sources.length);
    }

    function getCrossLayerArbitrageOpportunity(
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) external view returns (
        bool hasOpportunity,
        uint256 expectedProfit,
        string memory optimalLayer
    ) {
        try hyperCoreAdapter.getHyperCorePrice(tokenA, tokenB, amountIn) 
        returns (uint256 corePrice, uint256) {
            try laminarRouter.getOptimalSwap(tokenA, tokenB, amountIn) 
            returns (uint256 evmPrice, bytes memory) {
                if (corePrice > evmPrice) {
                    expectedProfit = corePrice - evmPrice;
                    optimalLayer = "HyperCore";
                    hasOpportunity = expectedProfit > (amountIn * CROSS_LAYER_FEE) / 10000;
                } else if (evmPrice > corePrice) {
                    expectedProfit = evmPrice - corePrice;
                    optimalLayer = "HyperEVM";
                    hasOpportunity = expectedProfit > (amountIn * CROSS_LAYER_FEE) / 10000;
                } else {
                    hasOpportunity = false;
                    expectedProfit = 0;
                    optimalLayer = "None";
                }
            } catch {
                hasOpportunity = false;
                expectedProfit = 0;
                optimalLayer = "None";
            }
        } catch {
            hasOpportunity = false;
            expectedProfit = 0;
            optimalLayer = "None";
        }
    }

    function updatePairLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external {
        pairLiquidity[tokenA][tokenB] = liquidity;
        pairLiquidity[tokenB][tokenA] = liquidity;
    }

    function addHyperCoreToken(address token) external {
        supportedHyperCoreTokens[token] = true;
    }

    function removeHyperCoreToken(address token) external {
        supportedHyperCoreTokens[token] = false;
    }

    function calculateAggregatedPriceImpact(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 priceImpact) {
    
        (uint256 totalLiq,,,) = laminarRouter.getAggregatedLiquidity(tokenIn, tokenOut);
        
        if (totalLiq == 0) return 10000;
        
        uint256 baseImpact = (amountIn * 10000) / totalLiq;
        priceImpact = (baseImpact * 80) / 100;
        
        return priceImpact > 10000 ? 10000 : priceImpact;
    }
    
}
