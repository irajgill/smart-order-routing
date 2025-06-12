// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRouteOptimizer {
    struct OptimizationParams {
        uint256 maxSplits;
        uint256 minSplitPercentage;
        uint256 gasPrice;
        uint256 maxGasCost;
        bool prioritizeGas;
        bool prioritizePrice;
    }

    struct RouteCandidate {
        address[] path;
        address[] adapters;
        uint256 expectedOutput;
        uint256 gasEstimate;
        uint256 priceImpact;
        uint256 score;
        bytes swapData;
    }

    struct OptimizedRoute {
        RouteCandidate[] routes;
        uint256[] allocations;
        uint256 totalOutput;
        uint256 totalGas;
        uint256 averageImpact;
        uint256 optimizationScore;
    }

    event RouteOptimized(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 routeCount,
        uint256 totalOutput,
        uint256 optimizationScore
    );

    function optimizeRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        RouteCandidate[] memory candidates,
        OptimizationParams memory params
    ) external view returns (OptimizedRoute memory optimized);

    function calculateRouteScore(RouteCandidate memory route, OptimizationParams memory params)
        external
        pure
        returns (uint256 score);

    function findOptimalSplits(RouteCandidate[] memory routes, uint256 totalAmount, OptimizationParams memory params)
        external
        pure
        returns (uint256[] memory allocations);

    function estimateGasSavings(OptimizedRoute memory optimized, RouteCandidate memory baseline)
        external
        pure
        returns (uint256 gasSavings, uint256 percentageSaved);

    function validateRoute(RouteCandidate memory route, OptimizationParams memory params)
        external
        pure
        returns (bool isValid, string memory reason);

    function getOptimizationMetrics(OptimizedRoute memory optimized, RouteCandidate memory baseline)
        external
        pure
        returns (uint256 priceImprovement, uint256 gasSavings, uint256 efficiencyScore);
}
