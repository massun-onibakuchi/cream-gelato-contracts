// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IComptroller.sol";
import { CTokenInterface as CToken } from "./interfaces/CTokenInterface.sol";

abstract contract CreamAccountDataProvider {
    uint256 public constant EXP_SCALE = 1e18;
    IComptroller public immutable comptroller;

    constructor(IComptroller _comptroller) {
        comptroller = _comptroller;
    }

    function _getUserAccountData(address account)
        internal
        view
        returns (
            uint256 totalCollateralInEth,
            uint256 totalBorrowInEth,
            uint256 healthFactor,
            uint256 weiPerUsdc
        )
    {
        (, uint256 totalCollateral, ) = comptroller.getAccountLiquidity(account);
        address[] memory assets = comptroller.getAssetsIn(account);
        weiPerUsdc = _getUsdcEthPrice();

        {
            CToken cToken;
            uint256 borrowAmt;
            uint256 length = assets.length;
            for (uint256 i = 0; i < length; i++) {
                cToken = CToken(assets[i]);
                borrowAmt = cToken.borrowBalanceStored(account);
                if (borrowAmt > 0) {
                    uint256 weiPerAsset = _getUnderlyingPrice(cToken);
                    totalBorrowInEth += (borrowAmt * weiPerAsset) / EXP_SCALE; // usdAmount * weiPerUsdc
                }
            }
        }

        totalCollateralInEth = (totalCollateral * weiPerUsdc) / EXP_SCALE; // usd * weiPerUsdc
        healthFactor = _calculateHealthFactor(totalCollateralInEth, totalBorrowInEth);
    }

    // the usdc price in wei
    // e.g Eth $3000, this method returns `1e18 * 1 / 3000`
    function _getUnderlyingPrice(CToken cToken) internal view virtual returns (uint256 price);

    // the usdc price in wei
    // e.g Eth $3000, this method returns `1e18 * 1 / 3000`
    function _getUsdcEthPrice() internal view virtual returns (uint256 price);

    function _calculateHealthFactor(uint256 totalCollateral, uint256 totalBorrow)
        internal
        view
        returns (uint256 healthFactor)
    {
        healthFactor = (totalCollateral * EXP_SCALE) / totalBorrow;
    }

    function _isUnderThresholdHealthFactor(address account, uint256 threshold) internal view returns (bool) {
        (, , uint256 currentHealthFactor, ) = _getUserAccountData(account);
        return threshold >= currentHealthFactor;
    }

    function isUnderThresholdHealthFactor(address account, uint256 threshold) internal view virtual returns (bool);
}
