// import * as dotenv from "dotenv";
// dotenv.config();
import 'dotenv/config';
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import "@openzeppelin/hardhat-upgrades";

const config: HardhatUserConfig = {
    // solidity: '0.8.24',
    solidity: {
        compilers: [
            {
                version: "0.8.24",
                settings: {
                  optimizer: {
                    enabled: true,
                    runs: 200
                  }
                }
            }
        ]
    },
    networks: {
        mainnet: {
            url: process.env.MAINNET_URL || "",
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        },
        sepolia: {
            url: "https://sepolia.infura.io/v3/fa47b8ee8c864836a2d552889ccac478", // "https://ethereum-sepolia-rpc.publicnode.com", https://1rpc.io/sepolia
            chainId: 11155111,
            gasPrice: 50000000000,
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        },
        bsc: {
            url: "https://bsc-dataseed.binance.org/",
            chainId: 56,
            gasPrice: 30000000000,
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        },
        bscTestnet: {
            url: "https://data-seed-prebsc-1-s1.binance.org:8545",
            chainId: 97,
            gasPrice: 30000000000,
            // accounts: {privatekey: privatekey},
            accounts:
                process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
        },
    },
    etherscan: {
        apiKey: {
            mainnet: process.env.ETHERSCAN_API_KEY ??  '',
            sepolia: process.env.ETHERSCAN_API_KEY ??  '',
            bscTestnet: process.env.BSCSCAN_API_KEY  ?? '',
        }
    }
};

export default config;
