const hre = require("hardhat");

async function main() {
    const lendingPool = '0x8dff5e27ea6b7ac08ebfdf9eb090f32ee9a30fcf'
    const dataProvider = '0x7551b5D2763519d4e37e8B81929D336De671d46d'
    const incentives = '0x357D51124f59836DeD84c8a1730D72B749d8BC23'

    const Executor = await hre.ethers.getContractFactory("AaveExecutor")
    const executor = await Executor.deploy(lendingPool, dataProvider, incentives)
    await executor.deployed()

    console.log('AaveExecutor: ', executor.address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });