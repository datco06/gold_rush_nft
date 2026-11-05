import { randomBytes } from "node:crypto";
import { network } from "hardhat";
import {
  BaseError,
  ContractFunctionRevertedError,
  getAddress,
  hashTypedData,
  isAddress,
  isAddressEqual,
  toHex,
  zeroAddress,
} from "viem";

// Chạy: SBT_ADDRESS=0x... npx hardhat run scripts/demo_sbt.ts --network localhost
// Tùy chọn: SBT_ACHIEVEMENT_ID=2 (mặc định 1; dùng ID chưa nhận để chạy lại).
// Chỉ dùng tài khoản được node Hardhat mở khóa; không đọc private key.
const TYPES = {
  PhieuSBT: [
    { name: "player", type: "address" },
    { name: "achievementId", type: "uint256" },
    { name: "nonce", type: "bytes32" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

async function main() {
  const configuredAddress = process.env.SBT_ADDRESS?.trim();
  if (!configuredAddress || !isAddress(configuredAddress) || isAddressEqual(configuredAddress, zeroAddress)) {
    throw new Error("Đặt SBT_ADDRESS thành địa chỉ ThanhTuuSBT đã deploy trên node local đang chạy.");
  }
  const address = getAddress(configuredAddress);
  const configuredId = process.env.SBT_ACHIEVEMENT_ID?.trim() ?? "1";
  if (!/^[1-5]$/.test(configuredId)) {
    throw new Error("SBT_ACHIEVEMENT_ID phải là số nguyên từ 1 đến 5.");
  }
  const achievementId = BigInt(configuredId);

  // Hardhat 3: lấy viem từ NetworkConnection, không dùng ethers của Hardhat 2.
  const connection = await network.create();
  try {
    if (connection.networkName !== "localhost" || connection.networkConfig.type !== "http") {
      throw new Error("Demo này yêu cầu node local đang chạy. Thêm --network localhost vào lệnh hardhat run.");
    }
    // Xác nhận RPC thực sự là Hardhat, không chỉ dựa vào tên mạng hoặc chainId.
    await connection.provider.request({ method: "hardhat_metadata", params: [] });
    const { viem } = connection;
    const publicClient = await viem.getPublicClient();
    const code = await publicClient.getCode({ address });
    if (!code || code === "0x") {
      throw new Error(`Không có hợp đồng tại ${address} trên node này. Kiểm tra SBT_ADDRESS và deploy lại nếu node đã khởi động lại.`);
    }
    const sbt = await viem.getContractAt("ThanhTuuSBT", address);
    const signerAddress = await sbt.read.signer();
    const wallets = await viem.getWalletClients();
    const backendSigner = wallets.find((wallet) => isAddressEqual(wallet.account.address, signerAddress));
    if (!backendSigner) {
      throw new Error(`Signer ${signerAddress} không nằm trong các tài khoản thử nghiệm của node. Deploy local với Backend signer là một tài khoản Hardhat.`);
    }
    // Ưu tiên tài khoản #2 như unit test; giữ signer và người chơi là hai ví riêng.
    const player = wallets.slice(2).find((wallet) => !isAddressEqual(wallet.account.address, signerAddress));
    if (!player) throw new Error("Node cần có tài khoản thử nghiệm cho người chơi, khác Backend signer.");

    const chainId = await publicClient.getChainId();
    const [fields, name, version, domainChainId, verifyingContract] = await sbt.read.eip712Domain();
    if (fields !== "0x0f" || name !== "GoldRushSBT" || version !== "1"
      || domainChainId !== BigInt(chainId) || !isAddressEqual(verifyingContract, address)) {
      throw new Error("Domain của hợp đồng không khớp ThanhTuuSBT: GoldRushSBT / 1 / chainId hiện tại / SBT_ADDRESS.");
    }
    const domain = { name, version, chainId, verifyingContract: address };
    if (await sbt.read.hasAchievement([player.account.address, achievementId])) {
      throw new Error(`Ví ${player.account.address} đã có thành tích ${achievementId}. Chọn SBT_ACHIEVEMENT_ID chưa nhận hoặc deploy hợp đồng local mới.`);
    }

    async function createVoucher() {
      const p = {
        player: player!.account.address,
        achievementId,
        nonce: toHex(randomBytes(32)),
        deadline: (await publicClient.getBlock()).timestamp + 900n,
      };
      const digest = hashTypedData({ domain, types: TYPES, primaryType: "PhieuSBT", message: p });
      if (digest !== await sbt.read.hashVoucher([p])) {
        throw new Error("Digest EIP-712 của viem không khớp hashVoucher trên hợp đồng.");
      }
      const signature = await backendSigner!.signTypedData({
        account: backendSigner!.account,
        domain,
        types: TYPES,
        primaryType: "PhieuSBT",
        message: p,
      });
      return { p, signature };
    }

    const voucher = await createVoucher();
    console.log(`Hợp đồng SBT: ${address}`);
    console.log(`Chain ID: ${chainId}`);
    console.log(`Backend signer: ${backendSigner.account.address}`);
    console.log(`Ví người chơi: ${player.account.address}`);
    console.log(`Achievement ID: ${achievementId}`);

    const hash = await sbt.write.claimSBT([voucher.p, voucher.signature], { account: player.account });
    console.log(`Transaction hash: ${hash}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash, confirmations: 1, timeout: 60_000 });
    if (receipt.status !== "success") throw new Error(`Giao dịch claimSBT thất bại: ${hash}`);
    console.log(`Đã xác nhận tại block: ${receipt.blockNumber}`);
    const ownsAchievement = await sbt.read.hasAchievement([player.account.address, achievementId]);
    console.log(`hasAchievement: ${ownsAchievement}`);
    if (!ownsAchievement || !await sbt.read.usedNonces([voucher.p.nonce])) {
      throw new Error("Giao dịch đã xác nhận nhưng trạng thái thành tích/nonce không đúng.");
    }

    async function expectRejected(v: Awaited<ReturnType<typeof createVoucher>>, expected: string) {
      // viem thường phát hiện revert khi ước lượng gas, trước khi gửi giao dịch.
      try {
        const duplicateHash = await sbt.write.claimSBT([v.p, v.signature], { account: player!.account });
        await publicClient.waitForTransactionReceipt({ hash: duplicateHash, timeout: 60_000 });
      } catch (error) {
        const cause = error instanceof BaseError
          ? error.walk((e) => e instanceof ContractFunctionRevertedError) : undefined;
        if (!(cause instanceof ContractFunctionRevertedError) || cause.data?.errorName !== expected) throw error;
        console.log(`Hợp đồng từ chối đúng dự kiến: ${expected}`);
        return;
      }
      throw new Error(`Không xác minh được lỗi ${expected}: giao dịch không bị từ chối như dự kiến.`);
    }

    // Phiếu mới có chữ ký hợp lệ + nonce mới: chứng minh chống nhận trùng thành tích.
    const duplicate = await createVoucher();
    await expectRejected(duplicate, "AchievementAlreadyClaimed");
    // Gửi lại đúng phiếu cũ: chứng minh chống replay nonce đã sử dụng.
    await expectRejected(voucher, "NonceAlreadyUsed");
    if (await sbt.read.usedNonces([duplicate.p.nonce])
      || !await sbt.read.hasAchievement([player.account.address, achievementId])) {
      throw new Error("Trạng thái sau khi từ chối nhận trùng không đúng.");
    }
    console.log("Demo SBT thành công: đã nhận thành tích, chặn nhận trùng và chặn dùng lại phiếu.");
  } finally {
    await connection.close();
  }
}

try {
  await main();
} catch (error) {
  console.error("Demo SBT thất bại:", error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
