// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../vaults/IVault.sol";


interface IStrategy {

    function capital() external view returns (address);

    function capitalBalance() external view returns (uint256);

    function vault() external view returns (address);

    function invest() external;

    function circulate() external;

    function withdrawToVault(uint256) external;

    function withdrawAllToVault() external;

    function getCapitalPrice() external view returns(uint256 price18);

    function getPoolRewardApy() external view returns (uint256 apy100);
}
