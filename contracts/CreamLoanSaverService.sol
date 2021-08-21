// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./gelato/PokeMe.sol";

import "./CreamLoanSaver.sol";

contract CreamLoanSaverService is CreamLoanSaver {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    constructor(
        address payable _pokeMe,
        address _cusdcAddress,
        address _gelato,
        IComptroller _comptroller,
        IUniswapV2Router02 _uniswapRouter,
        IPriceOracle _oracle
    ) CreamLoanSaver(_pokeMe, _cusdcAddress, _gelato, _comptroller, _uniswapRouter, _oracle) {}

    function submitProtection(
        uint256 thresholdHealthFactor,
        uint256 wantedHealthFactor,
        CToken colToken,
        CToken debtToken,
        address _resolverAddress,
        bytes calldata _resolverData,
        bool _useTaskTreasuryFunds
    ) public {
        bytes32 protectionId = keccak256(
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
