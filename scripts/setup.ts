import hre, { ethers } from "hardhat"
import { BigNumber, Contract } from "ethers"

const toWei = ethers.utils.parseEther
const EXP_SCALE = toWei("1")

const main = async () => {
    const { deployments, getNamedAccounts, ethers } = hre
    const { get } = deployments
    const { walletAddress, ownerAddress } = await getNamedAccounts()
    const owner = await ethers.getSigner(ownerAddress)
    const wallet = await ethers.getSigner(walletAddress)

    const DECIMALS = [6, 18]
    const TOKEN_PRICES = [
        toWei("0.001").mul(BigNumber.from(10).pow(18 - DECIMALS[0])),
        toWei("0.1").mul(BigNumber.from(10).pow(18 - DECIMALS[1])),
    ]
    const ETH_PRICE = EXP_SCALE.mul("1000") // 1 ETH = 1000$
    const [token0D, token1D, cToken0D, cToken1D, comptrollerD, oracleD, pairD, saverDeployment] = await Promise.all(
        [
            "USDCoin",
            "ERC20Mock",
            "CusdCoin",
            "CTokenMock",
            "ComptrollerMock",
            "PriceOracleMock",
            "UniswapV2PairMock",
            "CreamLoanSaverServiceTest",
        ].map(v => get(v)),
    )

    const token0 = new Contract(token0D.address, token0D.abi, owner)
    const token1 = new Contract(token1D.address, token1D.abi, owner)
    const cToken0 = new Contract(cToken0D.address, cToken0D.abi, owner)
    const cToken1 = new Contract(cToken1D.address, cToken1D.abi, owner)
    const comptroller = new Contract(comptrollerD.address, comptrollerD.abi, owner)
    const loanSaverService = new Contract(saverDeployment.address, saverDeployment.abi, owner)
    const oracle = new Contract(oracleD.address, oracleD.abi, owner)

    const mintAmount = BigNumber.from(10).pow(6).mul(1)
    const borrowAmount = BigNumber.from(10).pow(15)

    await token0.setDecimals(DECIMALS[0])
    await token1.setDecimals(DECIMALS[1])
    await oracle.setPrice(cToken0.address, TOKEN_PRICES[0])
    await oracle.setPrice(cToken1.address, TOKEN_PRICES[1])
    await fund([token0, token1], [cToken0, cToken1], pairD.address, wallet)
    await setLiquidity(
        [token0, token1],
        [cToken0, cToken1],
        comptroller,
        mintAmount,
        borrowAmount,
        TOKEN_PRICES,
        ETH_PRICE,
        wallet,
    )
    await loanSaverService.connect(owner).addTokenToWhiteList(cToken0.address)
    await loanSaverService.connect(owner).addTokenToWhiteList(cToken1.address)
}
const fund = async (tokens, cTokens, pair, wallet) => {
    await tokens[0].mint(pair.address, toWei("1"))
    await tokens[1].mint(pair.address, toWei("1"))
    await tokens[0].mint(wallet.address, toWei("1"))
    await tokens[1].mint(wallet.address, toWei("1"))
    await tokens[0].mint(cTokens[0].address, toWei("1"))
    await tokens[1].mint(cTokens[1].address, toWei("1"))
}
const setLiquidity = async (tokens, cTokens, comptroller, mintAmount, borrowAmount, prices, ethPrice, wallet) => {
    const totalCollateralInEth = prices[0].mul(mintAmount.mul(9).div(10)).div(EXP_SCALE)
    const totalBorrowInEth = prices[1].mul(borrowAmount).div(EXP_SCALE)
    const totalCollateral = totalCollateralInEth.mul(ethPrice).div(EXP_SCALE)
    const totalBorrow = totalBorrowInEth.mul(ethPrice).div(EXP_SCALE)
    await comptroller.setAssetsIn(wallet.address, [cTokens[0].address, cTokens[1].address])
    await tokens[0].approve(cTokens[0].address, mintAmount)
    await cTokens[0].connect(wallet).mint(mintAmount)
    await cTokens[1].connect(wallet).borrow(borrowAmount)
    await comptroller.setAccountLiquidity(wallet.address, totalCollateral.sub(totalBorrow))
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })
