import { readFileSync } from "node:fs";
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Danh sách màn chơi: MỘT nguồn sự thật dùng chung với app và máy chủ trọng tài.
// Đặt gold_rush/ và gold_rush_chain/ cạnh nhau như trong tệp zip.
const MAN_CHOI: { id: number; coc: number; thuong: number; so_xu: number }[] = JSON.parse(
  readFileSync(new URL("../../../gold_rush/assets/tiles/man_choi.json", import.meta.url), "utf8"),
).man;

// Triển khai + đặt giá các nhân vật + mở các màn chơi trong một lần chạy.
//   npx hardhat ignition deploy ./ignition/modules/CuaHangGoldRush.ts --network localhost
//   Sepolia: thêm --parameters '{"CuaHangGoldRushModule":{"trongTai":"<địa chỉ khoá trọng tài MỚI>"}}'
export default buildModule("CuaHangGoldRushModule", (m) => {
  // Mặc định: tài khoản thử #1 của Hardhat — CHỈ hợp lệ trên mạng cục bộ 31337.
  const trongTai = m.getParameter("trongTai", "0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
  const owner = m.getAccount(0);
  const backendSigner = m.getParameter(
    "backendSigner",
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  );
  const uri = m.getParameter("uri", "https://example.invalid/goldrush/{id}.json");

  const cuaHang = m.contract("CuaHangGoldRush", [trongTai, uri]);
  const vatPham = m.contract("VatPhamGoldRush", [owner, backendSigner]);

  // Liên kết hai hợp đồng: Cửa hàng burn vàng, VatPhamGoldRush mint NFT.
  m.call(cuaHang, "datHopDongVatPham", [vatPham], { id: "cau_hinh_hop_dong_vat_pham" });
  m.call(vatPham, "setStore", [cuaHang], { id: "cau_hinh_cua_hang_mint" });

  // id → giá (vàng). Khớp bangNhanVat trong lib/blockchain/nhan_vat.dart của app.
  m.call(cuaHang, "datGia", [1n, 10n], { id: "gia_tho_mo" });
  m.call(cuaHang, "datGia", [2n, 30n], { id: "gia_cao_boi" });
  m.call(cuaHang, "datGia", [3n, 60n], { id: "gia_hiep_si" });
  m.call(cuaHang, "datGia", [4n, 400n], { id: "gia_tho_mo_pixel" });
  m.call(cuaHang, "datGia", [5n, 500n], { id: "gia_meo_may_vang" });
  m.call(cuaHang, "datGia", [6n, 600n], { id: "gia_nha_tham_hiem_nu" });
  m.call(cuaHang, "datGia", [7n, 600n], { id: "gia_nha_tham_hiem_dao_vang" });
  m.call(cuaHang, "datGia", [8n, 600n], { id: "gia_nha_tham_hiem_con_sot_vang" });
  m.call(cuaHang, "datGia", [9n, 600n], { id: "gia_tho_mo_chibi" });

  // 27 token ID khớp thứ tự danhSachTrangBiCuaHang(): 1–9 súng,
  // 10–18 giáp, 19–27 giày. Vật phẩm hiếm có giá 100.000 vàng.
  const giaVatPham = [
    1n, 50n, 120n, 260n, 480n, 420n, 100000n, 100000n, 100000n,
    80n, 80n, 80n, 220n, 220n, 220n, 100000n, 100000n, 100000n,
    80n, 80n, 80n, 220n, 220n, 220n, 100000n, 100000n, 100000n,
  ];
  for (let i = 0; i < giaVatPham.length; i++) {
    const tokenId = BigInt(i + 1);
    m.call(
      vatPham,
      "registerItem",
      [tokenId, `https://example.invalid/goldrush/items/${i + 1}.json`, 1_000_000n],
      { id: `dang_ky_vat_pham_${i + 1}` },
    );
    m.call(cuaHang, "datGiaVatPham", [tokenId, giaVatPham[i]], { id: `gia_vat_pham_${i + 1}` });
  }

  // thuongToiDa = số xu trên bản đồ + thưởng hoàn thành (trần của một phiếu, chưa gồm cọc hoàn lại)
  for (const man of MAN_CHOI) {
    m.call(cuaHang, "datMan", [BigInt(man.id), BigInt(man.coc), BigInt(man.so_xu + man.thuong)], {
      id: `man_${man.id}`,
    });
  }
  return { cuaHang, vatPham };
});
