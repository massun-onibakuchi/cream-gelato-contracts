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
    PokeMe,
    LoanSaverResolver,
} from "../typechain"
import { creamFixture, gelatoDeployment } from "./fixtures"
import { defaultAbiCoder, keccak256 } from "ethers/lib/utils"
use(require("chai-bignumber")())

const toWei = ethers.utils.parseEther
const EXP_SCALE = toWei("1")
const ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"

describe("CreamLoanSaverService", async function () {
    const wallets = waffle.provider.getWallets()
    const [wallet, owner, gelato, treasury] = wallets
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
    let loanSaverService: CreamLoanSaverServiceTest
    let router: UniswapV2Router02Mock
    let pair: UniswapV2PairMock
    let pokeMe: PokeMe
    let resolver: LoanSaverResolver
    let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
    before(async function () {
        loadFixture = waffle.createFixtureLoader(wallets)
    })
    beforeEach(async function () {
        ;({ token0, token1, cToken0, cToken1, comptroller, oracle, router, pair } = await loadFixture(creamFixture))
        ;({ pokeMe, resolver, loanSaverService } = await gelatoDeployment(
            gelato,
            treasury,
            cToken0,
            comptroller,
            router,
            oracle,
            owner,
        ))
        await token0.setDecimals(DECIMALS[0])
        await token1.setDecimals(DECIMALS[1])
        await oracle.setPrice(cToken0.address, TOKEN_PRICES[0])
        await oracle.setPrice(cToken1.address, TOKEN_PRICES[1])

        await setup()

        const exchangeRate = await cToken0.exchangeRateStored()
        expect(await cToken0.balanceOf(wallet.address)).to.eq(toWei("1").mul(mintAmount).div(exchangeRate))
        expect(await token1.balanceOf(wallet.address)).to.eq(toWei("1").add(borrowAmount))
        expect(await cToken1.borrowBalanceStored(wallet.address)).to.eq(borrowAmount)
    })
    const setup = async () => {
        // fund
        await token0.mint(pair.address, toWei("1"))
        await token1.mint(pair.address, toWei("1"))
        await token0.mint(wallet.address, toWei("1"))
        await token1.mint(wallet.address, toWei("1"))
        await token0.mint(cToken0.address, toWei("1"))
        await token1.mint(cToken1.address, toWei("1"))

        // mint cToken0, borrow token1
        await comptroller.setAssetsIn(wallet.address, [cToken0.address, cToken1.address])
        await token0.approve(cToken0.address, mintAmount)
        await cToken0.connect(wallet).mint(mintAmount)
        await cToken1.connect(wallet).borrow(borrowAmount)

        await comptroller.setAccountLiquidity(wallet.address, totalCollateral.sub(totalBorrow))

        await loanSaverService.connect(owner).addTokenToWhiteList(cToken0.address)
        await loanSaverService.connect(owner).addTokenToWhiteList(cToken1.address)
    }
    it("initialize", async function () {
        expect(await loanSaverService.pokeMe()).to.eq(pokeMe.address)
        expect(await loanSaverService.CUSDC_ADDRESS()).to.eq(cToken0.address)
        expect(await loanSaverService.GELATO()).to.eq(gelato.address)
        expect(await loanSaverService.comptroller()).to.eq(comptroller.address)
        expect(await loanSaverService.uniswapRouter()).to.eq(router.address)
        expect(await loanSaverService.oracle()).to.eq(oracle.address)
        expect(await loanSaverService.flashFeeBps()).to.eq(0)
        expect(await loanSaverService.protectionFeeBps()).to.eq(0)
        expect(await loanSaverService.owner()).to.eq(owner.address)
        expect(await loanSaverService.whiteListedTokens(cToken0.address)).to.be.true
        expect(await loanSaverService.whiteListedTokens(cToken1.address)).to.be.true
    })
    it("whiteListing: only owner can call", async function () {
        await expect(loanSaverService.connect(wallet).addTokenToWhiteList(cToken0.address)).to.be.reverted
        await expect(loanSaverService.connect(wallet).removeTokenFromWhiteList(cToken0.address)).to.be.reverted
    })
    it("set fee: only owner can call", async function () {
        await expect(loanSaverService.connect(wallet).setProtectionFeeBps(3)).to.be.reverted
        await expect(loanSaverService.connect(wallet).setFlashFeeBps(3)).to.be.reverted
        await loanSaverService.connect(owner).setProtectionFeeBps(3)
        await loanSaverService.connect(owner).setFlashFeeBps(3)
    })
    it("submitProtection and cancelProtection", async function () {
        const thresholdHealthFactor = INITIAL_HEALTH_FACTOR.div(2)
        const wantedHealthFactor = INITIAL_HEALTH_FACTOR
        const resolverData = resolver.interface.encodeFunctionData("checker", [wallet.address, 0])
        const protectionId = keccak256(
            defaultAbiCoder.encode(
                ["address", "uint256", "uint256", "address", "address", "bytes"],
                [
                    wallet.address,
                    thresholdHealthFactor,
                    wantedHealthFactor,
                    cToken0.address,
                    cToken1.address,
                    resolverData,
                ],
            ),
        )
        // submit
        await expect(
            loanSaverService
                .connect(wallet)
                .submitProtection(
                    thresholdHealthFactor,
                    wantedHealthFactor,
                    cToken0.address,
                    cToken1.address,
                    resolver.address,
                    resolverData,
                    false,
                ),
        )
            .to.emit(loanSaverService, "ProtectionSubmitted")
            .withArgs(wallet.address, protectionId)

        expect(await loanSaverService.getUserProtectionAt(wallet.address, 0)).to.eq(protectionId)
        expect(await loanSaverService.isUnderThresholdHealthFactor(wallet.address)).to.be.false

        const [threshold, wanted, colToken, debtToken] = await loanSaverService.getProtectionData(protectionId)
        expect(threshold).to.eq(thresholdHealthFactor)
        expect(wanted).to.eq(wantedHealthFactor)
        expect(colToken).to.eq(cToken0.address)
        expect(debtToken).to.eq(cToken1.address)

        const [canExec, exeData] = await resolver.checker(wallet.address, 0)
        expect(canExec).to.be.false
        expect(exeData).to.eq("0x")

        // calcel
        await expect(loanSaverService.connect(wallet).cancelProtection(protectionId))
            .to.emit(loanSaverService, "ProtectionCanceled")
            .withArgs(wallet.address, protectionId)

        await expect(loanSaverService.getUserProtectionAt(wallet.address, 0)).to.be.reverted
        expect(await loanSaverService.isUnderThresholdHealthFactor(wallet.address)).to.be.false
    })
    const submitProtection = async (threshold, healthFactor, useTaskTreasuryFunds = true) => {
        const resolverData = resolver.interface.encodeFunctionData("checker", [wallet.address, 0])
        await loanSaverService
            .connect(wallet)
            .submitProtection(
                threshold,
                healthFactor,
                cToken0.address,
                cToken1.address,
                resolver.address,
                resolverData,
                useTaskTreasuryFunds,
            )
        const protectionId = keccak256(
            defaultAbiCoder.encode(
                ["address", "uint256", "uint256", "address", "address", "bytes"],
                [wallet.address, threshold, healthFactor, cToken0.address, cToken1.address, resolverData],
            ),
        )
        return { protectionId, resolverData }
    }
    it("saveLoan", async function () {
        const wantedHealthFactor = INITIAL_HEALTH_FACTOR
        const thresholdHealthFactor = INITIAL_HEALTH_FACTOR.div(2).add(toWei("1"))
        const amountOut = toWei("0.001")
        await router.setupMock(pair.address, amountOut)

        await cToken0.connect(wallet).approve(loanSaverService.address, ethers.constants.MaxUint256)
        // submit
        const { protectionId, resolverData } = await submitProtection(thresholdHealthFactor, wantedHealthFactor, false)

        // reduce collateral amount to half, which results in halving health factor
        await cToken0.redeemUnderlying(mintAmount.div(2))
        await comptroller.setAccountLiquidity(wallet.address, totalCollateral.div(2).sub(totalBorrow))

        expect(await loanSaverService.isUnderThresholdHealthFactor(wallet.address)).to.be.true
        const [canExec, exeData] = await resolver.checker(wallet.address, 0)
        expect(canExec).to.be.true
        expect(exeData).to.be.eq(
            loanSaverService.interface.encodeFunctionData("saveLoan", [wallet.address, protectionId]),
        )
        await pokeMe
            .connect(gelato)
            .exec(
                0,
                ETH,
                loanSaverService.address,
                false,
                keccak256(defaultAbiCoder.encode(["address", "bytes"], [resolver.address, resolverData])),
                loanSaverService.address,
                exeData,
            )
        await expect(loanSaverService.getUserProtectionAt(wallet.address, 0)).to.be.reverted
        expect(await loanSaverService.isUnderThresholdHealthFactor(wallet.address)).to.be.false
    })
})
