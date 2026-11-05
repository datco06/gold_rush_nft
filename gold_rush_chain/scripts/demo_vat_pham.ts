import { randomBytes } from "node:crypto";
import { network } from "hardhat";
import {
  BaseError,
  ContractFunctionRevertedError,
  getAddress,
  hashTypedData,
  isAddress,
  isAddressEqual,
  maxUint256,
  toHex,
  zeroAddress,
  type Hex,
} from "viem";

// NFT_ADDRESS=0x... npx hardhat run scripts/demo_vat_pham.ts --network localhost
// NFT_TOKEN_ID=2 để dùng loại khác (mặc định 1). Mỗi lần chạy tạo nonce mới.
// Chỉ dùng tài khoản được Hardhat node mở khóa, không đọc private key.
const TYPES = {
  PhieuVatPham: [
    { name: "player", type: "address" },
    { name: "tokenId", type: "uint256" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "bytes32" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

class ConfigurationError extends Error {}
class TransactionError extends Error {}

function ensure(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(`Xác minh thất bại: ${message}`);
}

async function main() {
  const configuredAddress = process.env.NFT_ADDRESS?.trim();
  if (!configuredAddress || !isAddress(configuredAddress) || isAddressEqual(configuredAddress, zeroAddress)) {
    throw new ConfigurationError("Đặt NFT_ADDRESS thành địa chỉ VatPhamGoldRush đã deploy trên node localhost đang chạy.");
  }
  const address = getAddress(configuredAddress);
  const configuredId = process.env.NFT_TOKEN_ID?.trim() ?? "1";
  if (!/^[1-9][0-9]*$/.test(configuredId) || configuredId.length > 78 || BigInt(configuredId) > maxUint256) {
    throw new ConfigurationError("NFT_TOKEN_ID phải là số nguyên dương trong phạm vi uint256 (mặc định 1).");
  }
  const tokenId = BigInt(configuredId);
  const amount = 1n;
  const connection = await network.create();

  try {
    if (connection.networkName !== "localhost" || connection.networkConfig.type !== "http") {
      throw new ConfigurationError("Chạy Hardhat node ở Terminal 1 và thêm --network localhost vào lệnh hardhat run.");
    }
    const { viem } = connection;
    const publicClient = await viem.getPublicClient();
    let chainId: number;
    try {
      // Không chỉ tin vào tên mạng: xác nhận RPC hỗ trợ API riêng của Hardhat.
      await connection.provider.request({ method: "hardhat_metadata", params: [] });
      chainId = await publicClient.getChainId();
    } catch (cause) {
      throw new ConfigurationError("Không kết nối được Hardhat localhost. Hãy chạy npx hardhat node và kiểm tra RPC localhost:8545.", { cause });
    }
    if (chainId !== 31337) throw new ConfigurationError(`Demo yêu cầu chain ID 31337, RPC đang trả về ${chainId}.`);
    console.log(`Hợp đồng NFT: ${address}`);
    console.log(`Chain ID: ${chainId}`);

    const code = await publicClient.getCode({ address });
    if (!code || code === "0x") {
      throw new ConfigurationError(`Không có hợp đồng tại ${address}. Kiểm tra NFT_ADDRESS; nếu reset node, hãy deploy lại.`);
    }
    const nft = await viem.getContractAt("VatPhamGoldRush", address);
    // Kiểm tra ABI/domain trước bất kỳ giao dịch ghi nào.
    const settings = await (async () => {
      try {
        return {
          ownerAddress: await nft.read.owner(),
          signerAddress: await nft.read.signer(),
          domain: await nft.read.eip712Domain(),
        };
      } catch (cause) {
        throw new ConfigurationError("NFT_ADDRESS không đọc được bằng ABI VatPhamGoldRush. Kiểm tra địa chỉ và mạng deploy.", { cause });
      }
    })();
    const [fields, name, version, domainChainId, verifyingContract] = settings.domain;
    if (fields !== "0x0f" || name !== "GoldRushEquipment" || version !== "1"
      || domainChainId !== BigInt(chainId) || !isAddressEqual(verifyingContract, address)) {
      throw new ConfigurationError("Domain phải là GoldRushEquipment / 1 / 31337 / NFT_ADDRESS.");
    }
    const domain = { name, version, chainId, verifyingContract: address };
    const wallets = await viem.getWalletClients();
    const localOwner = wallets.find((wallet) => isAddressEqual(wallet.account.address, settings.ownerAddress));
    const localBackendSigner = wallets.find((wallet) => isAddressEqual(wallet.account.address, settings.signerAddress));
    if (!localOwner || !localBackendSigner) {
      throw new ConfigurationError(
        `Owner ${settings.ownerAddress} hoặc signer ${settings.signerAddress} không có trong ví Hardhat local. `
        + "Deploy lại bằng địa chỉ công khai của tài khoản Hardhat #0 (owner) và #1 (backendSigner).",
      );
    }
    const owner = localOwner;
    const backendSigner = localBackendSigner;
    if (isAddressEqual(owner.account.address, backendSigner.account.address)) {
      throw new ConfigurationError("Demo cần owner và backendSigner là hai tài khoản Hardhat khác nhau.");
    }
    const players = wallets.filter((wallet) => !isAddressEqual(wallet.account.address, owner.account.address)
      && !isAddressEqual(wallet.account.address, backendSigner.account.address));
    const [playerA, playerB] = players;
    if (!playerA || !playerB) throw new ConfigurationError("Cần ít nhất 4 tài khoản local cho owner, backendSigner, playerA và playerB.");
    console.log(`Owner: ${owner.account.address}`);
    console.log(`Backend signer: ${backendSigner.account.address}`);
    console.log(`Ví A: ${playerA.account.address}`);
    console.log(`Ví B: ${playerB.account.address}`);
    console.log(`Token ID: ${tokenId}${tokenId === 1n ? " — Kiếm Vàng" : " — vật phẩm demo"}`);
    console.log(`Số lượng nhận/chuyển: ${amount}`);

    async function transact(label: string, send: () => Promise<Hex>) {
      try {
        const hash = await send();
        console.log(`${label} — transaction hash: ${hash}`);
        const receipt = await publicClient.waitForTransactionReceipt({ hash, confirmations: 1, timeout: 60_000 });
        if (receipt.status !== "success") throw new Error(`Receipt có trạng thái ${receipt.status}: ${hash}`);
        console.log(`${label} — xác nhận tại block: ${receipt.blockNumber}`);
        return receipt;
      } catch (cause) {
        throw new TransactionError(`${label} thất bại: ${cause instanceof Error ? cause.message : String(cause)}`, { cause });
      }
    }

    if (await nft.read.registered([tokenId])) {
      console.log(`Vật phẩm ${tokenId} đã đăng ký; giữ nguyên URI và maxSupply.`);
    } else {
      const metadataURI = `https://example.invalid/goldrush/items/${tokenId}.json`;
      // URI minh họa; demo không cần tải metadata. Cap 10 cho phép chạy lại nhiều lần.
      await transact("Đăng ký vật phẩm", () => nft.write.registerItem([tokenId, metadataURI, 10n], { account: owner.account }));
      ensure(await nft.read.registered([tokenId]), "vật phẩm chưa được đăng ký sau giao dịch.");
      console.log(`Đã đăng ký URI thử nghiệm: ${metadataURI}`);
    }
    const cap = await nft.read.maxSupply([tokenId]);
    const mintedBefore = await nft.read.totalMinted([tokenId]);
    console.log(`Metadata URI: ${await nft.read.uri([tokenId])}`);
    console.log(`Tổng đã mint / giới hạn: ${mintedBefore} / ${cap}`);
    ensure(mintedBefore <= cap, "totalMinted lớn hơn maxSupply.");
    if (cap - mintedBefore < amount) {
      throw new ConfigurationError(
        `Token ${tokenId} đã hết nguồn cung (${mintedBefore}/${cap}). `
        + "Chọn NFT_TOKEN_ID mới chưa đăng ký hoặc reset node local rồi deploy lại. "
        + "Nonce mới không vượt được maxSupply; không thể tăng cap sau lần mint đầu tiên.",
      );
    }

    async function createVoucher() {
      // Nonce ngẫu nhiên 32 byte và kiểm tra on-chain để hỗ trợ chạy lại an toàn.
      let nonce: Hex;
      do { nonce = toHex(randomBytes(32)); } while (await nft.read.usedNonces([nonce]));
      const p = {
        player: playerA.account.address, tokenId, amount, nonce,
        deadline: (await publicClient.getBlock()).timestamp + 900n,
      };
      ensure(hashTypedData({ domain, types: TYPES, primaryType: "PhieuVatPham", message: p })
        === await nft.read.hashVoucher([p]), "digest EIP-712 của viem không khớp hashVoucher.");
      const signature = await backendSigner.signTypedData({
        account: backendSigner.account, domain, types: TYPES, primaryType: "PhieuVatPham", message: p,
      });
      return { p, signature };
    }

    const voucher = await createVoucher();
    console.log(`Nonce phiếu: ${voucher.p.nonce}`);
    const aBeforeMint = await nft.read.balanceOf([playerA.account.address, tokenId]);
    console.log(`Số dư A trước mint: ${aBeforeMint}`);
    await transact("Mint claimItem", () => nft.write.claimItem([voucher.p, voucher.signature], { account: playerA.account }));
    const aAfterMint = await nft.read.balanceOf([playerA.account.address, tokenId]);
    const mintedAfter = await nft.read.totalMinted([tokenId]);
    ensure(aAfterMint === aBeforeMint + amount, "balanceOf(A) không tăng đúng amount.");
    ensure(mintedAfter === mintedBefore + amount, "totalMinted không tăng đúng amount.");
    ensure(await nft.read.usedNonces([voucher.p.nonce]), "nonce chưa được tiêu thụ sau mint.");
    console.log(`Số dư A sau mint: ${aAfterMint}`);
    console.log(`Tổng đã mint sau nhận NFT: ${mintedAfter}`);

    const aBeforeTransfer = await nft.read.balanceOf([playerA.account.address, tokenId]);
    const bBeforeTransfer = await nft.read.balanceOf([playerB.account.address, tokenId]);
    console.log(`Trước chuyển — A: ${aBeforeTransfer}, B: ${bBeforeTransfer}`);
    await transact("Chuyển safeTransferFrom A → B", () => nft.write.safeTransferFrom([
      playerA.account.address, playerB.account.address, tokenId, amount, "0x",
    ], { account: playerA.account }));
    const aAfterTransfer = await nft.read.balanceOf([playerA.account.address, tokenId]);
    const bAfterTransfer = await nft.read.balanceOf([playerB.account.address, tokenId]);
    ensure(aAfterTransfer === aBeforeTransfer - amount, "số dư A không giảm đúng 1 NFT.");
    ensure(bAfterTransfer === bBeforeTransfer + amount, "số dư B không tăng đúng 1 NFT.");
    ensure(await nft.read.totalMinted([tokenId]) === mintedAfter, "chuyển nhượng làm thay đổi totalMinted.");
    console.log(`Sau chuyển — A: ${aAfterTransfer}, B: ${bAfterTransfer}`);

    async function expectRejected(
      v: Awaited<ReturnType<typeof createVoucher>>, caller: typeof playerA,
      expected: "NonceAlreadyUsed" | "WrongPlayer",
    ) {
      // eth_call mô phỏng chính claimItem trên node: kiểm tra đúng custom error.
      // Không gửi giao dịch cố ý revert, vì receipt thất bại không chứa lý do revert.
      try {
        await publicClient.simulateContract({
          address, abi: nft.abi, functionName: "claimItem", args: [v.p, v.signature], account: caller.account,
        });
      } catch (error) {
        const cause = error instanceof BaseError
          ? error.walk((e) => e instanceof ContractFunctionRevertedError) : undefined;
        if (!(cause instanceof ContractFunctionRevertedError) || cause.data?.errorName !== expected) {
          throw new Error(`Không xác minh được ${expected}: lỗi nhận được không đúng dự kiến.`, { cause: error });
        }
        if (expected === "NonceAlreadyUsed") {
          ensure(cause.data.args?.[0] === v.p.nonce, "NonceAlreadyUsed trả về nonce khác.");
        }
        console.log(`Kiểm tra bảo mật (mô phỏng on-chain): từ chối đúng ${expected}.`);
        return;
      }
      throw new Error(`Kiểm tra bảo mật thất bại: hợp đồng không từ chối ${expected}.`);
    }

    await expectRejected(voucher, playerA, "NonceAlreadyUsed");
    // Phiếu mới chưa dùng để kiểm tra WrongPlayer độc lập với chống replay.
    const otherVoucher = await createVoucher();
    await expectRejected(otherVoucher, playerB, "WrongPlayer");
    ensure(!await nft.read.usedNonces([otherVoucher.p.nonce]), "phiếu bị từ chối vẫn tiêu thụ nonce mới.");
    ensure(await nft.read.usedNonces([voucher.p.nonce]), "nonce phiếu đã mint bị thay đổi.");
    ensure(await nft.read.balanceOf([playerA.account.address, tokenId]) === aAfterTransfer, "kiểm tra bảo mật thay đổi số dư A.");
    ensure(await nft.read.balanceOf([playerB.account.address, tokenId]) === bAfterTransfer, "kiểm tra bảo mật thay đổi số dư B.");
    ensure(await nft.read.totalMinted([tokenId]) === mintedAfter, "kiểm tra bảo mật thay đổi nguồn cung.");
    console.log("Demo NFT thành công: nhận bằng phiếu EIP-712, chuyển A → B, chặn replay và chặn ví khác dùng phiếu.");
  } finally {
    await connection.close();
  }
}

try {
  await main();
} catch (error) {
  const category = error instanceof ConfigurationError ? "Lỗi cấu hình"
    : error instanceof TransactionError ? "Lỗi giao dịch" : "Lỗi kết nối hoặc xác minh";
  console.error(`${category} — demo NFT thất bại:`, error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
