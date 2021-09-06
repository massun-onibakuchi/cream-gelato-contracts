// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./CTokenMock.sol";
import "hardhat/console.sol";

contract CusdCoin is CTokenMock {
    constructor(
        string memory _name,
        string memory _symbol,
        address _uToken,
        address interestRateModel
    ) CTokenMock(_name, _symbol, _uToken, interestRateModel) {}
}
