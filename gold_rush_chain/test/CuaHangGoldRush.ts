import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { encodeFunctionData, keccak256, toFunctionSelector, toHex } from "viem";

// Phiếu do MÁY CHỦ PYTHON ký (gold_rush_ai/scripts/sinh_phieu_mau.py) — kiểm chứng hai bên khớp nhau.
const MAU = JSON.parse(readFileSync(new URL("../du-lieu-kiem-thu/phieu_mau.json", import.meta.url), "utf8"));
// Calldata do APP DART tạo (Python sinh mẫu, test Dart so từng byte) — ở đây so với viem.
const ABI_MAU = JSON.parse(
  readFileSync(new URL("../../gold_rush/test/blockchain/abi_mau.json", import.meta.url), "utf8"),
);

const KIEU = {
  PhieuVang: [
    { name: "nguoiChoi", type: "address" },
    { name: "man", type: "uint256" },
    { name: "ve", type: "uint256" },
    { name: "soVang", type: "uint256" },
    { name: "maVan", type: "bytes32" },
    { name: "hanChot", type: "uint256" },
  ],
} as const;

/** Lỗi có tên `ten` (custom error) — viem đưa tên lỗi vào thông điệp. */
const loi = (ten: string) => (e: unknown) => String(e).includes(ten);

// Màn 1 luyện tập (24 xu), màn 2 cọc 5 vàng (18 xu + 5 thưởng), màn 3 cọc 8 (20 + 8) — như man_choi.json
const MAN = [
  [1n, 0n, 24n],
  [2n, 5n, 23n],
  [3n, 8n, 28n],
] as const;

async function dung() {
  const { viem } = await network.create();
  const [chu, trongTai, nguoiChoi, keGian] = await viem.getWalletClients();
  const so = await viem.deployContract("CuaHangGoldRush", [trongTai.account.address, "uri://{id}"]);
  for (const [id, coc, tran] of MAN) await so.write.datMan([id, coc, tran], { account: chu.account });
  const pc = await viem.getPublicClient();
  const bayGio = (await pc.getBlock()).timestamp;
  const chainId = await pc.getChainId();

  /** Trọng tài ký phiếu bằng viem — đúng việc máy chủ Python làm. */
  async function phieu(
    soVang: bigint,
    maVan: string,
    { man = 1n, ve = 0n, nguoi = nguoiChoi, nguoiKy = trongTai, han = bayGio + 900n } = {},
  ) {
    const p = { nguoiChoi: nguoi.account.address, man, ve, soVang, maVan: keccak256(toHex(maVan)), hanChot: han };
    const chuKy = await nguoiKy.signTypedData({
      account: nguoiKy.account,
      domain: { name: "GoldRush", version: "2", chainId, verifyingContract: so.address },
      types: KIEU,
      primaryType: "PhieuVang",
      message: p,
    });
    return { p, chuKy };
  }
  const nc = { account: nguoiChoi.account };
  const vang = () => so.read.balanceOf([nguoiChoi.account.address, 0n]);
  /** Cho người chơi `n` vàng bằng các ván luyện tập. */
  async function choVang(n: bigint) {
    let i = 0;
    while (n > 0n) {
      const x = n > 24n ? 24n : n;
      const { p, chuKy } = await phieu(x, `luyen-tap-${i++}`);
      await so.write.nhanVang([p, chuKy], nc);
      n -= x;
    }
  }
  return { viem, pc, so, chu, trongTai, nguoiChoi, keGian, phieu, bayGio, nc, vang, choVang };
}

describe("Vàng — màn luyện tập", () => {
  it("nhận vàng bằng phiếu hợp lệ", async () => {
    const { so, nc, vang, phieu } = await dung();
    const { p, chuKy } = await phieu(7n, "van-1");
    await so.write.nhanVang([p, chuKy], nc);
    assert.equal(await vang(), 7n);
    assert.equal(await so.read.daDoi([p.maVan]), true);
  });

  it("mỗi ván chỉ đổi một lần", async () => {
    const { so, nc, phieu } = await dung();
    const { p, chuKy } = await phieu(7n, "van-1");
    await so.write.nhanVang([p, chuKy], nc);
    await assert.rejects(so.write.nhanVang([p, chuKy], nc), loi("PhieuDaDung"));
  });

  it("ví khác không dùng được phiếu (chống cướp giao dịch đang chờ)", async () => {
    const { so, keGian, phieu } = await dung();
    const { p, chuKy } = await phieu(7n, "van-1");
    await assert.rejects(so.write.nhanVang([p, chuKy], { account: keGian.account }), loi("SaiNguoiNhan"));
  });

  it("chữ ký không phải của trọng tài, hoặc sửa phiếu sau khi ký, đều bị từ chối", async () => {
    const { so, nc, nguoiChoi, phieu } = await dung();
    const tuKy = await phieu(24n, "van-tu-ky", { nguoiKy: nguoiChoi });
    await assert.rejects(so.write.nhanVang([tuKy.p, tuKy.chuKy], nc), loi("ChuKySai"));
    const { p, chuKy } = await phieu(3n, "van-1");
    await assert.rejects(so.write.nhanVang([{ ...p, soVang: 24n }, chuKy], nc), loi("ChuKySai"));
  });

  it("quá hạn, 0 vàng, vượt trần của màn, màn chưa mở, ghi vé cho màn luyện tập: từ chối", async () => {
    const { so, nc, phieu, bayGio } = await dung();
    const cases: [Awaited<ReturnType<typeof phieu>>, string][] = [
      [await phieu(5n, "a", { han: bayGio - 1n }), "PhieuHetHan"],
      [await phieu(0n, "b"), "SoVangKhongHopLe"],
      [await phieu(25n, "c"), "SoVangKhongHopLe"],
      [await phieu(5n, "d", { man: 9n }), "ManKhongTonTai"],
      [await phieu(5n, "e", { ve: 1n }), "SaiVe"],
    ];
    for (const [{ p, chuKy }, ten] of cases) await assert.rejects(so.write.nhanVang([p, chuKy], nc), loi(ten));
  });

  it("đổi trọng tài thì phiếu ký bằng khoá cũ vô hiệu", async () => {
    const { so, chu, keGian, nc, phieu } = await dung();
    const { p, chuKy } = await phieu(5n, "van-1");
    await so.write.doiTrongTai([keGian.account.address], { account: chu.account });
    await assert.rejects(so.write.nhanVang([p, chuKy], nc), loi("ChuKySai"));
  });
});

describe("Màn có cọc — tự động trừ vàng khi không hoàn thành", () => {
  it("vào màn đốt cọc ngay; hoàn thành thì nhận lại cọc + xu + thưởng, vé đóng", async () => {
    const { so, nc, nguoiChoi, vang, choVang, phieu } = await dung();
    await choVang(10n);
    await so.write.vaoMan([2n], nc);
    assert.equal(await vang(), 5n, "cọc 5 bị đốt khi vào màn");
    assert.deepEqual(await so.read.ve([nguoiChoi.account.address]), [2n, 1n, 5n]);

    const { p, chuKy } = await phieu(23n, "man2-thang", { man: 2n, ve: 1n });   // 18 xu + 5 thưởng
    await so.write.nhanVang([p, chuKy], nc);
    assert.equal(await vang(), 5n + 5n + 23n);
    assert.deepEqual(await so.read.ve([nguoiChoi.account.address]), [0n, 0n, 0n]);
  });

  it("không hoàn thành: không có phiếu → cọc mất; vào màn khác thì vé cũ bị bỏ (sự kiện MatCoc)", async () => {
    const { so, pc, nc, nguoiChoi, vang, choVang, phieu } = await dung();
    await choVang(20n);
    await so.write.vaoMan([2n], nc);                                // thua màn 2: không làm gì cả
    const tx = await so.write.vaoMan([3n], nc);
    const ev = await so.getEvents.MatCoc({}, { blockHash: (await pc.getTransactionReceipt({ hash: tx })).blockHash });
    assert.equal(ev.length, 1);
    assert.deepEqual([ev[0].args.man, ev[0].args.so, ev[0].args.coc], [2n, 1n, 5n]);
    assert.equal(await vang(), 20n - 5n - 8n);

    // Phiếu của vé 1 (màn 2) không còn dùng được — cọc màn 2 mất hẳn
    const cu = await phieu(23n, "man2-muon", { man: 2n, ve: 1n });
    await assert.rejects(so.write.nhanVang([cu.p, cu.chuKy], nc), loi("SaiVe"));
    assert.deepEqual(await so.read.ve([nguoiChoi.account.address]), [3n, 2n, 8n]);
  });

  it("thiếu vàng để cọc, màn luyện tập, màn không tồn tại: không vào được", async () => {
    const { so, nc, choVang } = await dung();
    await assert.rejects(so.write.vaoMan([2n], nc), loi("ERC1155InsufficientBalance"));
    await choVang(30n);
    await assert.rejects(so.write.vaoMan([1n], nc), loi("ManMienPhi"));
    await assert.rejects(so.write.vaoMan([7n], nc), loi("ManKhongTonTai"));
  });

  it("phiếu ghi sai màn, sai vé, hoặc vé 0 cho màn có cọc: SaiVe", async () => {
    const { so, nc, choVang, phieu } = await dung();
    await choVang(10n);
    await so.write.vaoMan([2n], nc);
    for (const [man, ve] of [[3n, 1n], [2n, 2n], [2n, 0n]] as const) {
      const { p, chuKy } = await phieu(10n, `sai-${man}-${ve}`, { man, ve });
      await assert.rejects(so.write.nhanVang([p, chuKy], nc), loi("SaiVe"));
    }
  });

  it("hoàn đúng số cọc đã đốt, kể cả khi chủ hợp đồng đổi cọc giữa chừng", async () => {
    const { so, chu, nc, vang, choVang, phieu } = await dung();
    await choVang(5n);
    await so.write.vaoMan([2n], nc);
    await so.write.datMan([2n, 50n, 23n], { account: chu.account });
    const { p, chuKy } = await phieu(10n, "m2", { man: 2n, ve: 1n });
    await so.write.nhanVang([p, chuKy], nc);
    assert.equal(await vang(), 5n + 10n);
  });
});

describe("Gộp giao dịch (multicall) — MetaMask chỉ hỏi một lần", () => {
  it("nhận 2 phiếu đang chờ + vào màn mới trong MỘT giao dịch", async () => {
    const { so, nc, nguoiChoi, vang, phieu } = await dung();
    const a = await phieu(4n, "cho-1");
    const b = await phieu(6n, "cho-2");
    const goi = [
      encodeFunctionData({ abi: so.abi, functionName: "nhanVang", args: [a.p, a.chuKy] }),
      encodeFunctionData({ abi: so.abi, functionName: "nhanVang", args: [b.p, b.chuKy] }),
      encodeFunctionData({ abi: so.abi, functionName: "vaoMan", args: [3n] }),
    ];
    await so.write.multicall([goi], nc);
    assert.equal(await vang(), 10n - 8n);
    assert.deepEqual(await so.read.ve([nguoiChoi.account.address]), [3n, 1n, 8n]);
  });

  it("nguyên tử: một phần lỗi thì CẢ giao dịch hoàn tác, phiếu vẫn còn dùng được", async () => {
    const { so, chu, nc, vang, phieu } = await dung();
    await so.write.datGia([1n, 10n], { account: chu.account });
    const a = await phieu(4n, "cho-1");
    const goi = [
      encodeFunctionData({ abi: so.abi, functionName: "nhanVang", args: [a.p, a.chuKy] }),
      encodeFunctionData({ abi: so.abi, functionName: "mua", args: [1n] }),       // thiếu vàng
    ];
    await assert.rejects(so.write.multicall([goi], nc), loi("ERC1155InsufficientBalance"));
    assert.equal(await vang(), 0n);
    assert.equal(await so.read.daDoi([a.p.maVan]), false);
  });
});

describe("Nhân vật", () => {
  it("mua nhân vật: đốt đúng số vàng, nhận 1 nhân vật, không mua trùng", async () => {
    const { so, chu, nc, nguoiChoi, vang, choVang } = await dung();
    await so.write.datGia([1n, 10n], { account: chu.account });
    await choVang(14n);
    await so.write.mua([1n], nc);
    assert.equal(await vang(), 4n);
    assert.equal(await so.read.balanceOf([nguoiChoi.account.address, 1n]), 1n);
    await assert.rejects(so.write.mua([1n], nc), loi("DaCo"));
  });

  it("thiếu vàng, nhân vật chưa bán, hoặc mua 'vàng' đều bị từ chối", async () => {
    const { so, chu, nc } = await dung();
    await so.write.datGia([2n, 30n], { account: chu.account });
    await assert.rejects(so.write.mua([2n], nc), loi("ERC1155InsufficientBalance"));
    await assert.rejects(so.write.mua([9n], nc), loi("KhongBan"));
    await assert.rejects(so.write.mua([0n], nc), loi("KhongBan"));
  });

  it("chỉ chủ hợp đồng được đặt giá và mở màn", async () => {
    const { so, keGian } = await dung();
    const k = { account: keGian.account };
    await assert.rejects(so.write.datGia([1n, 1n], k), loi("OwnableUnauthorizedAccount"));
    await assert.rejects(so.write.datMan([2n, 0n, 999n], k), loi("OwnableUnauthorizedAccount"));
  });
});

describe("Không chuyển nhượng", () => {
  it("không chuyển vàng, không chuyển nhân vật, không uỷ quyền", async () => {
    const { so, nc, nguoiChoi, keGian, choVang } = await dung();
    await choVang(7n);
    await assert.rejects(
      so.write.safeTransferFrom([nguoiChoi.account.address, keGian.account.address, 0n, 1n, "0x"], nc),
      loi("KhongChuyenNhuong"),
    );
    // setApprovalForAll là `pure` trong ABI → viem xếp nó vào `read`.
    await assert.rejects(so.read.setApprovalForAll([keGian.account.address, true], nc), loi("KhongChuyenNhuong"));
  });
});

describe("Đối chiếu với máy chủ Python và app Dart", () => {
  it("phiếu (màn có cọc) do Python ký được hợp đồng chấp nhận", async () => {
    // Mạng MỚI → hợp đồng đầu tiên của tài khoản #0 (nonce 0) có địa chỉ cố định 0x5FbDB…
    const { viem } = await network.create();
    const [chu, trongTai, nguoiChoi] = await viem.getWalletClients();
    const so = await viem.deployContract("CuaHangGoldRush", [trongTai.account.address, "uri://{id}"]);
    assert.equal(so.address.toLowerCase(), MAU.hop_dong.toLowerCase());
    assert.equal(trongTai.account.address.toLowerCase(), MAU.trong_tai.toLowerCase());
    const nc = { account: nguoiChoi.account };
    for (const [id, coc, tran] of MAN) await so.write.datMan([id, coc, tran], { account: chu.account });

    const big = (o: Record<string, unknown>) =>
      Object.fromEntries(Object.entries(o).map(([k, v]) => [k, typeof v === "number" ? BigInt(v) : v]));
    // Phiếu luyện tập 10 vàng → đủ cọc màn 2 → vé số 1 → phiếu hoàn thành màn 2 do Python ký
    const lt = big(MAU.luyen_tap.phieu) as never;
    const m2 = big(MAU.man_coc.phieu) as never;
    assert.equal(await so.read.bamPhieu([lt]), MAU.luyen_tap.bam);
    assert.equal(await so.read.bamPhieu([m2]), MAU.man_coc.bam);
    await so.write.nhanVang([lt, MAU.luyen_tap.chu_ky], nc);
    await so.write.vaoMan([2n], nc);
    await so.write.nhanVang([m2, MAU.man_coc.chu_ky], nc);
    assert.equal(await so.read.balanceOf([nguoiChoi.account.address, 0n]), 10n - 5n + 5n + 23n);
  });

  it("calldata mẫu (Python sinh, app Dart phải khớp) trùng từng byte với viem", async () => {
    const { viem } = await network.create();
    const [, trongTai] = await viem.getWalletClients();
    const so = await viem.deployContract("CuaHangGoldRush", [trongTai.account.address, "uri://{id}"]);
    const abi = so.abi;
    const pv = (j: Record<string, unknown>) => ({
      ...(j as { nguoiChoi: `0x${string}`; maVan: `0x${string}` }),
      man: BigInt(j.man as number), ve: BigInt(j.ve as number),
      soVang: BigInt(j.soVang as number), hanChot: BigInt(j.hanChot as number),
    });
    const nv = ABI_MAU.nhanVang;
    const goiNhanVang = encodeFunctionData({ abi, functionName: "nhanVang", args: [pv(nv.phieu), nv.chu_ky] });
    assert.equal(goiNhanVang, nv.calldata);
    assert.equal(encodeFunctionData({ abi, functionName: "vaoMan", args: [BigInt(ABI_MAU.vaoMan.man)] }),
      ABI_MAU.vaoMan.calldata);
    assert.equal(encodeFunctionData({ abi, functionName: "mua", args: [BigInt(ABI_MAU.mua.nhan_vat)] }),
      ABI_MAU.mua.calldata);
    assert.equal(encodeFunctionData({ abi, functionName: "daDoi", args: [ABI_MAU.daDoi.ma_van] }),
      ABI_MAU.daDoi.calldata);
    assert.equal(encodeFunctionData({ abi, functionName: "ve", args: [ABI_MAU.ve.vi] }), ABI_MAU.ve.calldata);
    assert.equal(encodeFunctionData({ abi, functionName: "manChoi", args: [BigInt(ABI_MAU.manChoi.man)] }),
      ABI_MAU.manChoi.calldata);
    assert.equal(
      encodeFunctionData({ abi, functionName: "multicall", args: [ABI_MAU.multicall.cac_lenh] }),
      ABI_MAU.multicall.calldata,
    );
    // Bộ chọn của các lỗi tuỳ biến mà app dịch sang tiếng Việt
    const cacLoi = abi.filter((x) => x.type === "error");
    for (const [chon, ten] of Object.entries(ABI_MAU.loi) as [string, string][]) {
      const muc = cacLoi.find((x) => x.name === ten);
      assert.ok(muc, `ABI không có lỗi ${ten}`);
      assert.equal(toFunctionSelector(`${ten}(${muc.inputs.map((i) => i.type).join(",")})`), chon, ten);
    }
  });
});
