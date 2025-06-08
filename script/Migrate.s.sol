// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {SORRouter} from "../contracts/core/SORRouter.sol";
import {SORManager} from "../contracts/core/SORManager.sol";
import {MockPriceOracle} from "../tests/contracts/mocks/MockPriceOracle.sol";

contract MigrateScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Get existing contract addresses
        address sorRouterAddress = vm.envAddress("SOR_ROUTER_ADDRESS");
        address sorManagerAddress = vm.envAddress("SOR_MANAGER_ADDRESS");
        address priceOracleAddress = vm.envAddress("PRICE_ORACLE_ADDRESS");
        
        console.log("Starting migration...");
        console.log("SOR Router:", sorRouterAddress);
        console.log("SOR Manager:", sorManagerAddress);
        console.log("Price Oracle:", priceOracleAddress);

        vm.startBroadcast(deployerPrivateKey);

        //Use payable address conversion
        SORRouter sorRouter = SORRouter(payable(sorRouterAddress));
        SORManager sorManager = SORManager(sorManagerAddress);
        MockPriceOracle priceOracle = MockPriceOracle(priceOracleAddress);

        // 1. Update platform fee
        console.log("Updating platform fee...");
        uint256 currentFee = sorRouter.platformFee();
        uint256 targetFee = 25; // 0.25%
        
        if (currentFee != targetFee) {
            sorRouter.updatePlatformFee(targetFee);
            console.log("Platform fee updated from", currentFee, "to", targetFee);
        }

        // 2. Add new tokens
        console.log("Adding new ecosystem tokens...");
        address newToken1 = 0x4444444444444444444444444444444444444444; // HYPE-LP
        address newToken2 = 0x5555555555555555555555555555555555555555; // KITTEN
        
        if (!sorRouter.supportedTokens(newToken1)) {
            sorRouter.addSupportedToken(newToken1);
            sorManager.addSupportedToken(newToken1, 18, "HYPE-LP", "HYPE LP Token", address(0));
            console.log("Added HYPE-LP token support");
        }
        
        if (!sorRouter.supportedTokens(newToken2)) {
            sorRouter.addSupportedToken(newToken2);
            sorManager.addSupportedToken(newToken2, 18, "KITTEN", "KittenSwap Token", address(0));
            console.log("Added KITTEN token support");
        }

        // 3. Update prices
        console.log("Updating price oracle...");
        address hypeToken = 0x2222222222222222222222222222222222222222;
        address usdcToken = 0x1111111111111111111111111111111111111111;
        address wethToken = 0x3333333333333333333333333333333333333333;
        
        priceOracle.updatePrice(hypeToken, usdcToken, 2.75 ether); // Updated HYPE price
        priceOracle.updatePrice(wethToken, usdcToken, 2100 ether); // Updated ETH price
        console.log("Price oracle updated");

        // 4. Update liquidity data
        console.log("Updating liquidity data...");
        sorRouter.setPairLiquidity(hypeToken, usdcToken, 70000000 ether); // $70M
        sorRouter.setPairLiquidity(wethToken, usdcToken, 62000000 ether); // $62M
        console.log("Liquidity data updated");

        // 5. Optimize manager settings
        console.log("Optimizing manager settings...");
        if (sorManager.maxSplits() != 7) {
            sorManager.updateMaxSplits(7);
            console.log("Max splits updated to 7");
        }
        
        if (sorManager.maxSlippageBps() != 500) {
            sorManager.updateMaxSlippageBps(500);
            console.log("Max slippage updated to 5%");
        }

        vm.stopBroadcast();

        console.log("Migration completed successfully!");
    }
}
