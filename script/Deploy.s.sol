// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {SORRouter} from "../contracts/core/SORRouter.sol";
import {SORFactory} from "../contracts/core/SORFactory.sol";
import {SORManager} from "../contracts/core/SORManager.sol";
import {HyperSwapV2Adapter} from "../contracts/adapters/HyperSwapV2Adapter.sol";
import {HyperSwapV3Adapter} from "../contracts/adapters/HyperSwapV3Adapter.sol";
import {KittenSwapAdapter} from "../contracts/adapters/KittenSwapAdapter.sol";
import {LaminarAdapter} from "../contracts/adapters/LaminarAdapter.sol";
import {MockPriceOracle} from "../tests/contracts/mocks/MockPriceOracle.sol";
import {MockDEXRouter} from "../tests/contracts/mocks/MockDEXRouter.sol";
import {MockERC20} from "../tests/contracts/mocks/MockERC20.sol";

contract DeployScript is Script {
    // Deployment configuration
    uint256 public constant CREATION_FEE = 0.1 ether;
    uint256 public constant PLATFORM_FEE = 30; // 0.3%
    uint256 public constant MAX_SLIPPAGE_BPS = 500; // 5%
    uint256 public constant MAX_SPLITS = 7;

    // Hyperliquid ecosystem token addresses
    address public constant HYPE_TOKEN = 0x2222222222222222222222222222222222222222;
    address public constant USDC_TOKEN = 0x1111111111111111111111111111111111111111;
    address public constant WETH_TOKEN = 0x3333333333333333333333333333333333333333;

    // Deployed contracts
    SORRouter public sorRouter;
    SORFactory public sorFactory;
    SORManager public sorManager;
    MockPriceOracle public priceOracle;
    MockDEXRouter public mockDEXRouter;
    
    // Adapters
    HyperSwapV2Adapter public hyperSwapV2Adapter;
    HyperSwapV3Adapter public hyperSwapV3Adapter;
    KittenSwapAdapter public kittenSwapStableAdapter;
    KittenSwapAdapter public kittenSwapVolatileAdapter;
    LaminarAdapter public laminarAdapter;

    // Test tokens
    MockERC20 public testTokenA;
    MockERC20 public testTokenB;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying Hyperliquid Smart Order Router...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Price Oracle
        console.log("Deploying Price Oracle...");
        priceOracle = new MockPriceOracle();
        console.log("Price Oracle deployed to:", address(priceOracle));

        // 2. Deploy SOR Factory - Fix constructor (add missing parameter)
        console.log("Deploying SOR Factory...");
        sorFactory = new SORFactory(CREATION_FEE, deployer, address(priceOracle));
        console.log("SOR Factory deployed to:", address(sorFactory));

        // 3. Deploy SOR Manager
        console.log("Deploying SOR Manager...");
        sorManager = new SORManager();
        console.log("SOR Manager deployed to:", address(sorManager));

        // 4. Deploy Main Router
        console.log("Deploying SOR Router...");
        sorRouter = new SORRouter(address(priceOracle), deployer);
        console.log("SOR Router deployed to:", address(sorRouter));

        // 5. Deploy Mock DEX Router for testing
        console.log("Deploying Mock DEX Router...");
        mockDEXRouter = new MockDEXRouter();
        console.log("Mock DEX Router deployed to:", address(mockDEXRouter));

        // 6. Deploy DEX Adapters
        console.log("Deploying DEX Adapters...");
        
        hyperSwapV2Adapter = new HyperSwapV2Adapter(address(mockDEXRouter));
        console.log("HyperSwap V2 Adapter:", address(hyperSwapV2Adapter));

        hyperSwapV3Adapter = new HyperSwapV3Adapter(address(mockDEXRouter), address(mockDEXRouter));
        console.log("HyperSwap V3 Adapter:", address(hyperSwapV3Adapter));

        kittenSwapStableAdapter = new KittenSwapAdapter(address(mockDEXRouter), true);
        console.log("KittenSwap Stable Adapter:", address(kittenSwapStableAdapter));

        kittenSwapVolatileAdapter = new KittenSwapAdapter(address(mockDEXRouter), false);
        console.log("KittenSwap Volatile Adapter:", address(kittenSwapVolatileAdapter));

        laminarAdapter = new LaminarAdapter(address(mockDEXRouter));
        console.log("Laminar Adapter:", address(laminarAdapter));

        // 7. Deploy Test Tokens
        console.log("Deploying Test Tokens...");
        testTokenA = new MockERC20("Test Token A", "TESTA", 18);
        testTokenB = new MockERC20("Test Token B", "TESTB", 18);
        console.log("Test Token A:", address(testTokenA));
        console.log("Test Token B:", address(testTokenB));

        // 8. Configure Router
        console.log("Configuring Router...");
        
        // Add DEX adapters
        sorRouter.addDEXAdapter("hyperswap_v2", address(hyperSwapV2Adapter));
        sorRouter.addDEXAdapter("hyperswap_v3", address(hyperSwapV3Adapter));
        sorRouter.addDEXAdapter("kittenswap_stable", address(kittenSwapStableAdapter));
        sorRouter.addDEXAdapter("kittenswap_volatile", address(kittenSwapVolatileAdapter));
        sorRouter.addDEXAdapter("laminar", address(laminarAdapter));

        // Add supported tokens
        sorRouter.addSupportedToken(HYPE_TOKEN);
        sorRouter.addSupportedToken(USDC_TOKEN);
        sorRouter.addSupportedToken(WETH_TOKEN);
        sorRouter.addSupportedToken(address(testTokenA));
        sorRouter.addSupportedToken(address(testTokenB));

        // 9. Configure Manager - Fix SORManager addDEXAdapter calls (add missing parameters)
        console.log("Configuring Manager...");
        
        sorManager.addDEXAdapter("hyperswap_v2", address(hyperSwapV2Adapter), "1.0", deployer);
        sorManager.addDEXAdapter("hyperswap_v3", address(hyperSwapV3Adapter), "1.0", deployer);
        sorManager.addDEXAdapter("kittenswap_stable", address(kittenSwapStableAdapter), "1.0", deployer);
        sorManager.addDEXAdapter("kittenswap_volatile", address(kittenSwapVolatileAdapter), "1.0", deployer);
        sorManager.addDEXAdapter("laminar", address(laminarAdapter), "1.0", deployer);

        sorManager.addSupportedToken(HYPE_TOKEN, 18, "HYPE", "Hyperliquid Token", address(0));
        sorManager.addSupportedToken(USDC_TOKEN, 6, "USDC", "USD Coin", address(0));
        sorManager.addSupportedToken(WETH_TOKEN, 18, "WETH", "Wrapped Ether", address(0));
        sorManager.addSupportedToken(address(testTokenA), 18, "TESTA", "Test Token A", address(0));
        sorManager.addSupportedToken(address(testTokenB), 18, "TESTB", "Test Token B", address(0));

        // Fix authorizeRouter call (add missing parameter)
        SORManager.RouterPermissions memory permissions = SORManager.RouterPermissions({
            canAddTokens: true,
            canAddAdapters: false,
            canUpdateFees: false,
            canPause: false,
            maxDailyVolume: 1000000e18,
            dailyVolumeUsed: 0,
            lastVolumeReset: 0
        });
        sorManager.authorizeRouter(address(sorRouter), permissions);

        // 10. Set up price oracle
        console.log("Setting up Price Oracle...");
        priceOracle.updatePrice(HYPE_TOKEN, USDC_TOKEN, 2.5 ether); // HYPE = $2.5
        priceOracle.updatePrice(WETH_TOKEN, USDC_TOKEN, 2000 ether); // ETH = $2000
        priceOracle.updatePrice(address(testTokenA), address(testTokenB), 1 ether); // 1:1

        // 11. Set liquidity data
        console.log("Setting liquidity data...");
        sorRouter.setPairLiquidity(HYPE_TOKEN, USDC_TOKEN, 66000000 ether); // $66M TVL
        sorRouter.setPairLiquidity(WETH_TOKEN, USDC_TOKEN, 59070000 ether); // $59.07M TVL

        // 12. Mint test tokens
        console.log("Minting test tokens...");
        testTokenA.mint(deployer, 1000000 ether);
        testTokenB.mint(deployer, 1000000 ether);
        testTokenA.mint(address(mockDEXRouter), 1000000 ether);
        testTokenB.mint(address(mockDEXRouter), 1000000 ether);

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        // Fix console.log repeat issue
        console.log("==================================================");
        console.log("Contract Addresses:");
        console.log("SOR Router:", address(sorRouter));
        console.log("SOR Factory:", address(sorFactory));
        console.log("SOR Manager:", address(sorManager));
        console.log("Price Oracle:", address(priceOracle));
        console.log("Mock DEX Router:", address(mockDEXRouter));
        console.log("==================================================");
        console.log("Adapter Addresses:");
        console.log("HyperSwap V2 Adapter:", address(hyperSwapV2Adapter));
        console.log("HyperSwap V3 Adapter:", address(hyperSwapV3Adapter));
        console.log("KittenSwap Stable Adapter:", address(kittenSwapStableAdapter));
        console.log("KittenSwap Volatile Adapter:", address(kittenSwapVolatileAdapter));
        console.log("Laminar Adapter:", address(laminarAdapter));
        console.log("==================================================");
        console.log("Test Token Addresses:");
        console.log("Test Token A:", address(testTokenA));
        console.log("Test Token B:", address(testTokenB));
        console.log("==================================================");
    }
}
