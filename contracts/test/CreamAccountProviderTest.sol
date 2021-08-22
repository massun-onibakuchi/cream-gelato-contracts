// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../CreamAccountDataProvider.sol";
import "../interfaces/IPriceOracle.sol";
import { CTokenInterface as CToken } from "../interfaces/CTokenInterface.sol";

contract CreamAccountDataProviderTest is CreamAccountDataProvider {
    IPriceOracle public immutable oracle;
    address public immutable CUSDC_ADDRESS;

    constructor(
        address _cusdcAddress,
        IComptroller _comptroller,
        IPriceOracle _oracle
    ) CreamAccountDataProvider(_comptroller) {
        oracle = _oracle;
        CUSDC_ADDRESS = _cusdcAddress;
    }

    function calculateHealthFactor(uint256 totalCollateral, uint256 totalBorrow) public pure returns (uint256 price) {
        return _calculateHealthFactor(totalCollateral, totalBorrow);
    }

    function getUnderlyingPrice(CToken cToken) public view returns (uint256 price) {
        return _getUnderlyingPrice(cToken);
    }

    function getUsdcEthPrice() public view returns (uint256 price) {
        return _getUsdcEthPrice();
    }

    function _getUnderlyingPrice(CToken cToken) internal view override returns (uint256 price) {
        return oracle.getUnderlyingPrice(cToken);
    }

    function _getUsdcEthPrice() internal view override returns (uint256 price) {
        return oracle.getUnderlyingPrice(CToken(CUSDC_ADDRESS)) / 1e12;
    }

    function isUnderThresholdHealthFactor(address account) external view override returns (bool) {}
}
