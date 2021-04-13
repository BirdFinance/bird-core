// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LinearTimeUnlock is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bool inited = false;
    uint256 public start = 0;
    IERC20 public token;
    uint256 public lastWithdrawnTimestamp = 0;
    uint256 public rate;
    address public master;

    constructor(IERC20 _token, address _master) public {
        require(address(_token) != address(0), "address (_token ) != address(0)");
        token = _token;
        require(_master != address(0), "_master != address(0)");
        master = _master;

    }

    function init(uint256 _start, uint256 _balance, uint256 _duration) external onlyOwner {
        require(!inited, "!inited");
        inited = true;

        start = _start;
        lastWithdrawnTimestamp = _start;

        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _balance);
        uint256 balanceAfter = token.balanceOf(address(this));

        //only for log
        uint256 balance = balanceAfter.sub(balanceBefore);

        rate = balance.div(_duration);
    }

    //you can only change the rate,
    //or transfer more token into this contract.
    // watch out, the _balance may be different between before-transfer() and after-transfer()
    //    function updateRate(uint256 _balance, uint256 _duration) external onlyOwner {
    //        rate = _balance.div(_duration);
    //    }

    function getAmount() public view returns (uint256, string memory){
        if (lastWithdrawnTimestamp >= block.timestamp) {
            return (0, "lastWithdrawnTimestamp >= block.timestamp");
        }

        uint256 amount = block.timestamp.sub(lastWithdrawnTimestamp).mul(rate);
        uint256 remaining = token.balanceOf(address(this));

        if (remaining < amount) {
            return (remaining, "remaining < amount");
        }

        return (amount, "normal");
    }

    function withdraw() external nonReentrant{
        require(msg.sender == master, "msg.sender == master");
        //redundant
        require(start < block.timestamp, "start <= block.timestamp");
        require(lastWithdrawnTimestamp < block.timestamp, "lastWithdrawnTimestamp < block.timestamp");
        uint256 xferAmount;
        (xferAmount,) = getAmount();
        lastWithdrawnTimestamp = block.timestamp;

        if (xferAmount == 0) {
            return;
        }
        token.safeTransfer(master, xferAmount);
    }
}
