// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IResolver.sol";
import "./interfaces/ILoanSaver.sol";

contract LoanSaverResolver {
    ILoanSaver public loanSaver;

    constructor(ILoanSaver _loanSaver) public {
        loanSaver = _loanSaver;
    }

    function checker(address user, uint256 optionalIndex)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        bool underThreshold = loanSaver.isUnderThresholdHealthFactor(user);
        if (underThreshold) {
            canExec = true;
            bytes32 protectionId = loanSaver.getUserProtectionAt(account, optionalIndex);
            execPayload = abi.encodeWithSelector(ILoanSaver.saveLoan.selector, user, protectionId);
        }
    }
}
