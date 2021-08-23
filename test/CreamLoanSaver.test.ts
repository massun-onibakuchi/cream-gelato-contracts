import hre, { waffle, ethers } from "hardhat"
import { expect, use } from "chai"
import { BigNumber } from "ethers"
import {
    ERC20Mock,
    CTokenMock,
    PriceOracleMock,
    ComptrollerMock,
    CreamLoanSaverServiceTest,
    UniswapV2Router02Mock,
    UniswapV2PairMock,
} from "../typechain"
import { creamFixture } from "./fixtures"
import { AbiCoder, defaultAbiCoder } from "ethers/lib/utils"
use(require("chai-bignumber")())

const toWei = ethers.utils.parseEther
const EXP_SCALE = toWei("1")

describe("CreamLoanSaver", async function () {
    const wallets = waffle.provider.getWallets()
    const [wallet, lp, gelato, treasury, pokeMe] = wallets
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

    const totalCollateral = totalCollateralInEth.mul(ETH_PRICE).div(EXP_SCALE) //(0.001 * 1000 * 10**6 * 0.9)*10**18 = 9 * 10**5 * 10**18
    const totalBorrow = totalBorrowInEth.mul(ETH_PRICE).div(EXP_SCALE) //(0.1 * 1000 * 1000 = 10**5)*10**18

    let token0: ERC20Mock // USDC
    let token1: ERC20Mock
    let cToken0: CTokenMock
    let cToken1: CTokenMock
    let oracle: PriceOracleMock
    let comptroller: ComptrollerMock
    let loanSaver: CreamLoanSaverServiceTest
    let router: UniswapV2Router02Mock
    let pair: UniswapV2PairMock
    let LoanSaver
    let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
    before(async function () {
        LoanSaver = await ethers.getContractFactory("CreamLoanSaverServiceTest")
        loadFixture = waffle.createFixtureLoader(wallets)
    })
    beforeEach(async function () {
        ;({ token0, token1, cToken0, cToken1, comptroller, oracle, router, pair } = await loadFixture(creamFixture))
        loanSaver = (await LoanSaver.deploy(
            pokeMe.address,
            cToken0.address,
            gelato.address,
            comptroller.address,
            router.address,
            oracle.address,
        )) as CreamLoanSaverServiceTest
        await token0.setDecimals(DECIMALS[0])
        await token1.setDecimals(DECIMALS[1])
        await oracle.setPrice(cToken0.address, TOKEN_PRICES[0])
        await oracle.setPrice(cToken1.address, TOKEN_PRICES[1])

        await setup(mintAmount, borrowAmount)

        const exchangeRate = await cToken0.exchangeRateStored()
        expect(await cToken0.balanceOf(wallet.address)).to.eq(toWei("1").mul(mintAmount).div(exchangeRate))
        expect(await token1.balanceOf(wallet.address)).to.eq(toWei("1").add(borrowAmount))
        expect(await cToken1.borrowBalanceStored(wallet.address)).to.eq(borrowAmount)
    })
    const setup = async (mintAmount, borrowAmount) => {
        // fund
        await token0.mint(pair.address, toWei("1")) // fund
        await token1.mint(pair.address, toWei("1")) // fund
        await token0.mint(wallet.address, toWei("1"))
        await token1.mint(wallet.address, toWei("1"))
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
    }
    it("initialize", async function () {
        expect(await loanSaver.pokeMe()).to.eq(pokeMe.address)
        expect(await loanSaver.CUSDC_ADDRESS()).to.eq(cToken0.address)
        expect(await loanSaver.GELATO()).to.eq(gelato.address)
        expect(await loanSaver.comptroller()).to.eq(comptroller.address)
        expect(await loanSaver.uniswapRouter()).to.eq(router.address)
        expect(await loanSaver.oracle()).to.eq(oracle.address)
        expect(await loanSaver.flashFeeBps()).to.eq(0)
        expect(await loanSaver.protectionFeeBps()).to.eq(0)
    })
    it("calculate collateral amount to borrow", async function () {
        // reduce collateral amount to half, which results in halving health factor
        await cToken0.redeemUnderlying(mintAmount.div(2))
        await comptroller.setAccountLiquidity(wallet.address, totalCollateral.div(2).sub(totalBorrow))

        const result = await loanSaver.getUserAccountData(wallet.address)
        const currentTotalColInEth = result.totalCollateralInEth
        const wantedHealthFactor = INITIAL_HEALTH_FACTOR
        expect(result.healthFactor).to.eq(INITIAL_HEALTH_FACTOR.div(2))
        const protectionDataCompute = {
            colToken: cToken0.address,
            debtToken: cToken1.address,
            ethPerColToken: TOKEN_PRICES[0],
            wantedHealthFactor: wantedHealthFactor,
            colFactor: toWei("0.9"),
            totalCollateralInEth: currentTotalColInEth,
            totalBorrowInEth: totalBorrowInEth,
            protectionFeeBps: 0,
            flashLoanFeeBps: 0,
        }
        const amtToBorrow = getColAmtToBorrow(protectionDataCompute)
        expect(await loanSaver.calculateColAmtToBorrow(protectionDataCompute)).to.eq(amtToBorrow)
    })
    const getColAmtToBorrow = data => {
        const TEN_THOUSAND_BPS = BigNumber.from(10).pow(4)

        const nominator = data.wantedHealthFactor
            .mul(data.totalBorrowInEth)
            .sub(data.totalCollateralInEth.mul(EXP_SCALE))
        const feeBps = TEN_THOUSAND_BPS.add(data.flashLoanFeeBps).add(data.protectionFeeBps)
        const denominator = data.wantedHealthFactor.sub(feeBps.mul(BigNumber.from(10).pow(14)))
        const amtToBorrowInEth = nominator.div(denominator)

        return amtToBorrowInEth.mul(EXP_SCALE).div(data.colFactor).mul(EXP_SCALE).div(TOKEN_PRICES[0])
    }
    it("_paybackToCToken", async function () {
        expect(await cToken1.borrowBalanceStored(wallet.address)).to.eq(borrowAmount)
        await token1.mint(loanSaver.address, borrowAmount)
        await loanSaver.paybackToCToken(cToken1.address, token1.address, wallet.address, borrowAmount)
        expect(await cToken1.borrowBalanceStored(wallet.address)).to.eq(0)
    })
    it("_withdrawCollateral", async function () {
        await cToken0.connect(wallet).approve(loanSaver.address, ethers.constants.MaxUint256)
        await loanSaver.withdrawCollateral(cToken0.address, wallet.address, loanSaver.address, mintAmount)
        expect(await cToken0.balanceOf(wallet.address)).to.eq(0)
        expect(await token0.balanceOf(loanSaver.address)).to.eq(mintAmount)
    })
    it("_swap", async function () {
        const amountIn = BigNumber.from(10).pow(DECIMALS[0])
        const amountOut = toWei("0.001")
        await token0.mint(loanSaver.address, amountIn)
        await router.setupMock(pair.address, amountOut)

        expect(await token1.balanceOf(loanSaver.address)).to.eq(0)
        await loanSaver.swap(token0.address, token1.address, amountIn)
        expect(await token0.balanceOf(loanSaver.address)).to.eq(0)
        expect(await token1.balanceOf(loanSaver.address)).to.eq(amountOut)
    })

    it("_flashLoan", async function () {
        const amountIn = BigNumber.from(10).pow(DECIMALS[0])
        const amountOut = toWei("0.001")
        await router.setupMock(pair.address, amountOut)

        const borrowAmount = amountIn
        const data = {
            protectionData: {
                thresholdHealthFactor: toWei("4.5"),
                wantedHealthFactor: INITIAL_HEALTH_FACTOR,
                colToken: cToken0.address,
                debtToken: cToken1.address,
            },
            borrower: wallet.address,
            swapData: defaultAbiCoder.encode(
                ["address", "address", "uint256"],
                [token0.address, token1.address, borrowAmount],
            ),
        }
        expect(await token0.balanceOf(loanSaver.address)).to.eq(0)
        expect(await token1.balanceOf(loanSaver.address)).to.eq(0)
        expect(await token0.balanceOf(cToken0.address)).to.eq(toWei("1").add(mintAmount))

        await cToken0.connect(wallet).approve(loanSaver.address, ethers.constants.MaxUint256)
        await loanSaver.flashLoan(cToken0.address, loanSaver.address, borrowAmount, data)

        expect(await token0.balanceOf(loanSaver.address)).to.eq(0)
        expect(await token1.balanceOf(loanSaver.address)).to.eq(0)
        expect(await token1.balanceOf(cToken0.address)).to.eq(toWei("1").add(mintAmount))
    })
})
