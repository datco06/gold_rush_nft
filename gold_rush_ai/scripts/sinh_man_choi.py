"""Sinh các màn 2–6 bằng bộ sinh bản đồ thủ tục, rồi ghi `man_choi.json` cho app + máy chủ + hợp đồng.

    python scripts/sinh_man_choi.py            # ghi vào ../gold_rush/assets/tiles/
    python scripts/sinh_man_choi.py --xem      # thêm ảnh xem trước vào artifacts/ban_do/

Tái lập được: cùng seed → cùng bản đồ (giống notebook). Muốn đổi màn: sửa bảng THIET_KE rồi chạy lại.
Giới hạn thời gian KHÔNG đoán bằng mắt mà tính từ đường đi tham lam qua mọi đồng xu (core/man_choi.py).
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from config import APP_FLUTTER, ART_DIR  # noqa: E402
from core import man_choi, sinh_ban_do  # noqa: E402
from core.luoi import doc_tmx, kiem_tra_choi_duoc  # noqa: E402

# id, tên, mô tả, seed, mật độ vật cản, xu, zombie, skeleton, hệ số tốc độ kẻ địch, cọc, thưởng, sao
THIET_KE = [
    (2, "Rừng thưa", "Cây cối lưa thưa, ít quái — làm quen với đồng hồ.", 11, 0.36, 18, 4, 2, 1.00, 5, 5, 2),
    (3, "Hang đá", "Nhiều ngõ cụt; bộ xương bắt đầu đông hơn.", 23, 0.42, 20, 5, 3, 1.05, 8, 8, 3),
    (4, "Rừng rậm", "Vật cản dày đặc, phải tính đường trước khi đi.", 37, 0.45, 20, 4, 5, 1.10, 12, 12, 3),
    (5, "Thung lũng xương", "Bảy bộ xương canh giữ, chạy nhanh hơn.", 41, 0.40, 22, 3, 7, 1.15, 16, 16, 4),
    (6, "Mỏ vàng", "Màn cuối: 24 xu, 13 kẻ địch, kẻ địch nhanh hơn 20%.", 53, 0.43, 24, 7, 6, 1.20, 20, 24, 5),
]

ap = argparse.ArgumentParser()
ap.add_argument("--xem", action="store_true", help="vẽ ảnh xem trước từng màn")
a = ap.parse_args()

thu_muc = APP_FLUTTER / "assets" / "tiles"
thu_muc.mkdir(parents=True, exist_ok=True)

# Màn 1 = bản đồ gốc vẽ tay, luyện tập, không giới hạn thời gian, không cọc
goc = doc_tmx(thu_muc / "gold_rush.tmx")
cac_man = [{
    "id": 1, "ten": "Đồng cỏ", "mo_ta": "Màn luyện tập: không giới hạn thời gian, thua không mất gì.",
    "tep": "gold_rush.tmx", "gioi_han_giay": 0, "he_so_ke_dich": 1.0, "coc": 0, "thuong": 0,
    "so_xu": len(goc.cac_diem("coin")), "sao": 1,
}]
print(f"Màn 1  Đồng cỏ            xu={cac_man[0]['so_xu']}  (bản đồ gốc)")

for (mid, ten, mo_ta, seed, mat_do, xu, zb, sk, hs, coc, thuong, sao) in THIET_KE:
    kq = sinh_ban_do.sinh(seed=seed, mat_do=mat_do, so_xu=xu, so_zombie=zb, so_skeleton=sk)
    tep = f"man_{mid}.tmx"
    (thu_muc / tep).write_text(sinh_ban_do.thanh_tmx(kq), encoding="utf-8")
    bd = doc_tmx(thu_muc / tep)                       # đọc lại đúng như máy chủ sẽ đọc
    loi = kiem_tra_choi_duoc(bd)
    if loi:
        raise SystemExit(f"Màn {mid} không chơi được: {loi}")
    toi_thieu = man_choi.giay_vong_tham(bd)
    gioi_han = man_choi.de_xuat_gioi_han(toi_thieu)
    cac_man.append({"id": mid, "ten": ten, "mo_ta": mo_ta, "tep": tep, "gioi_han_giay": gioi_han,
                    "he_so_ke_dich": hs, "coc": coc, "thuong": thuong,
                    "so_xu": len(bd.cac_diem("coin")), "sao": sao})
    print(f"Màn {mid}  {ten:<18} xu={xu}  quái={zb}+{sk}  đi tham lam {toi_thieu:5.1f}s → giới hạn {gioi_han}s"
          f"  cọc {coc}  thưởng {thuong}")
    if a.xem:
        from core.ve import ve_ban_do
        (ART_DIR / "ban_do").mkdir(parents=True, exist_ok=True)
        ve_ban_do(bd, tieu_de=f"Màn {mid} · {ten}").savefig(ART_DIR / "ban_do" / f"man_{mid}.png")

ra = thu_muc / "man_choi.json"
ra.write_text(json.dumps({"phien_ban": 1, "man": cac_man}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
assert not man_choi.kiem_tra_khop_ban_do(man_choi.doc(ra), thu_muc)
print("Đã ghi", ra)
