// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../CreamLoanSaver.sol";

contract CreamLoanSaverTest is CreamLoanSaver {
    constructor(
        address payable _pokeMe,
        address _cusdcAddress,
        address _gelato,
        IComptroller _comptroller,
        IUniswapV2Router02 _uniswapRouter,
        IPriceOracle _oracle
    ) CreamLoanSaver(_pokeMe, _cusdcAddress, _gelato, _comptroller, _uniswapRouter, _oracle) {}
}
