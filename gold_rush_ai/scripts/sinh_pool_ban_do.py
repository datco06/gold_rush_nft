"""Sinh và đóng gói bộ Pool bản đồ sinh ngẫu nhiên (Procedural Maps) vào assets của Flutter.

Quy tắc:
  * Không ghi đè 6 màn cốt truyện gốc (gold_rush.tmx, man_2.tmx -> man_6.tmx).
  * Kiểm định đường đi BFS/A* trước khi ghi file.
  * Xuất file catalog `pool_ban_do.json` kèm theo.

Chạy: python scripts/sinh_pool_ban_do.py
"""
import json
import sys
from pathlib import Path

# Đảm bảo import được module từ thư mục gốc gold_rush_ai
GOC_AI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GOC_AI))

from config import APP_FLUTTER, ART_DIR
from core.luoi import doc_tmx, kiem_tra_choi_duoc
from core.quan_ly_ban_do import PHIEN_BAN_THUAT_TOAN, sinh_ban_do_hop_le
from core.ve import ve_ban_do

# Cấu hình danh sách bản đồ sinh ngẫu nhiên cho Pool
DANH_SACH_POOL = [
    {
        "seed": 101,
        "ten_tep": "map_seed_101.tmx",
        "ten": "Đồng Bằng Hoang Sơ",
        "mo_ta": "Bản đồ sinh ngẫu nhiên cấp Dễ: đường đi thoáng đãng, số lượng quái vừa phải.",
        "mat_do": 0.34,
        "so_xu": 20,
        "so_zombie": 4,
        "so_skeleton": 3,
        "sao": 2,
    },
    {
        "seed": 102,
        "ten_tep": "map_seed_102.tmx",
        "ten": "Khu Rừng Ẩn Giấu",
        "mo_ta": "Bản đồ sinh ngẫu nhiên cấp Trung bình: vật cản rải rác, thích hợp cho AI Quest.",
        "mat_do": 0.38,
        "so_xu": 24,
        "so_zombie": 5,
        "so_skeleton": 4,
        "sao": 3,
    },
    {
        "seed": 103,
        "ten_tep": "map_seed_103.tmx",
        "ten": "Mê Cung Đá Cổ",
        "mo_ta": "Bản đồ sinh ngẫu nhiên cấp Khó: ngóc ngách hiểm trở, bộ xương canh gác dày đặc.",
        "mat_do": 0.42,
        "so_xu": 28,
        "so_zombie": 7,
        "so_skeleton": 5,
        "sao": 4,
    },
]


def sinh_va_dong_goi_pool():
    thu_muc_tiles = APP_FLUTTER / "assets" / "tiles"
    thu_muc_tiles.mkdir(parents=True, exist_ok=True)
    thu_muc_art = ART_DIR / "ban_do"
    thu_muc_art.mkdir(parents=True, exist_ok=True)

    ket_qua_catalog = {
        "phien_ban_thuat_toan": PHIEN_BAN_THUAT_TOAN,
        "tong_so_ban_do": len(DANH_SACH_POOL),
        "danh_sach": [],
    }

    print("=" * 65)
    print(" BẮT ĐẦU SINH VÀ ĐÓNG GÓI POOL BẢN ĐỒ PROCEDURAL VÀO ASSETS")
    print("=" * 65)

    for item in DANH_SACH_POOL:
        seed = item["seed"]
        ten_tep = item["ten_tep"]
        duong_dan_tmx = thu_muc_tiles / ten_tep

        print(f"\n[+] Đang sinh '{item['ten']}' (seed={seed}, mật độ={item['mat_do']})...")

        # 1. Sinh bản đồ và kiểm định A*
        kq = sinh_ban_do_hop_le(
            seed=seed,
            mat_do=item["mat_do"],
            so_xu=item["so_xu"],
            so_zombie=item["so_zombie"],
            so_skeleton=item["so_skeleton"],
            phien_ban=PHIEN_BAN_THUAT_TOAN,
        )

        # 2. Ghi ra file .tmx trong assets/tiles
        duong_dan_tmx.write_text(kq["noi_dung_tmx"], encoding="utf-8")
        print(f"    -> Đã ghi file TMX: {duong_dan_tmx.name}")

        # 3. Kiểm định chéo lại từ file vừa ghi bằng doc_tmx
        ban_do_da_doc = doc_tmx(duong_dan_tmx)
        loi = kiem_tra_choi_duoc(ban_do_da_doc)
        if loi:
            raise RuntimeError(f"Bản đồ {ten_tep} ghi ra bị lỗi: {loi}")
        print(f"    -> Kiểm định chéo A*/BFS: HOÀN HẢO (100% xu tới được)")

        # 4. Xuất ảnh xem trước PNG vào artifacts (nếu matplotlib sẵn sàng)
        try:
            fig = ve_ban_do(kq["chi_so"], tieu_de=f"{item['ten']} (seed={seed})")
            duong_dan_png = thu_muc_art / f"{ten_tep.replace('.tmx', '.png')}"
            fig.savefig(duong_dan_png)
            print(f"    -> Đã xuất ảnh xem trước: {duong_dan_png.name}")
        except Exception as e:
            # Không bắt buộc phải có matplotlib để ghi game assets
            pass

        # 5. Lưu thông tin vào catalog
        ket_qua_catalog["danh_sach"].append({
            "seed": seed,
            "ten_tep": ten_tep,
            "ten": item["ten"],
            "mo_ta": item["mo_ta"],
            "sao": item["sao"],
            "so_xu": kq["so_xu"],
            "so_zombie": kq["so_zombie"],
            "so_skeleton": kq["so_skeleton"],
            "kich_thuoc": kq["kich_thuoc"],
            "chi_so": kq["chi_so"],
        })

    # Ghi catalog pool_ban_do.json vào assets/tiles
    catalog_path = thu_muc_tiles / "pool_ban_do.json"
    catalog_path.write_text(json.dumps(ket_qua_catalog, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n[OK] Đã cập nhật catalog: {catalog_path.name}")
    print("=" * 65)


if __name__ == "__main__":
    sinh_va_dong_goi_pool()

