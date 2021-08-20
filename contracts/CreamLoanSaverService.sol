// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./gelato/PokeMe.sol";

import "./CreamLoanSaver.sol";

contract CreamLoanSaverService is CreamLoanSaver {
    constructor(address _pokeMe) CreamLoanSaver(_pokeMe) {}

    function submitProtection(
        uint256 thresholdHealthFactor,
        uint256 wantedHealthFactor,
        cToken colToken,
        address debtToken,
        address _resolverAddress,
        bytes calldata _resolverData,
        bool _useTaskTreasuryFunds
    ) public {
        bytes23 protectionId = keccak256(
            abi.encodePacked(thresholdHealthFactor, wantedHealthFactor, colToken, debtToken, _resolverData)
        );

        require(_createdProtections[msg.sender].contains(protectionId) == false, "already started task");

        _createdProtections[msg.sender].add(protectionId);
        _protectionData[protectionId] = ProtectionData({
            thresholdHealthFactor: thresholdHealthFactor,
            wantedHealthFactor: wantedHealthFactor,
            colToken: colToken,
            debtToken: debtToken
        });

        PokeMe(pokeMe).createTask(
            address(this),
            this.saveLoan.selector,
            _resolverAddress,
            _resolverData,
            _useTaskTreasuryFunds
        );
    }
}
