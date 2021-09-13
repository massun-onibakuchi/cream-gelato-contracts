// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "./gelato/PokeMeReady.sol";
import "./CreamAccountDataProvider.sol";

import "./interfaces/ILoanSaver.sol";
import "./interfaces/IFlashloanReceiver.sol";
import "./interfaces/IPriceOracle.sol";
import { CTokenInterface as CToken, ICTokenFlashLoan } from "./interfaces/CTokenInterface.sol";

import "hardhat/console.sol";

contract CreamLoanSaver is PokeMeReady, CreamAccountDataProvider, ILoanSaver, IFlashloanReceiver {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct ProtectionFullData {
        bytes32 protectionId;
        uint256 thresholdHealthFactor;
        uint256 wantedHealthFactor;
        CToken colToken;
        CToken debtToken;
        /* 
        AccountData collateral
            {
                uint256 balanceUnderlying,
                uint256 debtUnderlying,
                uint256 exchangeRateStored,
                uint256 borrowRatePerBlock,
                uint256 supplyRatePerBlock
            }
        AccountData debt
            {
                uint256 balanceUnderlying,
                uint256 debtUnderlying,
                uint256 exchangeRateStored,
                uint256 borrowRatePerBlock,
                uint256 supplyRatePerBlock
            }
    */
    }
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
        uint256 ethPerColToken;
        uint256 wantedHealthFactor;
        uint256 colFactor;
        uint256 totalCollateralInEth;
        uint256 totalBorrowInEth;
        uint256 protectionFeeBps;
        uint256 flashLoanFeeBps;
    }

    uint256 private constant TEN_THOUSAND_BPS = 1e4;

    IUniswapV2Router02 public immutable uniswapRouter;
    IPriceOracle public immutable oracle;
    address public immutable CUSDC_ADDRESS;
    address public immutable GELATO;

    uint256 public flashFeeBps;
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

    /// @notice If the health factor is less than the registered protection health factor,
    /// repay the loan and increase the health factor to the target health factor.
    /// only pokeMe can call this function
    /// @param account cream fi user to be protected
    /// @param protectionId registered protection id
    function saveLoan(address account, bytes32 protectionId) external override onlyPokeMe {
        // check
        require(_createdProtections[account].contains(protectionId), "protection-not-found");

        // effect
        ProtectionData memory protectionData_ = _protectionData[protectionId];
        _createdProtections[account].remove(protectionId);
        delete _protectionData[protectionId];

        (uint256 totalCollateralInEth, uint256 totalBorrowInEth, uint256 healthFactor, ) = _getUserAccountData(account);
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(protectionData_.colToken));
        uint256 ethPerColToken = _getUnderlyingPrice(protectionData_.colToken);

        // check if healthFactor is under threshold
        require(collateralFactorMantissa > 0, "collateral-factor-zero");
        require(protectionData_.thresholdHealthFactor > healthFactor, "health-factor-not-under-threshold");
        require(ethPerColToken > 0, "collateral-price-zero");

        // Calculate repay amount and debtToken amount to flash borrow
        uint256 borrowColAmt = _calculateColAmtToBorrow(
            ProtectionDataCompute({
                colToken: protectionData_.colToken,
                debtToken: protectionData_.debtToken,
                ethPerColToken: ethPerColToken,
                wantedHealthFactor: protectionData_.wantedHealthFactor,
                colFactor: collateralFactorMantissa,
                totalCollateralInEth: totalCollateralInEth,
                totalBorrowInEth: totalBorrowInEth,
                protectionFeeBps: protectionFeeBps,
                flashLoanFeeBps: flashFeeBps
            })
        );

        require(borrowColAmt > 0, "amount-to-flash-borrow-zero");

        bytes memory swapData = abi.encode(
            protectionData_.colToken.underlying(),
            protectionData_.debtToken.underlying(),
            borrowColAmt
        );

        _flashLoan(
            protectionData_.colToken,
            address(this),
            borrowColAmt,
            FlashLoanData({ protectionData: protectionData_, borrower: account, swapData: swapData })
        );

        // Check user's position is safe
        (, , healthFactor, ) = _getUserAccountData(account);
        require(healthFactor <= protectionData_.thresholdHealthFactor, "health-factor-stay-unsafe");
    }

    /// @notice calculate amount of collateral to flashborrow
    /// @param _protectionDataCompute user position data, collateral price,collateral factor
    /// @return borrowColAmt amount of collateral to flashborrow in order to recover health factor
    function _calculateColAmtToBorrow(ProtectionDataCompute memory _protectionDataCompute)
        internal
        view
        returns (uint256 borrowColAmt)
    {
        // @audit calculate amount of collateral to flashborrow
        // @note
        // current hf means HF_c,which equals to y/x, wanted hf means HF_w = (y - ∆y*f) / (x-∆y)
        // we want to get `amount` in collateral token, ∆y means value (in Eth) to redeem,
        // ∆y = (HF_w * x - y) / (HF_w - (flashFee + protectionFee))
        // ∆y = amount * ethPerAsset * colFactor
        // amount = ∆y / ethPerAsset / colFactor

        uint256 borrowColAmtInEth = (_protectionDataCompute.wantedHealthFactor *
            _protectionDataCompute.totalBorrowInEth -
            _protectionDataCompute.totalCollateralInEth *
            EXP_SCALE) /
            (_protectionDataCompute.wantedHealthFactor -
                (TEN_THOUSAND_BPS + _protectionDataCompute.flashLoanFeeBps + _protectionDataCompute.protectionFeeBps) *
                1e14);
        // @note require ethPerColToken and colFactor non-zero
        borrowColAmt =
            (((borrowColAmtInEth * EXP_SCALE) / _protectionDataCompute.colFactor) * EXP_SCALE) /
            _protectionDataCompute.ethPerColToken;
    }

    function _requireAcceptableSlipage() internal view {
        // require(, "unacceptable-slipage");
    }

    function _swap(
        address tokenToSell,
        address tokenToBuy,
        uint256 amountToSell
    ) internal {
        address[] memory path;
        uint256 deadline = block.timestamp + (15 * 60);
        address WETH = uniswapRouter.WETH();

        // @todo slipage validation
        // @todo custom path
        if (tokenToBuy == WETH) {
            // path = new address[](3);
            // path[0] = tokenToSell;
            // path[1] = WETH;
            // SafeERC20.safeApprove(IERC20(tokenToSell), address(uniswapRouter), amountToSell);
            // uniswapRouter.swapExactTokensForETH(amountToSell, 1, path, address(this), deadline);
        } else if (tokenToSell == WETH) {
            /// @notice currently Cream fi does'nt provide crETH flashLoan
            // path[0] = WETH;
            // path[1] = tokenToBuy;
            // uniswapRouter.swapExactETHForTokens(1, path, address(this), deadline);
        } else {
            path = new address[](3);
            path[0] = tokenToSell;
            path[1] = WETH;
            path[2] = tokenToBuy;

            _approveERC20(IERC20(tokenToSell), address(uniswapRouter), amountToSell);
            uniswapRouter.swapExactTokensForTokens(amountToSell, 1, path, address(this), deadline);
        }
    }

    // @note
    /// @dev Only flash loans are supported, such as AAVE v2, where the borrower only has to return the amount of tokens borrowed in the flash loan plus the fee.
    /// This means flash loans, such as Aave v1 or current Cream , which require a constant amount of tokens to be held by the protocol, do not work well.
    /// @param receiver : The Flash Loan contract address you deployed.
    /// @param amount : Keep in mind that the decimal of amount is dependent on crToken's underlying asset.
    /// @param flashLoanData : encoded parameter for executeOperation().
    /// If no parameters are needed in your Flash Loan contract, use an empty value "".
    /// If you would like to pass parameters into your flash loan, you will need to encode it.
    function _flashLoan(
        ICTokenFlashLoan flashLender,
        address receiver,
        uint256 amount,
        FlashLoanData memory flashLoanData
    ) internal {
        flashLender.flashLoan(receiver, amount, abi.encode(address(flashLender), flashLoanData));
    }

    /// @notice flashLoan callback function
    /// @dev only crToken can call this function
    /// @param premiums fee in underlying token
    /// @param params encoded parameter
    function executeOperation(
        address sender,
        address, // underlying
        uint256, // amount
        uint256 premiums,
        bytes calldata params
    ) external override {
        (, FlashLoanData memory flashLoanData) = abi.decode(params, (address, FlashLoanData));
        require(
            address(this) == sender && msg.sender == address(flashLoanData.protectionData.colToken),
            "flashloan-callback-only-cToken"
        );
        _executeOperation(premiums, flashLoanData);
    }

    /// @dev swap flashborrow token to debtToken, payback loan,then withdraw col,transfer fee and return flashpayback
    function _executeOperation(uint256 premiums, FlashLoanData memory flashLoanData) internal {
        ProtectionData memory protectionData = flashLoanData.protectionData;
        address onBehalf = flashLoanData.borrower;
        bytes memory swapData = flashLoanData.swapData;

        (address uColToken, address uDebtToken, uint256 amtBorrowedToSell) = abi.decode(
            swapData,
            (address, address, uint256)
        );
        {
            uint256 balanceBefore = IERC20(uDebtToken).balanceOf(address(this));
            /// @notice swap  collateral underlying token to debt underlying token
            _swap(uColToken, uDebtToken, amtBorrowedToSell);
            uint256 receivedDebtTokenAmt = IERC20(uDebtToken).balanceOf(address(this)) - balanceBefore;
            /// @notice payback debt to cToken
            _paybackToCToken(protectionData.debtToken, IERC20(uDebtToken), onBehalf, receivedDebtTokenAmt);
        }
        uint256 fees = (amtBorrowedToSell * protectionFeeBps) / TEN_THOUSAND_BPS;
        uint256 amountToWithdraw = amtBorrowedToSell + fees + premiums;
        /// @notice Withdraw collateral (including fees) and flashloan premium.
        _withdrawCollateral(protectionData.colToken, onBehalf, address(this), amountToWithdraw);

        /// @notice transfer fees to Gelato
        SafeERC20.safeTransfer(IERC20(uColToken), GELATO, fees);

        // AAVE v1 don't work,use AAVE v2
        // @notice transfer flashborrow + premiums to cToken
        // SafeERC20.safeTransfer(IERC20(uColToken), address(protectionData.colToken), amtBorrowedToSell + premiums);

        /// @notice
        _approveERC20(IERC20(uColToken), address(protectionData.colToken), amtBorrowedToSell + premiums);
    }

    function _paybackToCToken(
        CToken debtToken,
        IERC20 uDebtToken,
        address borrower,
        uint256 debtToRepay
    ) internal {
        _approveERC20(uDebtToken, address(debtToken), debtToRepay);
        debtToken.repayBorrowBehalf(borrower, debtToRepay);
    }

    /// @dev assuming user pre-approved this contract using colToken
    /// @param colToken cToken to be redeemed
    /// @param onBehalf protection user
    /// @param to receiver of token
    /// @param amountToWithdraw amount of collateral underlying to be redeemed
    function _withdrawCollateral(
        CToken colToken,
        address onBehalf,
        address to,
        uint256 amountToWithdraw
    ) internal {
        SafeERC20.safeTransferFrom(
            colToken,
            onBehalf,
            to,
            (amountToWithdraw * EXP_SCALE) / colToken.exchangeRateStored()
        );
        colToken.redeemUnderlying(amountToWithdraw);
    }

    /// @dev Approves 0 first to comply with tokens that implement the anti frontrunning approval fix
    function _approveERC20(
        IERC20 token,
        address spender,
        uint256 amount
    ) internal {
        SafeERC20.safeApprove(token, spender, 0);
        SafeERC20.safeApprove(token, spender, amount);
    }

    /// @notice cream's price oracle proxy wrapper
    /// e.g underlying asset (uToken) price is $2 and ETH=$3000,
    /// ETH per uToken = 2/3000
    /// if its decimals is x, it is represented as 10**18 * 10**(18-x) * 2/3000
    /// @return price ethPerAsset
    function _getUnderlyingPrice(CToken cToken) internal view override returns (uint256 price) {
        price = oracle.getUnderlyingPrice(cToken);
    }

    /// @notice cream's price oracle proxy wrapper
    /// @return price ethPerUSDC USDC/ETH if ETH=$3000, return 1e18 * 1 / 3000
    function _getUsdcEthPrice() internal view override returns (uint256 price) {
        price = oracle.getUnderlyingPrice(CToken(CUSDC_ADDRESS)) / 1e12;
    }

    function getUserProtectionAt(address account, uint256 index) external view override returns (bytes32) {
        return _createdProtections[account].at(index);
    }

    function getUserProtectionCount(address account) external view override returns (uint256) {
        return _createdProtections[account].length();
    }

    function getProtectionData(bytes32 id) external view returns (ProtectionData memory) {
        return _protectionData[id];
    }

    function getUserProtectionDataByIndex(address account, uint256 index)
        external
        view
        returns (ProtectionFullData memory)
    {
        bytes32 id = _createdProtections[account].at(index);
        ProtectionData memory data = _protectionData[id];
        return
            ProtectionFullData({
                protectionId: id,
                thresholdHealthFactor: data.thresholdHealthFactor,
                wantedHealthFactor: data.wantedHealthFactor,
                colToken: data.colToken,
                debtToken: data.debtToken
            });
    }

    /// @dev this function expected to be called by Gelato resolver in `checker()`
    /// @param account borrower
    /// @return bool : true if account health factor is smaller than the threshold
    function isUnderThresholdHealthFactor(address account)
        external
        view
        override(CreamAccountDataProvider, ILoanSaver)
        returns (bool)
    {
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
