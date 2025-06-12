// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


interface IKittenSwapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForTokensStable(
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

    // ve(3,3) specific functions
    function getRewards(address account, address[] calldata tokens) external view returns (uint256[] memory);
    function claimRewards(address[] calldata tokens) external;
    function vote(address[] calldata poolVote, uint256[] calldata weights) external;
    function reset() external;
}

interface IKittenSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint);

    function isPair(address pair) external view returns (bool);
    function isStable(address pair) external view returns (bool);
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address);
    function allPairs(uint) external view returns (address);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
    function getInitializable() external view returns (address, address, bool);

    function feeManager() external view returns (address);
    function setFeeManager(address _feeManager) external;
    function protocolFeesShare() external view returns (uint256);
    function setProtocolFeesShare(uint256 _protocolFeesShare) external;
}

interface IKittenSwapPair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address, bool) external;
}

interface IKittenSwapGauge {
    function deposit(uint amount, uint tokenId) external;
    function depositAll(uint tokenId) external;
    function withdraw(uint amount) external;
    function withdrawAll() external;
    function withdrawToken(uint amount, uint tokenId) external;

    function getReward(address account, address[] memory tokens) external;
    function claimFees() external returns (uint claimed0, uint claimed1);

    function left(address token) external view returns (uint);
    function isForPair() external view returns (bool);
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
    function earned(address token, address account) external view returns (uint);
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function rewardRate(address token) external view returns (uint);
    function rewardPerToken(address token) external view returns (uint);
    function lastTimeRewardApplicable(address token) external view returns (uint);
}

interface IVotingEscrow {
    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    function create_lock_for(uint _value, uint _lock_duration, address _to) external returns (uint);
    function create_lock(uint _value, uint _lock_duration) external returns (uint);
    function increase_amount(uint _tokenId, uint _value) external;
    function increase_unlock_time(uint _tokenId, uint _lock_duration) external;
    function withdraw(uint _tokenId) external;
    function merge(uint _from, uint _to) external;
    function split(uint _tokenId, uint _amount) external returns (uint);

    function locked(uint _tokenId) external view returns (uint amount, uint end);
    function balanceOfNFT(uint _tokenId) external view returns (uint);
    function totalSupply() external view returns (uint);
    function supply() external view returns (uint);

    function ownerOf(uint _tokenId) external view returns (address);
    function balanceOf(address _owner) external view returns (uint);
    function tokenOfOwnerByIndex(address _owner, uint _tokenIndex) external view returns (uint);
    function isApprovedOrOwner(address _spender, uint _tokenId) external view returns (bool);

    function user_point_epoch(uint _tokenId) external view returns (uint);
    function epoch() external view returns (uint);
    function user_point_history(uint _tokenId, uint _loc) external view returns (Point memory);
    function point_history(uint _loc) external view returns (Point memory);
    function checkpoint() external;
    function deposit_for(uint _tokenId, uint _value) external;

    function voted(uint _tokenId) external view returns (bool);
    function attachments(uint _tokenId) external view returns (uint);
    function voting(uint _tokenId) external;
    function abstain(uint _tokenId) external;
    function attach(uint _tokenId) external;
    function detach(uint _tokenId) external;
}
