// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library SafetyChecks {
    uint256 constant MAX_SLIPPAGE = 1000; // 10%
    uint256 constant MAX_PRICE_IMPACT = 500; // 5%
    uint256 constant MIN_LIQUIDITY = 1000e18; // 1000 tokens minimum
    uint256 constant MAX_DEADLINE = 1800; // 30 minutes max
    uint256 constant MIN_AMOUNT = 1000; // Minimum wei amount

    error InvalidTokenAddress();
    error IdenticalTokens();
    error InsufficientAmount();
    error DeadlineExpired();
    error SlippageTooHigh();
    error PriceImpactTooHigh();
    error InsufficientLiquidity();
    error ReentrancyDetected();

    function validateSwapParams(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal view {
        if (tokenIn == address(0)) revert InvalidTokenAddress();
        if (tokenOut == address(0)) revert InvalidTokenAddress();
        if (tokenIn == tokenOut) revert IdenticalTokens();
        if (amountIn < MIN_AMOUNT) revert InsufficientAmount();
        if (minAmountOut == 0) revert InsufficientAmount();
        if (deadline < block.timestamp) revert DeadlineExpired();
        if (deadline > block.timestamp + MAX_DEADLINE) revert DeadlineExpired();
    }

    function validateSlippage(uint256 expectedOutput, uint256 minOutput) internal pure returns (bool) {
        if (expectedOutput == 0) return false;

        uint256 slippage = ((expectedOutput - minOutput) * 10000) / expectedOutput;
        return slippage <= MAX_SLIPPAGE;
    }

    function validatePriceImpact(uint256 priceImpact) internal pure returns (bool) {
        return priceImpact <= MAX_PRICE_IMPACT;
    }

    function validateLiquidity(uint256 liquidity) internal pure returns (bool) {
        return liquidity >= MIN_LIQUIDITY;
    }

    function validateRouteComplexity(uint256 hops, uint256 splits, uint256 maxHops, uint256 maxSplits)
        internal
        pure
        returns (bool)
    {
        return hops <= maxHops && splits <= maxSplits && hops > 0 && splits > 0;
    }

    function validateGasParameters(uint256 gasPrice, uint256 gasLimit, uint256 maxGasPrice, uint256 maxGasLimit)
        internal
        pure
        returns (bool)
    {
        return gasPrice <= maxGasPrice && gasLimit <= maxGasLimit && gasPrice > 0 && gasLimit > 21000; // Minimum gas for transaction
    }

    function checkReentrancy(mapping(address => bool) storage reentrancyGuard) internal {
        if (reentrancyGuard[msg.sender]) revert ReentrancyDetected();
        reentrancyGuard[msg.sender] = true;
    }

    function clearReentrancy(mapping(address => bool) storage reentrancyGuard) internal {
        reentrancyGuard[msg.sender] = false;
    }

    function validateTokenBalance(address token, address account, uint256 requiredAmount)
        internal
        view
        returns (bool)
    {
        if (token == address(0)) {
            return account.balance >= requiredAmount;
        } else {
            // For ERC20 tokens
            (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", account));

            if (!success || data.length < 32) return false;

            uint256 balance = abi.decode(data, (uint256));
            return balance >= requiredAmount;
        }
    }

    function validateTokenAllowance(address token, address owner, address spender, uint256 requiredAmount)
        internal
        view
        returns (bool)
    {
        if (token == address(0)) return true; // Native token doesn't need allowance

        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSignature("allowance(address,address)", owner, spender));

        if (!success || data.length < 32) return false;

        uint256 allowance = abi.decode(data, (uint256));
        return allowance >= requiredAmount;
    }

    function calculateMaxSlippage(uint256 amountIn, uint256 liquidity, uint256 baseSlippage)
        internal
        pure
        returns (uint256)
    {
        if (liquidity == 0) return MAX_SLIPPAGE;

        // Adjust slippage based on trade size relative to liquidity
        uint256 tradeRatio = (amountIn * 10000) / liquidity;
        uint256 adjustedSlippage = baseSlippage + (tradeRatio / 10);

        return adjustedSlippage > MAX_SLIPPAGE ? MAX_SLIPPAGE : adjustedSlippage;
    }

    function isContractAddress(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function validateRecipient(address recipient) internal view returns (bool) {
        return recipient != address(0) && recipient != address(this);
    }
}
