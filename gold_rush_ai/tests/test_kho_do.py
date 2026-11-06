"""Kiểm thử quản lý kho đồ người chơi."""
import tempfile
import unittest
from pathlib import Path

from core import csdl, kho_do, tien_trinh


class TestKhoDo(unittest.TestCase):
    def setUp(self):
        self.tam_dir = tempfile.mkdtemp()
        self.db_path = Path(self.tam_dir) / "test.db"
        csdl.khoi_tao_csdl(self.db_path)
        self.conn = csdl.ket_noi(self.db_path)
        tien_trinh.lay_hoac_tao_nguoi_choi(self.conn, "player_001")

    def tearDown(self):
        self.conn.close()

    def test_kho_do_khoi_dau(self):
        kd = kho_do.lay_kho_do(self.conn, "player_001")
        # Khởi đầu có kiếm gỗ và george
        item_ids = [it["item_id"] for it in kd]
        self.assertIn("kiem_go", item_ids)
        self.assertIn("george", item_ids)

    def test_them_vat_pham_va_cong_don(self):
        kho_do.them_vat_pham(self.conn, "player_001", "binh_mau", "potion", quantity=2)
        kd = kho_do.lay_kho_do(self.conn, "player_001", loai="potion")
        self.assertEqual(len(kd), 1)
        self.assertEqual(kd[0]["quantity"], 2)

        # Thêm tiếp 3 bình nữa -> thành 5
        kho_do.them_vat_pham(self.conn, "player_001", "binh_mau", "potion", quantity=3)
        kd = kho_do.lay_kho_do(self.conn, "player_001", loai="potion")
        self.assertEqual(kd[0]["quantity"], 5)

    def test_them_nhan_vat_moi_tu_dong_mo_khoa_nhan_vat(self):
        kho_do.them_vat_pham(self.conn, "player_001", "miner_bob", "character", quantity=1)
        p = tien_trinh.lay_tien_trinh(self.conn, "player_001")
        self.assertIn("miner_bob", p["unlocked_characters"])

    def test_tru_vat_pham(self):
        kho_do.them_vat_pham(self.conn, "player_001", "chia_khoa", "material", quantity=3)
        self.assertTrue(kho_do.tru_vat_pham(self.conn, "player_001", "chia_khoa", 2))
        kd = kho_do.lay_kho_do(self.conn, "player_001", loai="material")
        self.assertEqual(kd[0]["quantity"], 1)

        # Trừ quá số lượng -> trả về False
        self.assertFalse(kho_do.tru_vat_pham(self.conn, "player_001", "chia_khoa", 5))


if __name__ == "__main__":
    unittest.main()

