// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../CreamLoanSaverService.sol";

contract CreamLoanSaverServiceTest is CreamLoanSaverService {
    constructor(
        address payable _pokeMe,
        address _cusdcAddress,
        address _gelato,
        IComptroller _comptroller,
        IUniswapV2Router02 _uniswapRouter,
        IPriceOracle _oracle
    ) CreamLoanSaverService(_pokeMe, _cusdcAddress, _gelato, _comptroller, _uniswapRouter, _oracle) {}

    function calculateColAmtToBorrow(ProtectionDataCompute memory _protectionDataCompute)
        public
        pure
        returns (uint256)
    {
        return _calculateColAmtToBorrow(_protectionDataCompute);
    }

    function swap(
        address tokenToSell,
        address tokenToBuy,
        uint256 amountToSell
    ) public {
        _swap(tokenToSell, tokenToBuy, amountToSell);
    }

    function getUnderlyingPrice(CToken cToken) public view returns (uint256 price) {
        return _getUnderlyingPrice(cToken);
    }
}