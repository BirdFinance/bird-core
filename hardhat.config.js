/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const fs = require('fs')
const path = require('path')

require("@nomiclabs/hardhat-waffle");

task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts : {
        mnemonic: 'test test test test test test test test test test test junk',
        initialIndex: 0,
        path:"m/44'/60'/0'/0",
        count:10,
        accountsBalance:"10000000000000000000000",
      },
      throwOnTransactionFailures:true,
      throwOnCallFailures:true,
    },
    huobi: {
      url: "https://http-mainnet-node.huobichain.com",
      chainId: 128,
      gas:3000000,
      gasPrice:9000000000,
      accounts: {
        mnemonic: 'test test test test test test test test test test test jun',
        initialIndex: 0,
        path:"m/44'/60'/0'/0",
        count:10,
      },
      timeout: 20 * 1000
    },

    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      gas:3000000,
      gasPrice:9000000000,
      accounts: {
        mnemonic: 'test test test test test test test test test test test jun',
        initialIndex: 0,
        path:"m/44'/60'/0'/0",
        count:10,
      },
      timeout: 20 * 1000
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.7.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.8.2",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
};
