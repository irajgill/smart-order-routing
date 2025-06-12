// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IDEXAdapter.sol";

// Centralized management system for SOR ecosystem
// Handles adapter registration, token support, and global configuration
contract SORManager is Ownable, Pausable, ReentrancyGuard {
    // Adapter management
    mapping(string => address) public dexAdapters;
    mapping(address => AdapterInfo) public adapterInfo;
    mapping(string => bool) public dexEnabled;
    string[] public dexNames;
    
    // Token management
    mapping(address => bool) public supportedTokens;
    mapping(address => TokenInfo) public tokenInfo;
    address[] public tokenList;
    
    // Router authorization
    mapping(address => bool) public authorizedRouters;
    mapping(address => RouterPermissions) public routerPermissions;
    address[] public routerList;
    
    // Global configuration
    uint256 public maxSplits = 7;
    uint256 public maxSlippageBps = 1000; // 10%
    uint256 public minLiquidity = 1000e18;
    uint256 public maxGasPrice = 1000e9; // 1000 gwei
    
    // Fee management
    mapping(string => uint256) public protocolFees; // DEX name => fee in bps
    address public feeCollector;
    uint256 public globalProtocolFee = 10; // 0.1%

    struct AdapterInfo {
        string name;
        address adapter;
        bool enabled;
        uint256 addedAt;
        uint256 totalVolume;
        uint256 totalSwaps;
        string version;
        address maintainer;
    }

    struct TokenInfo {
        string symbol;
        string name;
        uint8 decimals;
        bool enabled;
        uint256 addedAt;
        uint256 totalVolume;
        address oracle;
        bool hasCustomOracle;
    }

    struct RouterPermissions {
        bool canAddTokens;
        bool canAddAdapters;
        bool canUpdateFees;
        bool canPause;
        uint256 maxDailyVolume;
        uint256 dailyVolumeUsed;
        uint256 lastVolumeReset;
    }
    
    // Events
    event DEXAdapterAdded(string indexed name, address indexed adapter, address maintainer);
    event DEXAdapterRemoved(string indexed name, address adapter);
    event DEXAdapterUpdated(string indexed name, address indexed oldAdapter, address indexed newAdapter);
    event DEXStatusChanged(string indexed name, bool enabled);
    
    event TokenAdded(address indexed token, string symbol, uint8 decimals, address oracle);
    event TokenRemoved(address indexed token, string symbol);
    event TokenStatusChanged(address indexed token, bool enabled);
    event TokenOracleUpdated(address indexed token, address oldOracle, address newOracle);
    
    event RouterAuthorized(address indexed router, RouterPermissions permissions);
    event RouterDeauthorized(address indexed router);
    event RouterPermissionsUpdated(address indexed router, RouterPermissions permissions);
    
    event ConfigurationUpdated(string parameter, uint256 oldValue, uint256 newValue);
    event ProtocolFeeUpdated(string dex, uint256 oldFee, uint256 newFee);
    event GlobalProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    
    modifier onlyAuthorizedRouter() {
        require(authorizedRouters[msg.sender], "SORManager: UNAUTHORIZED_ROUTER");
        _;
    }
    
    modifier validDEXName(string calldata name) {
        require(bytes(name).length > 0, "SORManager: INVALID_DEX_NAME");
        require(bytes(name).length <= 32, "SORManager: DEX_NAME_TOO_LONG");
        _;
    }

    modifier validToken(address token) {
        require(token != address(0), "SORManager: INVALID_TOKEN");
        require(token.code.length > 0, "SORManager: NOT_CONTRACT");
        _;
    }

    modifier checkRouterPermissions(address router, string memory permission) {
        require(authorizedRouters[router], "SORManager: UNAUTHORIZED_ROUTER");
        RouterPermissions memory perms = routerPermissions[router];
        
        if (keccak256(bytes(permission)) == keccak256(bytes("ADD_TOKENS"))) {
            require(perms.canAddTokens, "SORManager: NO_TOKEN_PERMISSION");
        } else if (keccak256(bytes(permission)) == keccak256(bytes("ADD_ADAPTERS"))) {
            require(perms.canAddAdapters, "SORManager: NO_ADAPTER_PERMISSION");
        } else if (keccak256(bytes(permission)) == keccak256(bytes("UPDATE_FEES"))) {
            require(perms.canUpdateFees, "SORManager: NO_FEE_PERMISSION");
        } else if (keccak256(bytes(permission)) == keccak256(bytes("PAUSE"))) {
            require(perms.canPause, "SORManager: NO_PAUSE_PERMISSION");
        }
        _;
    }

    constructor() {
        feeCollector = msg.sender;
    }

    // DEX Adapter Management
    function addDEXAdapter(
        string calldata name, 
        address adapter,
        string calldata version,
        address maintainer
    ) external onlyOwner validDEXName(name) {
        require(adapter != address(0), "SORManager: INVALID_ADAPTER");
        require(dexAdapters[name] == address(0), "SORManager: ADAPTER_EXISTS");
        require(maintainer != address(0), "SORManager: INVALID_MAINTAINER");
        
        // Verify adapter implements required interface
        try IDEXAdapter(adapter).getDEXName() returns (string memory dexName) {
            require(bytes(dexName).length > 0, "SORManager: INVALID_DEX_NAME_RESPONSE");
            
            dexAdapters[name] = adapter;
            dexNames.push(name);
            dexEnabled[name] = true;
            
            adapterInfo[adapter] = AdapterInfo({
                name: name,
                adapter: adapter,
                enabled: true,
                addedAt: block.timestamp,
                totalVolume: 0,
                totalSwaps: 0,
                version: version,
                maintainer: maintainer
            });
            
            emit DEXAdapterAdded(name, adapter, maintainer);
        } catch {
            revert("SORManager: INVALID_ADAPTER_INTERFACE");
        }
    }
    
    function updateDEXAdapter(
        string calldata name,
        address newAdapter,
        string calldata newVersion
    ) external onlyOwner validDEXName(name) {
        require(newAdapter != address(0), "SORManager: INVALID_ADAPTER");
        require(dexAdapters[name] != address(0), "SORManager: ADAPTER_NOT_EXISTS");
        
        address oldAdapter = dexAdapters[name];
        
        // Verify new adapter implements required interface
        try IDEXAdapter(newAdapter).getDEXName() returns (string memory) {
            dexAdapters[name] = newAdapter;
            
            // Update adapter info
            AdapterInfo storage info = adapterInfo[oldAdapter];
            adapterInfo[newAdapter] = AdapterInfo({
                name: name,
                adapter: newAdapter,
                enabled: info.enabled,
                addedAt: block.timestamp,
                totalVolume: info.totalVolume,
                totalSwaps: info.totalSwaps,
                version: newVersion,
                maintainer: info.maintainer
            });
            
            // Remove old adapter info
            delete adapterInfo[oldAdapter];
            
            emit DEXAdapterUpdated(name, oldAdapter, newAdapter);
        } catch {
            revert("SORManager: INVALID_ADAPTER_INTERFACE");
        }
    }
    
    function removeDEXAdapter(string calldata name) external onlyOwner {
        require(dexAdapters[name] != address(0), "SORManager: ADAPTER_NOT_EXISTS");
        
        address adapter = dexAdapters[name];
        delete dexAdapters[name];
        delete dexEnabled[name];
        delete adapterInfo[adapter];
        
        // Remove from array
        for (uint256 i = 0; i < dexNames.length; i++) {
            if (keccak256(bytes(dexNames[i])) == keccak256(bytes(name))) {
                dexNames[i] = dexNames[dexNames.length - 1];
                dexNames.pop();
                break;
            }
        }
        
        emit DEXAdapterRemoved(name, adapter);
    }
    
    function enableDEX(string calldata name) external onlyOwner {
        require(dexAdapters[name] != address(0), "SORManager: ADAPTER_NOT_EXISTS");
        dexEnabled[name] = true;
        adapterInfo[dexAdapters[name]].enabled = true;
        emit DEXStatusChanged(name, true);
    }
    
    function disableDEX(string calldata name) external onlyOwner {
        require(dexAdapters[name] != address(0), "SORManager: ADAPTER_NOT_EXISTS");
        dexEnabled[name] = false;
        adapterInfo[dexAdapters[name]].enabled = false;
        emit DEXStatusChanged(name, false);
    }

    // Token Management
    function addSupportedToken(
        address token, 
        uint8 decimals,
        string calldata symbol,
        string calldata name,
        address oracle
    ) external onlyOwner validToken(token) {
        require(!supportedTokens[token], "SORManager: TOKEN_EXISTS");
        require(decimals > 0 && decimals <= 18, "SORManager: INVALID_DECIMALS");
        require(bytes(symbol).length > 0, "SORManager: INVALID_SYMBOL");
        require(bytes(name).length > 0, "SORManager: INVALID_NAME");
        
        supportedTokens[token] = true;
        tokenList.push(token);
        
        tokenInfo[token] = TokenInfo({
            symbol: symbol,
            name: name,
            decimals: decimals,
            enabled: true,
            addedAt: block.timestamp,
            totalVolume: 0,
            oracle: oracle,
            hasCustomOracle: oracle != address(0)
        });
        
        emit TokenAdded(token, symbol, decimals, oracle);
    }

    function addSupportedToken(address token, uint256 decimals) external onlyOwner {
        // Simplified version for backward compatibility
        this.addSupportedToken(
            token,
            uint8(decimals),
            "UNKNOWN",
            "Unknown Token",
            address(0)
        );
    }
    
    function removeSupportedToken(address token) external onlyOwner {
        require(supportedTokens[token], "SORManager: TOKEN_NOT_EXISTS");
        
        supportedTokens[token] = false;
        string memory symbol = tokenInfo[token].symbol;
        delete tokenInfo[token];
        
        // Remove from array
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }
        
        emit TokenRemoved(token, symbol);
    }

    function enableToken(address token) external onlyOwner {
        require(supportedTokens[token], "SORManager: TOKEN_NOT_EXISTS");
        tokenInfo[token].enabled = true;
        emit TokenStatusChanged(token, true);
    }

    function disableToken(address token) external onlyOwner {
        require(supportedTokens[token], "SORManager: TOKEN_NOT_EXISTS");
        tokenInfo[token].enabled = false;
        emit TokenStatusChanged(token, false);
    }

    function updateTokenOracle(address token, address newOracle) external onlyOwner {
        require(supportedTokens[token], "SORManager: TOKEN_NOT_EXISTS");
        
        address oldOracle = tokenInfo[token].oracle;
        tokenInfo[token].oracle = newOracle;
        tokenInfo[token].hasCustomOracle = newOracle != address(0);
        
        emit TokenOracleUpdated(token, oldOracle, newOracle);
    }

    // Router Authorization
    function authorizeRouter(
        address router,
        RouterPermissions calldata permissions
    ) external onlyOwner {
        require(router != address(0), "SORManager: INVALID_ROUTER");
        require(!authorizedRouters[router], "SORManager: ROUTER_ALREADY_AUTHORIZED");
        require(permissions.maxDailyVolume > 0, "SORManager: INVALID_VOLUME_LIMIT");
        
        authorizedRouters[router] = true;
        routerList.push(router);
        routerPermissions[router] = permissions;
        routerPermissions[router].lastVolumeReset = block.timestamp;
        
        emit RouterAuthorized(router, permissions);
    }
    
    function deauthorizeRouter(address router) external onlyOwner {
        require(authorizedRouters[router], "SORManager: ROUTER_NOT_AUTHORIZED");
        
        authorizedRouters[router] = false;
        delete routerPermissions[router];
        
        // Remove from array
        for (uint256 i = 0; i < routerList.length; i++) {
            if (routerList[i] == router) {
                routerList[i] = routerList[routerList.length - 1];
                routerList.pop();
                break;
            }
        }
        
        emit RouterDeauthorized(router);
    }

    function updateRouterPermissions(
        address router,
        RouterPermissions calldata newPermissions
    ) external onlyOwner {
        require(authorizedRouters[router], "SORManager: ROUTER_NOT_AUTHORIZED");
        require(newPermissions.maxDailyVolume > 0, "SORManager: INVALID_VOLUME_LIMIT");
        
        routerPermissions[router] = newPermissions;
        routerPermissions[router].lastVolumeReset = block.timestamp;
        
        emit RouterPermissionsUpdated(router, newPermissions);
    }

    // Volume tracking
    function recordSwap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 volumeUSD
    ) external onlyAuthorizedRouter {
        require(router == msg.sender, "SORManager: INVALID_CALLER");
        
        // Check daily volume limit
        RouterPermissions storage perms = routerPermissions[router];
        if (block.timestamp >= perms.lastVolumeReset + 1 days) {
            perms.dailyVolumeUsed = 0;
            perms.lastVolumeReset = block.timestamp;
        }
        
        require(
            perms.dailyVolumeUsed + volumeUSD <= perms.maxDailyVolume,
            "SORManager: DAILY_VOLUME_EXCEEDED"
        );
        
        perms.dailyVolumeUsed += volumeUSD;
        
        // Update token volumes
        tokenInfo[tokenIn].totalVolume += volumeUSD;
        tokenInfo[tokenOut].totalVolume += volumeUSD;
    }

    // Configuration Management
    function updateMaxSplits(uint256 newMaxSplits) external onlyOwner {
        require(newMaxSplits > 0 && newMaxSplits <= 10, "SORManager: INVALID_MAX_SPLITS");
        uint256 oldValue = maxSplits;
        maxSplits = newMaxSplits;
        emit ConfigurationUpdated("maxSplits", oldValue, newMaxSplits);
    }
    
    function updateMaxSlippageBps(uint256 newMaxSlippageBps) external onlyOwner {
        require(newMaxSlippageBps <= 2000, "SORManager: SLIPPAGE_TOO_HIGH"); // Max 20%
        uint256 oldValue = maxSlippageBps;
        maxSlippageBps = newMaxSlippageBps;
        emit ConfigurationUpdated("maxSlippageBps", oldValue, newMaxSlippageBps);
    }
    
    function updateMinLiquidity(uint256 newMinLiquidity) external onlyOwner {
        uint256 oldValue = minLiquidity;
        minLiquidity = newMinLiquidity;
        emit ConfigurationUpdated("minLiquidity", oldValue, newMinLiquidity);
    }

    function updateMaxGasPrice(uint256 newMaxGasPrice) external onlyOwner {
        require(newMaxGasPrice > 0, "SORManager: INVALID_GAS_PRICE");
        uint256 oldValue = maxGasPrice;
        maxGasPrice = newMaxGasPrice;
        emit ConfigurationUpdated("maxGasPrice", oldValue, newMaxGasPrice);
    }

    // Fee Management
    function updateProtocolFee(string calldata dex, uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "SORManager: FEE_TOO_HIGH"); // Max 10%
        require(dexAdapters[dex] != address(0), "SORManager: DEX_NOT_EXISTS");
        
        uint256 oldFee = protocolFees[dex];
        protocolFees[dex] = newFee;
        emit ProtocolFeeUpdated(dex, oldFee, newFee);
    }

    function updateGlobalProtocolFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "SORManager: FEE_TOO_HIGH"); // Max 10%
        uint256 oldFee = globalProtocolFee;
        globalProtocolFee = newFee;
        emit GlobalProtocolFeeUpdated(oldFee, newFee);
    }

    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "SORManager: INVALID_COLLECTOR");
        feeCollector = newCollector;
    }

    
    function getAllDEXAdapters() external view returns (
        string[] memory names, 
        address[] memory adapters,
        bool[] memory enabled
    ) {
        names = dexNames;
        adapters = new address[](dexNames.length);
        enabled = new bool[](dexNames.length);
        
        for (uint256 i = 0; i < dexNames.length; i++) {
            adapters[i] = dexAdapters[dexNames[i]];
            enabled[i] = dexEnabled[dexNames[i]];
        }
    }
    
    function getEnabledDEXAdapters() external pure returns (
        string[] memory names,
        address[] memory adapters
    ) {
        uint256 enabledCount = 0;
        
    }


}