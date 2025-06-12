// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { SORRouter } from "../contracts/core/SORRouter.sol";

contract BenchmarkScript is Script {
    function setUp() public { }

    function run() public {
        address sorRouterAddress = vm.envAddress("SOR_ROUTER_ADDRESS");
        address hypeToken = 0x2222222222222222222222222222222222222222;
        address usdcToken = 0x1111111111111111111111111111111111111111;

        SORRouter sorRouter = SORRouter(payable(sorRouterAddress));

        console.log("Running Hyperliquid SOR benchmarks...");
        console.log("SOR Router:", sorRouterAddress);

        // Test scenarios
        uint256[4] memory testAmounts;
        testAmounts[0] = 1000 ether;
        testAmounts[1] = 10000 ether;
        testAmounts[2] = 100000 ether;
        testAmounts[3] = 1000000 ether;

        string[4] memory testNames =
            ["Small Trade (1K HYPE)", "Medium Trade (10K HYPE)", "Large Trade (100K HYPE)", "Whale Trade (1M HYPE)"];

        for (uint256 i = 0; i < testAmounts.length; i++) {
            console.log("Testing:", testNames[i]);

            try sorRouter.getSwapQuote(hypeToken, usdcToken, testAmounts[i]) returns (
                uint256 amountOut, uint256 gasEstimate, SORRouter.SplitRoute[] memory routes
            ) {
                // Calculate improvement vs single DEX
                uint256 singleDexOutput = testAmounts[i] * 997 / 1000; // 0.3% fee
                uint256 improvement = (amountOut - singleDexOutput) * 10000 / singleDexOutput;

                console.log("  Output:", amountOut);
                console.log("  Gas:", gasEstimate);
                console.log("  Routes:", routes.length);
                console.log("  Improvement:", improvement, "bps");
                console.log("  ---");
            } catch {
                console.log("  Failed to get quote");
                console.log("  ---");
            }
        }

        console.log("Benchmark completed!");
    }
}
