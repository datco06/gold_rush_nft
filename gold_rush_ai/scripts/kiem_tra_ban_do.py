"""Kiểm định MỌI tệp .tmx của app: George tới được mọi đồng xu, không đối tượng nào đứng trên ô chặn.
Đưa vào GitHub Actions để không ai vô tình đẩy lên một màn chơi không thể thắng.

    python scripts/kiem_tra_ban_do.py ../gold_rush/assets/tiles
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core.luoi import doc_tmx, kiem_tra_choi_duoc  # noqa: E402

thu_muc = Path(sys.argv[1] if len(sys.argv) > 1 else "../gold_rush/assets/tiles")
co_loi = False
for tep in sorted(thu_muc.glob("*.tmx")):
    loi = kiem_tra_choi_duoc(doc_tmx(tep))
    print(("LỖI " if loi else "OK  ") + tep.name)
    for l in loi:
        print("     -", l)
    co_loi |= bool(loi)
sys.exit(1 if co_loi else 0)
