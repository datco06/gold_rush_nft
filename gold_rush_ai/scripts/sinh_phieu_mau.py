"""Sinh PHIẾU MẪU do Python ký, để bài kiểm thử Hardhat chứng minh hợp đồng chấp nhận chúng.

    python scripts/sinh_phieu_mau.py   →  ../gold_rush_chain/du-lieu-kiem-thu/phieu_mau.json

Dùng khoá thử CÔNG KHAI của Hardhat (ai cũng biết — chỉ dùng cho mạng 31337):
  trọng tài = tài khoản #1, người chơi = tài khoản #2,
  hợp đồng  = hợp đồng đầu tiên tài khoản #0 triển khai (0x5FbDB2…0aa3).
Hai phiếu: một ván luyện tập (màn 1, 10 vàng) và một ván HOÀN THÀNH màn 2 có cọc (vé số 1, 18 xu + 5 thưởng).
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core.trong_tai import ky_phieu  # noqa: E402

KHOA_THU_1 = bytes.fromhex("59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d")
NGUOI_CHOI = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
HOP_DONG = "0x5FbDB2315678afecb367f032d93F642f64180aa3"


def mau(man, ve, so_vang, ma_van):
    kq = ky_phieu(NGUOI_CHOI, man, ve, so_vang, ma_van, KHOA_THU_1, chain_id=31337, hop_dong=HOP_DONG,
                  han_giay=0, bay_gio=2_000_000_000)          # hạn năm 2033: test không hết hạn
    return {k: kq[k] for k in ("phieu", "chu_ky", "bam")}


du_lieu = {"trong_tai": "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", "hop_dong": HOP_DONG,
           "luyen_tap": mau(1, 0, 10, "van-mau-0001"), "man_coc": mau(2, 1, 23, "van-mau-0002")}
dich = Path(__file__).resolve().parents[2] / "gold_rush_chain" / "du-lieu-kiem-thu" / "phieu_mau.json"
dich.parent.mkdir(parents=True, exist_ok=True)
dich.write_text(json.dumps(du_lieu, indent=2), encoding="utf-8")
print("Đã ghi", dich)
