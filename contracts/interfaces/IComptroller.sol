// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import { CTokenInterface as CToken } from "./CTokenInterface.sol";

interface IComptroller {
    /// @param account: The account whose list of entered markets shall be queried.
    /// @return cToken[] : The address of each market which is currently entered into.
    function getAssetsIn(address account) external view returns (CToken[] memory);

    /// @dev Account Liquidity represents the USD value borrowable by a user,
    ///      before it reaches liquidation. Users with a shortfall (negative liquidity
    ///      ) are subject to liquidation, and can’t withdraw or borrow assets until Account Liquidity is positive again.
    ///      For each market the user has entered into, their supplied balance is
    ///      multiplied by the market’s collateral factor, and summed; borrow balances are then subtracted,
    ///      to equal Account Liquidity.
    ///      Borrowing an asset reduces Account Liquidity for each USD borrowed;
    ///      withdrawing an asset reduces Account Liquidity by the asset’s collateral factor times each USD withdrawn.
    ///      Tuple of values (error, liquidity, shortfall). The error shall be 0 on success, otherwise an error code. A non-zero liquidity value indicates the account has available account liquidity. A non-zero shortfall value indicates the account is currently below his/her collateral requirement and is subject to liquidation. At most one of liquidity or shortfall shall be non-zero.
    /// @param account: The account whose liquidity shall be calculated.
    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256 error,
            uint256 liquidity,
            uint256 shortfall
        );

    /// @param cTokenAddress The address of the cToken to check if listed and get the collateral factor for.
    /// @return `isListed` represents whether the comptroller recognizes this cToken;
    /// @return `collateralFactorMantissa`, scaled by 1e18, is multiplied by a supply balance to determine how much value can be borrowed.
    /// @return `isComped` boolean indicates whether or not suppliers and borrowers are distributed COMP tokens.
    function markets(address cTokenAddress)
        external
        view
        returns (
            bool,
            uint256,
            bool
        );
}
