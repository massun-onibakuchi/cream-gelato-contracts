import hre, { waffle, ethers } from "hardhat"
import { Fixture } from "ethereum-waffle"
import {
    ERC20Mock,
    WETH,
    CTokenMock,
    ComptrollerMock,
    PriceOracleMock,
    PokeMe,
    LoanSaverResolver,
    CreamLoanSaverServiceTest,
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

export const gelatoDeployment = async (gelato, treasury, cusdc, comptroller, router, oracle, owner) => {
    const [PokeMe, LoanSaverResolver, CreamLoanSaverServiceTest] = await Promise.all([
        ethers.getContractFactory("PokeMe"),
        ethers.getContractFactory("LoanSaverResolver"),
        ethers.getContractFactory("CreamLoanSaverServiceTest", owner),
    ])
    const pokeMe = (await PokeMe.deploy(gelato.address, treasury.address)) as PokeMe
    const loanSaverService = (await CreamLoanSaverServiceTest.deploy(
        pokeMe.address,
        cusdc.address,
        gelato.address,
        comptroller.address,
        router.address,
        oracle.address,
    )) as CreamLoanSaverServiceTest
    const resolver = (await LoanSaverResolver.deploy(loanSaverService.address)) as LoanSaverResolver
    return { pokeMe, resolver, loanSaverService }
}
