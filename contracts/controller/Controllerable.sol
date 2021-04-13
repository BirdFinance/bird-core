// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./IController.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Controllerable is Ownable {
    IController public controller;

    constructor(IController _controller)public{
        controller = IController(_controller);
    }

    function setController(IController _controller) public onlyOwner {
        controller = _controller;
    }
}
