// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

interface IFlashloanReceiver {
    function executeOperation(
        address sender,
        address underlying,
        uint256 amount,
        uint256 fee,
        bytes calldata params
    ) external;
}

interface ICTokenFlashloan {
    function flashLoan(
        address receiver,
        uint256 amount,
        bytes calldata params
    ) external;
}
