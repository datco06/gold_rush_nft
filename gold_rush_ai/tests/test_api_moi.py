"""Kiểm thử tích hợp các endpoint API mới (Tiến trình, Kho đồ, Nhiệm vụ, Bản đồ)."""
import tempfile
import unittest
from pathlib import Path

from fastapi import HTTPException
from pydantic import ValidationError

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
from core import csdl, kho_do, quan_ly_nhiem_vu, tien_trinh


class TestApiMoi(unittest.TestCase):
    def setUp(self):
        self.tam_dir = tempfile.mkdtemp()
        self.db_path = Path(self.tam_dir) / "test_api.db"
        # Đặt CSDL_PATH tới test_api.db
        import config
        config.CSDL_PATH = self.db_path
        csdl.CSDL_PATH = self.db_path
        csdl.khoi_tao_csdl(self.db_path)

    def test_api_progress(self):
        # 1. Gọi lấy tiến trình người chơi mới -> tự động tạo
        tt = lay_thong_tin_tien_trinh(player_id="player_test_01", wallet=None, ten_hien_thi="TestUser")
        self.assertEqual(tt["player_id"], "player_test_01")
        self.assertEqual(tt["level"], 1)
        self.assertEqual(tt["unlocked_stage_ids"], [1])
        self.assertEqual(tt["equipped_weapon_id"], "kiem_go")
        self.assertEqual(tt["equipped_character_id"], "george")

    def test_api_inventory_va_equipment(self):
        # Khởi tạo người chơi
        lay_thong_tin_tien_trinh(player_id="player_test_02")

        # Lấy kho đồ
        kd = lay_danh_sach_kho_do(player_id="player_test_02")
        self.assertGreaterEqual(kd["so_luong_vat_pham"], 2)

        # Đổi sang trang bị có sẵn
        kq = chon_trang_bi(YeuCauDoiTrangBi(player_id="player_test_02", loai="weapon", item_id="kiem_go"))
        self.assertTrue(kq["thanh_cong"])

        # Đổi sang trang bị chưa sở hữu -> báo lỗi 400
        with self.assertRaises(HTTPException) as cm:
            chon_trang_bi(YeuCauDoiTrangBi(player_id="player_test_02", loai="weapon", item_id="kiem_huyen_thoai"))
        self.assertEqual(cm.exception.status_code, 400)

    def test_api_quests_va_ai_context(self):
        lay_thong_tin_tien_trinh(player_id="player_test_03")

        # 1. Gán nhiệm vụ AI
        yc_ai = YeuCauGanNhiemVuAI(
            player_id="player_test_03",
            title="Săn vàng hang động",
            description="Nhặt 15 xu trong màn 2",
            target_type="nhat_xu",
            target_count=15,
            reward_exp=100,
        )
        gan = gan_nhiem_vu_ai(yc_ai)
        self.assertTrue(gan["thanh_cong"])
        qid = gan["nhiem_vu"]["quest_id"]

        # 2. Lấy danh sách nhiệm vụ active
        act = lay_nhiem_vu_hien_co(player_id="player_test_03")
        self.assertEqual(act["tong_so"], 1)

        # 3. Lấy ngữ cảnh cho AI
        ctx = lay_ngu_canh_ai(player_id="player_test_03")
        self.assertEqual(ctx["player_id"], "player_test_03")
        self.assertIn("nhat_xu", ctx["muc_tieu_hop_le"])

        # 4. Giả lập người chơi hoàn thành nhiệm vụ và nhận thưởng
        with csdl.lay_csdl() as conn:
            quan_ly_nhiem_vu.cap_nhat_tien_do(conn, "player_test_03", "nhat_xu", 15)

        thuong = nhan_thuong_nhiem_vu(YeuCauNhanThuong(player_id="player_test_03", quest_id=qid))
        self.assertTrue(thuong["thanh_cong"])
        self.assertEqual(thuong["ket_qua"]["reward_exp"], 100)

        # Kiểm tra EXP sau nhận thưởng
        tt = lay_thong_tin_tien_trinh(player_id="player_test_03")
        self.assertEqual(tt["exp"], 100)
        self.assertEqual(tt["level"], 2)

    def test_api_maps(self):
        # 1. Cấu hình bản đồ
        cfg = lay_cau_hinh_ban_do()
        self.assertEqual(cfg["phien_ban_thuat_toan"], "v1.3")

        # 2. Sinh bản đồ metadata theo seed
        b = sinh_ban_do_theo_seed(seed=7, mat_do=0.36, dinh_dang="json")
        self.assertEqual(b["seed"], 7)
        self.assertGreater(b["so_xu"], 0)

        # 3. Quét pool bản đồ
        p = danh_sach_pool_ban_do()
        self.assertGreater(p["tong_so_ban_do"], 0)

    def test_tich_hop_nhat_ky_mo_man_va_nhiem_vu(self):
        # Tạo người chơi và nhiệm vụ
        lay_thong_tin_tien_trinh(player_id="player_test_04")
        with csdl.lay_csdl() as conn:
            quan_ly_nhiem_vu.tao_nhiem_vu(
                conn,
                player_id="player_test_04",
                title="Vượt qua Đồng cỏ",
                description="Hoàn thành màn 1",
                target_type="hoan_thanh_man",
                target_count=1,
                reward_exp=60,
            )

        # Giả lập hoàn thành màn 1 hợp lệ
        with csdl.lay_csdl() as conn:
            quan_ly_nhiem_vu.cap_nhat_tien_do(conn, "player_test_04", "hoan_thanh_man", 1)
            tien_trinh.hoan_thanh_man(conn, "player_test_04", stage_id=1)

        # Kiểm tra màn 2 đã được mở khóa tự động
        tt = lay_thong_tin_tien_trinh(player_id="player_test_04")
        self.assertIn(1, tt["completed_stage_ids"])
        self.assertIn(2, tt["unlocked_stage_ids"])

        # Kiểm tra nhiệm vụ đã chuyển sang 'hoan_thanh'
        ds_nv = lay_nhiem_vu_hien_co(player_id="player_test_04")
        self.assertEqual(ds_nv["nhiem_vu"][0]["status"], "hoan_thanh")



if __name__ == "__main__":
    unittest.main()
