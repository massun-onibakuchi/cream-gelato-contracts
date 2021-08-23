// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/CTokenInterface.sol";
import "../interfaces/IFlashloanReceiver.sol";

import "hardhat/console.sol";

contract CTokenMock is ERC20, CTokenInterface {
    address private uToken;
    address private _interestRateModel;
    uint256 private _supplyRate;
    uint256 private _exchangeRate;
    uint256 private _totalBorrows;
    uint256 private _totalReserves;
    uint256 private _reserveFactorMantissa;
    uint256 private _getCash;
    address private _comptroller;

    uint256 public flashFeeBps;
    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    //  Mapping of account addresses to outstanding borrow balances
    mapping(address => BorrowSnapshot) private accountBorrows;

    constructor(
        string memory _name,
        string memory _symbol,
        address _uToken,
        address interestRateModel
    ) ERC20(_name, _symbol) {
        uToken = _uToken;
        _interestRateModel = interestRateModel;
        _exchangeRate = 200000000000000;
        _supplyRate = 32847953230;
        // _mint(address(this), 10**14); // 1.000.000 cUSDC
    }

    function decimals() public view override returns (uint8) {
        return 8;
    }

    function underlying() public view override returns (address) {
        return uToken;
    }

    function mint(uint256 amount) public returns (uint256) {
        require(IERC20(uToken).transferFrom(msg.sender, address(this), amount), "Error during transferFrom");
        _mint(msg.sender, (amount * 10**18) / _exchangeRate);
        return 0;
    }

    function redeem(uint256 amount) public returns (uint256) {
        _burn(msg.sender, amount);
        require(IERC20(uToken).transfer(msg.sender, (amount * _exchangeRate) / 10**18), "Error during transfer");
        return 0;
    }

    function redeemUnderlying(uint256 redeemAmount) public override returns (uint256) {
        _burn(msg.sender, (redeemAmount * 10**18) / _exchangeRate);
        require(IERC20(uToken).transfer(msg.sender, redeemAmount), "Error during transfer");
        return 0;
    }

    function borrowBalanceStored(address account) public view override returns (uint256) {
        return accountBorrows[account].principal;
    }

    function borrow(uint256 borrowAmount) public returns (uint256) {
        BorrowSnapshot memory snapshot = accountBorrows[msg.sender];
        accountBorrows[msg.sender].principal = snapshot.principal + borrowAmount;
        require(IERC20(uToken).transfer(msg.sender, borrowAmount), "Error during transfer");
        return 0;
    }

    function repayBorrow(uint256 repayAmount) public returns (uint256) {
        return repayBorrowBehalf(msg.sender, repayAmount);
    }

    function repayBorrowBehalf(address borrower, uint256 repayAmount) public override returns (uint256) {
        require(IERC20(uToken).transferFrom(msg.sender, address(this), repayAmount), "Error during transfer");
        BorrowSnapshot memory snapshot = accountBorrows[borrower];
        accountBorrows[borrower].principal = snapshot.principal - repayAmount;
        return 0;
    }

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by comptroller to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (possible error, cToken balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account)
        public
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (0, balanceOf(account), borrowBalanceStored(account), _exchangeRate);
    }

    function exchangeRateStored() public view override returns (uint256) {
        return _exchangeRate;
    }

    function balanceOfUnderlying(address account) public view override returns (uint256) {
        return (balanceOf(account) * _exchangeRate) / 10**18;
    }

    /// @notice flash loan AAVE v1, CREAM
    // function flashLoan(
    //     address receiver,
    //     uint256 amount,
    //     bytes calldata params
    // ) external override {
    //     IERC20 uToken_ = IERC20(underlying());
    //     uint256 balanceBefore = uToken_.balanceOf(address(this));
    //     uint256 fee = (amount * flashFeeBps) / 10000;

    //     uint256 receiverBalanceBefore = uToken_.balanceOf(receiver);
    //     require(uToken_.transfer(receiver, amount), "flash-lend-token");

    //     // 3. update totalBorrows
    //     // totalBorrows = add_(totalBorrows, amount);

    //     uint256 receiverBalanceAfterTransfer = uToken_.balanceOf(receiver);
    //     IFlashloanReceiver(receiver).executeOperation(msg.sender, underlying(), amount, fee, params);

    //     uint256 receiverBalanceAfterExe = uToken_.balanceOf(receiver);
    //     uint256 balanceAfter = uToken_.balanceOf(address(this));

    //     // 6. update reserves and internal cash and totalBorrows
    //     // uint256 reservesFee = mul_ScalarTruncate(Exp({mantissa: reserveFactorMantissa}), totalFee);
    //     // totalReserves = add_(totalReserves, reservesFee);
    //     // internalCash = add_(cashBefore, totalFee);
    //     // totalBorrows = sub_(totalBorrows, amount);

    //     require(uToken_.balanceOf(address(this)) >= balanceBefore + fee, "balance-inconsistent");
    // }

    /// @dev Flash loan, AAVE v2, currently crToken does'nt support AAVE v2 style flash loan
    function flashLoan(
        address receiver,
        uint256 amount,
        bytes calldata params
    ) external override {
        IERC20 uToken_ = IERC20(underlying());
        uint256 fee = (amount * flashFeeBps) / 10000;

        require(uToken_.balanceOf(address(this)) > amount, "liquidity-inconsistent");
        require(uToken_.transfer(receiver, amount), "flash-lend-token");

        // totalBorrows = add_(totalBorrows, amount);

        IFlashloanReceiver(receiver).executeOperation(msg.sender, underlying(), amount, fee, params);

        // uint256 reservesFee = mul_ScalarTruncate(Exp({mantissa: reserveFactorMantissa}), totalFee);
        // totalReserves = add_(totalReserves, reservesFee);
        // internalCash = add_(cashBefore, totalFee);
        // totalBorrows = sub_(totalBorrows, amount);

        // pull
        require(uToken_.transferFrom(receiver, address(this), amount + fee));
    }

    function setExchangeRateStored(uint256 _rate) public returns (uint256) {
        _exchangeRate = _rate;
        return _exchangeRate;
    }

    function setComptroller(address _comp) public {
        _comptroller = _comp;
    }

    // function supplyRatePerBlock() public view returns (uint256) {
    //     return _supplyRate;
    // }

    // function totalReserves() public view returns (uint256) {
    //     return _totalReserves;
    // }

    // function getCash() public view returns (uint256) {
    //     return _getCash;
    // }

    // function totalBorrows() public view returns (uint256) {
    //     return _totalBorrows;
    // }

    // function interestRateModel() public view returns (address) {
    //     return _interestRateModel;
    // }

    function comptroller() public view returns (address) {
        return _comptroller;
    }
}
