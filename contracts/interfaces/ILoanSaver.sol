// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

interface ILoanSaver {
    function saveLoan(address account, bytes32 protectionId) external;

    function isUnderThresholdHealthFactor(address account) external view returns (bool);

    function getUserProtectionAt(address account, uint256 index) external view returns (bytes32 protectionId);
}
