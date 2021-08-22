import hre, { waffle, ethers } from "hardhat"
import { expect, use } from "chai"
import { BigNumber } from "ethers"
import { ERC20Mock, CTokenMock, PriceOracleMock, ComptrollerMock, CreamLoanSaverServiceTest } from "../typechain"
import { creamFixture } from "./fixtures"
use(require("chai-bignumber")())

const toWei = ethers.utils.parseEther
const amount = toWei("10")
const EXP_SCALE = toWei("1")

describe("CreamLoanSaver", async function () {
    const wallets = waffle.provider.getWallets()
    const [wallet, lp, gelato, treasury, pokeMe, router] = wallets
    const DECIMALS = [6, 18]
    const INITIAL_HEALTH_FACTOR = toWei("9")
    const ETH_PRICE = EXP_SCALE.mul("1000") // 1 ETH = 1000$
    const TOKEN_PRICES = [
        toWei("0.001").mul(BigNumber.from(10).pow(18 - DECIMALS[0])),
        toWei("0.1").mul(BigNumber.from(10).pow(18 - DECIMALS[1])),
    ] // token price in ETH ( eth per asset). (price * 10**18)* (10**18 / 10**decimals)
    const mintAmount = BigNumber.from(10).pow(6).mul(1) // 1 token0,whose collateral value is 0.9$ (collateral factor = 0.9)
    const borrowAmount = BigNumber.from(10).pow(15) // 0.001 token1,whose value is 0.1$

    const totalCollateralInEth = TOKEN_PRICES[0].mul(mintAmount.mul(9).div(10)).div(EXP_SCALE)
    const totalBorrowInEth = TOKEN_PRICES[1].mul(borrowAmount).div(EXP_SCALE)

    const totalCollateral = totalCollateralInEth.mul(ETH_PRICE).div(EXP_SCALE)
    const totalBorrow = totalBorrowInEth.mul(ETH_PRICE).div(EXP_SCALE)

    let token0: ERC20Mock // USDC
    let token1: ERC20Mock
    let cToken0: CTokenMock
    let cToken1: CTokenMock
    let oracle: PriceOracleMock
    let comptroller: ComptrollerMock
    let loanSaver: CreamLoanSaverServiceTest
    let LoanSaver
    let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
    before(async function () {
        LoanSaver = await ethers.getContractFactory("CreamLoanSaverServiceTest")
        loadFixture = waffle.createFixtureLoader(wallets)
    })
    beforeEach(async function () {
        ;({ token0, token1, cToken0, cToken1, comptroller, oracle } = await loadFixture(creamFixture))
        loanSaver = (await LoanSaver.deploy(
            pokeMe.address,
            cToken0.address,
            gelato.address,
            comptroller.address,
            router.address,
            oracle.address,
            0,
        )) as CreamLoanSaverServiceTest
        await token0.setDecimals(DECIMALS[0])
        await token1.setDecimals(DECIMALS[1])
        await oracle.setPrice(cToken0.address, TOKEN_PRICES[0])
        await oracle.setPrice(cToken1.address, TOKEN_PRICES[1])

        // totalCollateral= (0.001 * 1000 * 10**6 * 0.9)*10**18 = 9 * 10**5 * 10**18
        // totalBorrow= (0.1 * 1000 * 1000 = 10**5)*10**18
        await setup(mintAmount, borrowAmount)

        const exchangeRate = await cToken0.exchangeRateStored()
        expect(await cToken0.balanceOf(wallet.address)).to.eq(toWei("1").mul(mintAmount).div(exchangeRate))
        expect(await token1.balanceOf(wallet.address)).to.eq(amount.add(borrowAmount))
        expect(await cToken1.borrowBalanceStored(wallet.address)).to.eq(borrowAmount)
    })
    const setup = async (mintAmount, borrowAmount) => {
        // fund
        await token0.mint(wallet.address, amount)
        await token1.mint(wallet.address, amount)
        await token0.mint(cToken0.address, toWei("1"))
        await token1.mint(cToken1.address, toWei("1"))
        // mint cToken0, borrow token1
        await comptroller.setAssetsIn(wallet.address, [cToken0.address, cToken1.address])
        await token0.approve(cToken0.address, mintAmount)
        await cToken0.connect(wallet).mint(mintAmount)
        await cToken1.connect(wallet).borrow(borrowAmount)

        const totalCollateralInEth = TOKEN_PRICES[0].mul(mintAmount.mul(9).div(10)).div(EXP_SCALE)
        const totalBorrowInEth = TOKEN_PRICES[1].mul(borrowAmount).div(EXP_SCALE)
        const totalCollateral = totalCollateralInEth.mul(ETH_PRICE).div(EXP_SCALE)
        const totalBorrow = totalBorrowInEth.mul(ETH_PRICE).div(EXP_SCALE)

        await comptroller.setAccountLiquidity(wallet.address, totalCollateral.sub(totalBorrow))
        return { totalCollateral, totalBorrow }
    }
    it("constructor params", async function () {
        expect(await loanSaver.pokeMe()).to.eq(pokeMe.address)
        expect(await loanSaver.CUSDC_ADDRESS()).to.eq(cToken0.address)
        expect(await loanSaver.GELATO()).to.eq(gelato.address)
        expect(await loanSaver.comptroller()).to.eq(comptroller.address)
        expect(await loanSaver.uniswapRouter()).to.eq(router.address)
        expect(await loanSaver.oracle()).to.eq(oracle.address)
        expect(await loanSaver.oracle()).to.eq(oracle.address)
    })

    it("calculate collateral amount to borrow", async function () {
        // reduce collateral amount to half, which results in halving health factor
        await cToken0.redeemUnderlying(mintAmount.div(2))
        const result = await loanSaver.getUserAccountData(wallet.address)
        const wantedHealthFactor = INITIAL_HEALTH_FACTOR
        expect(result.healthFactor).to.eq(INITIAL_HEALTH_FACTOR.div(2))
        const protectionDataCompute = {
            colToken: cToken0.address,
            debtToken: cToken1.address,
            ethPerColToken: TOKEN_PRICES[0],
            wantedHealthFactor: wantedHealthFactor,
            colFactor: toWei("0.9"),
            totalCollateralInEth: totalCollateralInEth,
            totalBorrowInEth: totalBorrowInEth,
            protectionFeeBps: 0,
            flashLoanFeeBps: 0,
        }
        const amtToBorrow = getColAmtToBorrow(protectionDataCompute)
        console.log("amtToBorrow.toString() :>> ", amtToBorrow.toString())
        // expect(await loanSaver.calculateColAmtToBorrow(protectionDataCompute)).to.eq(amtToBorrow)
    })
    const getColAmtToBorrow = data => {
        const TEN_THOUSAND_BPS = BigNumber.from(10).pow(4)

        const nominator = data.wantedHealthFactor
            .mul(data.totalBorrowInEth)
            .sub(data.totalCollateralInEth.mul(data.colFactor))
        const feeBps = TEN_THOUSAND_BPS.add(data.flashLoanFeeBps).add(data.protectionFeeBps)
        const denominator = data.wantedHealthFactor.sub(data.colFactor.mul(feeBps).mul(BigNumber.from(10).pow(14)))

        const amtToBorrowInEth = nominator.div(denominator)
        return amtToBorrowInEth.mul(EXP_SCALE).div(TOKEN_PRICES[1]).div(data.colFactor)
    }
})
