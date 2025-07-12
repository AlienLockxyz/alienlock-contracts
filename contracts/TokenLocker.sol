// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
}

contract TokenLocker {
    address public owner;

    string public constant serviceName = "AlienLock.xyz";
    string public constant version = "1.0.0";

    string public serviceUrl;

    bool public whitelistEnabled;

    uint16 public lockFeePermille;

    bool public earlyUnlockEnabled;
    uint16 public earlyUnlockFeePermille;

    mapping(address => bool) public whitelist;

    struct LockInfo {
        address token;
        address locker;
        address recipient;        
        uint256 amount;
        uint256 lockTimestamp;
        uint256 unlockTimestamp;
        bool unlocked;
    }

    LockInfo[] public locks;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    event Locked(uint indexed lockId, address indexed locker, address token, uint amount, uint unlockTimestamp, address recipient);
    event Unlocked(uint indexed lockId, address indexed locker, address token, uint amount, address recipient);
    event WhitelistUpdated(address indexed user, bool status);
    event ServiceUrlUpdated(string newUrl);
    event LockFeeUpdated(uint16 newFeePermille);
    event EarlyUnlockUpdated(bool enabled, uint16 feePermille);

    constructor(string memory _serviceUrl) {
        owner = msg.sender;
        serviceUrl = _serviceUrl;
        whitelistEnabled = false;
        lockFeePermille = 0;
        earlyUnlockEnabled = false;
        earlyUnlockFeePermille = 0;
    }

    // Owner-only functions
    function setServiceUrl(string memory _serviceUrl) external onlyOwner {
        serviceUrl = _serviceUrl;
        emit ServiceUrlUpdated(_serviceUrl);
    }

    function setWhitelistEnabled(bool _enabled) external onlyOwner {
        whitelistEnabled = _enabled;
    }

    function addToWhitelist(address _user) external onlyOwner {
        whitelist[_user] = true;
        emit WhitelistUpdated(_user, true);
    }

    function removeFromWhitelist(address _user) external onlyOwner {
        whitelist[_user] = false;
        emit WhitelistUpdated(_user, false);
    }

    function setLockFeePermille(uint16 _fee) external onlyOwner {
        require(_fee <= 1000, "Fee too high");
        lockFeePermille = _fee;
        emit LockFeeUpdated(_fee);
    }

    function setEarlyUnlockEnabled(bool _enabled, uint16 _feePermille) external onlyOwner {
        earlyUnlockEnabled = _enabled;
        earlyUnlockFeePermille = _feePermille;
        emit EarlyUnlockUpdated(_enabled, _feePermille);
    }

    // Lock tokens 
    function lockToken(address _token, uint256 _amount, uint256 _unlockTimestamp, address _recipient) external {
        require(_amount > 0, "Amount > 0");
        require(_unlockTimestamp > block.timestamp, "Unlock time > now");
        require(_recipient != address(0), "Recipient cannot be zero address");

        if (whitelistEnabled) {
            require(whitelist[msg.sender], "Not in whitelist");
        }

        uint256 fee = (_amount * lockFeePermille) / 1000;
        uint256 amountAfterFee = _amount - fee;

        // Transfer tokens from user to contract (including fee)
        require(IERC20(_token).transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        // Transfer fee to owner (if applicable)
        if (fee > 0) {
            require(IERC20(_token).transfer(owner, fee), "Fee transfer failed");
        }

        locks.push(LockInfo({
            token: _token,
            locker: msg.sender,
            recipient: _recipient,
            amount: amountAfterFee,
            lockTimestamp: block.timestamp,
            unlockTimestamp: _unlockTimestamp,
            unlocked: false
        }));

        emit Locked(locks.length - 1, msg.sender, _token, amountAfterFee, _unlockTimestamp, _recipient);
    }

    // Unlock tokens after lock period or early unlock (with fee)
    function unlockToken(uint _lockId) external {
        require(_lockId < locks.length, "Invalid lockId");
        LockInfo storage lockInfo = locks[_lockId];
        require(msg.sender == lockInfo.locker || msg.sender == lockInfo.recipient, "Not authorized");
        require(!lockInfo.unlocked, "Already unlocked");

        if (block.timestamp < lockInfo.unlockTimestamp) {
            require(earlyUnlockEnabled, "Early unlock disabled");
            uint256 fee = (lockInfo.amount * earlyUnlockFeePermille) / 1000;
            uint256 amountAfterFee = lockInfo.amount - fee;
            require(IERC20(lockInfo.token).transfer(owner, fee), "Early unlock fee transfer failed");
            require(IERC20(lockInfo.token).transfer(lockInfo.recipient, amountAfterFee), "Token transfer failed");
        } else {
            require(IERC20(lockInfo.token).transfer(lockInfo.recipient, lockInfo.amount), "Token transfer failed");
        }

        lockInfo.unlocked = true;
        emit Unlocked(_lockId, msg.sender, lockInfo.token, lockInfo.amount, lockInfo.recipient);
    }

    // View total number of locks
    function totalLocks() external view returns (uint) {
        return locks.length;
    }
}
