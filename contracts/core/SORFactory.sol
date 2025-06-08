// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SORRouter.sol";

/**Factory contract for deploying SOR Router instances
 * Manages router creation, registration, and governance
 */
contract SORFactory is Ownable, Pausable, ReentrancyGuard {
    // Router registry
    mapping(address => bool) public isRouter;
    mapping(address => address) public routerCreator;
    mapping(address => RouterInfo) public routerInfo;
    address[] public allRouters;
    
    // Configuration
    uint256 public routerCount;
    uint256 public creationFee;
    address public feeRecipient;
    address public defaultPriceOracle;
    uint256 public maxRoutersPerUser = 5;
    
    // Router template for upgrades
    address public routerImplementation;
    bool public useProxy = false;

    struct RouterInfo {
        address creator;
        address priceOracle;
        address feeCollector;
        uint256 createdAt;
        uint256 totalVolume;
        bool verified;
        string name;
        string description;
    }
    
    // Events
    event RouterCreated(
        address indexed router, 
        address indexed creator, 
        address indexed priceOracle,
        uint256 routerId,
        string name
    );
    
    event RouterVerified(address indexed router, bool verified);
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event DefaultOracleUpdated(address oldOracle, address newOracle);
    event RouterImplementationUpdated(address oldImpl, address newImpl);
    
    modifier validRouter(address router) {
        require(isRouter[router], "SORFactory: Invalid router");
        _;
    }

    modifier onlyRouterCreator(address router) {
        require(routerCreator[router] == msg.sender, "SORFactory: Not router creator");
        _;
    }

    constructor(
        uint256 _creationFee,
        address _feeRecipient,
        address _defaultPriceOracle
    ) {
        require(_feeRecipient != address(0), "SORFactory: Invalid fee recipient");
        require(_defaultPriceOracle != address(0), "SORFactory: Invalid oracle");
        
        creationFee = _creationFee;
        feeRecipient = _feeRecipient;
        defaultPriceOracle = _defaultPriceOracle;
    }
    
    /**
     * Create a new SOR Router instance
     */
    function createRouter(
        address priceOracle,
        address feeCollector,
        string calldata name,
        string calldata description
    ) external payable whenNotPaused nonReentrant returns (address router) {
        require(msg.value >= creationFee, "SORFactory: Insufficient creation fee");
        require(bytes(name).length > 0, "SORFactory: Name required");
        require(bytes(description).length > 0, "SORFactory: Description required");
        
        // Check user router limit
        require(
            _getUserRouterCount(msg.sender) < maxRoutersPerUser,
            "SORFactory: Router limit exceeded"
        );
        
        // Use default oracle if none provided
        if (priceOracle == address(0)) {
            priceOracle = defaultPriceOracle;
        }
        
        // Use sender as fee collector if none provided
        if (feeCollector == address(0)) {
            feeCollector = msg.sender;
        }
        
        // Deploy new router
        if (useProxy && routerImplementation != address(0)) {
            router = _deployProxyRouter(priceOracle, feeCollector);
        } else {
            router = address(new SORRouter(priceOracle, feeCollector));
        }
        
        // Transfer ownership to creator
        SORRouter sorRouterInstance = SORRouter(payable(router));
        sorRouterInstance.transferOwnership(msg.sender);
        
        // Update registry
        isRouter[router] = true;
        routerCreator[router] = msg.sender;
        allRouters.push(router);
        routerCount++;
        
        // Store router info
        routerInfo[router] = RouterInfo({
            creator: msg.sender,
            priceOracle: priceOracle,
            feeCollector: feeCollector,
            createdAt: block.timestamp,
            totalVolume: 0,
            verified: false,
            name: name,
            description: description
        });
        
        // Transfer creation fee
        if (msg.value > 0 && feeRecipient != address(0)) {
            payable(feeRecipient).transfer(msg.value);
        }
        
        emit RouterCreated(router, msg.sender, priceOracle, routerCount, name);
    }

    /**
     * Create router with advanced configuration
     */
    function createAdvancedRouter(
        address priceOracle,
        address feeCollector,
        string calldata name,
        string calldata description,
        uint256 platformFee,
        uint256 maxSlippage
    ) external payable whenNotPaused nonReentrant returns (address router) {
        require(platformFee <= 100, "SORFactory: Fee too high"); // Max 1%
        require(maxSlippage <= 1000, "SORFactory: Slippage too high"); // Max 10%
        
        router = this.createRouter{value: msg.value}(
            priceOracle,
            feeCollector,
            name,
            description
        );
        
        // Configure advanced settings
        SORRouter sorRouterInstance = SORRouter(payable(router));
        sorRouterInstance.updatePlatformFee(platformFee);
        sorRouterInstance.updateMaxSlippageBps(maxSlippage);
        // Transfer ownership back to creator
        sorRouterInstance.transferOwnership(msg.sender);
        
    }

    /**
     * Deploy router using proxy pattern (for upgradeable routers)
     */
    function _deployProxyRouter(
        address priceOracle,
        address feeCollector
    ) internal returns (address) {
        // Implementation would use proxy pattern
        // For now, deploy regular router
        return address(new SORRouter(priceOracle, feeCollector));
    }

    /**
     * Verify a router (admin function)
     */
    function verifyRouter(address router, bool verified) external onlyOwner validRouter(router) {
        routerInfo[router].verified = verified;
        emit RouterVerified(router, verified);
    }

    /**
     * Update router volume (called by routers)
     */
    function updateRouterVolume(address router, uint256 volume) external validRouter(router) {
        require(msg.sender == router, "SORFactory: Only router can update");
        routerInfo[router].totalVolume += volume;
    }

    /**
     * Get routers created by a specific user
     */
    function getRoutersByCreator(address creator) external view returns (address[] memory) {
        uint256 count = _getUserRouterCount(creator);
        address[] memory userRouters = new address[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allRouters.length; i++) {
            if (routerCreator[allRouters[i]] == creator) {
                userRouters[index] = allRouters[i];
                index++;
            }
        }
        
        return userRouters;
    }

    /**
     * Get verified routers
     */
    function getVerifiedRouters() external view returns (address[] memory) {
        uint256 verifiedCount = 0;
        
        // Count verified routers
        for (uint256 i = 0; i < allRouters.length; i++) {
            if (routerInfo[allRouters[i]].verified) {
                verifiedCount++;
            }
        }
        
        // Create result array
        address[] memory verifiedRouters = new address[](verifiedCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allRouters.length; i++) {
            if (routerInfo[allRouters[i]].verified) {
                verifiedRouters[index] = allRouters[i];
                index++;
            }
        }
        
        return verifiedRouters;
    }

    /**
     * Get router statistics
     */
    function getRouterStats(address router) external view validRouter(router) returns (
        address creator,
        uint256 createdAt,
        uint256 totalVolume,
        bool verified,
        string memory name,
        string memory description
    ) {
        RouterInfo memory info = routerInfo[router];
        return (
            info.creator,
            info.createdAt,
            info.totalVolume,
            info.verified,
            info.name,
            info.description
        );
    }

    /**
     * Get factory statistics
     */
    function getFactoryStats() external view returns (
        uint256 totalRouters,
        uint256 verifiedRouters,
        uint256 totalVolume,
        uint256 totalFees
    ) {
        uint256 verified = 0;
        uint256 volume = 0;
        
        for (uint256 i = 0; i < allRouters.length; i++) {
            RouterInfo memory info = routerInfo[allRouters[i]];
            if (info.verified) verified++;
            volume += info.totalVolume;
        }
        
        return (
            allRouters.length,
            verified,
            volume,
            address(this).balance
        );
    }

    function _getUserRouterCount(address user) internal view returns (uint256 count) {
        for (uint256 i = 0; i < allRouters.length; i++) {
            if (routerCreator[allRouters[i]] == user) {
                count++;
            }
        }
    }
    
    function getRoutersCount() external view returns (uint256) {
        return allRouters.length;
    }

    // Admin functions
    function updateCreationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = creationFee;
        creationFee = newFee;
        emit CreationFeeUpdated(oldFee, newFee);
    }
    
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "SORFactory: Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    function updateDefaultPriceOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "SORFactory: Invalid oracle");
        address oldOracle = defaultPriceOracle;
        defaultPriceOracle = newOracle;
        emit DefaultOracleUpdated(oldOracle, newOracle);
    }

    function updateRouterImplementation(address newImplementation) external onlyOwner {
        address oldImpl = routerImplementation;
        routerImplementation = newImplementation;
        emit RouterImplementationUpdated(oldImpl, newImplementation);
    }

    function setUseProxy(bool _useProxy) external onlyOwner {
        useProxy = _useProxy;
    }

    function updateMaxRoutersPerUser(uint256 newMax) external onlyOwner {
        require(newMax > 0, "SORFactory: Invalid max");
        maxRoutersPerUser = newMax;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(owner()).transfer(balance);
        }
    }

    receive() external payable {}
}
