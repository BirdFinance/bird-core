// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import "../controller/IController.sol";
import "./IStrategy.sol";
import "../vaults/IVault.sol";
import "../controller/Controllerable.sol";

abstract contract BaseStrategy is IStrategy, Ownable, Controllerable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant  PERCENT = 100;
    uint256 constant baseDecimal = 1e18;
    uint256 constant baseCent = 100;

    uint256 public profitFee;
    address public swapRouter;
    IERC20 public rewardToken;

    IERC20 public capital_;
    IVault public vault_;

    constructor(
        IVault _vault,
        IController _controller,
        IERC20 _capital,
        address _swapRouter,
        IERC20 _rewardToken,
        uint256 _profitFee
    )  Controllerable(_controller)public {
        vault_ = _vault;
        capital_ = _capital;
        swapRouter = _swapRouter;
        rewardToken = _rewardToken;
        profitFee = _profitFee;//30
    }


    modifier restricted() {
        require(msg.sender == address(vault_) || msg.sender == address(controller) || msg.sender == owner(),
            "The sender has to be the controller or vault or owner");
        _;
    }

    modifier permitted() {
        require(IController(controller).check(msg.sender) || msg.sender == vault() || msg.sender == address(controller) || msg.sender == owner(),
            "address is ban");
        _;
    }

    // reward -> capital
    function compound() virtual internal;

    //input class is capital, not reward token
    function settleProfit(uint256 oldBalance, uint256 newBalance) internal {
        if (newBalance > oldBalance) {
            uint256 profit = newBalance.sub(oldBalance);
            uint256 feeAmount = profit.mul(profitFee).div(PERCENT);
            capital_.safeTransfer(controller.feeManager(), feeAmount);
        }
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        require(erc20Token != capital_, "For Capital, transferBack is not allowed, if you transfer Capital by mistake, sorry");

        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
    }

    function setProfitFee(uint256 _profitFee) onlyOwner external {
        profitFee = _profitFee;
    }

    function setRouterAddress(address _swapRouter) onlyOwner external {
        swapRouter = _swapRouter;
    }


    function capital() public override view returns (address){
        return address(capital_);
    }

    function vault() public override view returns (address){
        return address(vault_);
    }

}
