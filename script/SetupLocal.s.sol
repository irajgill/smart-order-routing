// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {SORRouter} from "../contracts/core/SORRouter.sol";
import {MockERC20} from "../tests/contracts/mocks/MockERC20.sol";
import {MockDEXRouter} from "../tests/contracts/mocks/MockDEXRouter.sol";
import {MockPriceOracle} from "../tests/contracts/mocks/MockPriceOracle.sol";
import {HyperSwapV2Adapter} from "../contracts/adapters/HyperSwapV2Adapter.sol";

contract SetupLocalScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Setting up local Hyperliquid development environment...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKNA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKNB", 18);
        MockERC20 tokenC = new MockERC20("Token C", "TKNC", 6);

        console.log("Token A:", address(tokenA));
        console.log("Token B:", address(tokenB));
        console.log("Token C:", address(tokenC));

        // Deploy DEX router
        MockDEXRouter mockDEXRouter = new MockDEXRouter();
        console.log("Mock DEX Router:", address(mockDEXRouter));

        // Deploy price oracle
        MockPriceOracle priceOracle = new MockPriceOracle();
        console.log("Price Oracle:", address(priceOracle));

        // Deploy SOR Router
        SORRouter sorRouter = new SORRouter(address(priceOracle), deployer);
        console.log("SOR Router:", address(sorRouter));

        // Deploy adapter
        HyperSwapV2Adapter adapter = new HyperSwapV2Adapter(address(mockDEXRouter));
        console.log("HyperSwap V2 Adapter:", address(adapter));

        // Configure router
        sorRouter.addSupportedToken(address(tokenA));
        sorRouter.addSupportedToken(address(tokenB));
        sorRouter.addSupportedToken(address(tokenC));
        sorRouter.addDEXAdapter("hyperswap_v2", address(adapter));

        // Mint tokens
        uint256 mintAmount = 1000000 ether;
        tokenA.mint(deployer, mintAmount);
        tokenB.mint(deployer, mintAmount);
        tokenC.mint(deployer, 1000000 * 10**6); // 6 decimals

        // Mint to DEX router for liquidity
        tokenA.mint(address(mockDEXRouter), mintAmount);
        tokenB.mint(address(mockDEXRouter), mintAmount);
        tokenC.mint(address(mockDEXRouter), 1000000 * 10**6);

        // Set up prices
        priceOracle.updatePrice(address(tokenA), address(tokenB), 1 ether);
        priceOracle.updatePrice(address(tokenA), address(tokenC), 2000 ether);
        priceOracle.updatePrice(address(tokenB), address(tokenC), 2000 ether);

        vm.stopBroadcast();

        console.log("Local environment ready!");
        console.log("Test with: forge test --fork-url http://localhost:8545");
    }
}
