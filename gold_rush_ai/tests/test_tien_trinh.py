"""Kiểm thử quản lý tiến trình người chơi và CSDL."""
import os
import tempfile
import unittest
from pathlib import Path

from core import csdl, tien_trinh


class TestTienTrinh(unittest.TestCase):
    def setUp(self):
        self.tam_dir = tempfile.mkdtemp()
        self.db_path = Path(self.tam_dir) / "test.db"
        csdl.khoi_tao_csdl(self.db_path)
        self.conn = csdl.ket_noi(self.db_path)

    def tearDown(self):
        self.conn.close()

    def test_khoi_tao_va_lay_nguoi_choi(self):
        p = tien_trinh.lay_hoac_tao_nguoi_choi(self.conn, "player_001", ten_hien_thi="Dũng")
        self.assertIsNotNone(p)
        self.assertEqual(p["player_id"], "player_001")
        self.assertEqual(p["level"], 1)
        self.assertEqual(p["exp"], 0)
        self.assertEqual(p["unlocked_stage_ids"], [1])
        self.assertEqual(p["completed_stage_ids"], [])
        self.assertEqual(p["equipped_weapon_id"], "kiem_go")
        self.assertEqual(p["equipped_character_id"], "george")

    def test_cong_exp_va_len_cap(self):
        tien_trinh.lay_hoac_tao_nguoi_choi(self.conn, "player_001")
        # Level 1 cần 100 EXP để lên Level 2
        p = tien_trinh.cong_exp(self.conn, "player_001", 120)
        self.assertEqual(p["level"], 2)
        self.assertEqual(p["exp"], 120)
        self.assertEqual(p["exp_hien_tai"], 20)  # 120 - 100 = 20

    def test_hoan_thanh_man_va_tu_dong_mo_man_ke(self):
        tien_trinh.lay_hoac_tao_nguoi_choi(self.conn, "player_001")
        # Hoàn thành màn 1 -> phải tự động mở màn 2 và cộng exp (50 EXP chính sách server)
        p = tien_trinh.hoan_thanh_man(self.conn, "player_001", stage_id=1, evidence_id="ev_stage1_unit_test")
        self.assertIn(1, p["completed_stage_ids"])
        self.assertIn(2, p["unlocked_stage_ids"])
        self.assertEqual(p["exp"], 50)

        # Hoàn thành tiếp màn 2 -> mở màn 3 và cộng thêm 50 EXP (tổng 100 EXP)
        p = tien_trinh.hoan_thanh_man(self.conn, "player_001", stage_id=2, evidence_id="ev_stage2_unit_test")
        self.assertIn(2, p["completed_stage_ids"])
        self.assertIn(3, p["unlocked_stage_ids"])
        self.assertEqual(p["exp"], 100)
        self.assertEqual(p["level"], 2)

    def test_doi_trang_bi(self):
        tien_trinh.lay_hoac_tao_nguoi_choi(self.conn, "player_001")
        # Người chơi có sẵn kiem_go, đổi sang kiem_go ok
        p = tien_trinh.doi_trang_bi(self.conn, "player_001", "weapon", "kiem_go")
        self.assertEqual(p["equipped_weapon_id"], "kiem_go")

        # Đổi sang món không có trong kho đồ -> ném lỗi ValueError
        with self.assertRaises(ValueError):
            tien_trinh.doi_trang_bi(self.conn, "player_001", "weapon", "kiem_kim_cuong")


if __name__ == "__main__":
    unittest.main()

