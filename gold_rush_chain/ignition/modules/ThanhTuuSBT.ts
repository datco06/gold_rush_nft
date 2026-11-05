import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Tham số bắt buộc trên mọi mạng, không tự dùng ví thử nghiệm trên testnet.
// Truyền bằng --parameters với cấu trúc:
// { "ThanhTuuSBTModule": { "owner": "0x...", "backendSigner": "0x..." } }
// Local: có thể truyền địa chỉ tài khoản thử #0 và #1 của Hardhat.
// Sepolia: phải truyền địa chỉ owner và Backend signer thực tế.
// Đây chỉ là địa chỉ công khai; không đặt private key trong module/tham số.
export default buildModule("ThanhTuuSBTModule", (m) => {
  const owner = m.getParameter<string>("owner");
  const backendSigner = m.getParameter<string>("backendSigner");

  // Constructor Solidity: (address initialOwner, address initialSigner).
  // Tài khoản gửi giao dịch deploy được Hardhat/Ignition quản lý riêng.
  const thanhTuuSBT = m.contract("ThanhTuuSBT", [owner, backendSigner]);

  return { thanhTuuSBT };
});
