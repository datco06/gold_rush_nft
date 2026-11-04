# gold_rush_chain — hợp đồng cửa hàng nhân vật, bản 2 (nhiều màn, cọc vào màn)

**Chỉ triển khai trên mạng cục bộ (Hardhat 31337) hoặc mạng thử nghiệm (Sepolia).**
Vàng và nhân vật KHÔNG chuyển nhượng được và không có giá trị quy đổi — xem mục pháp lý trong
tài liệu đề xuất (Nghị định 147/2024/NĐ-CP, Điều 57).

```bash
npm install                             # hardhat 3, toolbox-viem, @openzeppelin/contracts 5.7.0 (package.json)
npx hardhat test                        # 19 phép kiểm thử, gồm đối chiếu với máy chủ Python và calldata của app
#   Mạng chặn binaries.soliditylang.org? tải solc-static-linux 0.8.36 (GitHub Releases của Solidity) rồi:
#   SOLC_PATH=/duong/dan/solc npx hardhat test

# Terminal 1
npx hardhat node                        # http://127.0.0.1:8545, chainId 31337
# Terminal 2 — triển khai, đặt giá 3 nhân vật, mở 6 màn (đọc ../gold_rush/assets/tiles/man_choi.json)
npx hardhat ignition deploy ./ignition/modules/CuaHangGoldRush.ts --network localhost
#   → CuaHangGoldRushModule#CuaHangGoldRush - 0x5FbDB2315678afecb367f032d93F642f64180aa3
```

Khởi động lại `hardhat node` = chuỗi mới tinh: xoá `ignition/deployments/chain-31337/`, triển khai lại,
và trong MetaMask chọn *Cài đặt → Nâng cao → Xoá dữ liệu tab hoạt động* (nếu không sẽ gặp lỗi nonce).

Máy chủ trọng tài (`gold_rush_ai`) cần ba biến môi trường:

```bash
export TRONG_TAI_KHOA=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d  # khoá thử #1 — CHỈ 31337
export CHAIN_ID=31337
export HOP_DONG_CUA_HANG=0x5FbDB2315678afecb367f032d93F642f64180aa3
```

| Tệp | Vai trò |
|---|---|
| `contracts/CuaHangGoldRush.sol` | ERC-1155 + EIP-712 + Multicall: vàng, nhân vật, màn chơi, vé (cọc); không chuyển nhượng |
| `test/CuaHangGoldRush.ts` | 19 phép kiểm thử (node:test + viem) |
| `du-lieu-kiem-thu/phieu_mau.json` | 2 phiếu do máy chủ Python ký — `gold_rush_ai/scripts/sinh_phieu_mau.py` |
| `ignition/modules/CuaHangGoldRush.ts` | triển khai + giá nhân vật + `datMan` cho từng màn |
| `scripts/xuat-abi.mjs` | chép ABI sang `../gold_rush/assets/abi/` |

| Hàm | Ai gọi | Việc |
|---|---|---|
| `vaoMan(man)` | người chơi | đốt `coc` vàng, cấp vé mới (vé cũ chưa dùng → sự kiện `MatCoc`) |
| `nhanVang(phieu, chuKy)` | người chơi | phiếu luyện tập: đúc xu; phiếu màn có cọc (đúng vé): đúc cọc + xu + thưởng |
| `mua(nhanVat)` | người chơi | đốt vàng, đúc 1 nhân vật |
| `multicall(bytes[])` | người chơi | gộp các lời gọi trên vào MỘT giao dịch, nguyên tử |
| `datMan`, `datGia`, `doiTrongTai` | chủ hợp đồng | cấu hình |
