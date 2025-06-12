// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../contracts/libraries/RouteCalculator.sol";

contract RouteCalculatorTest is Test {
    using RouteCalculator for RouteCalculator.RouteParams;

    function testCalculatePriceImpact() public pure {
        uint256 amountIn = 1000e18;
        uint256 liquidity = 100000e18;

        uint256 impact = RouteCalculator.calculatePriceImpact(amountIn, liquidity);
        assertEq(impact, 100, "Price impact should be 1%");
    }

    function testCalculateOutputAmount() public pure {
        uint256 amountIn = 1000e18;
        uint256 reserveIn = 100000e18;
        uint256 reserveOut = 100000e18;
        uint256 fee = 300; // 0.3%

        uint256 output = RouteCalculator.calculateOutputAmount(amountIn, reserveIn, reserveOut, fee);

        assertGt(output, 0, "Should return positive output");
        assertLt(output, amountIn, "Output should be less than input due to fees");
    }

    function testCalculateRouteScore() public pure {
        uint256 expectedOutput = 1000e18;
        uint256 priceImpact = 100; // 1%
        uint256 gasEstimate = 150000;

        uint256 score = RouteCalculator.calculateRouteScore(expectedOutput, priceImpact, gasEstimate);

        assertGt(score, 0, "Should return positive score");
    }

    function testFindBestSplitPercentages() public pure {
        uint256[] memory routeOutputs = new uint256[](3);
        routeOutputs[0] = 1000e18;
        routeOutputs[1] = 950e18;
        routeOutputs[2] = 900e18;

        uint256[] memory routeGasEstimates = new uint256[](3);
        routeGasEstimates[0] = 150000;
        routeGasEstimates[1] = 180000;
        routeGasEstimates[2] = 200000;

        uint256 totalAmount = 1000e18;

        uint256[] memory percentages =
            RouteCalculator.findBestSplitPercentages(routeOutputs, routeGasEstimates, totalAmount);

        assertEq(percentages.length, 3, "Should return 3 percentages");

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < percentages.length; i++) {
            totalPercentage += percentages[i];
        }

        assertLe(totalPercentage, 10000, "Total percentage should not exceed 100%");
    }
}
