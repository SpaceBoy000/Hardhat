//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IUniswapV2Router01 {
    function WETH() external pure returns (address);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract BeastModeLock is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    
    address constant WBTC  = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant tBTC  = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;

    address constant stETH  = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant wstETH  = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant WeETH  = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address constant ezETH  = 0xbf5495Efe5DB9ce00f80364C8B423567e58d2110;
    address constant wSol  = 0xD31a59c85aE9D8edEFeC411D448f90841571b89c;

    address constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDT  = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC  = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address constant USDe  = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    uint256 constant DENOMINATOR = 100_000;
    uint256 constant MULTIPLIER_BTC = 180_000; // 1.8x
    uint256 constant MULTIPLIER_ETH = 140_000; // 1.4x
    uint256 constant MULTIPLIER_USD = 120_000; // 1.2x
    uint256 constant POINT_AMOUNT_PER_USD = 5; // 5 points per usd
    uint256 constant REFERRAL_FEE = 5_000;     // 5%
    
    uint256 public withdrawStartTime;
    address public bridgeProxyAddress;
    
    address constant router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router
    IUniswapV2Router01 dexRouter;

    bool public activeContract;
    
    // Info of each user.
    struct UserInfo {
        uint256 amount; // total assets amount
        uint256 totalPoints;
        uint256 lastUpdateTime;
        address referrer;
        uint256 refAmount;
        uint256 amountETH;
        mapping(address => uint256) amountTokens;
    }

    address[] public allUsers;

    uint256 public totalUserCount;
    
    mapping(address => uint256) public totalTokenAmounts;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    event DepositToken(address indexed user, address token, uint256 amount, uint256 totalPoints, uint256 totalUSDAmount, address referrer);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        
        IUniswapV2Router01 _dexRouter = IUniswapV2Router01(router);
        dexRouter = _dexRouter;

        activeContract = true;
       
        withdrawStartTime = block.timestamp + 100 days;
    }

    //to recieve ETH from dexRouter when swaping
    receive() external payable {}

    function getTokenPrice(address token, uint256 amount) public view returns (uint256) {
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = dexRouter.WETH();
        path[2] = USDT;

        uint256[] memory amounts = dexRouter.getAmountsOut(amount, path);
        return amounts[2];
    }

    function getETHPrice(uint256 amount) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = dexRouter.WETH();
        path[1] = USDT;

        uint256[] memory amounts = dexRouter.getAmountsOut(amount, path);
        return amounts[1];
    }

    // Deposit primary tokens
    function deposit(address _token, uint256 _amount, address _referrer ) public nonReentrant {
        require(activeContract, "Contract was paused for a while, please wait.");

        UserInfo storage user = userInfo[msg.sender];
        user.amountTokens[_token] += _amount;

        require(_referrer != msg.sender, "You could not be own referrer");
        if (user.referrer == address(0) && _referrer != address(0)) {
            user.referrer = _referrer;
        }

        if (user.amount == 0) { // new depositor
            totalUserCount++;
            allUsers.push(msg.sender);
            user.lastUpdateTime = block.timestamp;
        } else {
            updateUserPoints(msg.sender);
        }

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);

        totalTokenAmounts[_token] += _amount;

        uint256 _multiplier = DENOMINATOR;

        if (_token == WBTC || _token == tBTC) {
            _multiplier = MULTIPLIER_BTC;
        } else if (_token == dexRouter.WETH() || _token == stETH || _token == wstETH || _token == WeETH || _token == ezETH || _token == wSol) {
            _multiplier = MULTIPLIER_ETH;
        } else if (_token == DAI) {
            _multiplier = MULTIPLIER_USD;
        } else if (_token == USDC) {
            _multiplier = MULTIPLIER_USD;
        } else if (_token == USDT) {
            _multiplier = MULTIPLIER_USD;
        } else if (_token == sUSDe) {
            _multiplier = MULTIPLIER_USD;
        } else if (_token == USDe) {
            _multiplier = MULTIPLIER_USD;
        } else {
            return;
        }

        uint256 tokenPrice = _multiplier == MULTIPLIER_USD ? _amount : getTokenPrice(_token, _amount);
        uint256 amountUSD = (tokenPrice * _multiplier) / DENOMINATOR;
        // ** should consider decimal in _amount
        uint256 newPoints = amountUSD * POINT_AMOUNT_PER_USD;

        user.amount += amountUSD;
        user.lastUpdateTime = block.timestamp;
        user.totalPoints += newPoints;

        if (user.referrer != address(0)) {
            userInfo[user.referrer].refAmount += ((newPoints * REFERRAL_FEE) / DENOMINATOR);
            userInfo[user.referrer].totalPoints += ((newPoints * REFERRAL_FEE) / DENOMINATOR);
        }

        emit DepositToken(msg.sender, _token, _amount, user.totalPoints, user.amount, user.referrer);
    }

    // Deposit ETH
    function depositETH(address _referrer) public payable nonReentrant {
        require(activeContract, "Contract was paused for a while, please wait.");

        UserInfo storage user = userInfo[msg.sender];
        uint256 _amount = msg.value;
        user.amountETH += _amount;

        require(_referrer != msg.sender, "You could not be own referrer");

        if (user.referrer == address(0) && _referrer != address(0)) {
            user.referrer = _referrer;
        }

        if (user.amount == 0) { // new depositor
            totalUserCount++;
            allUsers.push(msg.sender);
            user.lastUpdateTime = block.timestamp;
        } else {
            updateUserPoints(msg.sender);
        }

        uint256 _multiplier = MULTIPLIER_ETH;

        uint256 tokenPrice = getETHPrice(_amount);
        uint256 amountUSD = (tokenPrice * _multiplier) / DENOMINATOR;
        // ** should consider decimal in _amount
        uint256 newPoints = amountUSD * POINT_AMOUNT_PER_USD;

        user.amount += amountUSD;
        user.lastUpdateTime = block.timestamp;
        user.totalPoints += newPoints;

        if (user.referrer != address(0)) {
            userInfo[user.referrer].refAmount += ((newPoints * REFERRAL_FEE) / DENOMINATOR);
            userInfo[user.referrer].totalPoints += ((newPoints * REFERRAL_FEE) / DENOMINATOR);
        }

        emit DepositToken(msg.sender, address(0), _amount, user.totalPoints, user.amount, user.referrer);
    }

    function updateUserPoints(address _user) internal {
        uint256 _pendingPoints = getPendingPoints(_user);

        if (_pendingPoints > 0) {
            userInfo[_user].totalPoints += _pendingPoints;
            userInfo[_user].lastUpdateTime = block.timestamp;
        }
    }

    function getPendingPoints(address _user) public view returns (uint256) {
        uint256 pendingPoints = (userInfo[_user].amount *
            POINT_AMOUNT_PER_USD *
            (block.timestamp - userInfo[_user].lastUpdateTime)) / 1 days;

        return pendingPoints;
    }

    function getMyTotalPoints(address _user) public view returns (uint256) {
        uint256 pendingPoints = (userInfo[_user].amount *
            POINT_AMOUNT_PER_USD *
            (block.timestamp - userInfo[_user].lastUpdateTime)) / 1 days;

        uint256 totalPoints = userInfo[_user].totalPoints + pendingPoints;

        return totalPoints;
    }

    function getUserInfo(address _user) public view returns (uint256, address) {
        uint256 _totalPoints = getMyTotalPoints(_user);
        address _referrer = userInfo[_user].referrer;
        return (_totalPoints, _referrer);
    }

    function withdrawToken(address _token) external {
        require(block.timestamp > withdrawStartTime, "Need to wait by withdraw time");

        UserInfo storage user = userInfo[msg.sender];
        uint256 tokenAmount = user.amountTokens[_token];
        require(tokenAmount > 0, "There is no assets that you can withdraw");

        uint256 contracBalance = IERC20(_token).balanceOf(address(this));
        if (tokenAmount > contracBalance) {
            user.amountTokens[_token] = 0;
            IERC20(_token).transfer(msg.sender, tokenAmount);
        } else {
            return;
        }
    }

    function withdrawETH(uint256 _amount) external {
        require(block.timestamp > withdrawStartTime, "Need to wait by withdraw time");

        UserInfo storage user = userInfo[msg.sender];
        uint256 ethAmount = user.amountETH;
        require(ethAmount > 0, "There is no ETH that you can withdraw");

        user.amountETH = 0;
        payable(msg.sender).transfer(_amount);
    }

    function Pause() external onlyOwner {
        require(activeContract == true, 'Contract is paused now');

        activeContract = false;
    }

    function Start() external onlyOwner {
        require(activeContract == false, 'Contract is actived now');

        activeContract = true;
    }
    
    function changeWithdrawalTime(uint256 newWithdrawalStartTime) external onlyOwner {
        require(block.timestamp < newWithdrawalStartTime, "New timestamp can't be historical");
        require(
            withdrawStartTime > newWithdrawalStartTime, "Withdrawal start time can only be decreased, not increased"
        );

        withdrawStartTime = newWithdrawalStartTime;
    }

    function setbridgeproxyaddress(address _bridge) external onlyOwner {
        bridgeProxyAddress = _bridge;
    }
}
