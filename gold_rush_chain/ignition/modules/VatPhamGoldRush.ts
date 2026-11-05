import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Hai tham số bắt buộc, không mặc định dùng ví Hardhat trên testnet.
// File JSON truyền qua --parameters có cấu trúc:
// { "VatPhamGoldRushModule": { "owner": "0x...", "backendSigner": "0x..." } }
// Chỉ truyền địa chỉ công khai, không đặt private key/seed phrase ở đây.
export default buildModule("VatPhamGoldRushModule", (m) => {
  const owner = m.getParameter<string>("owner");
  const backendSigner = m.getParameter<string>("backendSigner");

  // Constructor Solidity: (address initialOwner, address initialSigner).
  // Ví gửi giao dịch deploy do cấu hình mạng Hardhat/Ignition quản lý riêng.
  const vatPhamGoldRush = m.contract("VatPhamGoldRush", [owner, backendSigner]);

  // Sau deploy chưa có loại vật phẩm nào được đăng ký, kể cả các ID 1–4.
  // Owner cần gọi registerItem(tokenId, metadataURI, supplyLimit) cho từng loại:
  // tokenId > 0, URI không rỗng và supplyLimit > 0. Sau đó Backend mới cấp phiếu.
  // setMaxSupply chỉ được phép trước lần mint đầu tiên; setItemURI vẫn đổi được sau mint.
  // Không tự chọn URI/cap hoặc gọi registerItem từ ví deploy thay cho owner.
  return { vatPhamGoldRush };
});
