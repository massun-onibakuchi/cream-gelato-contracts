// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./gelato/PokeMe.sol";

import "./CreamLoanSaver.sol";

contract CreamLoanSaverService is CreamLoanSaver, Ownable {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    mapping(address => bool) public whiteListedTokens;

    constructor(
        address payable _pokeMe,
        address _cusdcAddress,
        address _gelato,
        IComptroller _comptroller,
        IUniswapV2Router02 _uniswapRouter,
        IPriceOracle _oracle
    ) CreamLoanSaver(_pokeMe, _cusdcAddress, _gelato, _comptroller, _uniswapRouter, _oracle) {}

    /// @notice submit loan protection to PokeMe
    /// To work protection, caller needs to approve this contract using Collateral crToken beforehand
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
        require(wantedHealthFactor >= thresholdHealthFactor, "health-factor-under-threshold");
        require(colToken != debtToken, "collateral-debt-same");
        require(whiteListedTokens[address(colToken)], "collateral-token-not-allowed");
        require(whiteListedTokens[address(debtToken)], "debt-token-not-allowed");

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

    function addTokenToWhiteList(CToken cToken) public onlyOwner {
        whiteListedTokens[address(cToken)] = true;
    }

    function removeTokenFromWhiteList(CToken cToken) public onlyOwner {
        delete whiteListedTokens[address(cToken)];
    }
}
