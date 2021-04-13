// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../strategy/IStrategy.sol";

interface IVault is IERC20 {
    function capital() external view returns (address);

    function strategy() external view returns (address);

    function stake(uint256) external;

    function exit() external;

    function withdraw(uint256) external;

    function getPricePerFullShare() external view returns (uint256 price18);

    function setStrategy(IStrategy) external;

    function getCapitalPriceAndValue() external view returns (uint256 capitalPrice18, uint256 capitalValue,uint256 bTokenPrice18);
}
