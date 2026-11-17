"""Sinh riêng 14 màn local (7–20), không ghi đè bộ 6 màn có cấu hình blockchain.

Chạy từ root: gold_rush_ai/.venv/bin/python gold_rush/cong-cu/sinh_man_mo_rong.py
Tái sử dụng bộ sinh/BFS hiện có, không chỉnh thuật toán Gameplay hoặc AI.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "gold_rush_ai"))
from core import man_choi, sinh_ban_do  # noqa: E402
from core.luoi import doc_tmx, kiem_tra_choi_duoc  # noqa: E402

NAMES = [
    "Nhà thợ rèn", "Quán trọ ven rừng", "Trạm gác", "Hội thợ săn",
    "Thư viện cổ", "Nhà ven suối", "Xưởng chế tác", "Đồn phương bắc",
    "Dinh thự đá", "Quán trọ bến sông", "Tháp gió", "Hội quán xanh",
    "Nhà hiền triết", "Thành trì cuối",
]


def main():
    folder = ROOT / "gold_rush" / "assets" / "tiles"
    levels = []
    for index, name in enumerate(NAMES):
        mid = index + 7
        coins = 24 + (index // 3) * 2
        data = sinh_ban_do.sinh(
            seed=202620 + mid * 37, mat_do=0.32 + (index % 5) * 0.025,
            so_xu=coins, so_zombie=5 + index // 3, so_skeleton=3 + index // 4,
        )
        filename = f"man_{mid}.tmx"
        (folder / filename).write_text(sinh_ban_do.thanh_tmx(data), encoding="utf-8")
        grid = doc_tmx(folder / filename)
        assert not kiem_tra_choi_duoc(grid), mid
        limit = man_choi.de_xuat_gioi_han(man_choi.giay_vong_tham(grid), he_so=1.9, cong_them=45)
        levels.append({
            "id": mid, "ten": name,
            "mo_ta": f"Khám phá {name.lower()}, thu thập đủ {coins} xu để mở địa điểm tiếp theo. Màn local, không giao dịch blockchain.",
            "tep": filename, "gioi_han_giay": limit,
            "he_so_ke_dich": round(1.05 + index * 0.015, 3),
            "coc": 0, "thuong": 0, "so_xu": coins,
            "sao": min(5, 3 + index // 5), "chi_choi_local": True,
        })
        print(f"{mid:2} {name}: {coins} xu, {limit}s; BFS đạt")
    (folder / "man_mo_rong.json").write_text(
        json.dumps({"phien_ban": 1, "man": levels}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
