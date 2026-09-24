import "@nomicfoundation/hardhat-ethers";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    bscTestnet: {
      url:
        process.env.BSC_TESTNET_RPC_URL ??
        "https://data-seed-prebsc-1-s1.bnbchain.org:8545",
      chainId: 97,
    },
  },
};

export default config;
