// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract AirDrop is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;


    IERC20 public bird;

    constructor(IERC20 _bird) public {
        bird = _bird;
    }

    mapping(address => uint256) public quota;
    mapping(address => uint256) public claimed;


    function claim() external {
        uint256 amount = quota[msg.sender];
        require(amount > 0, "not permitted");

        claimed[msg.sender] = claimed[msg.sender].add(amount);
        quota[msg.sender] = 0;

        bird.safeTransfer(msg.sender, amount);
    }

    function setQuotaIndividual(address[] calldata users, uint256 defaultAmount) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            quota[users[i]] = defaultAmount;
        }
    }

    function setQuotaBatch(address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        require(users.length == amounts.length, "users.length == quota.length");
        for (uint256 i = 0; i < users.length; i++) {
            quota[users[i]] = amounts[i];
        }
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
    }
}
