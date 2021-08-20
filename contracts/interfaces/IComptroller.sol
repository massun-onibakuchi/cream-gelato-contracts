// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

interface IComptroller {
    /// @param account: The account whose list of entered markets shall be queried.
    /// @return address[] : The address of each market which is currently entered into.
    function getAssetsIn(address account) external view returns (address[] memory);

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
}
