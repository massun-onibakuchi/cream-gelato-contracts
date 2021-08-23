import hre, { waffle, ethers } from "hardhat"
import { Fixture } from "ethereum-waffle"
import {
    ERC20Mock,
    WETH,
    CTokenMock,
    ComptrollerMock,
    PriceOracleMock,
    PokeMe,
    PokeMeReady,
    UniswapV2Router02Mock,
    UniswapV2PairMock,
} from "../typechain"

export const creamFixture: Fixture<{
    token0: ERC20Mock
    token1: ERC20Mock
    cToken0: CTokenMock
    cToken1: CTokenMock
    comptroller: ComptrollerMock
    oracle: PriceOracleMock
    router: UniswapV2Router02Mock
    pair: UniswapV2PairMock
}> = async () => {
    const [
        WEthFactory,
        ERC20MockFactory,
        CTokenMockFactory,
        ComptrollerFactory,
        OracleFactory,
        RouterFactory,
        PairFactory,
    ] = await Promise.all([
        ethers.getContractFactory("WETH"),
        ethers.getContractFactory("ERC20Mock"),
        ethers.getContractFactory("CTokenMock"),
        ethers.getContractFactory("ComptrollerMock"),
        ethers.getContractFactory("PriceOracleMock"),
        ethers.getContractFactory("UniswapV2Router02Mock"),
        ethers.getContractFactory("UniswapV2PairMock"),
    ])
    const weth = (await WEthFactory.deploy()) as WETH
    const token0 = (await ERC20MockFactory.deploy("Token0", "TOKEN0")) as ERC20Mock
    const token1 = (await ERC20MockFactory.deploy("Token1", "TOKEN1")) as ERC20Mock
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
    const [comptroller, oracle, router, pair] = (await Promise.all([
        ComptrollerFactory.deploy([cToken0.address, cToken1.address]),
        OracleFactory.deploy(),
        RouterFactory.deploy(weth.address),
        PairFactory.deploy(),
    ])) as [ComptrollerMock, PriceOracleMock, UniswapV2Router02Mock, UniswapV2PairMock]
    return { token0, token1, cToken0, cToken1, comptroller, oracle, router, pair }
}

// export const gelatoFixture: Fixture<{
//     token0: ERC20Mock
//     token1: ERC20Mock
//     cToken0: CTokenMock
//     cToken1: CTokenMock
//     comptroller: ComptrollerMock
//     oracle: PriceOracleMock
// }> = async () => {
//     const ERC20MockFactory = await ethers.getContractFactory("ERC20Mock")
//     const token0 = (await ERC20MockFactory.deploy("Token0", "TOKEN0")) as ERC20Mock
//     const token1 = (await ERC20MockFactory.deploy("Token1", "TOKEN1")) as ERC20Mock

//     const CTokenMockFactory = await ethers.getContractFactory("CTokenMock")

//     return { token0, token1, cToken0, cToken1, comptroller, oracle }
// }

// factory = await Factory.deploy(ethers.constants.AddressZero);
// const createPairTx = await factory.createPair(token0.address, token1.address);
// const pairAddr = (await getEvents(factory, createPairTx)).find(e => e.name == "PairCreated").args[2];
// pair = (await ethers.getContractAt("UniswapV2Pair", pairAddr)) as IUniswapV2Pair;

// export const uniswapMockFixture: Fixture<{
//     token0: ERC20Mock
//     token1: ERC20Mock
//     cToken0: CTokenMock
//     cToken1: CTokenMock
//     comptroller: ComptrollerMock
// }> = async () => {
//     const UniswapV2Router02Mock = await ethers.getContractFactory("UniswapV2Router02Mock")
//     const router = (await UniswapV2Router02Mock.deploy([cToken0.address, cToken1.address])) as UniswapV2Router02Mock

//     return { token0, token1, cToken0, cToken1, router }
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
