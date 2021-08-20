// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./gelato/PokeMeReady.sol";

import "./interfaces/ILoanSaver.sol";
import "./interfaces/IFlashloanReceiver.sol";
import "./interfaces/IPriceOracle.sol";
import { CTokenInterface as CToken } from "./interfaces/CTokenInterface.sol";

import "./CreamAccountDataProvider.sol";

contract CreamLoanSaver is PokeMeReady, CreamAccountDataProvider, ILoanSaver, IFlashloanReceiver {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct ProtectionData {
        uint256 thresholdHealthFactor;
        uint256 wantedHealthFactor;
        cToken colToken;
        IERC20 debtToken;
    }

    struct FlashLoanData {
        ProtectionData protectionData;
        bytes swapData;
    }

    uint256 public constant FLASH_FEE_BIPS = 3;
    address public constant CUSDC_ADDRESS = 0x0;

    // ISwapModule public immutable swapModule;
    IUniswapV2Router public immutable uniswapRouter;
    IPriceOracle public immutable oracle;

    mapping(address => EnumerableSet.Bytes32Set) internal _createdProtections;
    mapping(bytes32 => ProtectionData) internal _protectionData;

    constructor(address _pokeMe, IComptroller _comptroller)
        PokeMeReady(_pokeMe)
        CreamAccountDataProvider(_comptroller)
    {}

    function saveLoan(address account, bytes32 protectionId) external onlyPokeMe {
        // check
        require(_createdProtections[msg.sender].contains(protectionId), "protection-not-found");

        // effect
        ProtectionData memory protectionData_ = _protectionData[protectionId];
        _createdProtections[account].remove(protectionId);
        delete _protectionData[protectionId];

        (uint256 totalCollateralInEth, uint256 totalBorrowInEth, uint256 healthFactor, ) = _getUserAccountData(account);
        // check if healthFactor is under threshold
        if (healthFactor > protectionData_.thresholdHealthFactor) revert("health-factor-is-not-under-threshold");

        // Calculate repay amount and debtToken amount to flash borrow
        uint256 flashFee = 0;
        uint256 borrowColAmt = _calculateBorrowColAmt(
            protectionData_.colToken,
            wantedHealthFactor,
            healthFactor,
            flashFee,
            totalBorrowInEth
        );
        bytes swapData = abi.encode(
            protectionData_.colToken.underlying(),
            protectionData_.debtToken.underlying(),
            borrowColAmt
        );

        _flashLoan(
            protectionData_.colToken,
            address(this),
            borrowColAmt,
            abi.encode(
                address(protectionData_.colToken),
                FlashLoanData({ protectionData: protectionData_, swapData: swapData })
            )
        );

        // Check user's position is safe
    }

    function _calculateBorrowColAmt(
        cToken cToken,
        uint256 targetHf,
        uint256 currentHf,
        uint256 flashFee,
        uint256 debtAmount
    ) internal view returns (uint256 borrowColAmt) {
        borrowColAmtInEth = ((wantedHealthFactor - currentHf) * debtAmount) / (wantedHealthFactor - flashFee);
        uint256 weiPerAsset = oracle.getUnderlyingPrice(cToken);
        borrowColAmt = (borrowColAmtInEth * EXP_SCALE) / weiPerAsset;
    }

    function _swap(
        address tokenToSell,
        address tokenToBuy,
        uint256 amountToSell
    ) internal {
        address[] memory path = new address[](3);
        path[0] = tokenToSell;
        path[1] = uniswapRouter.WETH();
        path[2] = tokenToBuy;

        uniswapRouter.swapExactTokensForTokens(amountToSell, 1, path, address(this), block.timestamp + (15 * 60));
    }

    function _getUnderlyingPrice(CToken cToken) internal view override returns (uint256 price) {
        price = oracle.getUnderlyingPrice(cToken);
    }

    // the usdc price in wei
    // e.g Eth $3000, this method returns `1e18 * 1 / 3000`
    function _getUsdcEthPrice() internal view override returns (uint256 price) {
        price = oracle.getUnderlyingPrice(CUSDC_ADDRESS) / 1e12;
    }

    function getUserProtectionAt(address account, uint256 index) external view returns (bytes32 protectionId) {
        return _createdProtections[account].at(index);
    }

    /// @param receiver : The Flash Loan contract address you deployed.
    /// @param amount : Keep in mind that the decimal of amount is dependent on crToken's underlying asset.
    /// @param params : encoded parameter for executeOperation().
    /// If no parameters are needed in your Flash Loan contract, use an empty value "".
    /// If you would like to pass parameters into your flash loan, you will need to encode it.
    function _flashLoan(
        ICTokenFlashLoan flashLender,
        address receiver,
        uint256 amount,
        bytes calldata params
    ) internal {
        flashLender.flashLoan(receiver, amount, params);
    }

    // -- excuteOperation
    // swap col for debtToken
    // repay debt
    // withdraw col
    // flashPayBack col
    function _excuteOperation(FlashLoanData memory flashLoanData) internal {
        (ProtectionData memory protectionData, bytes swapData) = abi.decode((ProtectionData, bytes), flashLoanData);
        // tokenToSell = collateral uToken, tokenToBuy = debt uToken
        (address tokenToSell, address tokenToBuy, uint256 amountToSell) = abi.decode(
            (address, address, uint256),
            swapData
        );

        // flashLoan logic
        SafeERC20.safeApprove(tokenToSell, address(uniswapRouter), amountToSell);
        _swap(tokenToSell, tokenToBuy, amountToSell);
        uint256 debtBalance = IERC20(cToken.underlying()).balanceOf(address(this));

        _paybackToCToken(protectionData.debtToken, debtBalance);

        _withdrawCollateral(protectionData.colToken, amountToWithdraw, address(this));

        // transfer fund + fee back to cToken
        require(IERC20(underlying).transfer(cToken, amount + fee), "Transfer fund back failed");
    }

    function _paybackToCToken(
        cToken debtToken,
        address asset,
        uint256 debtToRepay
    ) internal {
        // Approves 0 first to comply with tokens that implement the anti frontrunning approval fix
        SafeERC20.safeApprove(asset, address(debtToken), 0);
        SafeERC20.safeApprove(asset, address(debtToken), debtToRepay);
        debtToken.repay(asset, debtToRepay, _onBehalf);
    }

    function _withdrawCollateral(cToken colToken, uint256 amountToWithdraw) internal {}

    // flashLoan callback function
    function excuteOperation(
        address sender,
        address underlying,
        uint256 amount,
        uint256 fee,
        bytes memory params
    ) external {
        (address flashLender, FlashLoanData memory flashLoanData) = abi.decode((address, FlashLoanData), params);
        require(msg.sender == flashLender, "flashloan-callback-only-cToken");
        _excuteOperation(sender, underlying, amount, flashLoanData);
    }

    function _transferFees(address _asset, uint256 _amount) {
        SafeERC20.safeTransfer(IERC20(_asset), GELATO, _amount);
    }

    // gas intensive
    function isUnderThresholdHealthFactor(uint256 account) external view override returns (bool) {
        bytes32 id;
        uint256 length = _createdProtections[account].length();
        (, , uint256 currentHealthFactor, ) = _getUserAccountData(account);

        for (uint256 i = 0; i < length; i++) {
            id = _createdProtections[account].at(i);
            uint256 threshold = _protectionData[id].thresholdHealthFactor;
            if (threshold >= currentHealthFactor) {
                return true;
            }
        }

        return false;
    }
}
