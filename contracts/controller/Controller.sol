// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "../strategy/IStrategy.sol";
import "../vaults/IVault.sol";
import "./IController.sol";

contract Controller is IController, Ownable {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public swapRouter;
    mapping(IVault => bool) public vaults;
    mapping(address => bool) public allowanceList;

    address public feeManager_;

    constructor(address _feeManager) public {
        feeManager_ = _feeManager;
    }


    //添加vault和对应的策略
    function addVaultAndStrategy(IVault vault, IStrategy strategy) onlyOwner external {
        require(address(vault) != address(0), "new vault shouldn't be empty");
        require(!vaults[vault], "vault already exists");
        require(address(strategy) != address(0), "new strategy shouldn't be empty");
        require(vault.capital() == strategy.capital(), "capital does not match");

        vaults[vault] = true;
        vault.setStrategy(strategy);
    }

    function changeVaultAndStrategy(IVault vault, IStrategy strategy) onlyOwner external {
        require(address(vault) != address(0), "new vault shouldn't be empty");
        require(vaults[vault], "vault does not exists");
        require(address(strategy) != address(0), "new strategy shouldn't be empty");
        require(vault.capital() == strategy.capital(), "capital does not match");

        vault.setStrategy(strategy);
    }

    function setSwapRouter(address _address) onlyOwner public {
        swapRouter = _address;
    }


    function setFeeManager(address _feeManager) onlyOwner public {
        feeManager_ = _feeManager;
    }


    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
    }

    //因为可以把一些合约的地址给ban掉
    //Do not ban access to the user, need to be in the whitelist contract address to be able to access
    function check(address _target) external override view returns (bool) {
        if (isContract(_target)) {
            return allowanceList[_target];
        }
        return true;
    }


    //将一个vault里,正在策略中操作的所有资金退回到vault中
    function withdrawAllToVault(address _vault) onlyOwner public {
        IStrategy(IVault(_vault).strategy()).withdrawAllToVault();
    }


    function withdrawToVault(address _vault, uint256 _amount) onlyOwner public {
        IStrategy(IVault(_vault).strategy()).withdrawToVault(_amount);
    }

    function capital(address vault) external view returns (address){
        return IVault(vault).capital();
    }

    //触发某个vault的复投
    function circulate(address _vault) onlyOwner external {
        IStrategy(IVault(_vault).strategy()).circulate();
    }

    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {codehash := extcodehash(account)}
        return (codehash != 0x0 && codehash != accountHash);
    }

    function setAllowanceList(address target, bool allowance) onlyOwner external {
        allowanceList[target] = allowance;
    }

    function feeManager() external view override returns (address){
        return feeManager_;
    }

}
