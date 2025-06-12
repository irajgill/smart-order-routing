// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IKittenSwapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensStable(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsOutStable(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    // ve(3,3) specific functions
    function getRewards(address account, address[] calldata tokens) external view returns (uint256[] memory);
    function claimRewards(address[] calldata tokens) external;
    function vote(address[] calldata poolVote, uint256[] calldata weights) external;
    function reset() external;
}

interface IKittenSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint256);

    function isPair(address pair) external view returns (bool);
    function isStable(address pair) external view returns (bool);
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address);
    function allPairs(uint256) external view returns (address);
    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
    function getInitializable() external view returns (address, address, bool);

    function feeManager() external view returns (address);
    function setFeeManager(address _feeManager) external;
    function protocolFeesShare() external view returns (uint256);
    function setProtocolFeesShare(uint256 _protocolFeesShare) external;
}

interface IKittenSwapPair {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint256);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    function MINIMUM_LIQUIDITY() external pure returns (uint256);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address, bool) external;
}

interface IKittenSwapGauge {
    function deposit(uint256 amount, uint256 tokenId) external;
    function depositAll(uint256 tokenId) external;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function withdrawToken(uint256 amount, uint256 tokenId) external;

    function getReward(address account, address[] memory tokens) external;
    function claimFees() external returns (uint256 claimed0, uint256 claimed1);

    function left(address token) external view returns (uint256);
    function isForPair() external view returns (bool);
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
    function earned(address token, address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function rewardRate(address token) external view returns (uint256);
    function rewardPerToken(address token) external view returns (uint256);
    function lastTimeRewardApplicable(address token) external view returns (uint256);
}

interface IVotingEscrow {
    struct Point {
        int128 bias;
        int128 slope;
        uint256 ts;
        uint256 blk;
    }

    function create_lock_for(uint256 _value, uint256 _lock_duration, address _to) external returns (uint256);
    function create_lock(uint256 _value, uint256 _lock_duration) external returns (uint256);
    function increase_amount(uint256 _tokenId, uint256 _value) external;
    function increase_unlock_time(uint256 _tokenId, uint256 _lock_duration) external;
    function withdraw(uint256 _tokenId) external;
    function merge(uint256 _from, uint256 _to) external;
    function split(uint256 _tokenId, uint256 _amount) external returns (uint256);

    function locked(uint256 _tokenId) external view returns (uint256 amount, uint256 end);
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function supply() external view returns (uint256);

    function ownerOf(uint256 _tokenId) external view returns (address);
    function balanceOf(address _owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address _owner, uint256 _tokenIndex) external view returns (uint256);
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool);

    function user_point_epoch(uint256 _tokenId) external view returns (uint256);
    function epoch() external view returns (uint256);
    function user_point_history(uint256 _tokenId, uint256 _loc) external view returns (Point memory);
    function point_history(uint256 _loc) external view returns (Point memory);
    function checkpoint() external;
    function deposit_for(uint256 _tokenId, uint256 _value) external;

    function voted(uint256 _tokenId) external view returns (bool);
    function attachments(uint256 _tokenId) external view returns (uint256);
    function voting(uint256 _tokenId) external;
    function abstain(uint256 _tokenId) external;
    function attach(uint256 _tokenId) external;
    function detach(uint256 _tokenId) external;
}
