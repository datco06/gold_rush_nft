"""Kiểm thử quản lý nhiệm vụ và tích hợp ngữ cảnh AI."""
import tempfile
import unittest
from pathlib import Path

from core import csdl, kho_do, quan_ly_nhiem_vu, tien_trinh


class TestQuanLyNhiemVu(unittest.TestCase):
    def setUp(self):
        self.tam_dir = tempfile.mkdtemp()
        self.db_path = Path(self.tam_dir) / "test.db"
        csdl.khoi_tao_csdl(self.db_path)
        self.conn = csdl.ket_noi(self.db_path)
        tien_trinh.lay_hoac_tao_nguoi_choi(self.conn, "player_001")

    def tearDown(self):
        self.conn.close()

    def test_tao_va_lay_danh_sach_nhiem_vu(self):
        q = quan_ly_nhiem_vu.tao_nhiem_vu(
            self.conn,
            player_id="player_001",
            title="Thợ mỏ tập sự",
            description="Nhặt 10 đồng xu trong bất kỳ màn nào",
            target_type="nhat_xu",
            target_count=10,
            reward_exp=50,
        )
        self.assertEqual(q["title"], "Thợ mỏ tập sự")
        self.assertEqual(q["status"], "dang_lam")
        self.assertEqual(q["target_count"], 10)
        self.assertEqual(q["current_count"], 0)

        ds = quan_ly_nhiem_vu.lay_danh_sach_nhiem_vu(self.conn, "player_001")
        self.assertEqual(len(ds), 1)

    def test_cap_nhat_tien_do_va_hoan_thanh(self):
        q = quan_ly_nhiem_vu.tao_nhiem_vu(
            self.conn,
            player_id="player_001",
            title="Nhặt xu",
            description="Nhặt 5 xu",
            target_type="nhat_xu",
            target_count=5,
            reward_exp=80,
            reward_items=[{"item_id": "binh_mau", "item_type": "potion", "quantity": 1}],
        )

        # Cập nhật nhặt 3 xu -> chưa xong
        hoan_thanh = quan_ly_nhiem_vu.cap_nhat_tien_do(self.conn, "player_001", "nhat_xu", 3)
        self.assertEqual(len(hoan_thanh), 0)
        q_hien_tai = quan_ly_nhiem_vu.lay_chi_tiet_nhiem_vu(self.conn, q["quest_id"])
        self.assertEqual(q_hien_tai["current_count"], 3)
        self.assertEqual(q_hien_tai["status"], "dang_lam")

        # Nhặt tiếp 2 xu -> hoàn thành
        hoan_thanh = quan_ly_nhiem_vu.cap_nhat_tien_do(self.conn, "player_001", "nhat_xu", 2)
        self.assertEqual(len(hoan_thanh), 1)
        self.assertEqual(hoan_thanh[0]["status"], "hoan_thanh")

        # Nhận thưởng
        nhan = quan_ly_nhiem_vu.nhan_thuong(self.conn, "player_001", q["quest_id"])
        self.assertEqual(nhan["status"], "da_nhan")
        self.assertEqual(nhan["reward_exp"], 80)

        # Kiểm tra EXP người chơi đã được cộng
        tt = tien_trinh.lay_tien_trinh(self.conn, "player_001")
        self.assertEqual(tt["exp"], 80)

        # Kiểm tra vật phẩm thưởng đã vào kho đồ
        kd = kho_do.lay_kho_do(self.conn, "player_001", loai="potion")
        self.assertEqual(len(kd), 1)
        self.assertEqual(kd[0]["item_id"], "binh_mau")

    def test_lay_ngu_canh_cho_ai(self):
        ctx = quan_ly_nhiem_vu.lay_ngu_canh_cho_ai(self.conn, "player_001")
        self.assertEqual(ctx["player_id"], "player_001")
        self.assertEqual(ctx["level"], 1)
        self.assertIn("nhat_xu", ctx["muc_tieu_hop_le"])
        self.assertIn("hoan_thanh_man", ctx["muc_tieu_hop_le"])


if __name__ == "__main__":
    unittest.main()

