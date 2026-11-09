import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Module triển khai CharacterRegistry bằng Hardhat Ignition.
 *
 * Sử dụng:
 * 1. Chạy node localhost:
 *    npx hardhat node
 *
 * 2. Triển khai lên localhost:
 *    npx hardhat ignition deploy ./ignition/modules/CharacterRegistry.ts --network localhost
 *
 * 3. Triển khai lên Sepolia testnet (không hardcode private key):
 *    npx hardhat ignition deploy ./ignition/modules/CharacterRegistry.ts --network sepolia \
 *      --parameters '{"CharacterRegistryModule":{"backendSigner":"<ĐỊA_CHỈ_VÍ_BACKEND_AI>"}}'
 */
export default buildModule("CharacterRegistryModule", (m) => {
  // Tài khoản deploy mặc định là account 0 của ví
  const owner = m.getAccount(0);

  // Địa chỉ backendSigner mặc định cho mạng thử nghiệm cục bộ (Hardhat Account #1)
  // 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
  const defaultSigner = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  const backendSigner = m.getParameter("backendSigner", defaultSigner);

  const characterRegistry = m.contract("CharacterRegistry", [owner, backendSigner]);

  return { characterRegistry };
});
