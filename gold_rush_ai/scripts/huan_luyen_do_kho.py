"""Huấn luyện mô hình độ khó rồi chép sang app Flutter.

    python scripts/huan_luyen_do_kho.py                      # dữ liệu mô phỏng
    python scripts/huan_luyen_do_kho.py --nguon nhat_ky      # nhật ký thật trong data/nhat_ky/
    python scripts/huan_luyen_do_kho.py --khong-chep-sang-app

Kết quả:
    artifacts/do_kho/do_kho_v1.json   ← mô hình (hệ số + chuẩn hoá + ca kiểm thử)
    artifacts/do_kho/metrics.json     ← chỉ số trên tập test
    ../gold_rush/assets/models/do_kho_v1.json   ← bản app dùng
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from config import APP_FLUTTER, ART_DIR, NHAT_KY_DIR  # noqa: E402
from core import do_kho, nhat_ky  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--nguon", choices=["mo_phong", "nhat_ky"], default="mo_phong")
ap.add_argument("--so-van", type=int, default=3000)
ap.add_argument("--khong-chep-sang-app", action="store_true")
a = ap.parse_args()

if a.nguon == "mo_phong":
    X, y, nhom = do_kho.mo_phong(so_van=a.so_van)
else:
    X, y, nhom = nhat_ky.thanh_du_lieu_huan_luyen(nhat_ky.doc_tat_ca(NHAT_KY_DIR))
    if len(set(nhom)) < 200:
        sys.exit(f"Mới có {len(set(nhom))} ván thắng/thua — cần ít nhất 200 ván để chia train/val/test có ý nghĩa.")

mo_hinh, chi_so = do_kho.huan_luyen(X, y, nhom)
chi_so["du_lieu"] = a.nguon
tep = do_kho.luu(mo_hinh, chi_so, ART_DIR / "do_kho")
print(json.dumps(chi_so, ensure_ascii=False, indent=2))
print("Đã lưu", tep)

if chi_so["test_auc"] <= chi_so["moc_so_sanh_auc(mau<0.5)"]:
    sys.exit("Mô hình KHÔNG hơn mốc so sánh đơn giản — không chép sang app.")

if not a.khong_chep_sang_app:
    dich = APP_FLUTTER / "assets" / "models"
    if not (APP_FLUTTER / "pubspec.yaml").exists():
        sys.exit(f"Không thấy app Flutter ở {APP_FLUTTER} (đặt biến APP_FLUTTER)")
    dich.mkdir(parents=True, exist_ok=True)
    shutil.copy2(tep, dich / tep.name)
    print("Đã chép sang", dich / tep.name)
