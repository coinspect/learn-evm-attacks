import fs from "fs";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-preprocessor";
import { HardhatUserConfig, task } from "hardhat/config";
import * as dotenv from 'dotenv'
dotenv.config()

import example from "./tasks/example";

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => line.trim().split("="));
}

task("example", "Example task").setAction(example);

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    }
  },
  networks: {
    hardhat: {
    },
    mainnet: {
      url: "https://rpc.ankr.com/eth",
      accounts: [process.env.BURNER_PRIVATE_KEY? process.env.BURNER_PRIVATE_KEY : ""]
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      accounts: [process.env.BURNER_PRIVATE_KEY? process.env.BURNER_PRIVATE_KEY : ""]
    },
    fantom: {
      url: "https://rpc.ankr.com/fantom",
      accounts: [process.env.BURNER_PRIVATE_KEY? process.env.BURNER_PRIVATE_KEY : ""]
    },
    gnosis: {
      url: "https://rpc.ankr.com/gnosis",
      accounts: [process.env.BURNER_PRIVATE_KEY? process.env.BURNER_PRIVATE_KEY : ""]
    },

    
  },
  paths: {
    sources: "./src", // Use ./src rather than ./contracts as Hardhat expects
    cache: "./cache_hardhat", // Use a different cache for Hardhat than Foundry
  },
  // This fully resolves paths for imports in the ./lib directory for Hardhat
  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match(find)) {
              line = line.replace(find, replace);
            }
          });
        }
        return line;
      },
    }),
  },
};

export default config;
