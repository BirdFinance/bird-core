// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./Vault.sol";

contract ERCVault is Vault {
    using SafeMath for uint256;

    constructor (IERC20 _capital, IController _controller) public Vault(_capital, _controller){}

    function idleCapital() public override view returns (uint256){
        return capital_.balanceOf(address(this));
    }


    function doTransferIn(address from, uint256 amount) internal override returns (uint256) {
        uint256 balanceBefore = capital_.balanceOf(address(this));
        capital_.safeTransferFrom(from, address(this), amount);

        uint256 balanceAfter = capital_.balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "TOKEN_TRANSFER_IN_OVERFLOW");
        return balanceAfter.sub(balanceBefore);

    }


    function doTransferOut(address to, uint256 amount) internal override {
        capital_.safeTransfer(to, amount);
    }
}
