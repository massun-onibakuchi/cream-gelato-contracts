import { DeployFunction } from "hardhat-deploy/dist/types"
import { HardhatRuntimeEnvironment } from "hardhat/types"

const gelatoDeployment: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts, ethers } = hre
    const { deploy, get } = deployments
    const { owner, gelato } = await getNamedAccounts()

    const options = { from: owner }
    const oracle = await get("PriceOracleMock")
    const router = await get("UniswapV2Router02Mock")
    const comptroller = await get("ComptrollerMock")
    const cusdc = await get("CusdCoin")

    const treasury = await deploy("TaskTreasury", { ...options, args: [gelato] })
    const pokeMe = await deploy("PokeMe", { ...options, args: [gelato, treasury.address] })
    const loanSaverService = await deploy("CreamLoanSaverServiceTest", {
        ...options,
        args: [pokeMe.address, cusdc.address, gelato, comptroller.address, router.address, oracle.address],
    })
    await deploy("LoanSaverResolver", { ...options, args: [loanSaverService.address] })
}

export default gelatoDeployment
gelatoDeployment.tags = ["Gelato"]
gelatoDeployment.dependencies = ["Cream"]
