"""Sinh ca kiểm thử mã hoá ABI cho app Dart (`test/blockchain/abi_test.dart`) và Hardhat.

Bộ mã hoá ở đây viết THEO ĐẶC TẢ ABI tổng quát (đầu/đuôi, offset cho kiểu động, mảng động) —
khác cách viết chuyên biệt bên Dart — nên hai bên khớp nhau là bằng chứng có giá trị. Bài kiểm thử
Hardhat so tiếp các calldata này với `encodeFunctionData` của viem: ba bộ mã hoá độc lập.

    python scripts/sinh_abi_mau.py   →  ../gold_rush/test/blockchain/abi_mau.json
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core.eth_ky import keccak256  # noqa: E402

GOC = Path(__file__).resolve().parents[2]


def tu(n: int) -> bytes:
    return int(n).to_bytes(32, "big")


def _tach(kieu_tuple: str) -> list[str]:
    """'(a,(b,c),d)' → ['a', '(b,c)', 'd']"""
    ra, sau, buoc = [], 0, ""
    for ch in kieu_tuple[1:-1]:
        if ch == "," and sau == 0:
            ra.append(buoc); buoc = ""
            continue
        sau += (ch == "(") - (ch == ")")
        buoc += ch
    return ra + [buoc]


def la_dong(kieu: str) -> bool:
    if kieu in ("bytes", "string") or kieu.endswith("[]"):
        return True
    return kieu.startswith("(") and any(la_dong(k) for k in _tach(kieu))


def ma_hoa(kieu: str, gt) -> bytes:
    if kieu == "uint256":
        return tu(gt)
    if kieu == "address":
        return tu(int(gt, 16))
    if kieu == "bytes32":
        return bytes.fromhex(gt[2:])
    if kieu == "bytes":
        b = bytes.fromhex(gt[2:])
        return tu(len(b)) + b + b"\x00" * ((-len(b)) % 32)
    if kieu.endswith("[]"):
        con = kieu[:-2]
        return tu(len(gt)) + ma_hoa_danh_sach([con] * len(gt), gt)
    if kieu.startswith("("):
        return ma_hoa_danh_sach(_tach(kieu), gt)
    raise ValueError(kieu)


def ma_hoa_danh_sach(kieu: list[str], gia_tri: list) -> bytes:
    """Phần đầu: giá trị tĩnh hoặc OFFSET (tính từ đầu danh sách) tới phần đuôi của giá trị động."""
    cac = [(ma_hoa(k, v), la_dong(k)) for k, v in zip(kieu, gia_tri)]
    kich_dau = sum(32 if dong else len(m) for m, dong in cac)
    dau, duoi = [], b""
    for m, dong in cac:
        if dong:
            dau.append(tu(kich_dau + len(duoi)))
            duoi += m
        else:
            dau.append(m)
    return b"".join(dau) + duoi


def chon(chu_ky_ham: str) -> bytes:
    return keccak256(chu_ky_ham.encode())[:4]


def goi(chu_ky_ham: str, kieu: list[str], gia_tri: list) -> str:
    return "0x" + (chon(chu_ky_ham) + ma_hoa_danh_sach(kieu, gia_tri)).hex()


PHIEU = "(address,uint256,uint256,uint256,bytes32,uint256)"


def nhan_vang(m: dict) -> str:
    p = m["phieu"]
    return goi(f"nhanVang({PHIEU},bytes)", [PHIEU, "bytes"],
               [[p["nguoiChoi"], p["man"], p["ve"], p["soVang"], p["maVan"], p["hanChot"]], m["chu_ky"]])


# Lỗi tuỳ biến của hợp đồng (+ lỗi chuẩn của OpenZeppelin) mà app dịch sang tiếng Việt
LOI = ["KhongChuyenNhuong()", "SaiNguoiNhan()", "PhieuHetHan()", "PhieuDaDung()", "SoVangKhongHopLe()",
       "ChuKySai()", "KhongBan(uint256)", "DaCo(uint256)", "DiaChiRong()", "ManKhongTonTai(uint256)",
       "ManMienPhi(uint256)", "SaiVe()", "ERC1155InsufficientBalance(address,uint256,uint256,uint256)"]


def main():
    mau = json.loads((GOC / "gold_rush_chain" / "du-lieu-kiem-thu" / "phieu_mau.json").read_text(encoding="utf-8"))
    vi = mau["man_coc"]["phieu"]["nguoiChoi"]
    cac_lenh = [nhan_vang(mau["luyen_tap"]), nhan_vang(mau["man_coc"]), goi("vaoMan(uint256)", ["uint256"], [3])]

    ca = {
        "bo_chon": {ten: chon(ten).hex() for ten in [
            f"nhanVang({PHIEU},bytes)", "vaoMan(uint256)", "mua(uint256)", "multicall(bytes[])",
            "balanceOf(address,uint256)", "gia(uint256)", "daDoi(bytes32)", "ve(address)", "manChoi(uint256)"]},
        "nhanVang": {**{k: mau["man_coc"][k] for k in ("phieu", "chu_ky")}, "calldata": nhan_vang(mau["man_coc"])},
        "vaoMan": {"man": 3, "calldata": goi("vaoMan(uint256)", ["uint256"], [3])},
        "mua": {"nhan_vat": 2, "calldata": goi("mua(uint256)", ["uint256"], [2])},
        "balanceOf": {"vi": vi, "id": 0, "calldata": goi("balanceOf(address,uint256)", ["address", "uint256"], [vi, 0])},
        "gia": {"nhan_vat": 3, "calldata": goi("gia(uint256)", ["uint256"], [3])},
        "daDoi": {"ma_van": mau["man_coc"]["phieu"]["maVan"],
                  "calldata": goi("daDoi(bytes32)", ["bytes32"], [mau["man_coc"]["phieu"]["maVan"]])},
        "ve": {"vi": vi, "calldata": goi("ve(address)", ["address"], [vi]),
               "ket_qua": "0x" + (tu(3) + tu(2) + tu(8)).hex(), "giai_ma": [3, 2, 8]},
        "manChoi": {"man": 2, "calldata": goi("manChoi(uint256)", ["uint256"], [2])},
        "multicall": {"cac_lenh": cac_lenh, "calldata": goi("multicall(bytes[])", ["bytes[]"], [cac_lenh])},
        "loi": {"0x" + chon(t).hex(): t.split("(")[0] for t in LOI},
        # Dữ liệu revert thật: ERC1155InsufficientBalance(vi, 3, 8, 0) — app phải đọc được tên lỗi
        "revert_mau": "0x" + (chon(LOI[-1]) + tu(int(vi, 16)) + tu(3) + tu(8) + tu(0)).hex(),
    }
    dich = GOC / "gold_rush" / "test" / "blockchain" / "abi_mau.json"
    dich.parent.mkdir(parents=True, exist_ok=True)
    dich.write_text(json.dumps(ca, indent=2), encoding="utf-8")
    print("Đã ghi", dich)
    for k, v in ca["bo_chon"].items():
        print(f"  {v}  {k}")
    print("multicall:", len(ca["multicall"]["calldata"]) // 2 - 1, "byte")


if __name__ == "__main__":
    main()
