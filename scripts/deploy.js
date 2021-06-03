const hre = require("hardhat");
const RLP = require('rlp');

async function main() {
  const deployerAddress = '0xe0468E2A40877F0FB0839895b4eCC81A19C6Cd4d'
  const aaveAddrProvider = '0xd05e3E715d945B59290df0ae8eF85c1BdB684744'
  const aaveDataProvider = '0x7551b5D2763519d4e37e8B81929D336De671d46d'
  
  // console.log("Deploying proxy...")

  // const ProxyFactory = await hre.ethers.getContractFactory("DangoProxyFactory")
  // const factory = await ProxyFactory.deploy()
  // await factory.deployed()

  // console.log("DangoProxyFactory: ", factory.address)

  const txCount = await hre.ethers.provider.getTransactionCount(deployerAddress) + 1
  const executorAddress = '0x' + hre.ethers.utils.keccak256(RLP.encode([deployerAddress, txCount])).slice(12).substring(14)

  const Receiver = await hre.ethers.getContractFactory("DangoReceiver")
  const receiver = await Receiver.deploy(aaveAddrProvider, executorAddress, aaveDataProvider)
  await receiver.deployed();

  const Executor = await hre.ethers.getContractFactory("DangoExecutor")
  const executor = await Executor.deploy(receiver.address, aaveAddrProvider, aaveDataProvider)
  await executor.deployed()

  await receiver.addAccess('0xdef1c0ded9bec7f1a1670819833240f027b25eff')

  console.log('DangoReceiver: ', receiver.address)
  console.log('DangoExecutor: ', executor.address)

  // await hre.run("verify:verify", {
  //   address: factory.address,
  //   constructorArguments: []
  // })

  // await hre.run("verify:verify", {
  //   address: receiver.address,
  //   constructorArguments: [aaveAddrProvider, executorAddress]
  // })

  // await hre.run("verify:verify", {
  //   address: executor.address,
  //   constructorArguments: [receiver.address, aaveAddrProvider, aaveDataProvider]
  // })
  
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
