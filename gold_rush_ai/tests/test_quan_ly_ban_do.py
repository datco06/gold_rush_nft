"""Kiểm thử bộ sinh bản đồ theo seed và kiểm tra tính hợp lệ."""
import tempfile
import unittest
from pathlib import Path

from core import quan_ly_ban_do


class TestQuanLyBanDo(unittest.TestCase):
    def test_sinh_ban_do_hop_le_theo_seed(self):
        # Kiểm tra tính nhất quán (cùng seed 7 sinh ra cùng chỉ số)
        b1 = quan_ly_ban_do.sinh_ban_do_hop_le(seed=7)
        b2 = quan_ly_ban_do.sinh_ban_do_hop_le(seed=7)
        self.assertEqual(b1["chi_so"], b2["chi_so"])
        self.assertEqual(b1["noi_dung_tmx"], b2["noi_dung_tmx"])
        self.assertGreater(b1["so_xu"], 0)
        self.assertGreater(b1["so_zombie"], 0)

    def test_sinh_3_seed_khac_nhau_deu_choi_duoc(self):
        # BACK-05: Sinh và kiểm tra được ít nhất ba bản đồ với ba seed khác nhau
        for s in (7, 42, 99):
            b = quan_ly_ban_do.sinh_ban_do_hop_le(seed=s)
            self.assertEqual(b["seed"], s)
            self.assertIn('<map version="1.10"', b["noi_dung_tmx"])

    def test_xuat_tep_tmx(self):
        with tempfile.TemporaryDirectory() as tam_dir:
            p = quan_ly_ban_do.xuat_tep_tmx(seed=123, thu_muc_xuat=Path(tam_dir))
            self.assertTrue(p.exists())
            self.assertTrue(p.name.endswith(".tmx"))


if __name__ == "__main__":
    unittest.main()

