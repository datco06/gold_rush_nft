import assert from "node:assert/strict";
import { describe, it, type TestContext } from "node:test";
import { network } from "hardhat";
import {
  BaseError,
  ContractFunctionRevertedError,
  hashTypedData,
  isAddressEqual,
  keccak256,
  toHex,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";

// Khớp chính xác PhieuSBT và PHIEU_SBT_TYPEHASH trong Solidity.
const TYPES = {
  PhieuSBT: [
    { name: "player", type: "address" },
    { name: "achievementId", type: "uint256" },
    { name: "nonce", type: "bytes32" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

type PhieuSBT = {
  player: Address;
  achievementId: bigint;
  nonce: Hex;
  deadline: bigint;
};

/** Kiểm tra custom error được viem giải mã, không chỉ khớp chuỗi thông báo. */
const customError = (name: string, args?: readonly unknown[]) => (error: unknown) => {
  assert.ok(error instanceof BaseError, String(error));
  const cause = error.walk((e) => e instanceof ContractFunctionRevertedError);
  assert.ok(cause instanceof ContractFunctionRevertedError, error.message);
  assert.equal(cause.data?.errorName, name, error.message);
  if (args !== undefined) {
    const normalizeAddress = (value: unknown) => typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value)
      ? value.toLowerCase() : value;
    assert.deepEqual(cause.data?.args?.map(normalizeAddress), args.map(normalizeAddress));
  }
  return true;
};

/** Mỗi test có mạng độc lập và đóng kết nối khi kết thúc. Chỉ dùng ví Hardhat. */
async function setup(t: TestContext) {
  const connection = await network.create();
  t.after(() => connection.close());
  const { viem } = connection;
  const [owner, backendSigner, playerA, playerB, attacker] = await viem.getWalletClients();
  const sbt = await viem.deployContract("ThanhTuuSBT", [owner.account.address, backendSigner.account.address]);
  const publicClient = await viem.getPublicClient();
  const testClient = await viem.getTestClient();
  const now = (await publicClient.getBlock()).timestamp;
  const chainId = await publicClient.getChainId();
  const domain = { name: "GoldRushSBT", version: "1", chainId, verifyingContract: sbt.address };
  let nonceCounter = 0;

  async function voucher(
    overrides: Partial<PhieuSBT> = {},
    { signingWallet = backendSigner, signingDomain = domain } = {},
  ) {
    const p: PhieuSBT = {
      player: playerA.account.address,
      achievementId: 1n,
      nonce: keccak256(toHex(`goldrush-sbt-${nonceCounter++}`)),
      deadline: now + 3600n,
      ...overrides,
    };
    const signature = await signingWallet.signTypedData({
      account: signingWallet.account,
      domain: signingDomain,
      types: TYPES,
      primaryType: "PhieuSBT",
      message: p,
    });
    return { p, signature };
  }

  async function claim(v: Awaited<ReturnType<typeof voucher>>, wallet = playerA) {
    const hash = await sbt.write.claimSBT([v.p, v.signature], { account: wallet.account });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    assert.equal(receipt.status, "success");
    return receipt;
  }

  async function assertUnclaimed(p: PhieuSBT) {
    assert.equal(await sbt.read.usedNonces([p.nonce]), false);
    assert.equal(await sbt.read.hasAchievement([p.player, p.achievementId]), false);
    assert.equal(await sbt.read.balanceOf([p.player]), 0n);
  }

  return {
    viem, sbt, publicClient, testClient, owner, backendSigner,
    playerA, playerB, attacker, domain, now, voucher, claim, assertUnclaimed,
  };
}

describe("ThanhTuuSBT — triển khai và EIP-712", () => {
  it("triển khai đúng tên, symbol, owner, signer và trạng thái ban đầu", async (t) => {
    const { sbt, publicClient, owner, backendSigner, playerA } = await setup(t);
    const code = await publicClient.getCode({ address: sbt.address });
    assert.ok(code && code !== "0x");
    assert.equal(await sbt.read.name(), "GoldRush Achievement");
    assert.equal(await sbt.read.symbol(), "GRSBT");
    assert.ok(isAddressEqual(await sbt.read.owner(), owner.account.address));
    assert.ok(isAddressEqual(await sbt.read.signer(), backendSigner.account.address));
    assert.equal(await sbt.read.MAX_ACHIEVEMENT_ID(), 5n);
    assert.equal(await sbt.read.balanceOf([playerA.account.address]), 0n);
    assert.equal(await sbt.read.supportsInterface(["0x80ac58cd"]), true);
  });

  it("từ chối owner là địa chỉ zero", async (t) => {
    const { viem, backendSigner } = await setup(t);
    await assert.rejects(
      viem.deployContract("ThanhTuuSBT", [zeroAddress, backendSigner.account.address]),
      (error: unknown) => String(error).includes("OwnableInvalidOwner"),
    );
  });

  it("từ chối signer ban đầu là địa chỉ zero", async (t) => {
    const { viem, owner } = await setup(t);
    await assert.rejects(
      viem.deployContract("ThanhTuuSBT", [owner.account.address, zeroAddress]),
      (error: unknown) => String(error).includes("InvalidSigner"),
    );
  });

  it("typehash và digest khớp viem; domain chứa đúng chain và địa chỉ hợp đồng", async (t) => {
    const { sbt, domain, voucher } = await setup(t);
    const { p } = await voucher();
    assert.equal(
      await sbt.read.PHIEU_SBT_TYPEHASH(),
      keccak256(toHex("PhieuSBT(address player,uint256 achievementId,bytes32 nonce,uint256 deadline)")),
    );
    assert.equal(await sbt.read.hashVoucher([p]), hashTypedData({
      domain, types: TYPES, primaryType: "PhieuSBT", message: p,
    }));
    const [fields, name, version, chainId, verifyingContract] = await sbt.read.eip712Domain();
    assert.equal(fields, "0x0f");
    assert.equal(name, domain.name);
    assert.equal(version, domain.version);
    assert.equal(chainId, BigInt(domain.chainId));
    assert.ok(isAddressEqual(verifyingContract, sbt.address));
  });
});

describe("ThanhTuuSBT — nhận và truy vấn thành tích", () => {
  it("nhận phiếu hợp lệ, mint đúng ví và phát sự kiện SBTClaimed/Transfer", async (t) => {
    const { sbt, playerA, playerB, voucher, claim } = await setup(t);
    const v = await voucher();
    const receipt = await claim(v);
    assert.ok(isAddressEqual(await sbt.read.ownerOf([1n]), playerA.account.address));
    assert.equal(await sbt.read.balanceOf([playerA.account.address]), 1n);
    assert.equal(await sbt.read.balanceOf([playerB.account.address]), 0n);
    assert.equal(await sbt.read.achievementOfToken([1n]), v.p.achievementId);
    assert.equal(await sbt.read.hasAchievement([playerA.account.address, v.p.achievementId]), true);
    assert.equal(await sbt.read.usedNonces([v.p.nonce]), true);
    const events = await sbt.getEvents.SBTClaimed({}, { blockHash: receipt.blockHash });
    assert.equal(events.length, 1);
    assert.deepEqual(events[0].args, {
      player: await sbt.read.ownerOf([1n]), tokenId: 1n, achievementId: 1n, nonce: v.p.nonce,
    });
    const transfers = await sbt.getEvents.Transfer({}, { blockHash: receipt.blockHash });
    assert.equal(transfers.length, 1);
    assert.equal(transfers[0].args.from, zeroAddress);
    assert.ok(isAddressEqual(transfers[0].args.to!, playerA.account.address));
    assert.equal(transfers[0].args.tokenId, 1n);
  });

  it("một ví nhận cả 5 loại thành tích với các tokenId riêng", async (t) => {
    const { sbt, playerA, voucher, claim } = await setup(t);
    for (let id = 1n; id <= 5n; id++) {
      await claim(await voucher({ achievementId: id }));
      assert.ok(isAddressEqual(await sbt.read.ownerOf([id]), playerA.account.address));
      assert.equal(await sbt.read.achievementOfToken([id]), id);
      assert.equal(await sbt.read.hasAchievement([playerA.account.address, id]), true);
    }
    assert.equal(await sbt.read.balanceOf([playerA.account.address]), 5n);
  });

  it("hai ví có thể nhận cùng achievementId bằng các nonce riêng", async (t) => {
    const { sbt, playerA, playerB, voucher, claim } = await setup(t);
    await claim(await voucher());
    await claim(await voucher({ player: playerB.account.address }), playerB);
    assert.equal(await sbt.read.hasAchievement([playerA.account.address, 1n]), true);
    assert.equal(await sbt.read.hasAchievement([playerB.account.address, 1n]), true);
    assert.ok(isAddressEqual(await sbt.read.ownerOf([2n]), playerB.account.address));
    assert.equal(await sbt.read.achievementOfToken([2n]), 1n);
  });

  it("không mint trùng thành tích kể cả có phiếu mới hợp lệ và nonce mới", async (t) => {
    const { sbt, playerA, voucher, claim } = await setup(t);
    await claim(await voucher());
    const second = await voucher();
    await assert.rejects(sbt.write.claimSBT([second.p, second.signature], { account: playerA.account }),
      customError("AchievementAlreadyClaimed", [playerA.account.address, 1n]));
    assert.equal(await sbt.read.usedNonces([second.p.nonce]), false);
    assert.equal(await sbt.read.balanceOf([playerA.account.address]), 1n);
    await claim(await voucher({ achievementId: 2n }));
    assert.equal(await sbt.read.achievementOfToken([2n]), 2n);
  });

  it("hasAchievement trả false với ví chưa nhận, thành tích khác và ID không hợp lệ", async (t) => {
    const { sbt, playerA, playerB, voucher, claim } = await setup(t);
    assert.equal(await sbt.read.hasAchievement([playerA.account.address, 1n]), false);
    await claim(await voucher());
    assert.equal(await sbt.read.hasAchievement([playerA.account.address, 1n]), true);
    assert.equal(await sbt.read.hasAchievement([playerB.account.address, 1n]), false);
    for (const id of [0n, 2n, 6n]) {
      assert.equal(await sbt.read.hasAchievement([playerA.account.address, id]), false);
    }
    assert.equal(await sbt.read.hasAchievement([zeroAddress, 1n]), false);
  });

  it("achievementOfToken và ownerOf từ chối token chưa tồn tại", async (t) => {
    const { sbt } = await setup(t);
    for (const tokenId of [0n, 1n, 999n]) {
      await assert.rejects(sbt.read.achievementOfToken([tokenId]), customError("ERC721NonexistentToken", [tokenId]));
      await assert.rejects(sbt.read.ownerOf([tokenId]), customError("ERC721NonexistentToken", [tokenId]));
    }
  });

  for (const achievementId of [0n, 6n, (1n << 256n) - 1n]) {
    it(`từ chối achievementId không hợp lệ: ${achievementId}`, async (t) => {
      const { sbt, playerA, voucher, assertUnclaimed } = await setup(t);
      const v = await voucher({ achievementId });
      await assert.rejects(sbt.write.claimSBT([v.p, v.signature], { account: playerA.account }),
        customError("InvalidAchievementId", [achievementId]));
      await assertUnclaimed(v.p);
    });
  }
});

describe("ThanhTuuSBT — chữ ký, hạn phiếu và chống replay", () => {
  it("từ chối chữ ký của attacker và người chơi; phiếu đúng vẫn dùng được sau đó", async (t) => {
    const { sbt, playerA, attacker, voucher, claim, assertUnclaimed } = await setup(t);
    const valid = await voucher();
    for (const signingWallet of [attacker, playerA]) {
      const forged = await voucher(valid.p, { signingWallet });
      await assert.rejects(sbt.write.claimSBT([forged.p, forged.signature], { account: playerA.account }),
        customError("InvalidSignature"));
      await assertUnclaimed(valid.p);
    }
    await claim(valid);
  });

  for (const signature of ["0x", "0x1234", `0x${"00".repeat(65)}`] as const) {
    it(`từ chối chữ ký sai định dạng (${(signature.length - 2) / 2} byte)`, async (t) => {
      const { sbt, playerA, voucher, assertUnclaimed } = await setup(t);
      const { p } = await voucher();
      await assert.rejects(sbt.write.claimSBT([p, signature], { account: playerA.account }),
        customError("InvalidSignature"));
      await assertUnclaimed(p);
    });
  }

  it("từ chối phiếu hết hạn mà không tiêu thụ nonce", async (t) => {
    const { sbt, playerA, now, voucher, assertUnclaimed } = await setup(t);
    const v = await voucher({ deadline: now - 1n });
    await assert.rejects(sbt.write.claimSBT([v.p, v.signature], { account: playerA.account }),
      customError("VoucherExpired"));
    await assertUnclaimed(v.p);
  });

  it("phiếu hợp lệ tại đúng deadline", async (t) => {
    const { publicClient, testClient, now, voucher, claim } = await setup(t);
    const v = await voucher({ deadline: now + 60n });
    await testClient.setNextBlockTimestamp({ timestamp: v.p.deadline });
    const receipt = await claim(v);
    assert.equal((await publicClient.getBlock({ blockHash: receipt.blockHash })).timestamp, v.p.deadline);
  });

  it("phiếu bị từ chối khi thời gian mạng vượt deadline một giây", async (t) => {
    const { sbt, testClient, playerA, now, voucher, assertUnclaimed } = await setup(t);
    const v = await voucher({ deadline: now + 60n });
    await testClient.setNextBlockTimestamp({ timestamp: v.p.deadline + 1n });
    await testClient.mine({ blocks: 1 });
    await assert.rejects(sbt.write.claimSBT([v.p, v.signature], { account: playerA.account }),
      customError("VoucherExpired"));
    await assertUnclaimed(v.p);
  });

  for (const field of ["achievementId", "player", "nonce", "deadline"] as const) {
    it(`từ chối phiếu bị sửa trường ${field} sau khi ký`, async (t) => {
      const { sbt, playerA, playerB, voucher, claim, assertUnclaimed } = await setup(t);
      const valid = await voucher();
      const replacements = {
        achievementId: 2n,
        player: playerB.account.address,
        nonce: keccak256(toHex("nonce-bi-sua")),
        deadline: valid.p.deadline + 600n,
      };
      const modified = { ...valid.p, [field]: replacements[field] };
      // Khi sửa player, gửi từ chính ví mới để đi qua kiểm tra WrongPlayer
      // và chứng minh trường player cũng được bảo vệ bởi chữ ký.
      const caller = field === "player" ? playerB : playerA;
      await assert.rejects(sbt.write.claimSBT([modified, valid.signature], { account: caller.account }),
        customError("InvalidSignature"));
      await assertUnclaimed(modified);
      assert.equal(await sbt.read.usedNonces([valid.p.nonce]), false);
      await claim(valid);
    });
  }

  it("không thể dùng lại đúng phiếu đã nhận", async (t) => {
    const { sbt, playerA, voucher, claim } = await setup(t);
    const v = await voucher();
    await claim(v);
    await assert.rejects(sbt.write.claimSBT([v.p, v.signature], { account: playerA.account }),
      customError("NonceAlreadyUsed", [v.p.nonce]));
    assert.equal(await sbt.read.balanceOf([playerA.account.address]), 1n);
  });

  it("nonce đã dùng bị từ chối cả với phiếu hợp lệ cho ví và thành tích khác", async (t) => {
    const { sbt, playerB, voucher, claim } = await setup(t);
    const first = await voucher();
    await claim(first);
    const second = await voucher({ player: playerB.account.address, achievementId: 2n, nonce: first.p.nonce });
    await assert.rejects(sbt.write.claimSBT([second.p, second.signature], { account: playerB.account }),
      customError("NonceAlreadyUsed", [first.p.nonce]));
    assert.equal(await sbt.read.hasAchievement([playerB.account.address, 2n]), false);
    assert.equal(await sbt.read.balanceOf([playerB.account.address]), 0n);
  });

  it("playerB và attacker không thể gửi phiếu dành cho playerA", async (t) => {
    const { sbt, playerB, attacker, voucher, claim, assertUnclaimed } = await setup(t);
    const v = await voucher();
    for (const wallet of [playerB, attacker]) {
      await assert.rejects(sbt.write.claimSBT([v.p, v.signature], { account: wallet.account }),
        customError("WrongPlayer"));
      assert.equal(await sbt.read.balanceOf([wallet.account.address]), 0n);
    }
    await assertUnclaimed(v.p);
    await claim(v);
  });

  for (const field of ["chainId", "verifyingContract", "name", "version"] as const) {
    it(`từ chối chữ ký dùng domain sai ${field}`, async (t) => {
      const { sbt, playerA, domain, voucher, claim, assertUnclaimed } = await setup(t);
      const valid = await voucher();
      const replacements = { chainId: domain.chainId + 1, verifyingContract: playerA.account.address,
        name: "GoldRush", version: "2" };
      const forged = await voucher(valid.p, { signingDomain: { ...domain, [field]: replacements[field] } });
      await assert.rejects(sbt.write.claimSBT([forged.p, forged.signature], { account: playerA.account }),
        customError("InvalidSignature"));
      await assertUnclaimed(valid.p);
      await claim(valid);
    });
  }

  it("phiếu hợp lệ của hợp đồng thứ nhất không dùng được trên hợp đồng thứ hai", async (t) => {
    const { viem, owner, backendSigner, playerA, voucher, claim } = await setup(t);
    const other = await viem.deployContract("ThanhTuuSBT", [owner.account.address, backendSigner.account.address]);
    const v = await voucher();
    await assert.rejects(other.write.claimSBT([v.p, v.signature], { account: playerA.account }),
      customError("InvalidSignature"));
    assert.equal(await other.read.usedNonces([v.p.nonce]), false);
    assert.equal(await other.read.balanceOf([playerA.account.address]), 0n);
    await claim(v);
  });
});

describe("ThanhTuuSBT — không chuyển nhượng và không phê duyệt", () => {
  for (const method of ["transferFrom", "safeTransferFrom", "safeTransferFromWithData"] as const) {
    it(`chặn ${method} từ playerA sang playerB`, async (t) => {
      const { sbt, playerA, playerB, voucher, claim } = await setup(t);
      await claim(await voucher());
      const args = [playerA.account.address, playerB.account.address, 1n] as const;
      const account = { account: playerA.account };
      const transfer = method === "transferFrom" ? sbt.write.transferFrom(args, account)
        : method === "safeTransferFrom" ? sbt.write.safeTransferFrom(args, account)
        : sbt.write.safeTransferFrom([...args, "0x1234"], account);
      await assert.rejects(transfer, customError("Soulbound"));
      assert.ok(isAddressEqual(await sbt.read.ownerOf([1n]), playerA.account.address));
      assert.equal(await sbt.read.balanceOf([playerA.account.address]), 1n);
      assert.equal(await sbt.read.balanceOf([playerB.account.address]), 0n);
      assert.equal(await sbt.read.hasAchievement([playerA.account.address, 1n]), true);
      assert.equal(await sbt.read.hasAchievement([playerB.account.address, 1n]), false);
    });
  }

  it("chặn approve; không có địa chỉ được phê duyệt", async (t) => {
    const { sbt, playerA, playerB, voucher, claim } = await setup(t);
    await claim(await voucher());
    // Solidity đánh dấu pure nên viem đưa approve vào nhóm read, giống test cửa hàng.
    await assert.rejects(sbt.read.approve([playerB.account.address, 1n], { account: playerA.account }),
      customError("Soulbound"));
    assert.equal(await sbt.read.getApproved([1n]), zeroAddress);
  });

  for (const approved of [true, false]) {
    it(`chặn setApprovalForAll(${approved})`, async (t) => {
      const { sbt, playerA, playerB, voucher, claim } = await setup(t);
      await claim(await voucher());
      await assert.rejects(
        sbt.read.setApprovalForAll([playerB.account.address, approved], { account: playerA.account }),
        customError("Soulbound"),
      );
      assert.equal(await sbt.read.isApprovedForAll([playerA.account.address, playerB.account.address]), false);
    });
  }
});

describe("ThanhTuuSBT — quản lý Backend signer", () => {
  it("owner đổi signer, phát sự kiện, từ chối phiếu cũ và chấp nhận phiếu ký lại", async (t) => {
    const { sbt, publicClient, owner, backendSigner, playerA, playerB, voucher, claim, assertUnclaimed } = await setup(t);
    const old = await voucher();
    const hash = await sbt.write.setSigner([playerB.account.address], { account: owner.account });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    assert.equal(receipt.status, "success");
    assert.ok(isAddressEqual(await sbt.read.signer(), playerB.account.address));
    const events = await sbt.getEvents.SignerUpdated({}, { blockHash: receipt.blockHash });
    assert.equal(events.length, 1);
    assert.ok(isAddressEqual(events[0].args.previousSigner!, backendSigner.account.address));
    assert.ok(isAddressEqual(events[0].args.newSigner!, playerB.account.address));
    await assert.rejects(sbt.write.claimSBT([old.p, old.signature], { account: playerA.account }),
      customError("InvalidSignature"));
    await assertUnclaimed(old.p);
    await claim(await voucher(old.p, { signingWallet: playerB }));
  });

  it("player, attacker và cả signer đều không được tự cập nhật signer", async (t) => {
    const { sbt, backendSigner, playerA, playerB, attacker } = await setup(t);
    for (const wallet of [playerA, playerB, attacker, backendSigner]) {
      await assert.rejects(sbt.write.setSigner([attacker.account.address], { account: wallet.account }),
        customError("OwnableUnauthorizedAccount", [wallet.account.address]));
      assert.ok(isAddressEqual(await sbt.read.signer(), backendSigner.account.address));
    }
  });

  it("owner không thể đổi signer sang địa chỉ zero", async (t) => {
    const { sbt, owner, backendSigner } = await setup(t);
    await assert.rejects(sbt.write.setSigner([zeroAddress], { account: owner.account }), customError("InvalidSigner"));
    assert.ok(isAddressEqual(await sbt.read.signer(), backendSigner.account.address));
  });

  it("đổi signer không làm mất quyền sở hữu hoặc cho phép dùng lại nonce", async (t) => {
    const { sbt, owner, playerA, playerB, voucher, claim } = await setup(t);
    const first = await voucher();
    await claim(first);
    await sbt.write.setSigner([playerB.account.address], { account: owner.account });
    const replay = await voucher(first.p, { signingWallet: playerB });
    await assert.rejects(sbt.write.claimSBT([replay.p, replay.signature], { account: playerA.account }),
      customError("NonceAlreadyUsed", [first.p.nonce]));
    const duplicate = await voucher({}, { signingWallet: playerB });
    await assert.rejects(sbt.write.claimSBT([duplicate.p, duplicate.signature], { account: playerA.account }),
      customError("AchievementAlreadyClaimed", [playerA.account.address, 1n]));
    assert.ok(isAddressEqual(await sbt.read.ownerOf([1n]), playerA.account.address));
    assert.equal(await sbt.read.hasAchievement([playerA.account.address, 1n]), true);
  });
});
