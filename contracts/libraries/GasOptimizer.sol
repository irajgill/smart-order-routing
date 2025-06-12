// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library GasOptimizer {
    struct GasParams {
        uint256 gasPrice;
        uint256 ethPrice; // In USD with 18 decimals
        uint256 maxGasCostUSD; // In USD with 18 decimals
    }

    struct OptimizationResult {
        bool isOptimal;
        uint256 adjustedScore;
        uint256 gasSavings;
        uint256 netBenefit;
    }

    uint256 constant USD_PRECISION = 1e18;
    uint256 constant GAS_BUFFER = 120; // 20% buffer

    function optimizeForGas(
        uint256 routeGasEstimate,
        uint256 baselineGas,
        uint256 outputImprovement,
        GasParams memory params
    ) internal pure returns (OptimizationResult memory) {
        OptimizationResult memory result;

        uint256 additionalGas = routeGasEstimate > baselineGas ? routeGasEstimate - baselineGas : 0;

        uint256 gasCostWei = additionalGas * params.gasPrice;
        uint256 gasCostUSD = (gasCostWei * params.ethPrice) / 1e18;

        // Check if gas cost is within acceptable limits
        result.isOptimal = gasCostUSD <= params.maxGasCostUSD && outputImprovement > gasCostWei;

        if (result.isOptimal) {
            result.netBenefit = outputImprovement > gasCostWei ? outputImprovement - gasCostWei : 0;

            result.adjustedScore = outputImprovement > 0 ? (result.netBenefit * 100) / outputImprovement : 0;

            result.gasSavings = result.netBenefit;
        }

        return result;
    }

    function calculateMinTradeSize(uint256 gasEstimate, uint256 gasPrice, uint256 tokenPrice)
        internal
        pure
        returns (uint256)
    {
        uint256 gasCostWei = gasEstimate * gasPrice * GAS_BUFFER / 100;
        uint256 minTradeValueWei = gasCostWei * 10; // 10x gas cost minimum

        return tokenPrice > 0 ? (minTradeValueWei * 1e18) / tokenPrice : 0;
    }

    function estimateComplexRouteGas(uint256 baseGas, uint256 hops, uint256 splits, bool hasNativeToken)
        internal
        pure
        returns (uint256)
    {
        uint256 hopGas = hops * 80000; // 80k gas per hop
        uint256 splitGas = splits > 1 ? (splits - 1) * 50000 : 0; // 50k gas per additional split
        uint256 nativeGas = hasNativeToken ? 2300 : 0; // Native token transfer

        return baseGas + hopGas + splitGas + nativeGas;
    }

    function calculateGasEfficiencyScore(uint256 outputImprovement, uint256 gasUsed, uint256 gasPrice, uint256 ethPrice)
        internal
        pure
        returns (uint256)
    {
        uint256 gasCostWei = gasUsed * gasPrice;
        uint256 gasCostUSD = (gasCostWei * ethPrice) / 1e18;

        if (outputImprovement == 0) return 0;

        // Score: output improvement per dollar of gas spent
        uint256 outputUSD = (outputImprovement * ethPrice) / 1e18;

        return gasCostUSD > 0 ? (outputUSD * 100) / gasCostUSD : 0;
    }

    function shouldUseComplexRoute(
        uint256 simpleRouteOutput,
        uint256 complexRouteOutput,
        uint256 simpleRouteGas,
        uint256 complexRouteGas,
        GasParams memory params
    ) internal pure returns (bool) {
        uint256 outputImprovement = complexRouteOutput > simpleRouteOutput ? complexRouteOutput - simpleRouteOutput : 0;

        if (outputImprovement == 0) return false;

        uint256 additionalGas = complexRouteGas > simpleRouteGas ? complexRouteGas - simpleRouteGas : 0;

        uint256 additionalGasCost = additionalGas * params.gasPrice;

        // Use complex route if output improvement exceeds additional gas cost by at least 50%
        return outputImprovement >= (additionalGasCost * 150) / 100;
    }

    function optimizeGasPrice(
        uint256 currentGasPrice,
        uint256 urgency, // 0-100, higher = more urgent
        uint256 networkCongestion // 0-100, higher = more congested
    ) internal pure returns (uint256) {
        uint256 baseMultiplier = 100;
        uint256 urgencyMultiplier = urgency * 2; // 0-200%
        uint256 congestionMultiplier = networkCongestion; // 0-100%

        uint256 totalMultiplier = baseMultiplier + urgencyMultiplier + congestionMultiplier;

        return (currentGasPrice * totalMultiplier) / 100;
    }
}
