import { configVariable, defineConfig } from "hardhat/config";
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    version: "0.8.36",
    // Mạng chặn binaries.soliditylang.org? Tải solc-static-linux 0.8.36 từ GitHub Releases của Solidity
    // rồi chạy:  SOLC_PATH=/duong/dan/solc npx hardhat test
    ...(process.env.SOLC_PATH ? { path: process.env.SOLC_PATH } : {}),
  },
  networks: {
    // Mạng thử công khai. RPC và khoá đọc từ kho khoá mã hoá của Hardhat:
    //   npx hardhat keystore set SEPOLIA_RPC_URL
    //   npx hardhat keystore set SEPOLIA_PRIVATE_KEY      (ví RIÊNG cho học tập)
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
});
