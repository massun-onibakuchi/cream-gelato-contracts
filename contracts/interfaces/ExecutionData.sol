// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

struct ExecutionData {
    address user;
    address action;
    uint256 subBlockNumber;
    bytes data;
    bytes offChainData;
    bool isPermanent;
}
