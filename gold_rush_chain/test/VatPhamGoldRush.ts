import assert from "node:assert/strict";
import { describe, it, type TestContext } from "node:test";
import { network } from "hardhat";
import {
  BaseError,
  ContractFunctionRevertedError,
  hashTypedData,
  isAddressEqual,
  keccak256,
  maxUint256,
  toHex,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";

// Khớp tên, kiểu và thứ tự trường của PhieuVatPham trong Solidity.
const TYPES = {
  PhieuVatPham: [
    { name: "player", type: "address" },
    { name: "tokenId", type: "uint256" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "bytes32" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

type PhieuVatPham = {
  player: Address;
  tokenId: bigint;
  amount: bigint;
  nonce: Hex;
  deadline: bigint;
};

const ITEMS = [
  { id: 1n, uri: "ipfs://goldrush/kiem-vang.json", cap: 10n },
  { id: 2n, uri: "ipfs://goldrush/khien-ve-binh.json", cap: 10n },
] as const;

/** So khớp custom error và tham số do viem giải mã, kể cả địa chỉ checksum. */
const customError = (name: string, args?: readonly unknown[]) => (error: unknown) => {
  assert.ok(error instanceof BaseError, String(error));
  const cause = error.walk((e) => e instanceof ContractFunctionRevertedError);
  assert.ok(cause instanceof ContractFunctionRevertedError, error.message);
  assert.equal(cause.data?.errorName, name, error.message);
  if (args !== undefined) {
    const normalize = (value: unknown) => typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value)
      ? value.toLowerCase() : value;
    assert.deepEqual(cause.data?.args?.map(normalize), args.map(normalize));
  }
  return true;
};

/** Mạng EDR riêng cho từng test, tự đóng sau test; chỉ ký bằng ví Hardhat. */
async function setup(t: TestContext) {
  const connection = await network.create();
  t.after(() => connection.close());
  const { viem } = connection;
  const [owner, backendSigner, playerA, playerB, attacker] = await viem.getWalletClients();
  const nft = await viem.deployContract("VatPhamGoldRush", [owner.account.address, backendSigner.account.address]);
  const publicClient = await viem.getPublicClient();
  const testClient = await viem.getTestClient();
  const now = (await publicClient.getBlock()).timestamp;
  const domain = {
    name: "GoldRushEquipment", version: "1",
    chainId: await publicClient.getChainId(), verifyingContract: nft.address,
  };
  let nonceCounter = 0;

  async function confirmed(hash: Hex) {
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    assert.equal(receipt.status, "success");
    return receipt;
  }

  async function register(tokenId = 1n, metadataURI: string = ITEMS[0].uri, cap = 10n) {
    return confirmed(await nft.write.registerItem([tokenId, metadataURI, cap], { account: owner.account }));
  }

  async function voucher(
    overrides: Partial<PhieuVatPham> = {},
    { signingWallet = backendSigner, signingDomain = domain } = {},
  ) {
    const p: PhieuVatPham = {
      player: playerA.account.address, tokenId: 1n, amount: 1n,
      nonce: keccak256(toHex(`goldrush-equipment-${nonceCounter++}`)),
      deadline: now + 3600n,
      ...overrides,
    };
    const signature = await signingWallet.signTypedData({
      account: signingWallet.account, domain: signingDomain,
      types: TYPES, primaryType: "PhieuVatPham", message: p,
    });
    return { p, signature };
  }

  async function claim(v: Awaited<ReturnType<typeof voucher>>, wallet = playerA) {
    return confirmed(await nft.write.claimItem([v.p, v.signature], { account: wallet.account }));
  }

  // Dùng khi chưa mint: một lần từ chối không được tiêu thụ nonce hay tạo cung/số dư.
  async function assertUnclaimed(p: PhieuVatPham) {
    assert.equal(await nft.read.usedNonces([p.nonce]), false);
    assert.equal(await nft.read.balanceOf([p.player, p.tokenId]), 0n);
    assert.equal(await nft.read.totalMinted([p.tokenId]), 0n);
  }

  return {
    viem, nft, publicClient, testClient, owner, backendSigner, playerA, playerB,
    attacker, now, domain, confirmed, register, voucher, claim, assertUnclaimed,
  };
}

/** Hai loại đã đăng ký, chưa có token được mint. */
async function registeredSetup(t: TestContext) {
  const f = await setup(t);
  for (const item of ITEMS) await f.register(item.id, item.uri, item.cap);
  return f;
}

/** Kho ban đầu của A: 5 kiếm và 3 khiên; dùng lại cho các test ERC-1155. */
async function inventorySetup(t: TestContext) {
  const f = await registeredSetup(t);
  const vouchers = [await f.voucher({ amount: 5n }), await f.voucher({ tokenId: 2n, amount: 3n })];
  for (const v of vouchers) await f.claim(v);

  async function assertInventory(a: readonly bigint[], b: readonly bigint[]) {
    assert.deepEqual(await f.nft.read.balanceOfBatch([
      [f.playerA.account.address, f.playerA.account.address, f.playerB.account.address, f.playerB.account.address],
      [1n, 2n, 1n, 2n],
    ]), [...a, ...b]);
    // Chuyển nhượng không tạo/đốt token và không mở lại nonce mint.
    assert.equal(await f.nft.read.totalMinted([1n]), 5n);
    assert.equal(await f.nft.read.totalMinted([2n]), 3n);
    for (const v of vouchers) assert.equal(await f.nft.read.usedNonces([v.p.nonce]), true);
  }

  async function transfer(batch: boolean, wallet = f.playerA, to = f.playerB.account.address) {
    return batch
      ? f.nft.write.safeBatchTransferFrom([f.playerA.account.address, to, [1n, 2n], [1n, 2n], "0x1234"],
        { account: wallet.account })
      : f.nft.write.safeTransferFrom([f.playerA.account.address, to, 1n, 1n, "0x1234"],
        { account: wallet.account });
  }

  return { ...f, assertInventory, transfer };
}

describe("VatPhamGoldRush — triển khai và EIP-712", () => {
  it("deploy thành công, đúng owner, backend signer, tên và các ID ban đầu", async (t) => {
    const { nft, publicClient, owner, backendSigner, playerA } = await setup(t);
    const code = await publicClient.getCode({ address: nft.address });
    assert.ok(code && code !== "0x");
    assert.ok(isAddressEqual(await nft.read.owner(), owner.account.address));
    assert.ok(isAddressEqual(await nft.read.signer(), backendSigner.account.address));
    assert.equal(await nft.read.name(), "Gold Rush Equipment");
    assert.deepEqual([
      await nft.read.KIEM_VANG(), await nft.read.KHIEN_VE_BINH(),
      await nft.read.TRUONG_BANG(), await nft.read.GIAP_HOANG_KIM(),
    ], [1n, 2n, 3n, 4n]);
    for (const id of [1n, 2n, 3n, 4n]) {
      assert.equal(await nft.read.registered([id]), false);
      assert.equal(await nft.read.maxSupply([id]), 0n);
      assert.equal(await nft.read.totalMinted([id]), 0n);
      assert.equal(await nft.read.balanceOf([playerA.account.address, id]), 0n);
    }
  });

  it("initialOwner có thể khác ví deploy", async (t) => {
    const { viem, backendSigner, playerA } = await setup(t);
    const other = await viem.deployContract("VatPhamGoldRush", [playerA.account.address, backendSigner.account.address]);
    assert.ok(isAddressEqual(await other.read.owner(), playerA.account.address));
    await other.write.registerItem([1n, ITEMS[0].uri, 1n], { account: playerA.account });
    assert.equal(await other.read.registered([1n]), true);
  });

  for (const field of ["owner", "signer"] as const) {
    it(`từ chối ${field} ban đầu là địa chỉ zero`, async (t) => {
      const { viem, owner, backendSigner } = await setup(t);
      // Lỗi deploy đi qua deployContract của viem, không có ContractFunctionRevertedError.
      await assert.rejects(viem.deployContract("VatPhamGoldRush", [
        field === "owner" ? zeroAddress : owner.account.address,
        field === "signer" ? zeroAddress : backendSigner.account.address,
      ]), (error: unknown) => {
        assert.ok(error instanceof BaseError, String(error));
        assert.match(error.message, field === "owner" ? /OwnableInvalidOwner/ : /InvalidSigner/);
        return true;
      });
    });
  }

  it("typehash, digest viem và toàn bộ domain EIP-712 khớp hợp đồng", async (t) => {
    const { nft, domain, voucher } = await setup(t);
    const { p } = await voucher();
    assert.equal(await nft.read.PHIEU_VAT_PHAM_TYPEHASH(), keccak256(toHex(
      "PhieuVatPham(address player,uint256 tokenId,uint256 amount,bytes32 nonce,uint256 deadline)",
    )));
    assert.equal(await nft.read.hashVoucher([p]), hashTypedData({
      domain, types: TYPES, primaryType: "PhieuVatPham", message: p,
    }));
    const [fields, name, version, chainId, verifyingContract, salt, extensions] = await nft.read.eip712Domain();
    assert.equal(fields, "0x0f");
    assert.equal(name, domain.name);
    assert.equal(version, domain.version);
    assert.equal(chainId, BigInt(domain.chainId));
    assert.ok(isAddressEqual(verifyingContract, nft.address));
    assert.equal(salt, toHex(0n, { size: 32 }));
    assert.deepEqual(extensions, []);
  });

  it("hỗ trợ ERC-165, ERC-1155 và metadata URI", async (t) => {
    const { nft } = await setup(t);
    for (const id of ["0x01ffc9a7", "0xd9b67a26", "0x0e89341c"] as const) {
      assert.equal(await nft.read.supportsInterface([id]), true);
    }
    assert.equal(await nft.read.supportsInterface(["0xffffffff"]), false);
  });
});

describe("VatPhamGoldRush — đăng ký và cấu hình vật phẩm", () => {
  it("owner đăng ký URI, maxSupply và phát ItemRegistered/URI", async (t) => {
    const { nft, register } = await setup(t);
    const receipt = await register();
    assert.equal(await nft.read.registered([1n]), true);
    assert.equal(await nft.read.uri([1n]), ITEMS[0].uri);
    assert.equal(await nft.read.maxSupply([1n]), 10n);
    assert.equal(await nft.read.totalMinted([1n]), 0n);
    const events = await nft.getEvents.ItemRegistered({}, { blockHash: receipt.blockHash });
    assert.equal(events.length, 1);
    assert.deepEqual(events[0].args, { tokenId: 1n, metadataURI: ITEMS[0].uri, maxSupply: 10n });
    const uris = await nft.getEvents.URI({}, { blockHash: receipt.blockHash });
    assert.equal(uris.length, 1);
    assert.deepEqual(uris[0].args, { value: ITEMS[0].uri, id: 1n });
  });

  it("không đăng ký trùng ID và giữ nguyên URI/cap cũ", async (t) => {
    const { nft, owner } = await registeredSetup(t);
    await assert.rejects(nft.write.registerItem([1n, "ipfs://replacement", 20n], { account: owner.account }),
      customError("ItemAlreadyRegistered", [1n]));
    assert.equal(await nft.read.uri([1n]), ITEMS[0].uri);
    assert.equal(await nft.read.maxSupply([1n]), 10n);
  });

  const invalidRegistrations = [
    { id: 0n, uri: ITEMS[0].uri, cap: 10n, error: "InvalidTokenId", args: [0n] },
    { id: 1n, uri: "", cap: 10n, error: "EmptyURI", args: undefined },
    { id: 1n, uri: ITEMS[0].uri, cap: 0n, error: "InvalidMaxSupply", args: [0n] },
  ];
  for (const c of invalidRegistrations) {
    it(`từ chối đăng ký với ${c.error}`, async (t) => {
      const { nft, register } = await setup(t);
      await assert.rejects(register(c.id, c.uri, c.cap), customError(c.error, c.args));
      assert.equal(await nft.read.registered([c.id]), false);
      assert.equal(await nft.read.maxSupply([c.id]), 0n);
      await assert.rejects(nft.read.uri([c.id]), customError("ItemNotRegistered", [c.id]));
    });
  }

  it("chấp nhận maxSupply=1 và uint256 tối đa; các ID có URI/cap riêng", async (t) => {
    const { nft, register } = await setup(t);
    await register(1n, ITEMS[0].uri, 1n);
    await register(2n, ITEMS[1].uri, maxUint256);
    assert.equal(await nft.read.maxSupply([1n]), 1n);
    assert.equal(await nft.read.maxSupply([2n]), maxUint256);
    assert.equal(await nft.read.uri([1n]), ITEMS[0].uri);
    assert.equal(await nft.read.uri([2n]), ITEMS[1].uri);
  });

  it("player, attacker và backend signer không được đăng ký", async (t) => {
    const { nft, playerA, attacker, backendSigner } = await setup(t);
    for (const wallet of [playerA, attacker, backendSigner]) {
      await assert.rejects(nft.write.registerItem([1n, ITEMS[0].uri, 10n], { account: wallet.account }),
        customError("OwnableUnauthorizedAccount", [wallet.account.address]));
      assert.equal(await nft.read.registered([1n]), false);
    }
  });

  it("uri từ chối ID chưa đăng ký", async (t) => {
    const { nft } = await setup(t);
    for (const id of [0n, 1n, 999n]) {
      await assert.rejects(nft.read.uri([id]), customError("ItemNotRegistered", [id]));
    }
  });

  it("owner đổi URI cả trước và sau mint, phát URI, giữ nguyên cung và số dư", async (t) => {
    const { nft, owner, playerA, voucher, claim, confirmed } = await registeredSetup(t);
    for (const minted of [false, true]) {
      if (minted) await claim(await voucher());
      const uri = `ipfs://metadata-${minted}.json`;
      const receipt = await confirmed(await nft.write.setItemURI([1n, uri], { account: owner.account }));
      assert.equal(await nft.read.uri([1n]), uri);
      const events = await nft.getEvents.URI({}, { blockHash: receipt.blockHash });
      assert.equal(events.length, 1);
      assert.deepEqual(events[0].args, { value: uri, id: 1n });
      assert.equal(await nft.read.totalMinted([1n]), minted ? 1n : 0n);
      assert.equal(await nft.read.balanceOf([playerA.account.address, 1n]), minted ? 1n : 0n);
      assert.equal(await nft.read.maxSupply([1n]), 10n);
    }
  });

  it("setItemURI từ chối ví không có quyền, ID chưa đăng ký và URI rỗng", async (t) => {
    const { nft, owner, playerA } = await registeredSetup(t);
    await assert.rejects(nft.write.setItemURI([1n, "ipfs://other"], { account: playerA.account }),
      customError("OwnableUnauthorizedAccount", [playerA.account.address]));
    await assert.rejects(nft.write.setItemURI([99n, "ipfs://other"], { account: owner.account }),
      customError("ItemNotRegistered", [99n]));
    await assert.rejects(nft.write.setItemURI([1n, ""], { account: owner.account }), customError("EmptyURI"));
    assert.equal(await nft.read.uri([1n]), ITEMS[0].uri);
  });

  it("owner tăng/giảm maxSupply trước mint và phát MaxSupplyUpdated", async (t) => {
    const { nft, owner, confirmed } = await registeredSetup(t);
    let previous = 10n;
    for (const cap of [20n, 1n]) {
      const receipt = await confirmed(await nft.write.setMaxSupply([1n, cap], { account: owner.account }));
      assert.equal(await nft.read.maxSupply([1n]), cap);
      const events = await nft.getEvents.MaxSupplyUpdated({}, { blockHash: receipt.blockHash });
      assert.equal(events.length, 1);
      assert.deepEqual(events[0].args, { tokenId: 1n, previousMaxSupply: previous, newMaxSupply: cap });
      previous = cap;
    }
  });

  it("setMaxSupply từ chối ví không có quyền, ID chưa đăng ký và cap=0", async (t) => {
    const { nft, owner, playerA } = await registeredSetup(t);
    await assert.rejects(nft.write.setMaxSupply([1n, 20n], { account: playerA.account }),
      customError("OwnableUnauthorizedAccount", [playerA.account.address]));
    await assert.rejects(nft.write.setMaxSupply([99n, 20n], { account: owner.account }),
      customError("ItemNotRegistered", [99n]));
    await assert.rejects(nft.write.setMaxSupply([1n, 0n], { account: owner.account }),
      customError("InvalidMaxSupply", [0n]));
    assert.equal(await nft.read.maxSupply([1n]), 10n);
  });

  it("khóa maxSupply sau mint đầu tiên, kể cả tăng/giảm/giữ cap", async (t) => {
    const { nft, owner, voucher, claim } = await registeredSetup(t);
    await claim(await voucher({ amount: 2n }));
    for (const cap of [1n, 10n, 20n]) {
      await assert.rejects(nft.write.setMaxSupply([1n, cap], { account: owner.account }),
        customError("SupplyLocked", [1n]));
    }
    assert.equal(await nft.read.maxSupply([1n]), 10n);
    assert.equal(await nft.read.totalMinted([1n]), 2n);
    await nft.write.setMaxSupply([2n, 1n], { account: owner.account });
    assert.equal(await nft.read.maxSupply([2n]), 1n);
  });
});

describe("VatPhamGoldRush — nhận NFT và giới hạn nguồn cung", () => {
  it("phiếu backend hợp lệ mint đúng amount, số dư, tổng cung, nonce và sự kiện", async (t) => {
    const { nft, playerA, playerB, voucher, claim } = await registeredSetup(t);
    const v = await voucher({ amount: 3n });
    const receipt = await claim(v);
    assert.equal(await nft.read.balanceOf([playerA.account.address, 1n]), 3n);
    assert.equal(await nft.read.balanceOf([playerB.account.address, 1n]), 0n);
    // Hợp đồng không kế thừa ERC1155Supply; API nguồn cung là totalMinted(tokenId).
    assert.equal(await nft.read.totalMinted([1n]), 3n);
    assert.equal(await nft.read.totalMinted([2n]), 0n);
    assert.equal(await nft.read.usedNonces([v.p.nonce]), true);
    const events = await nft.getEvents.ItemClaimed({}, { blockHash: receipt.blockHash });
    assert.equal(events.length, 1);
    assert.ok(isAddressEqual(events[0].args.player!, playerA.account.address));
    assert.deepEqual([events[0].args.tokenId, events[0].args.amount, events[0].args.nonce], [1n, 3n, v.p.nonce]);
    const transfers = await nft.getEvents.TransferSingle({}, { blockHash: receipt.blockHash });
    assert.equal(transfers.length, 1);
    assert.ok(isAddressEqual(transfers[0].args.operator!, playerA.account.address));
    assert.equal(transfers[0].args.from, zeroAddress);
    assert.ok(isAddressEqual(transfers[0].args.to!, playerA.account.address));
    assert.deepEqual([transfers[0].args.id, transfers[0].args.value], [1n, 3n]);
  });

  it("một ví nhận nhiều phiếu/cùng ID và nhiều loại; tổng cung cộng dồn qua nhiều ví", async (t) => {
    const { nft, playerA, playerB, voucher, claim } = await registeredSetup(t);
    await claim(await voucher({ amount: 2n }));
    await claim(await voucher({ amount: 3n }));
    await claim(await voucher({ tokenId: 2n, amount: 4n }));
    await claim(await voucher({ player: playerB.account.address, amount: 2n }), playerB);
    assert.deepEqual(await nft.read.balanceOfBatch([
      [playerA.account.address, playerA.account.address, playerB.account.address], [1n, 2n, 1n],
    ]), [5n, 4n, 2n]);
    assert.equal(await nft.read.totalMinted([1n]), 7n);
    assert.equal(await nft.read.totalMinted([2n]), 4n);
  });

  it("mint đến đúng cap; vượt phần còn lại bị từ chối mà không mất nonce", async (t) => {
    const { nft, playerA, playerB, voucher, claim } = await registeredSetup(t);
    await claim(await voucher({ amount: 7n }));
    const tooMany = await voucher({ player: playerB.account.address, amount: 4n });
    await assert.rejects(nft.write.claimItem([tooMany.p, tooMany.signature], { account: playerB.account }),
      customError("MaxSupplyExceeded", [1n, 4n, 3n]));
    assert.equal(await nft.read.usedNonces([tooMany.p.nonce]), false);
    assert.equal(await nft.read.totalMinted([1n]), 7n);
    assert.equal(await nft.read.balanceOf([playerB.account.address, 1n]), 0n);
    await claim(await voucher({ player: playerB.account.address, amount: 3n }), playerB);
    const extra = await voucher();
    await assert.rejects(nft.write.claimItem([extra.p, extra.signature], { account: playerA.account }),
      customError("MaxSupplyExceeded", [1n, 1n, 0n]));
    assert.equal(await nft.read.totalMinted([1n]), 10n);
    assert.equal(await nft.read.balanceOf([playerA.account.address, 1n]), 7n);
    assert.equal(await nft.read.balanceOf([playerB.account.address, 1n]), 3n);
    assert.equal(await nft.read.usedNonces([extra.p.nonce]), false);
  });

  it("maxSupply=1 là độc bản toàn hợp đồng, không phải mỗi ví một bản", async (t) => {
    const { nft, playerB, register, voucher, claim } = await setup(t);
    await register(1n, ITEMS[0].uri, 1n);
    await claim(await voucher());
    const second = await voucher({ player: playerB.account.address });
    await assert.rejects(nft.write.claimItem([second.p, second.signature], { account: playerB.account }),
      customError("MaxSupplyExceeded", [1n, 1n, 0n]));
    assert.equal(await nft.read.totalMinted([1n]), 1n);
    assert.equal(await nft.read.balanceOf([playerB.account.address, 1n]), 0n);
    assert.equal(await nft.read.usedNonces([second.p.nonce]), false);
  });

  it("amount uint256 tối đa vượt cap trả đúng custom error, không panic do tràn số", async (t) => {
    const { nft, playerA, voucher, assertUnclaimed } = await registeredSetup(t);
    const v = await voucher({ amount: maxUint256 });
    await assert.rejects(nft.write.claimItem([v.p, v.signature], { account: playerA.account }),
      customError("MaxSupplyExceeded", [1n, maxUint256, 10n]));
    await assertUnclaimed(v.p);
  });

  for (const tokenId of [0n, 99n]) {
    it(`không nhận ID chưa đăng ký: ${tokenId}`, async (t) => {
      const { nft, playerA, voucher, assertUnclaimed } = await registeredSetup(t);
      const v = await voucher({ tokenId });
      await assert.rejects(nft.write.claimItem([v.p, v.signature], { account: playerA.account }),
        customError("ItemNotRegistered", [tokenId]));
      await assertUnclaimed(v.p);
    });
  }

  it("không nhận amount=0", async (t) => {
    const { nft, playerA, voucher, assertUnclaimed } = await registeredSetup(t);
    const v = await voucher({ amount: 0n });
    await assert.rejects(nft.write.claimItem([v.p, v.signature], { account: playerA.account }),
      customError("InvalidAmount"));
    await assertUnclaimed(v.p);
  });

  it("ví B và attacker không được dùng phiếu của A; A vẫn nhận được sau đó", async (t) => {
    const { nft, playerB, attacker, voucher, claim, assertUnclaimed } = await registeredSetup(t);
    const v = await voucher();
    for (const wallet of [playerB, attacker]) {
      await assert.rejects(nft.write.claimItem([v.p, v.signature], { account: wallet.account }), customError("WrongPlayer"));
      assert.equal(await nft.read.balanceOf([wallet.account.address, 1n]), 0n);
      await assertUnclaimed(v.p);
    }
    await claim(v);
  });
});

describe("VatPhamGoldRush — chữ ký, thời hạn và chống replay", () => {
  it("từ chối phiếu do attacker/người chơi ký thay backend", async (t) => {
    const { nft, playerA, attacker, voucher, claim, assertUnclaimed } = await registeredSetup(t);
    const valid = await voucher();
    for (const signingWallet of [attacker, playerA]) {
      const forged = await voucher(valid.p, { signingWallet });
      await assert.rejects(nft.write.claimItem([forged.p, forged.signature], { account: playerA.account }),
        customError("InvalidSignature"));
      await assertUnclaimed(valid.p);
    }
    await claim(valid);
  });

  for (const signature of ["0x", "0x1234", `0x${"00".repeat(65)}`] as const) {
    it(`từ chối chữ ký không hợp lệ (${(signature.length - 2) / 2} byte)`, async (t) => {
      const { nft, playerA, voucher, assertUnclaimed } = await registeredSetup(t);
      const { p } = await voucher();
      await assert.rejects(nft.write.claimItem([p, signature], { account: playerA.account }), customError("InvalidSignature"));
      await assertUnclaimed(p);
    });
  }

  it("từ chối phiếu hết hạn, không tiêu thụ nonce", async (t) => {
    const { nft, playerA, now, voucher, assertUnclaimed } = await registeredSetup(t);
    const v = await voucher({ deadline: now - 1n });
    await assert.rejects(nft.write.claimItem([v.p, v.signature], { account: playerA.account }), customError("VoucherExpired"));
    await assertUnclaimed(v.p);
  });

  it("chấp nhận tại đúng deadline", async (t) => {
    const { publicClient, testClient, now, voucher, claim } = await registeredSetup(t);
    const v = await voucher({ deadline: now + 60n });
    await testClient.setNextBlockTimestamp({ timestamp: v.p.deadline });
    const receipt = await claim(v);
    assert.equal((await publicClient.getBlock({ blockHash: receipt.blockHash })).timestamp, v.p.deadline);
  });

  it("từ chối khi thời gian mạng vượt deadline một giây", async (t) => {
    const { nft, testClient, playerA, now, voucher, assertUnclaimed } = await registeredSetup(t);
    const v = await voucher({ deadline: now + 60n });
    await testClient.setNextBlockTimestamp({ timestamp: v.p.deadline + 1n });
    await testClient.mine({ blocks: 1 });
    await assert.rejects(nft.write.claimItem([v.p, v.signature], { account: playerA.account }), customError("VoucherExpired"));
    await assertUnclaimed(v.p);
  });

  for (const field of ["player", "tokenId", "amount", "nonce", "deadline"] as const) {
    it(`từ chối sửa ${field} sau khi ký`, async (t) => {
      const { nft, playerA, playerB, voucher, claim, assertUnclaimed } = await registeredSetup(t);
      const valid = await voucher();
      const replacements = {
        player: playerB.account.address, tokenId: 2n, amount: 2n,
        nonce: keccak256(toHex("nonce-bi-sua")), deadline: valid.p.deadline + 600n,
      };
      const modified = { ...valid.p, [field]: replacements[field] };
      // Gửi từ player mới để vượt kiểm tra WrongPlayer; ID/amount mới cũng hợp lệ.
      // Như vậy test chứng minh chữ ký bảo vệ trường đó, không bị chặn bởi lỗi khác.
      const caller = field === "player" ? playerB : playerA;
      await assert.rejects(nft.write.claimItem([modified, valid.signature], { account: caller.account }),
        customError("InvalidSignature"));
      await assertUnclaimed(modified);
      await assertUnclaimed(valid.p);
      await claim(valid);
    });
  }

  it("không dùng lại đúng phiếu đã nhận", async (t) => {
    const { nft, playerA, voucher, claim } = await registeredSetup(t);
    const v = await voucher({ amount: 2n });
    await claim(v);
    await assert.rejects(nft.write.claimItem([v.p, v.signature], { account: playerA.account }),
      customError("NonceAlreadyUsed", [v.p.nonce]));
    assert.equal(await nft.read.totalMinted([1n]), 2n);
    assert.equal(await nft.read.balanceOf([playerA.account.address, 1n]), 2n);
  });

  it("nonce dùng toàn cục: phiếu ký mới cho ví/ID khác vẫn không tái dùng được", async (t) => {
    const { nft, playerB, voucher, claim } = await registeredSetup(t);
    const first = await voucher();
    await claim(first);
    const replay = await voucher({ player: playerB.account.address, tokenId: 2n, nonce: first.p.nonce });
    await assert.rejects(nft.write.claimItem([replay.p, replay.signature], { account: playerB.account }),
      customError("NonceAlreadyUsed", [first.p.nonce]));
    assert.equal(await nft.read.totalMinted([1n]), 1n);
    assert.equal(await nft.read.totalMinted([2n]), 0n);
    assert.equal(await nft.read.balanceOf([playerB.account.address, 2n]), 0n);
  });

  for (const field of ["chainId", "verifyingContract", "name", "version"] as const) {
    it(`từ chối replay với domain sai ${field}`, async (t) => {
      const { nft, playerA, domain, voucher, claim, assertUnclaimed } = await registeredSetup(t);
      const valid = await voucher();
      const replacements = {
        chainId: domain.chainId + 1, verifyingContract: playerA.account.address,
        name: "GoldRushSBT", version: "2",
      };
      const forged = await voucher(valid.p, { signingDomain: { ...domain, [field]: replacements[field] } });
      await assert.rejects(nft.write.claimItem([forged.p, forged.signature], { account: playerA.account }),
        customError("InvalidSignature"));
      await assertUnclaimed(valid.p);
      await claim(valid);
    });
  }

  it("phiếu đã dùng trên hợp đồng A không replay được trên hợp đồng B cùng signer", async (t) => {
    const { viem, nft, owner, backendSigner, playerA, domain, voucher, claim, confirmed } = await registeredSetup(t);
    const other = await viem.deployContract("VatPhamGoldRush", [owner.account.address, backendSigner.account.address]);
    await confirmed(await other.write.registerItem([1n, ITEMS[0].uri, 10n], { account: owner.account }));
    const v = await voucher();
    await claim(v);
    assert.notEqual(await nft.read.hashVoucher([v.p]), await other.read.hashVoucher([v.p]));
    await assert.rejects(other.write.claimItem([v.p, v.signature], { account: playerA.account }),
      customError("InvalidSignature"));
    assert.equal(await other.read.usedNonces([v.p.nonce]), false);
    assert.equal(await other.read.totalMinted([1n]), 0n);
    assert.equal(await other.read.balanceOf([playerA.account.address, 1n]), 0n);
    // Cùng dữ liệu/nonce nhưng ký đúng domain B thì dùng được: nonce độc lập giữa hợp đồng.
    const local = await voucher(v.p, { signingDomain: { ...domain, verifyingContract: other.address } });
    await confirmed(await other.write.claimItem([local.p, local.signature], { account: playerA.account }));
    assert.equal(await other.read.totalMinted([1n]), 1n);
  });
});

describe("VatPhamGoldRush — quản lý backend signer", () => {
  it("owner đổi signer, phát sự kiện; khóa cũ bị từ chối, khóa mới được chấp nhận", async (t) => {
    const { nft, owner, backendSigner, playerA, playerB, confirmed, voucher, claim, assertUnclaimed } = await registeredSetup(t);
    const old = await voucher();
    const receipt = await confirmed(await nft.write.setSigner([playerB.account.address], { account: owner.account }));
    assert.ok(isAddressEqual(await nft.read.signer(), playerB.account.address));
    const events = await nft.getEvents.SignerUpdated({}, { blockHash: receipt.blockHash });
    assert.equal(events.length, 1);
    assert.ok(isAddressEqual(events[0].args.previousSigner!, backendSigner.account.address));
    assert.ok(isAddressEqual(events[0].args.newSigner!, playerB.account.address));
    await assert.rejects(nft.write.claimItem([old.p, old.signature], { account: playerA.account }), customError("InvalidSignature"));
    await assertUnclaimed(old.p);
    await claim(await voucher(old.p, { signingWallet: playerB }));
  });

  it("player, attacker và backend không được tự đổi signer", async (t) => {
    const { nft, backendSigner, playerA, playerB, attacker } = await setup(t);
    for (const wallet of [playerA, playerB, attacker, backendSigner]) {
      await assert.rejects(nft.write.setSigner([attacker.account.address], { account: wallet.account }),
        customError("OwnableUnauthorizedAccount", [wallet.account.address]));
      assert.ok(isAddressEqual(await nft.read.signer(), backendSigner.account.address));
    }
  });

  it("không đổi signer sang zero", async (t) => {
    const { nft, owner, backendSigner } = await setup(t);
    await assert.rejects(nft.write.setSigner([zeroAddress], { account: owner.account }), customError("InvalidSigner"));
    assert.ok(isAddressEqual(await nft.read.signer(), backendSigner.account.address));
  });

  it("đổi signer không xóa nonce, số dư, nguồn cung hoặc mở khóa cap", async (t) => {
    const { nft, owner, playerA, playerB, voucher, claim } = await registeredSetup(t);
    const first = await voucher({ amount: 2n });
    await claim(first);
    await nft.write.setSigner([playerB.account.address], { account: owner.account });
    const replay = await voucher(first.p, { signingWallet: playerB });
    await assert.rejects(nft.write.claimItem([replay.p, replay.signature], { account: playerA.account }),
      customError("NonceAlreadyUsed", [first.p.nonce]));
    assert.equal(await nft.read.usedNonces([first.p.nonce]), true);
    assert.equal(await nft.read.balanceOf([playerA.account.address, 1n]), 2n);
    assert.equal(await nft.read.totalMinted([1n]), 2n);
    await assert.rejects(nft.write.setMaxSupply([1n, 20n], { account: owner.account }), customError("SupplyLocked", [1n]));
    await claim(await voucher({}, { signingWallet: playerB }));
    assert.equal(await nft.read.totalMinted([1n]), 3n);
  });
});

describe("VatPhamGoldRush — chuyển nhượng ERC-1155, khác với SBT", () => {
  it("A safeTransferFrom một NFT cho B: số dư chính xác và TransferSingle", async (t) => {
    const { nft, playerA, playerB, confirmed, transfer, assertInventory } = await inventorySetup(t);
    const receipt = await confirmed(await transfer(false));
    await assertInventory([4n, 3n], [1n, 0n]);
    const events = await nft.getEvents.TransferSingle({}, { blockHash: receipt.blockHash });
    assert.equal(events.length, 1);
    assert.ok(isAddressEqual(events[0].args.operator!, playerA.account.address));
    assert.ok(isAddressEqual(events[0].args.from!, playerA.account.address));
    assert.ok(isAddressEqual(events[0].args.to!, playerB.account.address));
    assert.deepEqual([events[0].args.id, events[0].args.value], [1n, 1n]);
  });

  it("A safeBatchTransferFrom nhiều loại cho B: số dư chính xác và TransferBatch", async (t) => {
    const { nft, playerA, playerB, confirmed, transfer, assertInventory } = await inventorySetup(t);
    const receipt = await confirmed(await transfer(true));
    await assertInventory([4n, 1n], [1n, 2n]);
    const events = await nft.getEvents.TransferBatch({}, { blockHash: receipt.blockHash });
    assert.equal(events.length, 1);
    assert.ok(isAddressEqual(events[0].args.operator!, playerA.account.address));
    assert.ok(isAddressEqual(events[0].args.from!, playerA.account.address));
    assert.ok(isAddressEqual(events[0].args.to!, playerB.account.address));
    assert.deepEqual(events[0].args.ids, [1n, 2n]);
    assert.deepEqual(events[0].args.values, [1n, 2n]);
  });

  it("B tiếp tục chuyển NFT đã nhận về A mà không cần phiếu backend", async (t) => {
    const { nft, playerA, playerB, confirmed, transfer, assertInventory } = await inventorySetup(t);
    await confirmed(await transfer(false));
    await confirmed(await nft.write.safeTransferFrom([
      playerB.account.address, playerA.account.address, 1n, 1n, "0x",
    ], { account: playerB.account }));
    await assertInventory([5n, 3n], [0n, 0n]);
  });

  for (const batch of [false, true]) {
    const method = batch ? "safeBatchTransferFrom" : "safeTransferFrom";

    it(`${method}: attacker, owner và backend không có quyền chuyển NFT của A`, async (t) => {
      const { playerA, attacker, owner, backendSigner, transfer, assertInventory } = await inventorySetup(t);
      for (const wallet of [attacker, owner, backendSigner]) {
        await assert.rejects(transfer(batch, wallet),
          customError("ERC1155MissingApprovalForAll", [wallet.account.address, playerA.account.address]));
        await assertInventory([5n, 3n], [0n, 0n]);
      }
    });

    it(`${method}: từ chối vượt số dư, hoàn tác cả các phần tử batch trước đó`, async (t) => {
      const { nft, playerA, playerB, assertInventory } = await inventorySetup(t);
      const tx = batch
        ? nft.write.safeBatchTransferFrom([playerA.account.address, playerB.account.address, [1n, 2n], [1n, 4n], "0x"],
          { account: playerA.account })
        : nft.write.safeTransferFrom([playerA.account.address, playerB.account.address, 1n, 6n, "0x"],
          { account: playerA.account });
      await assert.rejects(tx, customError("ERC1155InsufficientBalance", batch
        ? [playerA.account.address, 3n, 4n, 2n] : [playerA.account.address, 5n, 6n, 1n]));
      await assertInventory([5n, 3n], [0n, 0n]);
    });

    it(`${method}: phê duyệt operator cho phép chuyển; thu hồi chặn lần tiếp theo`, async (t) => {
      const { nft, playerA, attacker, confirmed, transfer, assertInventory } = await inventorySetup(t);
      assert.equal(await nft.read.isApprovedForAll([playerA.account.address, attacker.account.address]), false);
      for (const approved of [true, false]) {
        const receipt = await confirmed(await nft.write.setApprovalForAll([attacker.account.address, approved],
          { account: playerA.account }));
        assert.equal(await nft.read.isApprovedForAll([playerA.account.address, attacker.account.address]), approved);
        const events = await nft.getEvents.ApprovalForAll({}, { blockHash: receipt.blockHash });
        assert.equal(events.length, 1);
        assert.ok(isAddressEqual(events[0].args.account!, playerA.account.address));
        assert.ok(isAddressEqual(events[0].args.operator!, attacker.account.address));
        assert.equal(events[0].args.approved, approved);
        if (approved) {
          const moved = await confirmed(await transfer(batch, attacker));
          const transfers = batch
            ? await nft.getEvents.TransferBatch({}, { blockHash: moved.blockHash })
            : await nft.getEvents.TransferSingle({}, { blockHash: moved.blockHash });
          assert.equal(transfers.length, 1);
          assert.ok(isAddressEqual(transfers[0].args.operator!, attacker.account.address));
        } else {
          await assert.rejects(transfer(batch, attacker),
            customError("ERC1155MissingApprovalForAll", [attacker.account.address, playerA.account.address]));
        }
        await assertInventory(batch ? [4n, 1n] : [4n, 3n], batch ? [1n, 2n] : [1n, 0n]);
      }
    });

    it(`${method}: từ chối receiver là zero`, async (t) => {
      const { transfer, playerA, assertInventory } = await inventorySetup(t);
      await assert.rejects(transfer(batch, playerA, zeroAddress), customError("ERC1155InvalidReceiver", [zeroAddress]));
      await assertInventory([5n, 3n], [0n, 0n]);
    });

    it(`${method}: hợp đồng không có ERC1155Receiver từ chối nhận, số dư hoàn tác`, async (t) => {
      const { nft, publicClient, playerA, transfer, assertInventory } = await inventorySetup(t);
      // Chính VatPhamGoldRush có bytecode nhưng không triển khai callback receiver.
      assert.ok((await publicClient.getCode({ address: nft.address }))!.length > 2);
      await assert.rejects(transfer(batch, playerA, nft.address), customError("ERC1155InvalidReceiver", [nft.address]));
      assert.equal(await nft.read.balanceOf([nft.address, 1n]), 0n);
      assert.equal(await nft.read.balanceOf([nft.address, 2n]), 0n);
      await assertInventory([5n, 3n], [0n, 0n]);
    });
  }

  it("batch từ chối mảng ID/amount khác độ dài", async (t) => {
    const { nft, playerA, playerB, assertInventory } = await inventorySetup(t);
    await assert.rejects(nft.write.safeBatchTransferFrom([
      playerA.account.address, playerB.account.address, [1n, 2n], [1n], "0x",
    ], { account: playerA.account }), customError("ERC1155InvalidArrayLength", [2n, 1n]));
    await assertInventory([5n, 3n], [0n, 0n]);
  });

  it("batch có ID lặp không được cộng dồn vượt số dư", async (t) => {
    const { nft, playerA, playerB, assertInventory } = await inventorySetup(t);
    await assert.rejects(nft.write.safeBatchTransferFrom([
      playerA.account.address, playerB.account.address, [1n, 1n], [3n, 3n], "0x",
    ], { account: playerA.account }), customError("ERC1155InsufficientBalance", [playerA.account.address, 2n, 3n, 1n]));
    await assertInventory([5n, 3n], [0n, 0n]);
  });

  it("approval của B cho attacker không cấp quyền chuyển token của A", async (t) => {
    const { nft, playerA, playerB, attacker, transfer, confirmed, assertInventory } = await inventorySetup(t);
    await confirmed(await nft.write.setApprovalForAll([attacker.account.address, true], { account: playerB.account }));
    assert.equal(await nft.read.isApprovedForAll([playerB.account.address, attacker.account.address]), true);
    assert.equal(await nft.read.isApprovedForAll([playerA.account.address, attacker.account.address]), false);
    await assert.rejects(transfer(false, attacker),
      customError("ERC1155MissingApprovalForAll", [attacker.account.address, playerA.account.address]));
    await assertInventory([5n, 3n], [0n, 0n]);
  });

  it("không phê duyệt operator zero", async (t) => {
    const { nft, playerA } = await setup(t);
    await assert.rejects(nft.write.setApprovalForAll([zeroAddress, true], { account: playerA.account }),
      customError("ERC1155InvalidOperator", [zeroAddress]));
    assert.equal(await nft.read.isApprovedForAll([playerA.account.address, zeroAddress]), false);
  });
});
