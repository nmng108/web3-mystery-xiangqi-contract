import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 100,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
      blockGasLimit: 0x1d4c2000,
      gasPrice: 0.2,
    },
    local: {
      url: "http://127.0.0.1:8545",
      chainId: 1337 /*Number("0x539")*/,
      gasPrice: 'auto',
      accounts: [process.env.PRIVATE_KEY || ""],
    },
  }
};

export default config;