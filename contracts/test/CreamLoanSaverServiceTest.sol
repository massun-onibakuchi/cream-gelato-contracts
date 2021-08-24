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
        view
        returns (uint256)
    {
        return _calculateColAmtToBorrow(_protectionDataCompute);
    }

    function flashLoan(
        ICTokenFlashLoan flashLender,
        address receiver,
        uint256 amount,
        FlashLoanData memory flashLoanData
    ) public {
        _flashLoan(flashLender, receiver, amount, flashLoanData);
    }

    function swap(
        address tokenToSell,
        address tokenToBuy,
        uint256 amountToSell
    ) public {
        _swap(tokenToSell, tokenToBuy, amountToSell);
    }

    function paybackToCToken(
        CToken debtToken,
        IERC20 uDebtToken,
        address borrower,
        uint256 debtToRepay
    ) public {
        _paybackToCToken(debtToken, uDebtToken, borrower, debtToRepay);
    }

    function withdrawCollateral(
        CToken colToken,
        address onBehalf,
        address to,
        uint256 amountToWithdraw
    ) public {
        _withdrawCollateral(colToken, onBehalf, to, amountToWithdraw);
    }
}
