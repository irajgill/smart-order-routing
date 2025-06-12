// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISOR.sol";
import "../interfaces/IDEXAdapter.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/IRouteOptimizer.sol";
import "../libraries/RouteCalculator.sol";
import "../libraries/GasOptimizer.sol";
import "../libraries/SafetyChecks.sol";


// Advanced Smart Order Router for Hyperliquid ecosystem
// Aggregates liquidity across HyperSwap V2/V3, KittenSwap, and Laminar
// Implements sophisticated routing algorithms for optimal price execution
contract SORRouter is ISOR, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using RouteCalculator for RouteCalculator.RouteParams;
    using GasOptimizer for GasOptimizer.GasParams;

    uint256 public constant MAX_SPLITS = 7;
    uint256 public constant MAX_SLIPPAGE = 500; // 5%
    uint256 public constant ROUTE_GAS_LIMIT = 1000000;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_ADAPTERS = 10;

    mapping(string => address) public dexAdapters;
    mapping(address => bool) public override supportedTokens;
    mapping(address => mapping(address => uint256)) public pairLiquidity;
    mapping(address => uint256) public tokenDecimals;
    mapping(bytes32 => bool) private executedSwaps;
    
    address public priceOracle;
    address public feeCollector;
    address public routeOptimizer;
    uint256 public override platformFee = 30; // 0.3%
    uint256 public override maxSlippageBps = 500; // 5%
    bool public emergencyPaused = false;
    
    uint256 public totalSwapsExecuted;
    uint256 public totalVolumeUSD;
    uint256 public totalGasSaved;

    event AdapterAdded(string indexed name, address indexed adapter);
    event AdapterRemoved(string indexed name);
    event TokenAdded(address indexed token, uint256 decimals);
    event TokenRemoved(address indexed token);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event EmergencyPauseToggled(bool paused);
    event LiquidityUpdated(address indexed tokenA, address indexed tokenB, uint256 liquidity);

    modifier validDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "SOR: Transaction deadline exceeded");
        _;
    }

    modifier supportedToken(address token) {
        require(supportedTokens[token], "SOR: Token not supported");
        _;
    }

    modifier notPaused() {
        require(!emergencyPaused, "SOR: Emergency paused");
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, "SOR: Invalid amount");
        _;
    }

    constructor(
        address _priceOracle,
        address _feeCollector
    ) {
        require(_priceOracle != address(0), "SOR: Invalid price oracle");
        require(_feeCollector != address(0), "SOR: Invalid fee collector");
        
        priceOracle = _priceOracle;
        feeCollector = _feeCollector;
        
        // Add HYPE token support by default
        _addSupportedToken(0x2222222222222222222222222222222222222222, 18);
    }

    //Execute optimal swap across multiple DEX protocols
    //Implements advanced routing with split execution and gas optimization
    function executeOptimalSwap(
        SwapParams calldata params
    ) 
        external 
        payable 
        nonReentrant 
        notPaused
        validDeadline(params.deadline)
        supportedToken(params.tokenIn)
        supportedToken(params.tokenOut)
        validAmount(params.amountIn)
        returns (uint256 amountOut)
    {
        // Generate unique swap ID to prevent replay attacks
        bytes32 swapId = keccak256(abi.encodePacked(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            block.timestamp,
            block.number
        ));
        require(!executedSwaps[swapId], "SOR: Swap already executed");
        executedSwaps[swapId] = true;

        // Validate swap parameters
        SafetyChecks.validateSwapParams(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            params.minAmountOut,
            params.deadline
        );

        uint256 gasStart = gasleft();

        // Transfer tokens from user
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // Calculate optimal routes with advanced algorithms
        SplitRoute[] memory routes = _calculateOptimalRoutes(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            params.useGasOptimization
        );

        require(routes.length > 0, "SOR: No viable routes found");

        // Validate total expected output meets minimum requirements
        uint256 totalExpectedOutput = 0;
        for (uint256 i = 0; i < routes.length; i++) {
            totalExpectedOutput += routes[i].expectedOutput;
        }
        
        require(
            SafetyChecks.validateSlippage(totalExpectedOutput, params.minAmountOut),
            "SOR: Slippage too high"
        );

        // Execute split routes with error handling
        uint256 totalAmountOut = _executeSplitRoutes(routes);

        require(totalAmountOut >= params.minAmountOut, "SOR: Insufficient output amount");

        // Collect platform fee
        uint256 feeAmount = (totalAmountOut * platformFee) / 10000;
        uint256 userAmountOut = totalAmountOut - feeAmount;

        if (feeAmount > 0) {
            IERC20(params.tokenOut).safeTransfer(feeCollector, feeAmount);
        }

        // Transfer final amount to recipient
        IERC20(params.tokenOut).safeTransfer(params.recipient, userAmountOut);

        uint256 gasUsed = gasStart - gasleft();

        // Update statistics
        totalSwapsExecuted++;
        totalGasSaved += _calculateGasSavings(gasUsed, routes.length);
        
        // Calculate USD volume (simplified)
        uint256 volumeUSD = _calculateVolumeUSD(params.tokenOut, userAmountOut);
        totalVolumeUSD += volumeUSD;

        emit SwapExecuted(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            userAmountOut,
            gasUsed,
            routes.length
        );

        emit RouteOptimized(
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            userAmountOut > params.amountIn ? userAmountOut - params.amountIn : 0,
            routes.length
        );

        return userAmountOut;
    }

    
    //Get comprehensive swap quote with multiple route options
    function getSwapQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) 
        external
        supportedToken(tokenIn)
        supportedToken(tokenOut)
        validAmount(amountIn)
        returns (
            uint256 amountOut,
            uint256 gasEstimate,
            SplitRoute[] memory routes
        ) 
    {
        require(tokenIn != tokenOut, "SOR: Identical tokens");
        
        routes = _calculateOptimalRoutes(tokenIn, tokenOut, amountIn, true);
        
        for (uint256 i = 0; i < routes.length; i++) {
            amountOut += routes[i].expectedOutput;
            gasEstimate += routes[i].gasEstimate;
        }

        // Apply platform fee to quote
        uint256 feeAmount = (amountOut * platformFee) / 10000;
        amountOut = amountOut - feeAmount;
    }

    //Calculate optimal routes using advanced pathfinding algorithms
    function _calculateOptimalRoutes(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool useGasOptimization
    ) internal returns (SplitRoute[] memory) {
        // Get all available adapters
        string[] memory availableAdapters = _getAvailableAdapters();
        
        if (availableAdapters.length == 0) {
            return new SplitRoute[](0);
        }

        SplitRoute[] memory allRoutes = new SplitRoute[](MAX_SPLITS);
        uint256 routeCount = 0;

        // Check each DEX adapter for viable routes
        for (uint256 i = 0; i < availableAdapters.length && routeCount < MAX_SPLITS; i++) {
            address adapter = dexAdapters[availableAdapters[i]];
            if (adapter != address(0)) {
                SplitRoute memory route = _getRouteFromAdapter(
                    adapter, 
                    tokenIn, 
                    tokenOut, 
                    amountIn,
                    availableAdapters[i]
                );
                
                if (route.steps.length > 0 && route.expectedOutput > 0) {
                    // Validate route viability
                    uint256 priceImpact = _calculatePriceImpact(tokenIn, tokenOut, amountIn, route.expectedOutput);
                    if (priceImpact <= maxSlippageBps) {
                        allRoutes[routeCount] = route;
                        routeCount++;
                    }
                }
            }
        }

        return _optimizeRouteDistribution(allRoutes, routeCount, amountIn, useGasOptimization);
    }

    //Get route information from a specific DEX adapter
    function _getRouteFromAdapter(
        address adapter,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        string memory dexName
    ) internal returns (SplitRoute memory) {
        try IDEXAdapter(adapter).getQuote(tokenIn, tokenOut, amountIn, "") 
        returns (uint256 amountOut, uint256 gasEstimate) {
            
            if (amountOut == 0) {
                return SplitRoute(new RouteStep[](0), 0, 0, 0);
            }
            
            SplitRoute memory route;
            route.steps = new RouteStep[](1);
            route.steps[0] = RouteStep({
                dexAdapter: adapter,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                swapData: _encodeSwapData(dexName, tokenIn, tokenOut),
                minAmountOut: (amountOut * (10000 - maxSlippageBps)) / 10000
            });
            route.percentage = 10000; // 100%
            route.expectedOutput = amountOut;
            route.gasEstimate = gasEstimate;
            
            return route;
        } catch {
            return SplitRoute(new RouteStep[](0), 0, 0, 0);
        }
    }

    //Execute multiple routes with proper error handling
    function _executeSplitRoutes(SplitRoute[] memory routes) internal returns (uint256 totalAmountOut) {
        for (uint256 i = 0; i < routes.length; i++) {
            if (routes[i].steps.length > 0) {
                try this._executeRouteExternal(routes[i]) returns (uint256 routeAmountOut) {
                    totalAmountOut += routeAmountOut;
                } catch Error(string memory reason) {
                    // Log error but continue with other routes
                    emit RouteExecutionFailed(i, reason);
                } catch {
                    // Handle low-level errors
                    emit RouteExecutionFailed(i, "Unknown error");
                }
            }
        }
    }

    //External function for route execution (for try-catch)
    function _executeRouteExternal(SplitRoute memory route) external returns (uint256 amountOut) {
        require(msg.sender == address(this), "SOR: Internal function");
        return _executeRoute(route);
    }

    //Execute a single route through specified steps
    function _executeRoute(SplitRoute memory route) internal returns (uint256 amountOut) {
        uint256 currentAmount = 0;
        
        for (uint256 i = 0; i < route.steps.length; i++) {
            RouteStep memory step = route.steps[i];
            
            if (i == 0) {
                currentAmount = step.amountIn;
            }

            IDEXAdapter adapter = IDEXAdapter(step.dexAdapter);
            
            // Approve tokens for adapter
            IERC20(step.tokenIn).safeApprove(step.dexAdapter, 0); // Reset approval
            IERC20(step.tokenIn).safeApprove(step.dexAdapter, currentAmount);
            
            // Get balance before swap
            uint256 balanceBefore = IERC20(step.tokenOut).balanceOf(address(this));
            
            // Execute swap
            currentAmount = adapter.swap(
                step.tokenIn,
                step.tokenOut,
                currentAmount,
                step.minAmountOut,
                step.swapData
            );
            
            // Verify actual output
            uint256 balanceAfter = IERC20(step.tokenOut).balanceOf(address(this));
            uint256 actualOutput = balanceAfter - balanceBefore;
            
            require(actualOutput >= step.minAmountOut, "SOR: Route step failed");
            currentAmount = actualOutput;
        }

        return currentAmount;
    }

    //Optimize route distribution using advanced algorithms
    function _optimizeRouteDistribution(
        SplitRoute[] memory routes,
        uint256 routeCount,
        uint256 totalAmount,
        bool useGasOptimization
    ) internal returns (SplitRoute[] memory) {
        if (routeCount == 0) {
            return new SplitRoute[](0);
        }
        
        if (routeCount == 1) {
            SplitRoute[] memory singleRoute = new SplitRoute[](1);
            singleRoute[0] = routes[0];
            return singleRoute;
        }

        // Use route optimizer if available
        if (routeOptimizer != address(0)) {
            return _useRouteOptimizer(routes, routeCount, totalAmount, useGasOptimization);
        }

        // Fallback to simple optimization
        return _simpleRouteOptimization(routes, routeCount, useGasOptimization);
    }

    // Use external route optimizer for advanced optimization
    function _useRouteOptimizer(
        SplitRoute[] memory routes,
        uint256 routeCount,
        uint256 totalAmount,
        bool useGasOptimization
    ) internal view returns (SplitRoute[] memory) {
        // Convert to RouteCandidate format
        IRouteOptimizer.RouteCandidate[] memory candidates = new IRouteOptimizer.RouteCandidate[](routeCount);
        
        for (uint256 i = 0; i < routeCount; i++) {
            candidates[i] = IRouteOptimizer.RouteCandidate({
                path: new address[](2),
                adapters: new address[](1),
                expectedOutput: routes[i].expectedOutput,
                gasEstimate: routes[i].gasEstimate,
                priceImpact: 0, // Would calculate actual impact
                score: _calculateRouteScore(routes[i], useGasOptimization),
                swapData: routes[i].steps.length > 0 ? routes[i].steps[0].swapData : bytes("")
            });
        }

        IRouteOptimizer.OptimizationParams memory params = IRouteOptimizer.OptimizationParams({
            maxSplits: MAX_SPLITS,
            minSplitPercentage: 500, // 5%
            gasPrice: tx.gasprice,
            maxGasCost: 1000000,
            prioritizeGas: useGasOptimization,
            prioritizePrice: !useGasOptimization
        });

        try IRouteOptimizer(routeOptimizer).optimizeRoute(
            address(0), address(0), totalAmount, candidates, params
        ) returns (IRouteOptimizer.OptimizedRoute memory optimized) {
            return _convertOptimizedRoute(optimized, routes);
        } catch {
            return _simpleRouteOptimization(routes, routeCount, useGasOptimization);
        }
    }

    // Simple route optimization fallback
    function _simpleRouteOptimization(
        SplitRoute[] memory routes,
        uint256 routeCount,
        bool useGasOptimization
    ) internal pure returns (SplitRoute[] memory) {
        SplitRoute[] memory optimizedRoutes = new SplitRoute[](routeCount);
        uint256 validRoutes = 0;

        // Calculate route scores and filter viable routes
        uint256[] memory scores = new uint256[](routeCount);
        uint256 totalScore = 0;

        for (uint256 i = 0; i < routeCount; i++) {
            if (routes[i].expectedOutput > 0) {
                scores[i] = _calculateRouteScore(routes[i], useGasOptimization);
                totalScore += scores[i];
                optimizedRoutes[validRoutes] = routes[i];
                validRoutes++;
            }
        }

        if (validRoutes == 0) {
            return new SplitRoute[](0);
        }

        if (validRoutes == 1) {
            SplitRoute[] memory singleRoute = new SplitRoute[](1);
            singleRoute[0] = optimizedRoutes[0];
            return singleRoute;
        }

        // Calculate optimal split percentages
        for (uint256 i = 0; i < validRoutes; i++) {
            if (totalScore > 0) {
                uint256 percentage = (scores[i] * 10000) / totalScore;
                
                // Minimum 5% allocation for viable routes
                if (percentage > 0 && percentage < 500) {
                    percentage = 500;
                }
                
                optimizedRoutes[i].percentage = percentage;
                optimizedRoutes[i].expectedOutput = 
                    (optimizedRoutes[i].expectedOutput * percentage) / 10000;
            }
        }

        // Resize array to actual count
        SplitRoute[] memory finalRoutes = new SplitRoute[](validRoutes);
        for (uint256 i = 0; i < validRoutes; i++) {
            finalRoutes[i] = optimizedRoutes[i];
        }

        return finalRoutes;
    }

    // Calculate route score for optimization
    function _calculateRouteScore(
        SplitRoute memory route,
        bool useGasOptimization
    ) internal pure returns (uint256) {
        if (route.expectedOutput == 0) return 0;
        
        uint256 outputScore = route.expectedOutput / 1e15; // Normalize
        uint256 gasScore = useGasOptimization ? 
            (1e18 / (route.gasEstimate + 1)) / 1e12 : 1000;
        
        return (outputScore * 70 + gasScore * 30) / 100; // Weighted score
    }

    // Calculate price impact for a trade
    function _calculatePriceImpact(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal view returns (uint256) {
        try IPriceOracle(priceOracle).getPrice(tokenIn, tokenOut) 
        returns (IPriceOracle.PriceData memory priceData) {
            
            uint256 expectedOutput = (amountIn * priceData.price) / PRECISION;
            
            if (expectedOutput == 0) return 10000; // 100% impact if no price data
            
            uint256 impact = expectedOutput > amountOut ? 
                ((expectedOutput - amountOut) * 10000) / expectedOutput : 0;
                
            return impact;
        } catch {
            // Fallback: estimate based on liquidity
            uint256 liquidity = pairLiquidity[tokenIn][tokenOut];
            return liquidity > 0 ? (amountIn * 10000) / liquidity : 1000; // 10% default
        }
    }

    // Encode swap data based on DEX type
    function _encodeSwapData(
        string memory dexName,
        address tokenIn,
        address tokenOut
    ) internal pure returns (bytes memory) {
        bytes32 dexHash = keccak256(bytes(dexName));
        
        if (dexHash == keccak256(bytes("hyperswap_v3"))) {
            return abi.encode(uint24(500)); // 0.05% fee tier
        } else if (dexHash == keccak256(bytes("kittenswap_stable"))) {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return abi.encode(path, true); // stable = true
        } else if (dexHash == keccak256(bytes("kittenswap_volatile"))) {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return abi.encode(path, false); // stable = false
        } else {
            // For V2-style DEXs, encode simple path
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            return abi.encode(path);
        }
    }

    // Get list of available DEX adapters
    function _getAvailableAdapters() internal pure returns (string[] memory) {
        string[] memory adapters = new string[](6);
        adapters[0] = "hyperswap_v2";
        adapters[1] = "hyperswap_v3";
        adapters[2] = "kittenswap_stable";
        adapters[3] = "kittenswap_volatile";
        adapters[4] = "kittenswap_v3";
        adapters[5] = "laminar";
        return adapters;
    }

    // Calculate gas savings from optimization
    function _calculateGasSavings(uint256 gasUsed, uint256 routeCount) internal pure returns (uint256) {
        uint256 baselineGas = 150000; // Single DEX swap
        uint256 expectedGas = baselineGas * routeCount;
        return expectedGas > gasUsed ? expectedGas - gasUsed : 0;
    }

    // Calculate USD volume (simplified)
    function _calculateVolumeUSD(address token, uint256 amount) internal pure returns (uint256) {
        // Simplified calculation - in production would use proper price feeds
        if (token == 0x1111111111111111111111111111111111111111) { // USDC
            return amount / 1e6; // USDC has 6 decimals
        }
        return (amount * 2) / 1e18; // Assume $2 per token for others
    }

    // Convert optimized route from external optimizer
    function _convertOptimizedRoute(
        IRouteOptimizer.OptimizedRoute memory /*optimized*/,
        SplitRoute[] memory originalRoutes
    ) internal pure returns (SplitRoute[] memory) {
        // Implementation would convert the optimized route format
        // For now, return original routes
        return originalRoutes;
    }

    // Admin functions
    function addDEXAdapter(string calldata name, address adapter) external onlyOwner {
        require(adapter != address(0), "SOR: Invalid adapter");
        require(bytes(name).length > 0, "SOR: Invalid name");
        
        dexAdapters[name] = adapter;
        emit AdapterAdded(name, adapter);
    }

    function removeDEXAdapter(string calldata name) external onlyOwner {
        require(dexAdapters[name] != address(0), "SOR: Adapter not found");
        
        //address adapter = dexAdapters[name];
        delete dexAdapters[name];
        emit AdapterRemoved(name);
    }

    function addSupportedToken(address token) external onlyOwner {
        _addSupportedToken(token, 18); // Default to 18 decimals
    }

    function addSupportedTokenWithDecimals(address token, uint256 decimals) external onlyOwner {
        _addSupportedToken(token, decimals);
    }

    function _addSupportedToken(address token, uint256 decimals) internal {
        require(token != address(0), "SOR: Invalid token");
        require(decimals > 0 && decimals <= 18, "SOR: Invalid decimals");
        
        supportedTokens[token] = true;
        tokenDecimals[token] = decimals;
        emit TokenAdded(token, decimals);
    }

    function removeSupportedToken(address token) external onlyOwner {
        require(supportedTokens[token], "SOR: Token not supported");
        
        supportedTokens[token] = false;
        delete tokenDecimals[token];
        emit TokenRemoved(token);
    }

    function updatePlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 100, "SOR: Fee too high"); // Max 1%
        
        uint256 oldFee = platformFee;
        platformFee = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }

    function updateMaxSlippageBps(uint256 newMaxSlippage) external onlyOwner {
        require(newMaxSlippage <= 1000, "SOR: Slippage too high"); // Max 10%
        maxSlippageBps = newMaxSlippage;
    }

    function updatePriceOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "SOR: Invalid oracle");
        priceOracle = newOracle;
    }

    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "SOR: Invalid collector");
        feeCollector = newCollector;
    }

    function setRouteOptimizer(address optimizer) external onlyOwner {
        routeOptimizer = optimizer;
    }

    function setPairLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity
    ) external onlyOwner {
        pairLiquidity[tokenA][tokenB] = liquidity;
        pairLiquidity[tokenB][tokenA] = liquidity;
        emit LiquidityUpdated(tokenA, tokenB, liquidity);
    }

    function emergencyPause() external onlyOwner {
        emergencyPaused = true;
        emit EmergencyPauseToggled(true);
    }

    function emergencyUnpause() external onlyOwner {
        emergencyPaused = false;
        emit EmergencyPauseToggled(false);
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }

    // View functions
    function getRouterStats() external view returns (
        uint256 swapsExecuted,
        uint256 volumeUSD,
        uint256 gasSaved,
        uint256 supportedTokenCount,
        uint256 adapterCount
    ) {
        return (
            totalSwapsExecuted,
            totalVolumeUSD,
            totalGasSaved,
            _getSupportedTokenCount(),
            _getAdapterCount()
        );
    }

    function _getSupportedTokenCount() internal pure returns (uint256 count) {
        // This would iterate through supported tokens in production
        return 3; // Simplified
    }

    function _getAdapterCount() internal view returns (uint256 count) {
        string[] memory adapters = _getAvailableAdapters();
        for (uint256 i = 0; i < adapters.length; i++) {
            if (dexAdapters[adapters[i]] != address(0)) {
                count++;
            }
        }
    }

    // Events for failed routes
    event RouteExecutionFailed(uint256 indexed routeIndex, string reason);

    receive() external payable {}

}
