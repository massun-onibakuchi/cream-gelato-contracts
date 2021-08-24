import hre, { waffle, ethers } from "hardhat"
import { expect, use } from "chai"
import { BigNumber } from "ethers"
import { ERC20Mock, CTokenMock, PriceOracleMock, ComptrollerMock, CreamAccountDataProviderTest } from "../typechain"
import { creamFixture } from "./fixtures"
use(require("chai-bignumber")())

const toWei = ethers.utils.parseEther
const amount = toWei("10")
const EXP_SCALE = toWei("1")

describe("CreamAccountDataProvider", async function () {
    // const amount = BigNumber.from(10).pow(24);
    const wallets = waffle.provider.getWallets()
    const [wallet, lp] = wallets
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
    let creamAccountDataProvider: CreamAccountDataProviderTest
    let CreamAccountDataProvider
    let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
    before(async function () {
        CreamAccountDataProvider = await ethers.getContractFactory("CreamAccountDataProviderTest")
        loadFixture = waffle.createFixtureLoader(wallets)
    })
    beforeEach(async function () {
        ;({ token0, token1, cToken0, cToken1, comptroller, oracle } = await loadFixture(creamFixture))
        creamAccountDataProvider = (await CreamAccountDataProvider.deploy(
            cToken0.address,
            comptroller.address,
            oracle.address,
        )) as CreamAccountDataProviderTest
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
        expect(await creamAccountDataProvider.oracle()).to.eq(oracle.address)
        expect(await creamAccountDataProvider.comptroller()).to.eq(comptroller.address)
        expect(await creamAccountDataProvider.CUSDC_ADDRESS()).to.eq(cToken0.address)
    })
    it("get price from oracle", async function () {
        expect(await creamAccountDataProvider.getUnderlyingPrice(cToken0.address)).to.eq(TOKEN_PRICES[0])
        expect(await creamAccountDataProvider.getUnderlyingPrice(cToken1.address)).to.eq(TOKEN_PRICES[1])
        expect(await creamAccountDataProvider.getUsdcEthPrice()).to.eq(TOKEN_PRICES[0].div(BigNumber.from(10).pow(12)))
    })
    it("get user account liquidity", async function () {
        const data = await comptroller.getAccountLiquidity(wallet.address)
        expect(data[1]).to.eq(totalCollateral.sub(totalBorrow))
    })
    it("calculate health factor", async function () {
        expect(await creamAccountDataProvider.calculateHealthFactor(totalCollateral, totalBorrow)).to.eq(
            INITIAL_HEALTH_FACTOR,
        )
    })
    it("calculate health factor:if denominator equal to zero, return 0", async function () {
        expect(await creamAccountDataProvider.calculateHealthFactor(totalCollateral, 0)).to.eq(0)
    })
    it("get account data", async function () {
        const ethPerUsd = TOKEN_PRICES[0].div(BigNumber.from(10).pow(12))
        const result = await creamAccountDataProvider.getUserAccountData(wallet.address)
        expect(result[0]).to.eq(totalCollateralInEth)
        expect(result[1]).to.eq(totalBorrowInEth)
        expect(result[2]).to.eq(INITIAL_HEALTH_FACTOR)
        expect(result[3]).to.eq(ethPerUsd)
    })
})
