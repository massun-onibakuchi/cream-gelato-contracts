// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/IComptroller.sol";
import { CTokenInterface as CToken } from "../interfaces/CTokenInterface.sol";

contract ComptrollerMock is IComptroller {
    struct Market {
        bool isListed;
        uint256 collateralFactorMantissa;
        mapping(address => bool) accountMembership;
        bool isComped;
    }

    /**
     * @notice Official mapping of cTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public override markets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => CToken[]) public accountAssets;

    /**
     * @dev test purpose
     */
    mapping(address => uint256) public accountsLiquidity;

    constructor(address[] memory _assets) {
        uint256 length = _assets.length;
        for (uint256 i = 0; i < length; i++) {
            markets[_assets[i]].isListed = true;
            markets[_assets[i]].collateralFactorMantissa = 9 * 1e17;
        }
    }

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) public view override returns (CToken[] memory) {
        CToken[] memory assetsIn = accountAssets[account];
        return assetsIn;
    }

    function setAssetsIn(address account, CToken[] memory assets) public {
        uint256 length = assets.length;
        CToken[] storage assetsIn = accountAssets[account];
        for (uint256 i = 0; i < length; i++) {
            assetsIn.push(assets[i]);
        }
    }

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
        public
        view
        override
        returns (
            uint256 error,
            uint256 liquidity,
            uint256 shortfall
        )
    {
        // uint256 totalCollateral;
        // uint256 totalDebt;
        // CToken asset;
        // CToken[] memory assetsIn = getAssetsIn(account);
        // uint256 length = assetsIn.length;
        // for (uint256 i = 0; i < length; i++) {
        //     asset = assetsIn[i];
        //     uint256 colFactor = markets[address(asset)].collateralFactorMantissa;
        //     totalCollateral += asset.balanceOfUnderlying(account) * colFactor * price;
        //     totalDebt += asset.borrowBalanceStored(account);
        // }
        // liquidity = totalCollateral - totalDebt;
        return (0, accountsLiquidity[account], 0);
    }

    function setAccountLiquidity(address account, uint256 liquidity) public {
        accountsLiquidity[account] = liquidity;
    }
}
