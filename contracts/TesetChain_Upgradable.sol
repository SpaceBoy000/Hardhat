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

interface ILido is IERC20 {
    function submit(address user) external payable;
}

interface WLido is IERC20 {
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
    function getClaimableEther(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
    function claimWithdrawal(uint256 _requestId) external;
    function requestWithdrawals(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
}

interface IDsrManager {
    function join(address dst, uint256 wad) external;
    function exit(address dst, uint256 wad) external;
    function exitAll(address dst) external;
    function daiBalance(address usr) external returns (uint256 wad);
    function pot() external view returns (address);
    function pieOf(address) external view returns (uint256);
}

interface IDssPsm {
    function sellGem(address usr, uint256 gemAmt) external;
    function buyGem(address usr, uint256 gemAmt) external;
    function dai() external view returns (address);
    function gemJoin() external view returns (address);
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
}

interface ICurve3Pool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

contract TestChainUpgradable is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    
    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WLido public constant withdrawLIDO = WLido(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);
    IDsrManager public constant DSR_MANAGER = IDsrManager(0x373238337Bfe1146fb49989fc222523f83081dDb);
    IDssPsm public constant PSM = IDssPsm(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A);
    ICurve3Pool public constant CURVE_3POOL = ICurve3Pool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    address public constant WBTC  = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDT  = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC  = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    uint256 internal constant _USD_DECIMALS = 6;
    uint256 internal constant _WAD_DECIMALS = 18;
     int128 internal constant _CURVE_USDT_INDEX = 2;
     int128 internal constant _CURVE_DAI_INDEX = 0;
    uint256 internal constant _WAD = 10 ** 18;

    uint256 public constant DENOMINATOR = 100_000;
    uint256 public constant MULTIPLIER_BTC = 180_000; // 1.8x
    uint256 public constant MULTIPLIER_ETH = 140_000; // 1.4x
    uint256 public constant MULTIPLIER_USD = 120_000; // 1.2x
    uint256 public constant POINT_AMOUNT_PER_USD = 5; // 5 points per usd
    uint256 public constant REFERRAL_FEE = 5_000;     // 5%
    uint256 public slippage;
    
    address constant router = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // BSC Test
    IUniswapV2Router01 public dexRouter;

    bool public activeContract;
    bool public activeWithdraw;

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
    uint256 public totalStakedDAIAmount;

    mapping(address => uint256) public totalTokenAmounts;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    

    event DepositToken(address indexed user, address token, uint256 amount, uint256 totalPoints, uint256 totalUSDAmount, address referrer);
    event USDCDeposited(address indexed user, uint256 usdcAmount);
    event USDTExchanged(address indexed user, uint256 usdtAmount);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        
        IUniswapV2Router01 _dexRouter = IUniswapV2Router01(router);
        dexRouter = _dexRouter;

        // IERC20(USDC).approve(PSM.gemJoin(), type(uint256).max);
        // IERC20(USDT).approve(address(CURVE_3POOL), type(uint256).max);
        // IERC20(DAI).approve(address(DSR_MANAGER), type(uint256).max);

        activeContract = true;
        activeWithdraw = false;

        slippage = 10_000; // 10%
    }

    //to recieve ETH from dexRouter when swaping
    receive() external payable {}

    /**
     * @notice Convert from wad (18 decimals) to USD (6 decimals) denomination
     * @param wad Amount in wad
     * @return Amount in USD
     */
    function _wadToUSD(uint256 wad) internal pure returns (uint256) {
        return wad / (10 ** (_WAD_DECIMALS - _USD_DECIMALS));
    }

    /**
     * @notice Convert from USD (6 decimals) to wad (18 decimals) denomination
     * @param usd Amount in USD
     * @return Amount in wad
     */
    function _usdToWad(uint256 usd) internal pure returns (uint256) {
        return usd * (10 ** (_WAD_DECIMALS - _USD_DECIMALS));
    }


    function exchangeUSDC(uint256 usdcAmount) internal {
        /* Convert USDC to DAI through MakerDAO Peg Stability Mechanism. */
        PSM.sellGem(address(this), usdcAmount);

        emit USDCDeposited(msg.sender, usdcAmount);
    }

    function exchangeUSDT(uint256 usdtAmount, uint256 minDAIAmount) internal {
        CURVE_3POOL.exchange(
            _CURVE_USDT_INDEX,
            _CURVE_DAI_INDEX,
            usdtAmount,
            minDAIAmount
        );
        
        emit USDTExchanged(msg.sender, usdtAmount);
    }

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

        if (_token == WBTC) {
            _multiplier = MULTIPLIER_BTC;
        } else if (_token == dexRouter.WETH()) {
            _multiplier = MULTIPLIER_ETH;
        } else if (_token == DAI) {
            _multiplier = MULTIPLIER_USD;
        } else if (_token == USDC) {
            _multiplier = MULTIPLIER_USD;
            exchangeUSDC(_amount);
        } else if (_token == USDT) {
            _multiplier = MULTIPLIER_USD;
            exchangeUSDT(_amount, _amount - _amount * slippage / DENOMINATOR);
        } else if (_token == sUSDe) {
            _multiplier = MULTIPLIER_USD;
        } else {
            return;
        }

        uint256 daiBalance = IERC20(DAI).balanceOf(address(this));
        if (daiBalance > 0) {
            totalStakedDAIAmount += daiBalance;
            DSR_MANAGER.join(address(this), daiBalance);
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

        LIDO.submit{value: msg.value}(address(0));

        emit DepositToken(msg.sender, address(0), _amount, user.totalPoints, user.amount, user.referrer);
    }

    function updateUserPoints(address _user) public {
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

    function giveAway(address _user, uint256 _points) public onlyOwner {
        require(userInfo[_user].amount > 0, "Only depositer can receive giveaway");

        userInfo[_user].totalPoints += _points;
    }

    function withdrawToken(address _token) external {
        require(activeWithdraw, "Withdraw was paused for a while, please wait.");

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
        require(activeWithdraw, "Withdraw was paused for a while, please wait.");

        UserInfo storage user = userInfo[msg.sender];
        uint256 ethAmount = user.amountETH;
        require(ethAmount > 0, "There is no ETH that you can withdraw");

        user.amountETH = 0;
        payable(msg.sender).transfer(_amount);
    }

    function totalstETHBalance() public view returns (uint256) {
        return LIDO.balanceOf(address(this));
    }

    uint256 public requestId;

    function requestWithdrawToLido() external onlyOwner {
        require(activeWithdraw, "withdraw is not allowed yet");

        uint256 sthBalance = LIDO.balanceOf(address(this));
        uint256[] memory sthBalances = new uint256[](1);
        sthBalances[0] = sthBalance;
        uint256[] memory requestIds = withdrawLIDO.requestWithdrawals(sthBalances, address(this));
        requestId = requestIds[0];
    }

    function claimWithdrawalFromLIDO() external onlyOwner {
        require(activeWithdraw, "withdraw is not allowed yet");
        
        if (requestId != 0) {
            withdrawLIDO.claimWithdrawal(requestId);
        }
    }

    function unstakeDAIFromMakeDAO(uint256 amount) external onlyOwner {
        DSR_MANAGER.exit(address(this), amount);
    }

    function exchangeDAI_USDC(uint256 daiAmount) external onlyOwner {
        /* Convert DAI to USDC through MakerDAO Peg Stability Mechanism. */
        PSM.buyGem(address(this), daiAmount);
        
        emit USDCDeposited(msg.sender, daiAmount);
    }

    function exchangeDAI_USDT(uint256 daiAmount, uint256 minUSDTAmount) external onlyOwner {
        CURVE_3POOL.exchange(
            _CURVE_DAI_INDEX,
            _CURVE_USDT_INDEX,
            daiAmount,
            minUSDTAmount
        );
        
        emit USDTExchanged(msg.sender, daiAmount);
    }

    function setSlippage(uint256 _value) external onlyOwner {
        require(_value < 100_000 && _value > 1000, "minimum slippage is 1% and maximum slippage is 100%");

        slippage = _value;
    }

    function pauseContract() external onlyOwner {
        require(activeContract == true, 'Contract is paused now');

        activeContract = false;
    }

    function resumeContract() external onlyOwner {
        require(activeContract == false, 'Contract is actived now');

        activeContract = true;
    }

    function pauseWithdraw() external onlyOwner {
        require(activeWithdraw == true, 'Withdraw is paused now');

        activeWithdraw = false;
    }
    
    function resumeWithdraw() external onlyOwner {
        require(activeWithdraw == false, 'Withdraw is actived now');

        activeWithdraw = true;
    }
}
