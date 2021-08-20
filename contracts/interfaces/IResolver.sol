// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IResolver {
    function checker() external view returns (bool canExec, bytes memory execPayload);
}
