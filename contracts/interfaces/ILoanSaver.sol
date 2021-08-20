// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface ILoanSaver {
    function saveLoan(
        address account,
        address cToken,
        address debtToken
    ) external;

    function pokeMe() external view returns (address _pokeMe);

    function isUnderThresholdHealthFactor(uint256 account) external view returns (bool);
}
