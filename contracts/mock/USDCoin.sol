// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ERC20Mock.sol";

contract USDCoin is ERC20Mock {
    constructor(string memory _name, string memory _symbol) ERC20Mock(_name, _symbol) {}
}
