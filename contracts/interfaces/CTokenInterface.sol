// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./ICTokenFlashLoan.sol";

interface CTokenInterface is ICTokenFlashLoan {
    function getAccountSnapshot(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        );

    function underlying() external returns (address);

    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    /// @notice msg.sender : The account which shall repay the borrow.
    /// @param borrower : The account which borrowed the asset to be repaid.
    /// @param repayAmount : The amount of the underlying borrowed asset to be repaid.
    /// A value of -1 (i.e. 2256 - 1) can be used to repay the full amount.
    /// @return  0 on success, otherwise an Error code
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);
}
