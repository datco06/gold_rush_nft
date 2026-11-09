// Xuất ABI CharacterRegistry độc lập để Flutter và Backend AI tham khảo
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const chainDir = resolve(__dirname, "..");

const artifactPath = resolve(chainDir, "artifacts/contracts/CharacterRegistry.sol/CharacterRegistry.json");
const outputDir = resolve(chainDir, "abi");
const outputPath = resolve(outputDir, "CharacterRegistry.json");

try {
  const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));
  mkdirSync(outputDir, { recursive: true });
  writeFileSync(outputPath, JSON.stringify(artifact.abi, null, 2));
  console.log(`✅ Đã xuất ABI CharacterRegistry thành công tới: ${outputPath}`);
} catch (err) {
  console.error("❌ Lỗi khi xuất ABI:", err.message);
  process.exit(1);
}
