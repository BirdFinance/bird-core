// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../controller/Controllerable.sol";
import "../strategy/IStrategy.sol";
import "./IVault.sol";

abstract contract Vault is IVault, ERC20, ReentrancyGuard, Controllerable {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant baseDecimal = 1e18;

    uint256 public feeNumerator = 0;
    uint256 constant MILLION = 10 ** 6;

    uint256 public borrowNumerator = 5;
    uint256 constant PERCENT = 100;

    IERC20 internal capital_;
    IStrategy internal strategy_;

    //you have to deploy Controller first
    constructor (IERC20 _capital, IController _controller) public
    ERC20(
        string(abi.encodePacked("bird", ERC20(address(_capital)).name())),
        string(abi.encodePacked("b", ERC20(address(_capital)).symbol()))
    )
    Controllerable(_controller){
        capital_ = _capital;
        controller = _controller;
    }

    modifier restricted(){
        require(msg.sender == address(controller) || msg.sender == owner(),
            "msg.sender == address(controller) || msg.sender == owner()");
        _;
    }

    function capitalBalance() public view returns (uint256) {
        return idleCapital().add(IStrategy(strategy_).capitalBalance());
    }


    function available() public view returns (uint256) {
        uint256 idle = idleCapital();
        uint256 toRetain = capitalBalance().mul(borrowNumerator).div(PERCENT);
        if (idle > toRetain) {
            return idle.sub(toRetain);
        }
        return 0;
    }

    function earn() public {
        require(controller.check(msg.sender), "address is ban");
        uint256 availableCapital = available();
        if (availableCapital > 0) {
            capital_.safeTransfer(address(strategy_), availableCapital);
        }
        strategy_.circulate();
    }

    function stakeAll() external {
        stake(capital_.balanceOf(msg.sender));
    }

    function stake(uint256 _amount) public nonReentrant override {
        require(IController(controller).check(msg.sender), "address is ban");
        require(_amount > 0, "amount must greater than 0");
        uint256 investedCapital = capitalBalance();

        uint256 _before = idleCapital();
        doTransferIn(msg.sender, _amount);
        uint256 _after = idleCapital();
        _amount = _after.sub(_before);

        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(investedCapital);
        }
        _mint(msg.sender, shares);

        //immediately do a circulation
        earn();
    }

    function exit() external override {
        withdraw(balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public nonReentrant override {
        //do a compound
        strategy_.circulate();

        uint256 amount = (capitalBalance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        uint256 idle = idleCapital();
        if (idle < amount) {
            //not enough idle capital tokens
            uint256 diff = amount.sub(idle);
            //withdraw the gap from strategy
            IStrategy(strategy_).withdrawToVault(diff);
            uint256 newIdle = idleCapital();
            if (newIdle.sub(idle) < diff) {//still not enough
                amount = newIdle;
            }
        }
        //get fee from withdrawn capital
        uint256 fee = amount.mul(feeNumerator).div(MILLION);
        //charge fee?
        if (fee > 0) {
            capital_.safeTransfer(controller.feeManager(), fee);
        }
        //refund
        doTransferOut(msg.sender, amount.sub(fee));
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        require(erc20Token != capital_, "For Capital, transferBack is not allowed, if you transfer LPT by mistake, sorry");

        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
    }

    //called from controller, or owner
    function setStrategy(IStrategy _newStrategy) external override restricted {
        require(address(_newStrategy) != address(0), "new _strategy cannot be empty");
        require(
            _newStrategy.capital() == address(capital_),
            "Vault underlying must match Strategy underlying"
        );

        if (_newStrategy != strategy_) {
            if (address(strategy_) != address(0)) {
                // at begin, the strategy is undefined intermediately after constructor
                capital_.safeApprove(address(strategy_), 0);
                //have to withdraw all funds in strategy and pool back to vault
                strategy_.withdrawAllToVault();
            }
            strategy_ = _newStrategy;
            capital_.safeApprove(address(strategy_), 0);
            capital_.safeApprove(address(strategy_), uint256(~0));
        }
    }


    function setFee(uint256 _feeNumerator) external onlyOwner {
        feeNumerator = _feeNumerator;
    }

    function setBorrowNumerator(uint256 _borrowNumerator) external onlyOwner {
        borrowNumerator = _borrowNumerator;
    }

    function capital() external override view returns (address){
        return address(capital_);
    }

    function strategy() external override view returns (address){
        return address(strategy_);
    }

    function getPricePerFullShare() public override view returns (uint256 price18) {
        price18 = capitalBalance().mul(baseDecimal).div(totalSupply());
    }

    function getCapitalPriceAndValue() override external view returns (uint256 capitalPrice18, uint256 capitalValue, uint256 bTokenPrice18){
        capitalPrice18 = strategy_.getCapitalPrice();
        uint256 capitalBal = capitalBalance();
        capitalValue = capitalBal.mul(capitalPrice18).div(baseDecimal);
        if(totalSupply()==0){
            bTokenPrice18 = 0;
        }else{
            bTokenPrice18 = capitalPrice18.mul(capitalBal).div(totalSupply());

        }
    }

    function idleCapital() public virtual view returns (uint256);

    function doTransferIn(address from, uint256 amount) internal virtual returns (uint256);

    function doTransferOut(address to, uint256 amount) internal virtual;
}
