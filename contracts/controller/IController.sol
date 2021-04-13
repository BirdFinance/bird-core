// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IController {

    function feeManager() external view returns (address);

    function check(address _target) external view returns (bool);
}
