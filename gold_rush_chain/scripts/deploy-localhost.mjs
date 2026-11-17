/**
 * Script triển khai CharacterRegistry.sol lên mạng Hardhat Localhost (Chain ID: 31337).
 *
 * Cách sử dụng:
 * 1. Khởi động local node ở 1 terminal:
 *    cd gold_rush_chain && npx hardhat node
 *
 * 2. Chạy script deploy:
 *    export PATH="/Users/nguyenquangdat/.nvm/versions/node/v22.23.4/bin:$PATH"
 *    cd gold_rush_chain && node scripts/deploy-localhost.mjs
 *
 * Tuân thủ bảo mật:
 * - Không hardcode private key thật (chỉ dùng khóa dev công khai của Hardhat 31337 khi dev cục bộ).
 * - Cho phép ghi đè qua biến môi trường: DEPLOYER_PRIVATE_KEY, BACKEND_SIGNER_ADDRESS, RPC_URL.
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createWalletClient, createPublicClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { hardhat } from "viem/chains";

const __dirname = dirname(fileURLToPath(import.meta.url));
const chainDir = resolve(__dirname, "..");

const rpcUrl = process.env.RPC_URL || "http://127.0.0.1:8545";

// Khóa công khai mặc định của Hardhat Node Account #0 (chỉ dùng cho local test):
// 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
const defaultDevKey = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const deployerKey = process.env.DEPLOYER_PRIVATE_KEY || defaultDevKey;

// Hardhat Node Account #1 dùng làm Backend AI Signer mặc định:
// 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
const defaultSigner = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
const backendSignerAddress = process.env.BACKEND_SIGNER_ADDRESS || defaultSigner;

async function deploy() {
  console.log("==================================================");
  console.log("🚀 Bắt đầu triển khai CharacterRegistry lên Localhost");
  console.log("==================================================");

  const artifactPath = resolve(chainDir, "artifacts/contracts/CharacterRegistry.sol/CharacterRegistry.json");
  let artifact;
  try {
    artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  } catch (err) {
    console.error("❌ Chưa biên dịch hợp đồng. Hãy chạy 'npx hardhat compile' trước.");
    process.exit(1);
  }

  const account = privateKeyToAccount(deployerKey);
  const client = createWalletClient({
    account,
    chain: hardhat,
    transport: http(rpcUrl),
  });

  const publicClient = createPublicClient({
    chain: hardhat,
    transport: http(rpcUrl),
  });

  try {
    const chainId = await publicClient.getChainId();
    console.log(`📡 Kết nối node: ${rpcUrl} (Chain ID: ${chainId})`);
    console.log(`👤 Deployer: ${account.address}`);
    console.log(`🔑 Backend AI Signer: ${backendSignerAddress}`);

    console.log("⏳ Đang gửi giao dịch deploy...");
    const hash = await client.deployContract({
      abi: artifact.abi,
      bytecode: artifact.bytecode,
      args: [account.address, backendSignerAddress],
    });
    console.log(`📝 Transaction Hash: ${hash}`);

    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    const contractAddress = receipt.contractAddress;
    console.log(`🎉 CharacterRegistry đã deploy thành công tại: ${contractAddress}`);

    // Ghi lại thông tin triển khai vào gold_rush_chain/deployments/
    const deployDir = resolve(chainDir, "deployments");
    mkdirSync(deployDir, { recursive: true });
    const deployInfo = {
      contractName: "CharacterRegistry",
      contractAddress,
      chainId,
      transactionHash: hash,
      deployer: account.address,
      authorizedSigner: backendSignerAddress,
      deployedAt: new Date().toISOString(),
    };

    const deployFilePath = resolve(deployDir, "localhost-character-registry.json");
    writeFileSync(deployFilePath, JSON.stringify(deployInfo, null, 2));
    console.log(`💾 Đã lưu thông tin deployment: ${deployFilePath}`);

    console.log("\n--------------------------------------------------");
    console.log("📋 Cấu hình môi trường cho Backend AI (.env):");
    console.log(`AI_BLOCKCHAIN_RPC_URL=${rpcUrl}`);
    console.log(`AI_BLOCKCHAIN_CHAIN_ID=${chainId}`);
    console.log(`AI_CHARACTER_REGISTRY_ADDRESS=${contractAddress}`);
    console.log("--------------------------------------------------\n");
  } catch (err) {
    console.error("❌ Lỗi trong quá trình deploy:", err.message);
    console.error("💡 Gợi ý: Hãy đảm bảo 'npx hardhat node' đang chạy tại cổng 8545.");
    process.exit(1);
  }
}

deploy();
