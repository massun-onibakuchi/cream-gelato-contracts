// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import { CTokenInterface as CToken } from "../interfaces/CTokenInterface.sol";
import "../interfaces/IPriceOracle.sol";

contract PriceOracleMock is IPriceOracle {
    mapping(CToken => uint256) private tokenPrices;

    function getUnderlyingPrice(CToken cToken) external view override returns (uint256) {
        return tokenPrices[cToken];
    }

    function setPrice(CToken cToken, uint256 price) public {
        tokenPrices[cToken] = price;
    }
}
