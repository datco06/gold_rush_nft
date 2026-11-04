"""Sinh bản đồ mới cho Gold Rush và (tuỳ chọn) đặt thẳng vào app.

    python scripts/sinh_ban_do.py --seed 7                       # → artifacts/ban_do/gold_rush_7.tmx + .png
    python scripts/sinh_ban_do.py --seed 7 --mat-do 0.45 --vao-app
        # → ../gold_rush/assets/tiles/gold_rush_7.tmx ; đổi tên tệp trong BanDo.nap() để chơi thử
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from config import APP_FLUTTER, ART_DIR  # noqa: E402
from core import sinh_ban_do  # noqa: E402
from core.ve import ve_ban_do  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, default=0)
ap.add_argument("--mat-do", type=float, default=0.42)
ap.add_argument("--vao-app", action="store_true")
a = ap.parse_args()

kq = sinh_ban_do.sinh(seed=a.seed, mat_do=a.mat_do)
ra = (APP_FLUTTER / "assets" / "tiles") if a.vao_app else (ART_DIR / "ban_do")
ra.mkdir(parents=True, exist_ok=True)
tep = ra / f"gold_rush_{a.seed}.tmx"
tep.write_text(sinh_ban_do.thanh_tmx(kq), encoding="utf-8")
ve_ban_do(kq["ban_do"], tieu_de=f"seed={a.seed}  mat_do={a.mat_do}").savefig(ART_DIR / "ban_do" / f"gold_rush_{a.seed}.png")
print(json.dumps(kq["chi_so"], ensure_ascii=False))
print("Đã ghi", tep)
