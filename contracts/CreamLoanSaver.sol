// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./gelato/PokeMeReady.sol";

import "./interfaces/ILoanSaver.sol";
import "./interfaces/IFlashloanReceiver.sol";
import "./interfaces/IPriceOracle.sol";
import { CTokenInterface as CToken, ICTokenFlashLoan } from "./interfaces/CTokenInterface.sol";

import "./CreamAccountDataProvider.sol";

contract CreamLoanSaver is PokeMeReady, CreamAccountDataProvider, ILoanSaver, IFlashloanReceiver {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct ProtectionData {
        uint256 thresholdHealthFactor;
        uint256 wantedHealthFactor;
        CToken colToken;
        CToken debtToken;
    }

    struct FlashLoanData {
        ProtectionData protectionData;
        address borrower;
        bytes swapData;
    }

    struct ProtectionDataCompute {
        CToken colToken;
        CToken debtToken;
        uint256 weiPerColToken;
        uint256 wantedHealthFactor;
        uint256 colFactor;
        uint256 totalCollateralInEth;
        uint256 totalBorrowInEth;
        uint256 protectionFeeBps;
        uint256 flashLoanFeeBps;
    }

    uint256 private constant TEN_THOUSAND_BPS = 1e4;
    uint256 public constant FLASH_FEE_BIPS = 3;

    IUniswapV2Router02 public immutable uniswapRouter;
    IPriceOracle public immutable oracle;
    address public immutable CUSDC_ADDRESS;
    address public immutable GELATO;

    uint256 public protectionFeeBps;

    mapping(address => EnumerableSet.Bytes32Set) internal _createdProtections;
    mapping(bytes32 => ProtectionData) internal _protectionData;

    constructor(
        address payable _pokeMe,
        address _cusdcAddress,
        address _gelato,
        IComptroller _comptroller,
        IUniswapV2Router02 _uniswapRouter,
        IPriceOracle _oracle
    ) PokeMeReady(_pokeMe) CreamAccountDataProvider(_comptroller) {
        CUSDC_ADDRESS = _cusdcAddress;
        GELATO = _gelato;
        uniswapRouter = _uniswapRouter;
        oracle = _oracle;
    }

    function saveLoan(address account, bytes32 protectionId) external override onlyPokeMe {
        // check
        require(_createdProtections[account].contains(protectionId), "protection-not-found");

        // effect
        ProtectionData memory protectionData_ = _protectionData[protectionId];
        _createdProtections[account].remove(protectionId);
        delete _protectionData[protectionId];

        (uint256 totalCollateralInEth, uint256 totalBorrowInEth, uint256 healthFactor, ) = _getUserAccountData(account);
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(protectionData_.colToken));
        // check if healthFactor is under threshold
        if (healthFactor > protectionData_.thresholdHealthFactor) revert("health-factor-is-not-under-threshold");

        // Calculate repay amount and debtToken amount to flash borrow
        uint256 borrowColAmt = _calculateBorrowColAmt(
            ProtectionDataCompute({
                colToken: protectionData_.colToken,
                debtToken: protectionData_.debtToken,
                weiPerColToken: _getUnderlyingPrice(protectionData_.colToken),
                wantedHealthFactor: protectionData_.wantedHealthFactor,
                colFactor: collateralFactorMantissa,
                totalCollateralInEth: totalCollateralInEth,
                totalBorrowInEth: totalBorrowInEth,
                protectionFeeBps: protectionFeeBps,
                flashLoanFeeBps: FLASH_FEE_BIPS
            })
        );
        bytes memory swapData = abi.encode(
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
                FlashLoanData({ protectionData: protectionData_, borrower: account, swapData: swapData })
            )
        );

        // Check user's position is safe
        (, , healthFactor, ) = _getUserAccountData(account);
        if (healthFactor <= protectionData_.thresholdHealthFactor) revert("health-factor-stay-unsafe");
    }

    function _calculateBorrowColAmt(ProtectionDataCompute memory _protectionDataCompute)
        internal
        pure
        returns (uint256 borrowColAmt)
    {
        uint256 borrowColAmtInEth = ((_protectionDataCompute.wantedHealthFactor *
            _protectionDataCompute.totalBorrowInEth) -
            (_protectionDataCompute.totalCollateralInEth * _protectionDataCompute.colFactor)) /
            (_protectionDataCompute.wantedHealthFactor -
                _protectionDataCompute.colFactor *
                (TEN_THOUSAND_BPS + _protectionDataCompute.flashLoanFeeBps + _protectionDataCompute.protectionFeeBps) *
                1e14);

        borrowColAmt = (borrowColAmtInEth * EXP_SCALE) / _protectionDataCompute.weiPerColToken;
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

    /// @param receiver : The Flash Loan contract address you deployed.
    /// @param amount : Keep in mind that the decimal of amount is dependent on crToken's underlying asset.
    /// @param params : encoded parameter for executeOperation().
    /// If no parameters are needed in your Flash Loan contract, use an empty value "".
    /// If you would like to pass parameters into your flash loan, you will need to encode it.
    function _flashLoan(
        ICTokenFlashLoan flashLender,
        address receiver,
        uint256 amount,
        bytes memory params
    ) internal {
        flashLender.flashLoan(receiver, amount, params);
    }

    /// @notice flashLoan callback function
    /// @dev only crToken call call this function
    /// @param sender msg.sender of flashLoan()
    /// @param underlying underlying token address of cToken
    /// @param amount flashborrow amount in underlying token
    /// @param premiums fee in underlying token
    /// @param params encoded parameter
    function executeOperation(
        address sender,
        address underlying,
        uint256 amount,
        uint256 premiums,
        bytes memory params
    ) external override {
        (address flashLender, FlashLoanData memory flashLoanData) = abi.decode(params, (address, FlashLoanData));
        require(msg.sender == flashLender, "flashloan-callback-only-cToken");
        _executeOperation(premiums, flashLoanData);
    }

    function _executeOperation(uint256 premiums, FlashLoanData memory flashLoanData) internal {
        ProtectionData memory protectionData = flashLoanData.protectionData;
        address onBehalf = flashLoanData.borrower;
        bytes memory swapData = flashLoanData.swapData;
        // uTokenToSell = collateral uToken, tokenToBuy = debt uToken
        (address uColToken, address uDebtToken, uint256 amtBorrowedToSell) = abi.decode(
            swapData,
            (address, address, uint256)
        );

        uint256 balanceBefore = IERC20(uDebtToken).balanceOf(address(this));

        SafeERC20.safeApprove(IERC20(uColToken), address(uniswapRouter), amtBorrowedToSell);
        _swap(uColToken, uDebtToken, amtBorrowedToSell);

        uint256 receivedDebtTokenAmt = IERC20(uDebtToken).balanceOf(address(this)) - balanceBefore;

        /// @notice payback debt to cToken
        _paybackToCToken(protectionData.debtToken, IERC20(uDebtToken), onBehalf, receivedDebtTokenAmt);

        uint256 fees = (amtBorrowedToSell * protectionFeeBps) / TEN_THOUSAND_BPS;
        uint256 amountToWithdraw = amtBorrowedToSell + fees + premiums;
        /// @notice Withdraw collateral (including fees) and flashloan premium.
        _withdrawCollateral(protectionData.colToken, onBehalf, address(this), amountToWithdraw);

        /// @notice transfer fees to Gelato
        SafeERC20.safeTransfer(IERC20(uColToken), GELATO, fees);
        /// @notice transfer flashborrow + premiums to cToken
        SafeERC20.safeTransfer(IERC20(uColToken), address(protectionData.colToken), amtBorrowedToSell + premiums);
    }

    function _paybackToCToken(
        CToken debtToken,
        IERC20 uDebtToken,
        address borrower,
        uint256 debtToRepay
    ) internal {
        // Approves 0 first to comply with tokens that implement the anti frontrunning approval fix
        SafeERC20.safeApprove(uDebtToken, address(debtToken), 0);
        SafeERC20.safeApprove(uDebtToken, address(debtToken), debtToRepay);
        debtToken.repayBorrowBehalf(borrower, debtToRepay);
    }

    function _withdrawCollateral(
        CToken colToken,
        address onBehalf,
        address to,
        uint256 amountToWithdraw
    ) internal {
        SafeERC20.safeTransferFrom(colToken, onBehalf, to, amountToWithdraw);
        colToken.redeemUnderlying(amountToWithdraw);
    }

    function _getUnderlyingPrice(CToken cToken) internal view override returns (uint256 price) {
        price = oracle.getUnderlyingPrice(cToken);
    }

    // the usdc price in wei
    // e.g Eth $3000, this method returns `1e18 * 1 / 3000`
    function _getUsdcEthPrice() internal view override returns (uint256 price) {
        price = oracle.getUnderlyingPrice(CToken(CUSDC_ADDRESS)) / 1e12;
    }

    function getUserProtectionAt(address account, uint256 index) external view override returns (bytes32 protectionId) {
        return _createdProtections[account].at(index);
    }

    function isUnderThresholdHealthFactor(address account) external view override returns (bool) {
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
