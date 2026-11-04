"""Kiểm thử ĐẦU–CUỐI không cần app/trình duyệt: máy chủ trọng tài thật + chuỗi Hardhat thật.

Đóng vai app Gold Rush: chơi (giả lập) màn luyện tập → nhận vàng → vào màn 2 có cọc → THUA (mất cọc)
→ vào lại màn 2 → THẮNG → nhận cọc + xu + thưởng và mua nhân vật trong CÙNG MỘT giao dịch (multicall).

Cần chạy sẵn (xem README):  npx hardhat node  ·  ignition deploy  ·  uvicorn api.main:app --port 8000
    pip install eth-account          # chỉ script này cần, để ký giao dịch thay MetaMask
    python scripts/thu_dau_cuoi.py

Khoá dùng ở đây là khoá thử CÔNG KHAI #2 của Hardhat — chỉ có nghĩa trên mạng 31337.
"""
import json
import sys
import time
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core.luoi import doc_tmx  # noqa: E402
from scripts.sinh_abi_mau import PHIEU, goi  # noqa: E402
from tests.test_trong_tai import TILES, van_that  # noqa: E402

try:
    from eth_account import Account
except ImportError:
    raise SystemExit("Cần: pip install eth-account")

RPC, API = "http://127.0.0.1:8545", "http://127.0.0.1:8000"
NGUOI_CHOI = Account.from_key("0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a")
VI = NGUOI_CHOI.address


def _http(url, du_lieu=None):
    yc = urllib.request.Request(url, data=None if du_lieu is None else json.dumps(du_lieu).encode(),
                                headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(yc, timeout=30) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def rpc(phuong_thuc, *tham_so):
    _, j = _http(RPC, {"jsonrpc": "2.0", "id": 1, "method": phuong_thuc, "params": list(tham_so)})
    if "error" in j:
        raise RuntimeError(j["error"])
    return j["result"]


CH = _http(f"{API}/api/vang/cau-hinh")[1]
HOP_DONG = CH["hop_dong"]


def doc(ham, kieu, gia_tri, so_tu=1):
    kq = rpc("eth_call", {"to": HOP_DONG, "data": goi(ham, kieu, gia_tri)}, "latest")[2:]
    return [int(kq[i * 64:(i + 1) * 64], 16) for i in range(so_tu)]


def vang():
    return doc("balanceOf(address,uint256)", ["address", "uint256"], [VI, 0])[0]


def gui(du_lieu, nhan):
    """Đúng các bước bộ giao dịch của app: mô phỏng → ước lượng gas (+20%) → ký → gửi → chờ biên lai."""
    tx = {"from": VI, "to": HOP_DONG, "data": du_lieu}
    rpc("eth_call", tx, "latest")                                      # revert ở đây = không làm phiền ví
    gas = int(rpc("eth_estimateGas", tx), 16) * 12 // 10
    ky = NGUOI_CHOI.sign_transaction({
        "to": HOP_DONG, "data": du_lieu, "gas": gas, "chainId": CH["chain_id"],
        "nonce": int(rpc("eth_getTransactionCount", VI, "pending"), 16),
        "maxFeePerGas": int(rpc("eth_gasPrice"), 16) * 2, "maxPriorityFeePerGas": 10**9,
    })
    ma = rpc("eth_sendRawTransaction", "0x" + ky.raw_transaction.hex().removeprefix("0x"))
    for _ in range(60):
        bl = rpc("eth_getTransactionReceipt", ma)
        if bl:
            assert bl["status"] == "0x1", f"{nhan}: revert"
            print(f"  ✓ {nhan}  (gas {int(bl['gasUsed'], 16):,})")
            return
        time.sleep(0.5)
    raise RuntimeError("quá lâu")


def nhan_vang_calldata(p):
    q, ck = p["phieu"], p["chu_ky"]
    return goi(f"nhanVang({PHIEU},bytes)", [PHIEU, "bytes"],
               [[q["nguoiChoi"], q["man"], q["ve"], q["soVang"], q["maVan"], q["hanChot"]], ck])


def choi(man, ban_do, so_xu, ket_qua, ma=None):
    nk = van_that(doc_tmx(TILES / ban_do), so_xu, ket_qua=ket_qua)
    ma = ma or str(uuid.uuid4())
    than = {"ma_van": ma, "phien_ban_app": "1.3.0", "man": man, "ban_do": ban_do, **nk}
    assert _http(f"{API}/api/nhat-ky", than)[0] == 201
    return ma, nk


print(f"Ví người chơi {VI} · hợp đồng {HOP_DONG}")
print(f"Vàng ban đầu: {vang()}")

print("\n1. Màn luyện tập (24 xu), nhặt 12 xu rồi chết")
ma, _ = choi(1, "gold_rush.tmx", 12, "thua")
st, p1 = _http(f"{API}/api/vang/phieu", {"ma_van": ma, "vi": VI})
assert st == 200, p1
gui(nhan_vang_calldata(p1), "nhanVang 12 vàng")
v0 = vang()

print("\n2. Vào màn 2 (cọc 5) rồi THUA — không có giao dịch nào lúc thua")
gui(goi("vaoMan(uint256)", ["uint256"], [2]), "vaoMan(2)")
man_, so_ve, coc = doc("ve(address)", ["address"], [VI], 3)
ma = str(uuid.uuid4())
assert _http(f"{API}/api/man/bat-dau", {"ma_van": ma, "vi": VI, "man": 2, "ve": so_ve})[0] == 201
choi(2, "man_2.tmx", 7, "thua", ma)
st, j = _http(f"{API}/api/vang/phieu", {"ma_van": ma, "vi": VI})
print(f"  máy chủ: {st} {j['detail']['ly_do'][0] if st == 422 else j}")
assert st == 422 and vang() == v0 - 5
print(f"  vàng: {v0} → {vang()}  (mất cọc 5)")

print("\n3. Vào lại màn 2 (vé mới), chơi trọn vẹn và THẮNG")
gui(goi("vaoMan(uint256)", ["uint256"], [2]), "vaoMan(2) — vé cũ bị bỏ (sự kiện MatCoc)")
_, so_ve, _ = doc("ve(address)", ["address"], [VI], 3)
ma = str(uuid.uuid4())
assert _http(f"{API}/api/man/bat-dau", {"ma_van": ma, "vi": VI, "man": 2, "ve": so_ve})[0] == 201
nk = van_that(doc_tmx(TILES / "man_2.tmx"), 18, ket_qua="thang")
print(f"  đang 'chơi' {nk['giay']:.0f} giây thật (máy chủ đối chiếu đồng hồ)…", flush=True)
time.sleep(nk["giay"])
choi(2, "man_2.tmx", 18, "thang", ma)
st, p2 = _http(f"{API}/api/vang/phieu", {"ma_van": ma, "vi": VI})
assert st == 200, p2
print(f"  phiếu: màn {p2['phieu']['man']}, vé {p2['phieu']['ve']}, {p2['phieu']['soVang']} vàng (+ cọc hoàn lại)")

print("\n4. Một giao dịch: nhận phiếu màn 2 + mua Thợ mỏ (10 vàng)")
truoc = vang()
gui(goi("multicall(bytes[])", ["bytes[]"], [[nhan_vang_calldata(p2), goi("mua(uint256)", ["uint256"], [1])]]),
    "multicall[nhanVang, mua(1)]")
print(f"  vàng: {truoc} → {vang()}  (+5 cọc +23 xu/thưởng −10 nhân vật)")
assert vang() == truoc + 5 + 23 - 10
assert doc("balanceOf(address,uint256)", ["address", "uint256"], [VI, 1])[0] == 1
assert doc("daDoi(bytes32)", ["bytes32"], [p2["phieu"]["maVan"]])[0] == 1

print("\n5. Phiếu chờ nhận sau khi 'tải lại trang': máy chủ ký lại, app lọc bằng daDoi")
cho = _http(f"{API}/api/vang/cho-nhan?vi={VI}")[1]["phieu"]
con = [p for p in cho if not doc("daDoi(bytes32)", ["bytes32"], [p["phieu"]["maVan"]])[0]]
print(f"  {len(cho)} phiếu đã cấp, {len(con)} chưa nộp")
assert not con
print("\nĐẦU–CUỐI: ĐẠT")
