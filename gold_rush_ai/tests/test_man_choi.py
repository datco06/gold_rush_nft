"""Một nguồn sự thật: man_choi.json khớp bản đồ .tmx, khớp Ignition, và chơi được."""
import re
import unittest
from pathlib import Path

from core import man_choi
from core.luoi import doc_tmx, kiem_tra_choi_duoc

GOC = Path(__file__).resolve().parents[2]
TILES = GOC / "gold_rush" / "assets" / "tiles"


@unittest.skipUnless((TILES / "man_choi.json").exists(), "cần ../gold_rush")
class TestManChoi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ds = man_choi.doc(TILES / "man_choi.json")

    def test_khop_ban_do_va_choi_duoc(self):
        self.assertEqual(man_choi.kiem_tra_khop_ban_do(self.ds, TILES), [])
        for m in self.ds.values():
            self.assertEqual(kiem_tra_choi_duoc(doc_tmx(TILES / m.tep)), [], m.id)

    def test_luat_coc(self):
        self.assertTrue(self.ds[1].mien_phi, "màn 1 phải là màn luyện tập — người mới 0 vàng vẫn chơi được")
        coc = [m.coc for m in self.ds.values()]
        self.assertEqual(coc, sorted(coc), "cọc tăng dần theo màn")
        for m in self.ds.values():
            if not m.mien_phi:
                self.assertGreater(m.gioi_han_giay, 0)
                self.assertGreaterEqual(m.thuong, m.coc, "hoàn thành phải lời ít nhất bằng tiền cọc")

    def test_gioi_han_du_rong(self):
        for m in self.ds.values():
            if m.gioi_han_giay:
                toi_thieu = man_choi.giay_vong_tham(doc_tmx(TILES / m.tep))
                self.assertGreater(m.gioi_han_giay, 1.5 * toi_thieu, m.id)

    def test_ignition_doc_dung_tep_nay(self):
        mod = (GOC / "gold_rush_chain" / "ignition" / "modules" / "CuaHangGoldRush.ts")
        if not mod.exists():
            self.skipTest("cần ../gold_rush_chain")
        self.assertIn("gold_rush/assets/tiles/man_choi.json", mod.read_text(encoding="utf-8"))
        self.assertTrue(re.search(r"man\.so_xu \+ man\.thuong", mod.read_text(encoding="utf-8")))

    def test_han_nop_khop_app(self):
        from core import trong_tai
        dart = (GOC / "gold_rush" / "lib" / "man_choi.dart").read_text(encoding="utf-8")
        self.assertEqual(trong_tai.HE_SO_TAM_DUNG, 2.0)
        self.assertIn("Duration(seconds: 2 * gioiHanGiay + 60)", dart)

    def test_tu_choi_json_sai(self):
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            tep = Path(d) / "m.json"
            sai = {"id": 2, "ten": "x", "mo_ta": "", "tep": "../a.tmx", "gioi_han_giay": 0, "he_so_ke_dich": 1,
                   "coc": 5, "thuong": 5, "so_xu": 3, "sao": 1}
            tep.write_text(json.dumps({"man": [sai]}))
            with self.assertRaises(ValueError):
                man_choi.doc(tep)


if __name__ == "__main__":
    unittest.main()
