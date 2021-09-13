// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./ICTokenFlashLoan.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface CTokenInterface is ICTokenFlashLoan, IERC20 {
    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (possible error, token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function underlying() external view returns (address);

    function balanceOfUnderlying(address account) external view returns (uint256);

    // function mint(uint256 mintAmount) external returns (uint256);

    // function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    // function repayBorrow(uint256 repayAmount) external returns (uint256);

    /// @notice msg.sender : The account which shall repay the borrow.
    /// @param borrower : The account which borrowed the asset to be repaid.
    /// @param repayAmount : The amount of the underlying borrowed asset to be repaid.
    /// A value of -1 (i.e. 2256 - 1) can be used to repay the full amount.
    /// @return  0 on success, otherwise an Error code
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

    // function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    // function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function borrowRatePerBlock() external view returns (uint256);

    function supplyRatePerBlock() external view returns (uint256);
}
