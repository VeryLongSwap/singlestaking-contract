// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWBNB.sol";

contract PancakeFixedStaking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10000;
    struct Pool {
        IERC20 token;
        uint32 endDay;
        uint32 lockDayPercent;
        uint32 unlockDayPercent;
        uint32 lockPeriod; // Multiples of 3
        uint32 withdrawalCut1;
        uint32 withdrawalCut2;
        bool depositEnabled;
        uint128 maxDeposit;
        uint128 minDeposit;
        uint128 totalDeposited;
        uint128 maxPoolAmount;
    }
    Pool[] public pools;
    address public earn;

    struct UserInfo {
        uint128 userDeposit; // User deposit on pool
        uint128 accrueInterest; // User accrued interest
        uint32 lastDayAction;
    }

    struct InfoFront {
        Pool pool;
        UserInfo userInfo;
        uint32 endLockTime;
    }
    mapping(address => mapping(uint256 => UserInfo)) public userInfo; // User info storage: user address => pool id => UserInfo struct
    mapping(uint32 => mapping(uint256 => uint128)) public pendingWithdraw; // Day pending withdraw flag: day => pool id => amount, for offchain reference only
    mapping(address => mapping(uint256 => uint32)) public userPendingWithdraw; // User pending withdraw flag: user address => pool id => day, for offchain reference only
    mapping(uint32 => mapping(uint256 => uint128)) public dailyDeposit; // Daily deposit of pools: day => pool id => balance, for offchain reference only
    mapping(uint32 => mapping(uint256 => uint128)) public dailyWithdraw; // Daily withdraw of pools: day => pool id => balance, for offchain reference only
    // mapping(address => mapping(address => uint256)) public user;

    event PendingWithdraw(address indexed user, uint256 poolIndex, uint128 accumAmount);
    event PoolAdded(address indexed token, uint32 lockPeriod, uint256 poolIndex);
    event PoolChangeState(uint256 poolIndex, bool state);
    event PoolChanged(uint256 poolIndex);
    event Deposit(address indexed user, uint256 poolIndex, address indexed token, uint128 amount);
    event Withdraw(address indexed user, uint256 poolIndex, address indexed token, uint128 amount);
    event Harvest(address indexed user, uint256 poolIndex, address indexed token, uint128 amount);
    event TokenWithdraw(address indexed token, uint256 amount, address indexed to);

    address private constant WBNB = 0x441325a0e1D5aC0d64C9cc790FcAbf9c5416a4a1;
    address private earn_;
    uint128 private constant PERCENT_BASE = 1000_000_000;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _earn) public initializer {
        require(_earn != address(0), "Address cant be zero");

        __Ownable_init(owner);
        __ReentrancyGuard_init();
        __Pausable_init();

        earn = _earn;
    }

    modifier notContract() {
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        require(msg.sender.code.length == 0, "Contract not allowed");
        _;
    }

    receive() external payable {}
    fallback() external {}

    function addPool(Pool calldata _pool) external onlyOwner {
        require(address(_pool.token) != address(0), "Cant be zero address");
        pools.push(_pool);
        emit PoolAdded(address(_pool.token), _pool.lockPeriod, pools.length - 1);
    }

    function changePool(uint256 _poolIndex, Pool calldata _pool) external onlyOwner {
        require(_poolIndex < pools.length, "Index out of bound");
        require(_pool.maxDeposit >= _pool.minDeposit, "Incorrect deposit limit");
        uint128 _totalDeposited = pools[_poolIndex].totalDeposited;
        IERC20 _token = pools[_poolIndex].token;
        pools[_poolIndex] = _pool;
        pools[_poolIndex].totalDeposited = _totalDeposited; // Save total deposited when upgrade pool
        pools[_poolIndex].token = _token; // Cant change token
        emit PoolChanged(_poolIndex);
    }

    function setPoolState(uint256 _poolIndex, bool _state) external onlyOwner {
        require(_poolIndex < pools.length, "Index out of bound");
        pools[_poolIndex].depositEnabled = _state;
        if (!_state) {
            pools[_poolIndex].endDay = getCurrentDay();
        }
        emit PoolChangeState(_poolIndex, _state);
    }

    function setPoolEndDay(uint256 _poolIndex, uint32 _endDay) external onlyOwner {
        require(_poolIndex < pools.length, "Index out of bound");
        require(_endDay >= getCurrentDay(), "End day earlier than current day");
        pools[_poolIndex].endDay = _endDay;
    }

    function setEarn(address _newEarn) external onlyOwner {
        require(_newEarn != address(0), "Cant be zero address");
        earn = _newEarn;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function poolLength() public view returns (uint256 length) {
        length = pools.length;
    }

    function getCurrentDay() public view returns (uint32 currentDay) {
        currentDay = uint32((block.timestamp + 43200) / 86400); // Accrue everyday on 12:00 PM UTC
    }

    function getDailyBalances(
        uint256 poolId,
        uint32 firstDay,
        uint256 count
    ) public view returns (uint128[] memory _deposit, uint128[] memory _withdraw) {
        require(firstDay <= getCurrentDay(), "Wrong firstDay");
        count = count == 0 ? getCurrentDay() - firstDay + 1 : count;
        _deposit = new uint128[](count);
        _withdraw = new uint128[](count);
        for (uint32 i = 0; i < count; ++i) {
            _deposit[i] = dailyDeposit[firstDay + i][poolId];
            _withdraw[i] = dailyWithdraw[firstDay + i][poolId];
        }
        return (_deposit, _withdraw);
    }

    function getUserInfo(uint256 _poolIndex, address _user)
        public
        view
        returns (InfoFront memory info, uint32 currentDay)
    {
        require(_poolIndex < pools.length, "Index out of bound");

        info.pool = pools[_poolIndex];
        info.userInfo = userInfo[_user][_poolIndex];
        currentDay = getCurrentDay();

        (uint32 lockDays, uint32 unlockDays) = getMultiplier(
            info.userInfo.lastDayAction,
            info.pool.endDay,
            info.pool.lockPeriod
        );
        uint128 lockInterest = (info.userInfo.userDeposit * info.pool.lockDayPercent * lockDays) / PERCENT_BASE;
        uint128 unlockInterest = (info.userInfo.userDeposit * info.pool.unlockDayPercent * unlockDays) / PERCENT_BASE;
        info.userInfo.accrueInterest += lockInterest + unlockInterest;

        uint32 lockEndDay = info.userInfo.lastDayAction + info.pool.lockPeriod;
        info.endLockTime = info.userInfo.userDeposit > 0
            ? lockEndDay < info.pool.endDay ? lockEndDay * 86400 + 43200 : info.pool.endDay * 86400 + 43200
            : info.userInfo.lastDayAction * 86400 + 43200;
    }

    function deposit(uint256 _poolIndex, uint128 _amount) public payable nonReentrant whenNotPaused notContract {
        require(_poolIndex < pools.length, "Index out of bound");

        Pool memory _pool = pools[_poolIndex];
        UserInfo storage _userInfo = userInfo[msg.sender][_poolIndex];
        uint32 currentDay = getCurrentDay();

        require(_pool.depositEnabled && currentDay < _pool.endDay, "Deposit on pool is disabled");
        require(_amount >= _pool.minDeposit, "Need more amount");
        require(
            _userInfo.userDeposit + _amount <= _pool.maxDeposit &&
            _pool.totalDeposited + _amount <= _pool.maxPoolAmount,
            "Amount over pool limits"
        );
        require(currentDay + _pool.lockPeriod < _pool.endDay, "Too late");

        if (WBNB == address(_pool.token)) {
            if (msg.value > 0) {
                require(_amount == msg.value, "Incorrect amount");
                IWBNB(WBNB).deposit{value: msg.value}();
            } else {
                _pool.token.safeTransferFrom(msg.sender, earn, _amount);
            }
        } else {
            _pool.token.safeTransferFrom(msg.sender, earn, _amount);
        }

        if (_userInfo.userDeposit != 0) {
            (uint32 lockDays, uint32 unlockDays) = getMultiplier(
                _userInfo.lastDayAction,
                _pool.endDay,
                _pool.lockPeriod
            );
            uint128 lockInterest = (_userInfo.userDeposit * _pool.lockDayPercent * lockDays) / PERCENT_BASE;
            uint128 unlockInterest = (_userInfo.userDeposit * _pool.unlockDayPercent * unlockDays) / PERCENT_BASE;
            _userInfo.accrueInterest += lockInterest + unlockInterest;
        }

        _userInfo.lastDayAction = currentDay;
        _userInfo.userDeposit += _amount;
        pools[_poolIndex].totalDeposited += _amount;
        dailyDeposit[currentDay][_poolIndex] += _amount;

        emit Deposit(msg.sender, _poolIndex, address(_pool.token), _amount);
    }

    function withdraw(uint256 _poolIndex) public payable nonReentrant whenNotPaused notContract {
        require(_poolIndex < pools.length, "Index out of bound");
        Pool memory _pool = pools[_poolIndex];
        UserInfo storage _userInfo = userInfo[msg.sender][_poolIndex];
        require(_userInfo.userDeposit > 0, "User has zero deposit");
        
        uint128 lockInterest = 0;
        uint128 unlockInterest = 0;
        uint128 totalInterest = _userInfo.accrueInterest + lockInterest + unlockInterest;
        uint128 accumAmount = _userInfo.userDeposit + totalInterest;

        uint32 currentDay = getCurrentDay();
        uint32 poolLockPeriodUnit = _pool.lockPeriod / 3;
        uint128 amount;
        if (currentDay < _pool.endDay) {
            uint32 days_ = currentDay - _userInfo.lastDayAction;
            //require(days_ > poolLockPeriodUnit, "No withdrawal allowed");
            if (days_ <= poolLockPeriodUnit * 2) {
                amount = (_userInfo.userDeposit * _pool.withdrawalCut1) / BASIS_POINTS_DENOMINATOR + totalInterest;
            } else if (days_ <= poolLockPeriodUnit * 3) {
                amount = (_userInfo.userDeposit * _pool.withdrawalCut2) / BASIS_POINTS_DENOMINATOR + totalInterest;
            }
        }
        
        if (_pool.token.balanceOf(address(this)) < accumAmount) {
            if (userPendingWithdraw[msg.sender][_poolIndex] != currentDay) {
                pendingWithdraw[currentDay][_poolIndex] += accumAmount;
                userPendingWithdraw[msg.sender][_poolIndex] = currentDay;
                emit PendingWithdraw(msg.sender, _poolIndex, accumAmount);
            } else {
                revert("Withdrawal request pending");
            }
        } else {
            pools[_poolIndex].totalDeposited -= _userInfo.userDeposit;
            dailyWithdraw[currentDay][_poolIndex] += _userInfo.userDeposit;
            _userInfo.userDeposit = 0;
            _userInfo.accrueInterest = 0;
            _userInfo.lastDayAction = currentDay;
            _pool.token.safeTransfer(msg.sender, accumAmount - amount);
            emit Withdraw(msg.sender, _poolIndex, address(_pool.token), accumAmount - amount);
        }
    }

    function harvest(uint256 _poolIndex) public payable nonReentrant whenNotPaused notContract {
        require(_poolIndex < pools.length, "Index out of bound");
        Pool memory _pool = pools[_poolIndex];
        UserInfo storage _userInfo = userInfo[msg.sender][_poolIndex];

        uint32 currentDay = getCurrentDay();
        require(
            currentDay - _userInfo.lastDayAction > _pool.lockPeriod || currentDay >= _pool.endDay,
            "Lock period not finished"
        );

        (uint32 lockDays, uint32 unlockDays) = getMultiplier(
            _userInfo.lastDayAction,
            _pool.endDay,
            _pool.lockPeriod
        );
        uint128 lockInterest = (_userInfo.userDeposit * _pool.lockDayPercent * lockDays) / PERCENT_BASE;
        uint128 unlockInterest = (_userInfo.userDeposit * _pool.unlockDayPercent * unlockDays) / PERCENT_BASE;
        uint128 totalInterest = _userInfo.accrueInterest + lockInterest + unlockInterest;

        if (_pool.token.balanceOf(address(this)) < totalInterest) {
            if (userPendingWithdraw[msg.sender][_poolIndex] != currentDay) {
                pendingWithdraw[currentDay][_poolIndex] += totalInterest;
                userPendingWithdraw[msg.sender][_poolIndex] = currentDay;
                emit PendingWithdraw(msg.sender, _poolIndex, totalInterest);
            } else {
                revert("Harvest request pending");
            }
        } else {
            _userInfo.accrueInterest = 0;
            _userInfo.lastDayAction = currentDay;
            _pool.token.safeTransfer(msg.sender, totalInterest);
            emit Harvest(msg.sender, _poolIndex, address(_pool.token), totalInterest);
        }
    }

    function withdrawToken(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        require( _to != address(0), "Cant be zero address");
        if (address(_token) == address(0)) {
            payable(_to).transfer(_amount);
            emit TokenWithdraw(address(_token), _amount, _to);
        } else {
            _token.safeTransfer(_to, _amount);
            emit TokenWithdraw(address(_token), _amount, _to);
        }

    }

    function getMultiplier(
        uint32 _lastDayAction,
        uint32 _poolEndDay,
        uint32 _poolLockPeriod
    ) internal view returns (uint32 lockDays, uint32 unlockDays) {
        uint32 currentDay = getCurrentDay();
        uint32 lockEndDay = _lastDayAction + _poolLockPeriod;

        if (_lastDayAction == 0) return (0, 0);

        if ((currentDay >= _lastDayAction) && (currentDay <= _poolEndDay)) {
            if (lockEndDay < currentDay) {
                lockDays = _poolLockPeriod;
                unlockDays = currentDay - lockEndDay;
            } else {
                lockDays = currentDay - _lastDayAction;
                unlockDays = 0;
            }
        } else if ((currentDay >= _lastDayAction) && (currentDay > _poolEndDay) && (_poolEndDay >= _lastDayAction)) {
            if (lockEndDay < _poolEndDay) {
                lockDays = _poolLockPeriod;
                unlockDays = _poolEndDay - lockEndDay;
            } else {
                lockDays = _poolEndDay - _lastDayAction;
                unlockDays = 0;
            }
        } else {
            lockDays = 0;
            unlockDays = 0;
        }
    }
}