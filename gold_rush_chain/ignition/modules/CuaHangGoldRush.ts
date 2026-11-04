import { readFileSync } from "node:fs";
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Danh sách màn chơi: MỘT nguồn sự thật dùng chung với app và máy chủ trọng tài.
// Đặt gold_rush/ và gold_rush_chain/ cạnh nhau như trong tệp zip.
const MAN_CHOI: { id: number; coc: number; thuong: number; so_xu: number }[] = JSON.parse(
  readFileSync(new URL("../../../gold_rush/assets/tiles/man_choi.json", import.meta.url), "utf8"),
).man;

// Triển khai + đặt giá 3 nhân vật + mở các màn chơi trong một lần chạy.
//   npx hardhat ignition deploy ./ignition/modules/CuaHangGoldRush.ts --network localhost
//   Sepolia: thêm --parameters '{"CuaHangGoldRushModule":{"trongTai":"<địa chỉ khoá trọng tài MỚI>"}}'
export default buildModule("CuaHangGoldRushModule", (m) => {
  // Mặc định: tài khoản thử #1 của Hardhat — CHỈ hợp lệ trên mạng cục bộ 31337.
  const trongTai = m.getParameter("trongTai", "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
  const uri = m.getParameter("uri", "https://example.invalid/goldrush/{id}.json");

  const cuaHang = m.contract("CuaHangGoldRush", [trongTai, uri]);

  // id → giá (vàng). Khớp bangNhanVat trong lib/blockchain/nhan_vat.dart của app.
  m.call(cuaHang, "datGia", [1n, 10n], { id: "gia_tho_mo" });
  m.call(cuaHang, "datGia", [2n, 30n], { id: "gia_cao_boi" });
  m.call(cuaHang, "datGia", [3n, 60n], { id: "gia_hiep_si" });

  // thuongToiDa = số xu trên bản đồ + thưởng hoàn thành (trần của một phiếu, chưa gồm cọc hoàn lại)
  for (const man of MAN_CHOI) {
    m.call(cuaHang, "datMan", [BigInt(man.id), BigInt(man.coc), BigInt(man.so_xu + man.thuong)], {
      id: `man_${man.id}`,
    });
  }
  return { cuaHang };
});
