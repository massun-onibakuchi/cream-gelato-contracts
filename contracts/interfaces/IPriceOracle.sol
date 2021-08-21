// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;
import { CTokenInterface as CToken } from "./CTokenInterface.sol";

interface IPriceOracle {
    /**
     * @notice Get the underlying price of a listed cToken asset
     *  Zero means the price is unavailable.
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     */
    function getUnderlyingPrice(CToken cToken) external view returns (uint256);
}
