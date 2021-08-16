//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.3;

import "../IStrat.sol";
import './IIToken.sol';
import "../../vault/IVault.sol";
import "../../misc/Timelock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";


contract IDleTokenStrat is IStrat {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Detailed;
    IVault public vault;
    IIdleToken public iToken;
    IERC20Detailed public underlying;
    Timelock public timelock;
    uint public immutable minWithdrawalCap; // prevents the owner from completely blocking withdrawals
    uint public withdrawalCap = uint(-1); // max uint
    uint public buffer; // buffer of underlying to keep in the strat
    string public name = "Idle"; // for display purposes only
    address public strategist;

    modifier onlyVault {
        require(msg.sender == address(vault));
        _;
    }

    modifier onlyTimelock {
        require(msg.sender == address(timelock));
        _;
    }

    modifier onlyStrategist {
        require(msg.sender == strategist || msg.sender == address(timelock));
        _;
    }

    constructor(IVault vault_, IIdleToken iToken_, Timelock timelock_) {
        strategist = msg.sender;
        vault = vault_;
        iToken = iToken_;
        timelock = timelock_;
        underlying = IERC20Detailed(iToken_.token());
        underlying.safeApprove(address(iToken), uint(-1)); // intentional underflow
        minWithdrawalCap = 1000 * (10 ** underlying.decimals()); // 10k min withdrawal cap
    }

    function invest() external override onlyVault {
        uint balance = underlying.balanceOf(address(this));
        if(balance > buffer) {
            iToken.mintIdleToken(balance - buffer, true, address(this));
            // uint max = iToken.availableDepositLimit();
            // if(max > 0) {
            //      // can't underflow because of above if statement
            // }
        }
    }

    function divest(uint amount) external override onlyVault {
        uint balance = underlying.balanceOf(address(this));
        if(balance < amount) {
            uint missingAmount = amount - balance; // can't underflow because of above it statement
            require(missingAmount <= withdrawalCap, "Reached withdrawal cap"); // Big withdrawals can cause slippage on Idle's side. Users must split into multiple txs
            iToken.redeemIdleToken(iToken.balanceOf(address(this)));
        }
        underlying.safeTransfer(address(vault), amount);
    }

    function totalIdleDeposits() public view returns (uint) {
        return iToken.balanceOf(address(this))
                .mul(iToken.tokenPrice())
                .div(10**iToken.decimals());
    }

    function calcTotalValue() external view override returns (uint) {
        return Math.max(totalIdleDeposits(), 1) // cannot be lower than 1 because we subtract 1 after
        .sub(1) // account for dust
        .add(underlying.balanceOf(address(this)));
    }

    // set buffer to -1 to pause deposits to Idle. 0 to remove buffer.
    function setBuffer(uint _buffer) public onlyStrategist {
        buffer = _buffer;
    }

    // set to -1 for no cap
    function setWithdrawalCap(uint underlyingCap) public onlyStrategist {
        require(underlyingCap >= minWithdrawalCap);
        withdrawalCap = underlyingCap;
    }

    // function sharesForAmount(uint amount) internal view returns (uint) {
    //     return amount.mul(iToken.totalSupply()).div(iToken.totalAssets());
    // }

    function setStrategist(address _strategist) public onlyTimelock {
        strategist = _strategist;
    }
}