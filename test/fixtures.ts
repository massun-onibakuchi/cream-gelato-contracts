import hre, { waffle, ethers } from "hardhat"
import { Fixture } from "ethereum-waffle"
import {
    ERC20Mock,
    CTokenMock,
    ComptrollerMock,
    PriceOracleMock,
    // UniswapV2Router02,
    // UniswapV2Factory,
    // UniswapV2Pair,
} from "../typechain"

export const creamFixture: Fixture<{
    token0: ERC20Mock
    token1: ERC20Mock
    cToken0: CTokenMock
    cToken1: CTokenMock
    comptroller: ComptrollerMock
    oracle: PriceOracleMock
}> = async () => {
    const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock")
    const token0 = (await ERC20MockFactory.deploy("Token0", "TOKEN0")) as ERC20Mock
    const token1 = (await ERC20MockFactory.deploy("Token1", "TOKEN1")) as ERC20Mock

    const CTokenMockFactory = await ethers.getContractFactory("CTokenMock")
    const cToken0 = (await CTokenMockFactory.deploy(
        "cToken0",
        "CTOKEN0",
        token0.address,
        ethers.constants.AddressZero,
    )) as CTokenMock
    const cToken1 = (await CTokenMockFactory.deploy(
        "cToken1",
        "CTOKEN1",
        token1.address,
        ethers.constants.AddressZero,
    )) as CTokenMock

    const ComptrollerFactory = await ethers.getContractFactory("ComptrollerMock")
    const comptroller = (await ComptrollerFactory.deploy([cToken0.address, cToken1.address])) as ComptrollerMock

    const Oracle = await ethers.getContractFactory("PriceOracleMock")
    const oracle = (await Oracle.deploy()) as PriceOracleMock
    return { token0, token1, cToken0, cToken1, comptroller, oracle }
}

// factory = await Factory.deploy(ethers.constants.AddressZero);
// const createPairTx = await factory.createPair(token0.address, token1.address);
// const pairAddr = (await getEvents(factory, createPairTx)).find(e => e.name == "PairCreated").args[2];
// pair = (await ethers.getContractAt("UniswapV2Pair", pairAddr)) as IUniswapV2Pair;

// export const uniswapFixture: Fixture<{
//     token0: ERC20Mock
//     token1: ERC20Mock
//     cToken0: CTokenMock
//     cToken1: CTokenMock
//     comptroller: ComptrollerMock
// }> = async () => {
//     const ComptrollerFactory = await ethers.getContractFactory("ComptrollerMock")
//     const comptroller = (await ComptrollerFactory.deploy([cToken0.address, cToken1.address])) as ComptrollerMock

//     await comptroller.setAssetsIn([cToken0.address, cToken1.address])
//     return { token0, token1, cToken0, cToken1, comptroller }
// }

// // const addLiquidity = async (signer: Wallet, pair, token0: ERC20, token1: ERC20, amount = toWei("1")) => {
// //     await token0.mint(pair.address, amount)
// //     await token1.mint(pair.address, amount)
// //     await pair.connect(signer).mint(signer.address)
// // }
// // const redeemLpToken = async (signer: Wallet, amount) => {
// //     await pair.connect(signer).approve(migrator.address, amount)
// //     await migrator.redeemLpToken(pair.address)
// // }
