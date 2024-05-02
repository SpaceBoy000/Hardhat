//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract TestChain is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // address public WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    // address public rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    address public DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;

    uint256 public constant DENOMINATOR = 10000;
    uint256 public constant MULTIPLIER_BTC = 18000;
    uint256 public constant MULTIPLIER_ETH = 14000;
    uint256 public constant MULTIPLIER_USD = 12000;
    uint256 public constant POINT_AMOUNT_PER_USD = 5;
    uint256 public constant POINT_DECIMALS = 18; // Point decimal: 18
    uint256 public constant REFERRAL_FEE = 500; // 5%

    // Info of each user.
    struct UserInfo {
        uint256 amount; // total assets amount
        uint256 totalPoints;
        uint256 lastUpdateTime;
        address referrer;
        uint256 refAmount;
    }

    uint256 public totalUserCount;
    address[] public allUsers;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    address router = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // BSC Test
    IUniswapV2Router02 public immutable dexRouter;

    event DepositToken(address indexed user, address token, uint256 amount, uint256 totalPoints, uint256 totalUSDAmount, address referrer);

    constructor(address _usdt) Ownable(msg.sender) {
        IUniswapV2Router02 _dexRouter = IUniswapV2Router02(router);
        // set the rest of the contract variables
        dexRouter = _dexRouter;
        USDT = _usdt;
    }

    //to recieve ETH from dexRouter when swaping
    receive() external payable {}

    // Get token price
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
    function deposit(address _token, uint256 _amount, address _referrer) public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        require(_referrer != msg.sender, "You could not be own referrer");
        if (user.referrer == address(0) && _referrer != address(0)) {
            user.referrer = _referrer;
        }

        if (user.amount == 0) {
            // new depositor
            totalUserCount++;
            allUsers.push(msg.sender);
            user.lastUpdateTime = block.timestamp;
        } else {
            updateUserPoints(msg.sender);
        }

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);

        uint256 _multiplier = DENOMINATOR;
        
        if (_token == WBTC) {
            _multiplier = MULTIPLIER_BTC;
        } else if (_token == dexRouter.WETH()) {
            _multiplier = MULTIPLIER_ETH;
        } else if ( _token == DAI || _token == USDT || _token == USDC || _token == sUSDe ) {
            _multiplier = MULTIPLIER_USD;
        }

        uint256 tokenPrice = _multiplier == MULTIPLIER_USD ? _amount : getTokenPrice(_token, _amount);
        uint256 amountUSD = tokenPrice * _multiplier / DENOMINATOR;
        // ** should consider decimal in _amount
        uint256 newPoints = amountUSD * POINT_AMOUNT_PER_USD;

        user.amount += amountUSD;
        user.lastUpdateTime = block.timestamp;
        user.totalPoints += newPoints;
        if (user.referrer != address(0)) {
            userInfo[user.referrer].refAmount += (newPoints * REFERRAL_FEE / DENOMINATOR);
            userInfo[user.referrer].totalPoints += (newPoints * REFERRAL_FEE / DENOMINATOR);
        }

        emit DepositToken(msg.sender, _token, _amount, user.totalPoints, user.amount, user.referrer);
    }

    // Deposit ETH
    function depositETH(address _referrer) public payable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 _amount = msg.value;

        require(_referrer != msg.sender, "You could not be own referrer");
        if (user.referrer == address(0) && _referrer != address(0)) {
            user.referrer = _referrer;
        }
        
        if (user.amount == 0) {
            // new depositor
            totalUserCount++;
            allUsers.push(msg.sender);
            user.lastUpdateTime = block.timestamp;
        } else {
            updateUserPoints(msg.sender);
        }

        uint256 _multiplier = MULTIPLIER_ETH;

        uint256 tokenPrice = getETHPrice(_amount);
        uint256 amountUSD = tokenPrice * _multiplier / DENOMINATOR;
        // ** should consider decimal in _amount
        uint256 newPoints = amountUSD * POINT_AMOUNT_PER_USD;

        user.amount += amountUSD;
        user.lastUpdateTime = block.timestamp;
        user.totalPoints += newPoints;
        if (user.referrer != address(0)) {
            userInfo[user.referrer].refAmount += (newPoints * REFERRAL_FEE / DENOMINATOR);
            userInfo[user.referrer].totalPoints += (newPoints * REFERRAL_FEE / DENOMINATOR);
        }
        
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
        require(
            userInfo[_user].amount > 0,
            "Only depositer can receive giveaway"
        );
        userInfo[_user].totalPoints += _points;
    }

    function withdrawToken(
        address _token,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        if (IERC20(_token).balanceOf(address(this)) >= _amount) {
            IERC20(_token).transfer(_to, _amount);
        }
    }

    function withdrawETH(address _to, uint256 _amount) public onlyOwner {
        if (address(this).balance >= _amount) {
            payable(_to).transfer(_amount);
        }
    }

    function setTokenaddressWBTC(address _token) public onlyOwner {
        WBTC = _token;
    }

    function setTokenaddressUSDT(address _token) public onlyOwner {
        USDT = _token;
    }
    
    function setTokenaddressUSDC(address _token) public onlyOwner {
        USDC = _token;
    }
    
    function setTokenaddressDAI(address _token) public onlyOwner {
        DAI = _token;
    }
}
