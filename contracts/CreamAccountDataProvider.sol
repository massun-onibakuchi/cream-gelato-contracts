// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IComptroller.sol";
import { CTokenInterface as CToken } from "./interfaces/CTokenInterface.sol";

/// @notice Cream Comptroller wrapper
/// @dev contract to get user position
abstract contract CreamAccountDataProvider {
    uint256 public constant EXP_SCALE = 1e18;
    IComptroller public immutable comptroller;

    constructor(IComptroller _comptroller) {
        comptroller = _comptroller;
    }

    function getUserReserveData(address asset, address account)
        public
        view
        returns (
            uint256 balanceUnderlying,
            uint256 debtUnderlying,
            uint256 exchangeRateStored,
            uint256 borrowRatePerBlock,
            uint256 supplyRatePerBlock
        )
    {
        CToken cToken = CToken(asset);
        balanceUnderlying = cToken.balanceOfUnderlying(account);
        debtUnderlying = cToken.borrowBalanceStored(account);
        exchangeRateStored = cToken.exchangeRateStored();
        borrowRatePerBlock = cToken.borrowRatePerBlock();
        supplyRatePerBlock = cToken.supplyRatePerBlock();
    }

    function getUserAccountData(address account)
        public
        view
        returns (
            uint256 totalCollateralInEth,
            uint256 totalBorrowInEth,
            uint256 healthFactor,
            uint256 ethPerUsd
        )
    {
        return _getUserAccountData(account);
    }

    /// @notice ref Compound and Aave Doc for more detail
    /// @dev get specified user's position
    /// @param account cream account
    function _getUserAccountData(address account)
        internal
        view
        returns (
            uint256 totalCollateralInEth,
            uint256 totalBorrowInEth,
            uint256 healthFactor,
            uint256 ethPerUsd
        )
    {
        (, uint256 liquidity, ) = comptroller.getAccountLiquidity(account);
        CToken[] memory assets = comptroller.getAssetsIn(account);
        ethPerUsd = _getUsdcEthPrice();

        {
            // calculate account total borrow amount
            uint256 length = assets.length;
            for (uint256 i = 0; i < length; i++) {
                uint256 borrowBalance = assets[i].borrowBalanceStored(account);
                if (borrowBalance > 0) {
                    uint256 ethPerAsset = _getUnderlyingPrice(assets[i]);
                    totalBorrowInEth += (borrowBalance * ethPerAsset) / EXP_SCALE; // usdAmount * ethPerUsd
                }
            }
        }

        totalCollateralInEth = totalBorrowInEth + (liquidity * ethPerUsd) / EXP_SCALE; // usd * ethPerUsd
        healthFactor = _calculateHealthFactor(totalCollateralInEth, totalBorrowInEth);
    }

    function _calculateHealthFactor(uint256 totalCollateral, uint256 totalBorrow)
        internal
        pure
        returns (uint256 healthFactor)
    {
        if (totalBorrow == 0) return 0;
        healthFactor = (totalCollateral * EXP_SCALE) / totalBorrow;
    }

    function _isUnderThresholdHealthFactor(address account, uint256 threshold) internal view returns (bool) {
        (, , uint256 currentHealthFactor, ) = _getUserAccountData(account);
        return threshold >= currentHealthFactor;
    }

    // -------------- abstract function --------------

    /// @return price ethPerAsset
    function _getUnderlyingPrice(CToken cToken) internal view virtual returns (uint256 price);

    /// @return price weiPerUSDC USDC/ETH if ETH=$3000, return 1e18 * 1 / 3000
    function _getUsdcEthPrice() internal view virtual returns (uint256 price);

    function isUnderThresholdHealthFactor(address account) external view virtual returns (bool);
}
