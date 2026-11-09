import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { keccak256, toHex, stringToHex, getAddress } from "viem";

const VOUCHER_TYPES = {
  CharacterVoucher: [
    { name: "characterId", type: "string" },
    { name: "characterHash", type: "bytes32" },
    { name: "owner", type: "address" },
    { name: "nonce", type: "bytes32" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

/** Helper kiểm tra thông điệp lỗi hoặc tên Custom Error của Solidity. */
const loi = (ten: string) => (e: unknown) => String(e).includes(ten);

async function khoiTao() {
  const { viem } = await network.create();
  const [owner, backendSigner, player1, player2, attacker] = await viem.getWalletClients();
  const pc = await viem.getPublicClient();

  const registry = await viem.deployContract("CharacterRegistry", [
    owner.account.address,
    backendSigner.account.address,
  ]);

  const chainId = await pc.getChainId();
  const currentBlock = await pc.getBlock();
  const bayGio = currentBlock.timestamp;

  let nonceCounter = 0;
  function sinhNonce(id = "") {
    nonceCounter++;
    return keccak256(toHex(`nonce-${id}-${nonceCounter}`));
  }

  async function kyVoucher(
    voucher: {
      characterId: string;
      characterHash: `0x${string}`;
      owner: `0x${string}`;
      nonce: `0x${string}`;
      deadline: bigint;
    },
    signer = backendSigner,
    domainOverrides = {},
  ) {
    const domain = {
      name: "CharacterRegistry",
      version: "1",
      chainId,
      verifyingContract: registry.address,
      ...domainOverrides,
    };

    return await signer.signTypedData({
      account: signer.account,
      domain,
      types: VOUCHER_TYPES,
      primaryType: "CharacterVoucher",
      message: voucher,
    });
  }

  function taoVoucherChuan(
    overrides: Partial<{
      characterId: string;
      characterHash: `0x${string}`;
      owner: `0x${string}`;
      nonce: `0x${string}`;
      deadline: bigint;
    }> = {},
  ) {
    return {
      characterId: "char_" + "1".repeat(32),
      characterHash: ("0x" + "a".repeat(64)) as `0x${string}`,
      owner: player1.account.address,
      nonce: sinhNonce(),
      deadline: bayGio + 3600n,
      ...overrides,
    };
  }

  return {
    viem,
    pc,
    registry,
    owner,
    backendSigner,
    player1,
    player2,
    attacker,
    chainId,
    bayGio,
    sinhNonce,
    kyVoucher,
    taoVoucherChuan,
  };
}

describe("CharacterRegistry — Đăng ký quyền sở hữu nhân vật AI on-chain", () => {
  // 1. Đăng ký thành công với chữ ký hợp lệ
  it("01. Đăng ký thành công với chữ ký EIP-712 hợp lệ", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    const sig = await kyVoucher(v);

    await registry.write.registerCharacter([v, sig], { account: player1.account });

    assert.equal(await registry.read.isCharacterRegistered([v.characterId]), true);
    assert.equal(await registry.read.isCharacterHashRegistered([v.characterHash]), true);
    assert.equal(await registry.read.totalCharacters(), 1n);

    const rec = await registry.read.getCharacter([v.characterId]);
    assert.equal(rec.characterId, v.characterId);
    assert.equal(rec.characterHash, v.characterHash);
    assert.equal(rec.owner.toLowerCase(), player1.account.address.toLowerCase());
    assert.ok(rec.registeredAt > 0n);
  });

  // 2. Đăng ký trùng characterId
  it("02. Ngăn chặn đăng ký trùng characterId", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher, sinhNonce } = await khoiTao();
    const v1 = taoVoucherChuan();
    const sig1 = await kyVoucher(v1);
    await registry.write.registerCharacter([v1, sig1], { account: player1.account });

    // Cố tình dùng lại characterId nhưng đổi hash và nonce khác
    const v2 = taoVoucherChuan({
      characterHash: ("0x" + "b".repeat(64)) as `0x${string}`,
      nonce: sinhNonce(),
    });
    const sig2 = await kyVoucher(v2);

    await assert.rejects(
      registry.write.registerCharacter([v2, sig2], { account: player1.account }),
      loi("CharacterAlreadyRegistered"),
    );
  });

  // 3. Đăng ký trùng characterHash
  it("03. Ngăn chặn đăng ký trùng characterHash (chính sách 1 hash - 1 nhân vật)", async () => {
    const { registry, player1, player2, taoVoucherChuan, kyVoucher, sinhNonce } = await khoiTao();
    const hashChung = ("0x" + "c".repeat(64)) as `0x${string}`;

    const v1 = taoVoucherChuan({
      characterId: "char_" + "1".repeat(32),
      characterHash: hashChung,
    });
    const sig1 = await kyVoucher(v1);
    await registry.write.registerCharacter([v1, sig1], { account: player1.account });

    // Người chơi 2 cố tình đăng ký nhân vật mới nhưng trùng hash đã có
    const v2 = taoVoucherChuan({
      characterId: "char_" + "2".repeat(32),
      characterHash: hashChung,
      owner: player2.account.address,
      nonce: sinhNonce(),
    });
    const sig2 = await kyVoucher(v2);

    await assert.rejects(
      registry.write.registerCharacter([v2, sig2], { account: player2.account }),
      loi("CharacterHashAlreadyRegistered"),
    );
  });

  // 4. Chữ ký giả mạo
  it("04. Từ chối chữ ký giả mạo không hợp lệ", async () => {
    const { registry, player1, taoVoucherChuan } = await khoiTao();
    const v = taoVoucherChuan();
    // Chữ ký 65 bytes giả mạo
    const fakeSig = ("0x" + "1".repeat(130)) as `0x${string}`;

    await assert.rejects(
      registry.write.registerCharacter([v, fakeSig], { account: player1.account }),
      loi("InvalidSignature"),
    );
  });

  // 5. Chữ ký hết hạn
  it("05. Từ chối phiếu đã hết hạn (deadline < block.timestamp)", async () => {
    const { registry, player1, bayGio, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan({ deadline: bayGio - 100n });
    const sig = await kyVoucher(v);

    await assert.rejects(
      registry.write.registerCharacter([v, sig], { account: player1.account }),
      loi("VoucherExpired"),
    );
  });

  // 6. Chữ ký sai chainId
  it("06. Từ chối chữ ký ký cho chainId khác", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    // Ký với chainId 1 thay vì chain cục bộ
    const sigSaiChain = await kyVoucher(v, undefined, { chainId: 1 });

    await assert.rejects(
      registry.write.registerCharacter([v, sigSaiChain], { account: player1.account }),
      loi("InvalidSignature"),
    );
  });

  // 7. Chữ ký dành cho contract khác
  it("07. Từ chối chữ ký ký cho verifyingContract khác", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    const sigSaiContract = await kyVoucher(v, undefined, {
      verifyingContract: "0x9999999999999999999999999999999999999999",
    });

    await assert.rejects(
      registry.write.registerCharacter([v, sigSaiContract], { account: player1.account }),
      loi("InvalidSignature"),
    );
  });

  // 8. Chữ ký dành cho ví khác
  it("08. Từ chối khi người gọi giao dịch không phải voucher.owner", async () => {
    const { registry, player1, attacker, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan({ owner: player1.account.address });
    const sig = await kyVoucher(v);

    // Kẻ gian attacker cố tình lấy voucher của player1 để gửi
    await assert.rejects(
      registry.write.registerCharacter([v, sig], { account: attacker.account }),
      loi("UnauthorizedCaller"),
    );
  });

  // 9. Sai characterHash
  it("09. Từ chối khi voucher bị sửa characterHash sau khi ký", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    const sig = await kyVoucher(v);

    // Kẻ gian sửa hash trong voucher trước khi gửi lên chain
    const tamperedVoucher = {
      ...v,
      characterHash: ("0x" + "f".repeat(64)) as `0x${string}`,
    };

    await assert.rejects(
      registry.write.registerCharacter([tamperedVoucher, sig], { account: player1.account }),
      loi("InvalidSignature"),
    );
  });

  // 10. Chữ ký bị sử dụng lại (Replay nonce)
  it("10. Từ chối khi tái sử dụng nonce (chống replay attack)", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher, sinhNonce } = await khoiTao();
    const nonceChung = sinhNonce();

    const v1 = taoVoucherChuan({
      characterId: "char_" + "1".repeat(32),
      characterHash: ("0x" + "1".repeat(64)) as `0x${string}`,
      nonce: nonceChung,
    });
    const sig1 = await kyVoucher(v1);
    await registry.write.registerCharacter([v1, sig1], { account: player1.account });

    // Phiếu 2 cố tình dùng lại nonce đã ghi nhận
    const v2 = taoVoucherChuan({
      characterId: "char_" + "2".repeat(32),
      characterHash: ("0x" + "2".repeat(64)) as `0x${string}`,
      nonce: nonceChung,
    });
    const sig2 = await kyVoucher(v2);

    await assert.rejects(
      registry.write.registerCharacter([v2, sig2], { account: player1.account }),
      loi("NonceAlreadyUsed"),
    );
  });

  // 11. characterId rỗng hoặc sai định dạng
  it("11. Từ chối characterId rỗng hoặc sai định dạng char_<32_hex>", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher } = await khoiTao();

    // 11a: Rỗng
    const vRong = taoVoucherChuan({ characterId: "" });
    const sigRong = await kyVoucher(vRong);
    await assert.rejects(
      registry.write.registerCharacter([vRong, sigRong], { account: player1.account }),
      loi("InvalidCharacterId"),
    );

    // 11b: Thiếu tiền tố char_
    const vSaiTienTo = taoVoucherChuan({ characterId: "hero_" + "1".repeat(32) });
    const sigSaiTienTo = await kyVoucher(vSaiTienTo);
    await assert.rejects(
      registry.write.registerCharacter([vSaiTienTo, sigSaiTienTo], { account: player1.account }),
      loi("InvalidCharacterId"),
    );

    // 11c: Chứa ký tự không phải hex
    const vKhongHex = taoVoucherChuan({ characterId: "char_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" });
    const sigKhongHex = await kyVoucher(vKhongHex);
    await assert.rejects(
      registry.write.registerCharacter([vKhongHex, sigKhongHex], { account: player1.account }),
      loi("InvalidCharacterId"),
    );
  });

  // 12. Địa chỉ owner không hợp lệ
  it("12. Từ chối voucher có owner là address(0)", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan({ owner: "0x0000000000000000000000000000000000000000" });
    const sig = await kyVoucher(v);

    await assert.rejects(
      registry.write.registerCharacter([v, sig], { account: player1.account }),
      loi("UnauthorizedCaller"),
    );
  });

  // 13. Unauthorized signer
  it("13. Từ chối chữ ký do tài khoản không có quyền cấp phép ký", async () => {
    const { registry, player1, attacker, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    // Kẻ gian attacker tự ký
    const sigAttacker = await kyVoucher(v, attacker);

    await assert.rejects(
      registry.write.registerCharacter([v, sigAttacker], { account: player1.account }),
      loi("InvalidSignature"),
    );
  });

  // 14. Thay đổi authorized signer
  it("14. Quản trị viên thay đổi authorized signer thành công, khoá cũ bị vô hiệu", async () => {
    const { registry, owner, player1, attacker, taoVoucherChuan, kyVoucher } = await khoiTao();

    // Owner cập nhật signer mới sang attacker
    await registry.write.updateSigner([attacker.account.address], { account: owner.account });
    assert.equal(
      (await registry.read.authorizedSigner()).toLowerCase(),
      attacker.account.address.toLowerCase(),
    );

    const v = taoVoucherChuan();
    // Ký bằng backendSigner cũ -> bị từ chối
    const sigCu = await kyVoucher(v);
    await assert.rejects(
      registry.write.registerCharacter([v, sigCu], { account: player1.account }),
      loi("InvalidSignature"),
    );

    // Ký bằng signer mới (attacker) -> thành công
    const sigMoi = await kyVoucher(v, attacker);
    await registry.write.registerCharacter([v, sigMoi], { account: player1.account });
    assert.equal(await registry.read.isCharacterRegistered([v.characterId]), true);
  });

  // 15. Kiểm tra event và các topic
  it("15. Phát ra event CharacterRegistered với Topic 0, 1, 2, 3 khớp chuẩn EVM", async () => {
    const { registry, pc, player1, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    const sig = await kyVoucher(v);

    const txHash = await registry.write.registerCharacter([v, sig], { account: player1.account });
    const receipt = await pc.waitForTransactionReceipt({ hash: txHash });

    assert.equal(receipt.status, "success");
    assert.ok(receipt.logs.length > 0);

    const log = receipt.logs.find(
      (l) => l.address.toLowerCase() === registry.address.toLowerCase(),
    );
    assert.ok(log, "Phải tìm thấy log phát ra từ CharacterRegistry");

    // Topic 0: Keccak-256 của "CharacterRegistered(string,bytes32,address)"
    const expectedTopic0 = keccak256(toHex("CharacterRegistered(string,bytes32,address)")).toLowerCase();
    assert.equal(log.topics[0]?.toLowerCase(), expectedTopic0);

    // Topic 1: Keccak-256 của indexed string characterId
    const expectedTopic1 = keccak256(toHex(v.characterId)).toLowerCase();
    assert.equal(log.topics[1]?.toLowerCase(), expectedTopic1);

    // Topic 2: bytes32 characterHash
    const expectedTopic2 = v.characterHash.toLowerCase();
    assert.equal(log.topics[2]?.toLowerCase(), expectedTopic2);

    // Topic 3: address owner (padded 12 bytes 0)
    const expectedTopic3 = ("0x000000000000000000000000" + v.owner.toLowerCase().replace("0x", "")).toLowerCase();
    assert.equal(log.topics[3]?.toLowerCase(), expectedTopic3);
  });

  // 16. verifyCharacter trả về dữ liệu đúng
  it("16. verifyCharacter trả về true khi khớp đầy đủ, false khi sai bất kỳ trường nào", async () => {
    const { registry, player1, player2, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    const sig = await kyVoucher(v);
    await registry.write.registerCharacter([v, sig], { account: player1.account });

    // Khớp đầy đủ
    assert.equal(
      await registry.read.verifyCharacter([v.characterId, v.characterHash, v.owner]),
      true,
    );

    // Sai characterId
    assert.equal(
      await registry.read.verifyCharacter(["char_" + "9".repeat(32), v.characterHash, v.owner]),
      false,
    );

    // Sai characterHash
    assert.equal(
      await registry.read.verifyCharacter([
        v.characterId,
        ("0x" + "9".repeat(64)) as `0x${string}`,
        v.owner,
      ]),
      false,
    );

    // Sai owner
    assert.equal(
      await registry.read.verifyCharacter([
        v.characterId,
        v.characterHash,
        player2.account.address,
      ]),
      false,
    );
  });

  // 17. getCharacter trả về dữ liệu đúng
  it("17. getCharacter trả về đầy đủ và chính xác thông tin nhân vật", async () => {
    const { registry, player1, taoVoucherChuan, kyVoucher } = await khoiTao();
    const v = taoVoucherChuan();
    const sig = await kyVoucher(v);
    await registry.write.registerCharacter([v, sig], { account: player1.account });

    const rec = await registry.read.getCharacter([v.characterId]);
    assert.equal(rec.characterId, v.characterId);
    assert.equal(rec.characterHash, v.characterHash);
    assert.equal(rec.owner.toLowerCase(), v.owner.toLowerCase());
    assert.ok(rec.registeredAt > 0n);

    // Kiểm tra getCharacterIdByHash
    const charId = await registry.read.getCharacterIdByHash([v.characterHash]);
    assert.equal(charId, v.characterId);
  });

  // 18. Tài khoản không có quyền không thể thực hiện thao tác quản trị
  it("18. Tài khoản không phải chủ hợp đồng không thể gọi updateSigner", async () => {
    const { registry, attacker } = await khoiTao();

    await assert.rejects(
      registry.write.updateSigner([attacker.account.address], { account: attacker.account }),
      loi("OwnableUnauthorizedAccount"),
    );
  });
});
