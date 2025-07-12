// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20, Ownable {
    struct TokenParams {
        string name;
        string symbol;
        uint256 initialSupply;
        bool mintable;
        address minter;
        uint256 maxHoldAmount;
        uint256 maxTxAmount;
        bool antiBotEnabled;
        bool throttleEnabled;
        uint256 throttleLimit;
        uint256 throttlePeriod;
        uint256 tradeStartTime;
    }

    bool public mintable;
    address public minter;

    uint256 public maxHoldAmount;
    uint256 public maxTxAmount;

    bool public antiBotEnabled;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public blocklist;

    uint256 public tradeStartTime;

    bool public throttleEnabled;
    uint256 public throttleLimit;
    uint256 public throttlePeriod;

    mapping(address => uint256) public txCount;
    mapping(address => uint256) public lastTxTime;

    event MaxHoldAmountUpdated(uint256);
    event MaxTxAmountUpdated(uint256);
    event AntiBotEnabledUpdated(bool);
    event WhitelistAddressAdded(address);
    event WhitelistAddressRemoved(address);
    event BlocklistAddressAdded(address);
    event BlocklistAddressRemoved(address);
    event TradeStartTimeUpdated(uint256);
    event ThrottleSettingsUpdated(bool, uint256, uint256);

    constructor(TokenParams memory p) ERC20(p.name, p.symbol) {
        mintable = p.mintable;
        minter = p.minter;

        _mint(p.minter, p.initialSupply);
        transferOwnership(p.minter);

        maxHoldAmount = p.maxHoldAmount;
        maxTxAmount = p.maxTxAmount;
        antiBotEnabled = p.antiBotEnabled;
        throttleEnabled = p.throttleEnabled;
        throttleLimit = p.throttleLimit;
        throttlePeriod = p.throttlePeriod;
        tradeStartTime = p.tradeStartTime;
    }

    function mint(address to, uint256 amount) external {
        require(mintable, "Minting disabled");
        require(msg.sender == minter, "Not minter");
        _mint(to, amount);
    }

    function setMaxHoldAmount(uint256 amount) external onlyOwner {
        maxHoldAmount = amount;
        emit MaxHoldAmountUpdated(amount);
    }

    function setMaxTxAmount(uint256 amount) external onlyOwner {
        maxTxAmount = amount;
        emit MaxTxAmountUpdated(amount);
    }

    function setAntiBotEnabled(bool enabled) external onlyOwner {
        antiBotEnabled = enabled;
        emit AntiBotEnabledUpdated(enabled);
    }

    function addWhitelistAddress(address account) external onlyOwner {
        whitelist[account] = true;
        emit WhitelistAddressAdded(account);
    }

    function removeWhitelistAddress(address account) external onlyOwner {
        whitelist[account] = false;
        emit WhitelistAddressRemoved(account);
    }

    function addBlocklistAddress(address account) external onlyOwner {
        blocklist[account] = true;
        emit BlocklistAddressAdded(account);
    }

    function removeBlocklistAddress(address account) external onlyOwner {
        blocklist[account] = false;
        emit BlocklistAddressRemoved(account);
    }

    function setTradeStartTime(uint256 timestamp) external onlyOwner {
        tradeStartTime = timestamp;
        emit TradeStartTimeUpdated(timestamp);
    }

    function setThrottleSettings(bool enabled, uint256 limit, uint256 period) external onlyOwner {
        throttleEnabled = enabled;
        throttleLimit = limit;
        throttlePeriod = period;
        emit ThrottleSettingsUpdated(enabled, limit, period);
    }

    function _checkThrottle(address account) internal {
        if (!throttleEnabled) return;

        uint256 currentTime = block.timestamp;
        if (currentTime > lastTxTime[account] + throttlePeriod) {
            txCount[account] = 1;
            lastTxTime[account] = currentTime;
        } else {
            require(txCount[account] < throttleLimit, "Throttle limit exceeded");
            txCount[account]++;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        bool isMintOrBurn = from == address(0) || to == address(0);

        if (tradeStartTime > 0 && block.timestamp < tradeStartTime) {
            require(isMintOrBurn, "Trading not started");
        }

        require(!blocklist[from], "Sender blocked");
        require(!blocklist[to], "Recipient blocked");

        if (!isMintOrBurn) {
            if (maxTxAmount > 0) {
                require(amount <= maxTxAmount, "Exceeds max tx amount");
            }

            if (maxHoldAmount > 0) {
                require(balanceOf(to) + amount <= maxHoldAmount, "Exceeds max hold");
            }

            if (antiBotEnabled) {
                require(whitelist[from] || whitelist[to], "Not whitelisted");
            }

            _checkThrottle(from);
        }
    }
}

contract TokenFactory {
    address public owner;
    event TokenCreated(address tokenAddress);

    constructor() {
        owner = msg.sender;
    }

    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        bool mintable,
        address minter,
        uint256 maxHoldAmount,
        uint256 maxTxAmount,
        bool antiBotEnabled,
        bool throttleEnabled,
        uint256 throttleLimit,
        uint256 throttlePeriod,
        uint256 tradeStartTime
    ) external returns (address) {
        require(
            !mintable || (minter == msg.sender || minter == owner),
            "Invalid minter"
        );

        MyToken.TokenParams memory p = MyToken.TokenParams(
            name,
            symbol,
            initialSupply,
            mintable,
            minter,
            maxHoldAmount,
            maxTxAmount,
            antiBotEnabled,
            throttleEnabled,
            throttleLimit,
            throttlePeriod,
            tradeStartTime
        );

        MyToken token = new MyToken(p);
        emit TokenCreated(address(token));
        return address(token);
    }
}
