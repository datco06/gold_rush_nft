import { network } from "hardhat";
import { getAddress, isAddress, isAddressEqual } from "viem";

// Cập nhật giá cho contract ĐÃ deploy, không tạo contract mới.
// Chạy bằng ví owner của CuaHangGoldRush:
// STORE_ADDRESS=0x... npx hardhat run scripts/cap_nhat_gia_theo_fe.ts --network sepolia

// Khớp bangNhanVat + _priceForItem trong gold_rush/lib.
const GIA_NHAN_VAT = [10n, 30n, 60n, 400n, 500n, 600n, 600n, 600n, 600n];
const GIA_VAT_PHAM = [
  1n, 50n, 120n, 260n, 480n, 420n, 100000n, 100000n, 100000n,
  80n, 80n, 80n, 220n, 220n, 220n, 100000n, 100000n, 100000n,
  80n, 80n, 80n, 220n, 220n, 220n, 100000n, 100000n, 100000n,
];

async function main() {
  const rawAddress = process.env.STORE_ADDRESS?.trim();
  if (!rawAddress || !isAddress(rawAddress)) {
    throw new Error("STORE_ADDRESS phải là địa chỉ CuaHangGoldRush đã deploy.");
  }

  const connection = await network.create();
  try {
    const { viem } = connection;
    const publicClient = await viem.getPublicClient();
    const address = getAddress(rawAddress);
    const store = await viem.getContractAt("CuaHangGoldRush", address);
    const ownerAddress = await store.read.owner();
    const owner = (await viem.getWalletClients()).find((wallet) =>
      isAddressEqual(wallet.account.address, ownerAddress),
    );
    if (!owner) {
      throw new Error(
        `Ví đang cấu hình không phải owner (${ownerAddress}). ` +
        "Hãy dùng đúng ví owner, không đưa private key vào mã nguồn.",
      );
    }

    const capNhat = async (loai: string, id: bigint, gia: bigint) => {
      const hienTai = loai === "nhân vật"
        ? await store.read.gia([id])
        : await store.read.giaVatPham([id]);
      if (hienTai === gia) {
        console.log(`${loai} ${id}: ${gia} — đã đúng`);
        return;
      }
      const hash = loai === "nhân vật"
        ? await store.write.datGia([id, gia], { account: owner.account })
        : await store.write.datGiaVatPham([id, gia], { account: owner.account });
      await publicClient.waitForTransactionReceipt({ hash, confirmations: 1 });
      console.log(`${loai} ${id}: ${hienTai} → ${gia} — ${hash}`);
    };

    for (let i = 0; i < GIA_NHAN_VAT.length; i++) {
      await capNhat("nhân vật", BigInt(i + 1), GIA_NHAN_VAT[i]);
    }
    for (let i = 0; i < GIA_VAT_PHAM.length; i++) {
      await capNhat("vật phẩm", BigInt(i + 1), GIA_VAT_PHAM[i]);
    }
  } finally {
    await connection.close();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
