// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/ILoanSaver.sol";

contract LoanSaverResolver {
    ILoanSaver public immutable loanSaver;

    constructor(ILoanSaver _loanSaver) {
        loanSaver = _loanSaver;
    }

    /// @notice ref `Gelato PokeMe` for more detail
    /// @dev called off-chain
    /// @param user registered user
    /// @param index protectionId, optional integer
    function checker(address user, uint256 index) external view returns (bool canExec, bytes memory execPayload) {
        bool underThreshold = loanSaver.isUnderThresholdHealthFactor(user);
        if (underThreshold) {
            canExec = true;
            bytes32 protectionId = loanSaver.getUserProtectionAt(user, index);
            execPayload = abi.encodeWithSelector(ILoanSaver.saveLoan.selector, user, protectionId);
        }
    }
}
