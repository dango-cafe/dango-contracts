require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

require("dotenv").config();

const ALCHEMY_ID = process.env.ALCHEMY_ID;
const INFURA_ID = process.env.INFURA_ID;
const ETHERSCAN = process.env.ETHERSCAN;
const PRIVATE_KEY = process.env.PRIVATE_KEY;


// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.7.6",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_ID}`,
        blockNumber: 25155741,
      },
      blockGasLimit: 12000000,
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${ALCHEMY_ID}`,
      accounts: [`0x${PRIVATE_KEY}`]
    },
    polygon: {
      url: `https://polygon-mainnet.infura.io/v3/${INFURA_ID}`,
      accounts: [`0x${PRIVATE_KEY}`]
    }
  },
  etherscan: {
    apiKey: ETHERSCAN
  }
};

