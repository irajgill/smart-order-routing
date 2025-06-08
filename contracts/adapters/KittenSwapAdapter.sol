// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IDEXAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IKittenSwapRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);
        
    function getAmountsOutStable(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts);

    function swapExactTokensForTokensStable(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    // ve(3,3) specific functions
    function getRewards(address account, address[] calldata tokens) external view returns (uint256[] memory);
    
    function claimRewards(address[] calldata tokens) external;
}

interface IKittenSwapPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
    function totalSupply() external view returns (uint256);
}

interface IKittenSwapFactory {
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address);
    function allPairsLength() external view returns (uint256);
    function isPair(address pair) external view returns (bool);
}

interface IKittenSwapGauge {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function rewardRate() external view returns (uint256);
}

contract KittenSwapAdapter is IDEXAdapter {
    using SafeERC20 for IERC20;
    
    IKittenSwapRouter public immutable router;
    IKittenSwapFactory public immutable factory;
    bool public immutable isStable;
    
    uint256 private constant STABLE_FEE_RATE = 10;   // 0.01%
    uint256 private constant VOLATILE_FEE_RATE = 300; // 0.3%
    uint256 private constant VE_MULTIPLIER = 110;     // 10% bonus for ve(3,3)
    
    mapping(address => address) public pairGauges;
    
    constructor(address _router, bool _isStable) {
        router = IKittenSwapRouter(_router);
        isStable = _isStable;
        // In production, get factory from router
        factory = IKittenSwapFactory(_router); // Using router address as mock factory
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes calldata swapData
    ) external override returns (uint256 amountOut) {
        address[] memory path;
        bool useStable = isStable;
        
        if (swapData.length > 0) {
            (path, useStable) = abi.decode(swapData, (address[], bool));
        } else {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        }
        
        require(path[0] == tokenIn && path[path.length - 1] == tokenOut, "KittenSwap: Invalid path");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        uint[] memory amounts;
        
        if (useStable) {
            amounts = router.swapExactTokensForTokensStable(
                amountIn,
                minAmountOut,
                path,
                msg.sender,
                block.timestamp + 300
            );
        } else {
            amounts = router.swapExactTokensForTokens(
                amountIn,
                minAmountOut,
                path,
                msg.sender,
                block.timestamp + 300
            );
        }

        return amounts[amounts.length - 1];
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata swapData
    ) external view override returns (uint256 amountOut, uint256 gasEstimate) {
        address[] memory path;
        bool useStable = isStable;
        
        if (swapData.length > 0) {
            (path, useStable) = abi.decode(swapData, (address[], bool));
        } else {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
        }
        
        uint256 baseOutput;
        if (useStable) {
            try router.getAmountsOutStable(amountIn, path) returns (uint[] memory amounts) {
                baseOutput = amounts[amounts.length - 1];
            } catch {
                return (0, 160000);
            }
        } else {
            try router.getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
                baseOutput = amounts[amounts.length - 1];
            } catch {
                return (0, 160000);
            }
        }
    

    // Apply ve(3,3) bonus if applicable
        uint256 bonusOutput = (baseOutput * VE_MULTIPLIER) / 100;
    
        return (bonusOutput, 160000);
        
    }

    function getDEXName() external view override returns (string memory) {
        return isStable ? "KittenSwap Stable" : "KittenSwap Volatile";
    }
    
    function getSupportedFeeTiers() external view override returns (uint256[] memory) {
        uint256[] memory fees = new uint256[](1);
        fees[0] = isStable ? STABLE_FEE_RATE : VOLATILE_FEE_RATE;
        return fees;
    }

    function getPairInfo(
        address tokenA,
        address tokenB
    ) external view returns (
        address pair,
        bool stable,
        uint256 reserve0,
        uint256 reserve1,
        uint256 totalSupply
    ) {
        pair = factory.getPair(tokenA, tokenB, isStable);
        if (pair == address(0)) return (address(0), false, 0, 0, 0);
        
        IKittenSwapPair pairContract = IKittenSwapPair(pair);
        stable = pairContract.stable();
        (uint112 _reserve0, uint112 _reserve1,) = pairContract.getReserves();
        reserve0 = uint256(_reserve0);
        reserve1 = uint256(_reserve1);
        totalSupply = pairContract.totalSupply();
    }

    function getVeRewards(
        address account,
        address tokenA,
        address tokenB
    ) external view returns (uint256 pendingRewards, uint256 rewardRate) {
        address pair = factory.getPair(tokenA, tokenB, isStable);
        if (pair == address(0)) return (0, 0);
        
        address gauge = pairGauges[pair];
        if (gauge == address(0)) return (0, 0);
        
        IKittenSwapGauge gaugeContract = IKittenSwapGauge(gauge);
        pendingRewards = gaugeContract.earned(account);
        rewardRate = gaugeContract.rewardRate();
    }

    function calculateStableSwapOutput(
        uint256 amountIn,
        uint256 reserve0,
        uint256 reserve1,
        uint256 amplificationParameter
    ) external pure returns (uint256 amountOut) {
        // Simplified stable swap calculation
        // In production, this would use the full StableSwap invariant
        
        if (reserve0 == 0 || reserve1 == 0) return 0;
        
        //uint256 totalReserves = reserve0 + reserve1;
        //uint256 balanceRatio = (reserve0 * 1e18) / totalReserves;
        
        // Stable swap has lower slippage than constant product
        uint256 fee = (amountIn * STABLE_FEE_RATE) / 10000;
        uint256 amountInAfterFee = amountIn - fee;
        
        // Simplified calculation - in production would use proper invariant
        amountOut = (amountInAfterFee * reserve1) / (reserve0 + amountInAfterFee);
        
        // Apply amplification factor benefit (reduces slippage)
        uint256 ampBonus = (amountOut * amplificationParameter) / 100;
        amountOut = amountOut + (ampBonus / 1000); // Small bonus
        
        return amountOut;
    }

    function calculateVolatileSwapOutput(
        uint256 amountIn,
        uint256 reserve0,
        uint256 reserve1
    ) external pure returns (uint256 amountOut) {
        // Standard constant product formula with KittenSwap fee
        if (reserve0 == 0 || reserve1 == 0) return 0;
        
        uint256 amountInWithFee = amountIn * (10000 - VOLATILE_FEE_RATE);
        uint256 numerator = amountInWithFee * reserve1;
        uint256 denominator = (reserve0 * 10000) + amountInWithFee;
        
        return numerator / denominator;
    }

    function estimateVeBonus(
        address /*account*/,
        uint256 baseOutput
    ) external pure returns (uint256 bonusOutput) {
        // In production, this would check user's ve(3,3) balance and lock duration
        // For now, return a fixed bonus
        return (baseOutput * 10) / 100; // 10% bonus
    }

    function claimTradingRewards(address[] calldata tokens) external {
        router.claimRewards(tokens);
    }

    function setPairGauge(address pair, address gauge) external {
        // In production, this would be restricted to authorized accounts
        pairGauges[pair] = gauge;
    }

    function calculatePriceImpact(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 priceImpact) {
        address pair = factory.getPair(tokenIn, tokenOut, isStable);
        if (pair == address(0)) return 10000; // 100% if no pair
        
        (uint112 reserve0, uint112 reserve1,) = IKittenSwapPair(pair).getReserves();
        address token0 = IKittenSwapPair(pair).token0();
        
        uint256 reserveIn = token0 == tokenIn ? uint256(reserve0) : uint256(reserve1);
        
        if (reserveIn == 0) return 10000;
        
        if (isStable) {
            // Stable pairs have lower price impact
            priceImpact = (amountIn * 5000) / reserveIn; // 50% of normal impact
        } else {
            // Volatile pairs use standard calculation
            priceImpact = (amountIn * 10000) / reserveIn;
        }
        
        return priceImpact > 10000 ? 10000 : priceImpact;
    }
}
