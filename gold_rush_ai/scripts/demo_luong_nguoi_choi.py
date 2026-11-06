"""Script demo toàn bộ luồng hoạt động của Người 5 (Tiến trình, Kho đồ, AI Quest, Map Pool).

Chạy: python scripts/demo_luong_nguoi_choi.py
"""
import json
import sys
import tempfile
from pathlib import Path

# Đảm bảo import được các module trong gold_rush_ai
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core import csdl, quan_ly_nhiem_vu, tien_trinh
from api.ban_do_moi import danh_sach_pool_ban_do, lay_cau_hinh_ban_do, sinh_ban_do_theo_seed
from api.kho_do import YeuCauDoiTrangBi, chon_trang_bi, lay_danh_sach_kho_do
from api.nhiem_vu import (
    YeuCauGanNhiemVuAI,
    YeuCauNhanThuong,
    gan_nhiem_vu_ai,
    lay_ngu_canh_ai,
    lay_nhiem_vu_hien_co,
    nhan_thuong_nhiem_vu,
)
from api.tien_trinh import lay_thong_tin_tien_trinh


def in_tieu_de(text: str):
    print("\n" + "=" * 70)
    print(f" {text}")
    print("=" * 70)


def in_json(label: str, data: dict):
    print(f"\n--- {label} ---")
    print(json.dumps(data, indent=2, ensure_ascii=False))


def main():
    tam_dir = tempfile.mkdtemp()
    demo_db = Path(tam_dir) / "demo_gold_rush.db"
    csdl.CSDL_PATH = demo_db
    csdl.khoi_tao_csdl(demo_db)

    print(">>> Khởi tạo CSDL SQLite Demo thành công tại:", demo_db)

    in_tieu_de("BƯỚC 1: KHỞI TẠO TIẾN TRÌNH & WORLD MAP BAN ĐẦU")
    player_id = "player_hiep_si_01"
    wallet = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

    tt = lay_thong_tin_tien_trinh(player_id=player_id, wallet=wallet, ten_hien_thi="Hiệp Sĩ Vàng")
    in_json("Tiến trình người chơi", {
        "player_id": tt["player_id"],
        "level": tt["level"],
        "unlocked_stage_ids": tt["unlocked_stage_ids"],
        "completed_stage_ids": tt["completed_stage_ids"],
        "equipped_weapon": tt["equipped_weapon_id"],
    })

    in_tieu_de("BƯỚC 2: TÍCH HỢP AI QUEST (NGƯỜI 3)")
    ctx = lay_ngu_canh_ai(player_id=player_id)
    in_json("Ngữ cảnh cho Người 3 đưa vào Prompt", ctx)

    gan_nhiem_vu_ai(YeuCauGanNhiemVuAI(
        player_id=player_id,
        title="Chinh phục Màn 1",
        description="Hoàn thành Màn 1 để mở đường sang Rừng thưa",
        target_type="hoan_thanh_man",
        target_count=1,
        reward_exp=100,
        reward_items=[{"item_id": "kiem_sat", "item_type": "weapon", "quantity": 1}],
    ))

    in_tieu_de("BƯỚC 3: THẮNG MÀN 1 VÀ TỰ ĐỘNG MỞ MÀN 2")
    with csdl.lay_csdl() as conn:
        quan_ly_nhiem_vu.cap_nhat_tien_do(conn, player_id, "hoan_thanh_man", 1)
        tien_trinh.hoan_thanh_man(conn, player_id, stage_id=1, exp_thuong=50)

    tt_moi = lay_thong_tin_tien_trinh(player_id=player_id)
    in_json("Tiến trình sau khi thắng Màn 1", {
        "level": tt_moi["level"],
        "completed_stage_ids": tt_moi["completed_stage_ids"],
        "unlocked_stage_ids (TỰ ĐỘNG MỞ MÀN 2)": tt_moi["unlocked_stage_ids"],
    })

    in_tieu_de("BƯỚC 4: NHẬN THƯỞNG QUEST & TRANG BỊ KIẾM SẮT")
    ds_q = lay_nhiem_vu_hien_co(player_id=player_id)
    qid = ds_q["nhiem_vu"][0]["quest_id"]
    nhan_thuong_nhiem_vu(YeuCauNhanThuong(player_id=player_id, quest_id=qid))
    doi = chon_trang_bi(YeuCauDoiTrangBi(player_id=player_id, loai="weapon", item_id="kiem_sat"))
    in_json("Đổi trang bị", doi)

    in_tieu_de("BƯỚC 5: POOL BẢN ĐỒ PROCEDURAL ĐÃ ĐÓNG GÓI SẴN")
    pool = danh_sach_pool_ban_do()
    in_json("Danh sách Pool bản đồ sẵn có trong assets", pool)

    print("\n>>> DEMO HOÀN TẤT THÀNH CÔNG!\n")


if __name__ == "__main__":
    main()
