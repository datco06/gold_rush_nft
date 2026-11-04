// Chép ABI sang app (để tham khảo / dùng với web3dart nếu muốn) — app hiện mã hoá lời gọi bằng tay.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const { abi } = JSON.parse(readFileSync(
  "artifacts/contracts/CuaHangGoldRush.sol/CuaHangGoldRush.json", "utf8"));
mkdirSync("../gold_rush/assets/abi", { recursive: true });
writeFileSync("../gold_rush/assets/abi/cua_hang_gold_rush.json", JSON.stringify(abi, null, 2));
console.log("Đã ghi ../gold_rush/assets/abi/cua_hang_gold_rush.json");
