import hre, { waffle, ethers, deployments, getNamedAccounts } from "hardhat"
import { DeployFunction, DeployResult } from "hardhat-deploy/dist/types"
import { HardhatRuntimeEnvironment } from "hardhat/types"

const creamDeployment: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre
    const { deploy } = deployments
    const { owner } = await getNamedAccounts()

    const options = { from: owner }
    const weth = await deploy("WETH", options)
    const token0 = await deploy("USDCoin", { ...options, args: ["Token0", "TOKEN0"] })
    const token1 = await deploy("ERC20Mock", { ...options, args: ["Token1", "TOKEN1"] })
    const cToken0 = await deploy("CusdCoin", {
        ...options,
        args: ["CToken0", "CTOKEN0", token0.address, ethers.constants.AddressZero],
    })
    const cToken1 = await deploy("CTokenMock", {
        ...options,
        args: ["CToken0", "CTOKEN1", token1.address, ethers.constants.AddressZero],
    })
    const deployOptions = {
        CTokenMock: { args: ["CToken0", "CTOKEN1", token1.address, ethers.constants.AddressZero] },
        ComptrollerMock: { args: [[cToken0.address, cToken1.address]] },
        PriceOracleMock: { args: [] },
        UniswapV2Router02Mock: { args: [weth.address] },
        UniswapV2PairMock: { args: [] },
    }
    await Promise.all(
        ["ComptrollerMock", "PriceOracleMock", "UniswapV2PairMock", "UniswapV2Router02Mock"].map(async v => {
            deploy(v, { ...options, ...deployOptions[v] })
        }),
    )
}
export default creamDeployment
creamDeployment.tags = ["Cream"]
