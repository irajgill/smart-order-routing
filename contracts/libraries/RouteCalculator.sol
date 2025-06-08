// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library RouteCalculator {
    struct RouteParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 maxSplits;
        uint256 gasPrice;
    }

    struct RouteResult {
        address[] path;
        uint256 expectedOutput;
        uint256 priceImpact;
        uint256 gasEstimate;
        uint256 score;
    }

    uint256 constant PRECISION = 1e18;
    uint256 constant MAX_PRICE_IMPACT = 1000; // 10%

    function calculateOptimalRoute(
        RouteParams memory params,
        address[] memory /*availableAdapters */
    ) internal pure returns (RouteResult memory) {
        RouteResult memory result;
        result.path = new address[](2);
        result.path[0] = params.tokenIn;
        result.path[1] = params.tokenOut;
        
        // Simulate route calculation with mock data
        result.expectedOutput = params.amountIn * 997 / 1000; // 0.3% fee simulation
        result.priceImpact = calculatePriceImpact(params.amountIn, PRECISION * 1000000); // Mock liquidity
        result.gasEstimate = 150000;
        result.score = calculateRouteScore(result.expectedOutput, result.priceImpact, result.gasEstimate);
        
        return result;
    }

    function calculatePriceImpact(
        uint256 amountIn,
        uint256 liquidity
    ) internal pure returns (uint256) {
        if (liquidity == 0) return MAX_PRICE_IMPACT;
        
        uint256 impact = (amountIn * 10000) / liquidity;
        return impact > MAX_PRICE_IMPACT ? MAX_PRICE_IMPACT : impact;
    }

    function calculateOutputAmount(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 fee
    ) internal pure returns (uint256) {
        require(amountIn > 0, "RouteCalculator: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "RouteCalculator: INSUFFICIENT_LIQUIDITY");
        
        uint256 amountInWithFee = amountIn * (10000 - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 10000) + amountInWithFee;
        
        return numerator / denominator;
    }

    function calculateRouteScore(
        uint256 expectedOutput,
        uint256 priceImpact,
        uint256 gasEstimate
    ) internal pure returns (uint256) {
        // Higher output = higher score
        uint256 outputScore = expectedOutput / 1e15; // Normalize to reasonable range
        
        // Lower impact = higher score
        uint256 impactPenalty = priceImpact * 10;
        
        // Lower gas = higher score
        uint256 gasPenalty = gasEstimate / 10000;
        
        uint256 score = outputScore > (impactPenalty + gasPenalty) ? 
            outputScore - impactPenalty - gasPenalty : 0;
            
        return score;
    }

    function optimizeMultiHopRoute(
        address[] memory tokens,
        uint256[] memory reserves,
        uint256[] memory fees,
        uint256 amountIn
    ) internal pure returns (uint256 finalOutput) {
        uint256 currentAmount = amountIn;
        
        for (uint256 i = 0; i < tokens.length - 1; i++) {
            currentAmount = calculateOutputAmount(
                currentAmount,
                reserves[i * 2],
                reserves[i * 2 + 1],
                fees[i]
            );
        }
        
        return currentAmount;
    }

    function findBestSplitPercentages(
        uint256[] memory routeOutputs,
        uint256[] memory routeGasEstimates,
        uint256 /*totalAmount*/
    ) internal pure returns (uint256[] memory percentages) {
        uint256 routeCount = routeOutputs.length;
        percentages = new uint256[](routeCount);
        
        if (routeCount == 1) {
            percentages[0] = 10000; // 100%
            return percentages;
        }
        
        // Calculate efficiency scores
        uint256[] memory scores = new uint256[](routeCount);
        uint256 totalScore = 0;
        
        for (uint256 i = 0; i < routeCount; i++) {
            // Score based on output per gas ratio
            scores[i] = routeGasEstimates[i] > 0 ? 
                (routeOutputs[i] * 1e18) / routeGasEstimates[i] : 0;
            totalScore += scores[i];
        }
        
        // Distribute based on scores
        for (uint256 i = 0; i < routeCount; i++) {
            percentages[i] = totalScore > 0 ? (scores[i] * 10000) / totalScore : 0;
            
            // Minimum 5% allocation if route is viable
            if (percentages[i] > 0 && percentages[i] < 500) {
                percentages[i] = 500;
            }
        }
        
        // Normalize to 100%
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < routeCount; i++) {
            totalPercentage += percentages[i];
        }
        
        if (totalPercentage > 10000) {
            for (uint256 i = 0; i < routeCount; i++) {
                percentages[i] = (percentages[i] * 10000) / totalPercentage;
            }
        }
        
        return percentages;
    }
}
