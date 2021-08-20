// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IAction {
    function exec(
        bytes32 _taskHash,
        bytes memory _data,
        bytes memory _offChainData
    ) external;
}
