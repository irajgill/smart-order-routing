// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILaminarRouter {
    struct RouteInfo {
        address[] path;
        address[] adapters;
        uint256[] fees;
        bytes[] swapData;
        string[] layers; // "HyperEVM" or "HyperCore"
    }

    struct LiquiditySource {
        address adapter;
        string name;
        uint256 liquidity;
        uint256 fee;
        string layer;
    }

    event OptimalRouteFound(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 expectedOutput, uint256 sources
    );

    event CrossLayerSwap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        string fromLayer,
        string toLayer
    );

    function getOptimalSwap(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, bytes memory routeData);

    function executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata routeData
    ) external returns (uint256 amountOut);

    function getAggregatedLiquidity(address tokenA, address tokenB)
        external
        view
        returns (uint256 totalLiquidity, address[] memory sources);

    function getCrossLayerRoutes(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (RouteInfo[] memory routes);

    function getAllLiquiditySources(address tokenA, address tokenB)
        external
        view
        returns (LiquiditySource[] memory sources);

    function estimateCrossLayerGas(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 gasEstimate);
}

interface ILaminarHyperCoreAdapter {
    struct HyperCoreOrderbook {
        uint256 bestBid;
        uint256 bestAsk;
        uint256 bidLiquidity;
        uint256 askLiquidity;
        uint256 spread;
    }

    event HyperCoreSwapExecuted(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, uint256 executionPrice
    );

    function getHyperCorePrice(address tokenA, address tokenB, uint256 amount)
        external
        view
        returns (uint256 price, uint256 liquidity);

    function executeHyperCoreSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);

    function getOrderbook(address tokenA, address tokenB) external view returns (HyperCoreOrderbook memory orderbook);

    function estimateSlippage(address tokenA, address tokenB, uint256 amountIn)
        external
        view
        returns (uint256 slippage);

    function isHyperCoreToken(address token) external view returns (bool);

    function getHyperCoreLiquidity(address tokenA, address tokenB) external view returns (uint256 totalLiquidity);
}

interface ILaminarBridge {
    enum BridgeStatus {
        Pending,
        Confirmed,
        Failed,
        Cancelled
    }

    struct BridgeTransaction {
        bytes32 id;
        address token;
        uint256 amount;
        address from;
        address to;
        string fromLayer;
        string toLayer;
        BridgeStatus status;
        uint256 timestamp;
        uint256 fee;
    }

    event BridgeInitiated(
        bytes32 indexed bridgeId,
        address indexed token,
        uint256 amount,
        address indexed from,
        string fromLayer,
        string toLayer
    );

    event BridgeCompleted(
        bytes32 indexed bridgeId, address indexed token, uint256 amount, address indexed to, uint256 fee
    );

    event BridgeFailed(bytes32 indexed bridgeId, string reason);

    function bridgeToHyperCore(address token, uint256 amount, bytes calldata swapData)
        external
        returns (bytes32 bridgeId);

    function bridgeFromHyperCore(address token, uint256 amount, address recipient)
        external
        returns (uint256 amountReceived);

    function getBridgeTransaction(bytes32 bridgeId) external view returns (BridgeTransaction memory);

    function estimateBridgeFee(address token, uint256 amount, string calldata fromLayer, string calldata toLayer)
        external
        view
        returns (uint256 fee);

    function getBridgeStatus(bytes32 bridgeId) external view returns (BridgeStatus);

    function cancelBridge(bytes32 bridgeId) external;

    function isBridgeSupported(address token) external view returns (bool);

    function getBridgeCapacity(address token) external view returns (uint256 capacity);
}

interface ILaminarAggregator {
    struct AggregationResult {
        uint256 totalOutput;
        uint256 totalGas;
        uint256 priceImpact;
        address[] sources;
        uint256[] allocations;
        bytes[] swapData;
    }

    function aggregateSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxSources
    ) external returns (AggregationResult memory result);

    function getAggregationQuote(address tokenIn, address tokenOut, uint256 amountIn, uint256 maxSources)
        external
        view
        returns (AggregationResult memory result);

    function addLiquiditySource(address source, string calldata name, uint256 weight) external;

    function removeLiquiditySource(address source) external;

    function updateSourceWeight(address source, uint256 weight) external;

    function getActiveSources() external view returns (address[] memory sources);

    function getSourceInfo(address source)
        external
        view
        returns (string memory name, uint256 weight, bool active, uint256 totalVolume);
}
