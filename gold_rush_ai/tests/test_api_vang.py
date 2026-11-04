"""API màn chơi + phiếu vàng — cần fastapi, httpx (bỏ qua nếu chưa cài)."""
import importlib
import json
import os
import tempfile
import time
import unittest
import uuid

try:
    from fastapi.testclient import TestClient
except ImportError:
    raise unittest.SkipTest("chưa cài fastapi/httpx")

_TAM = tempfile.mkdtemp()
os.environ.update({
    "NHAT_KY_DIR": os.path.join(_TAM, "nk"), "SO_PHIEU": os.path.join(_TAM, "phieu.jsonl"),
    "SO_VE": os.path.join(_TAM, "ve.jsonl"),
    "TRONG_TAI_KHOA": "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
    "CHAIN_ID": "31337", "HOP_DONG_CUA_HANG": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
})
# test_api.py có thể đã import config/api.main với biến môi trường khác → nạp lại cho chắc
import config  # noqa: E402
import api.main  # noqa: E402
from core import trong_tai  # noqa: E402
from core.luoi import doc_tmx  # noqa: E402
from tests.test_trong_tai import TILES, TMX, van_that  # noqa: E402

importlib.reload(config)
importlib.reload(api.main)
VI = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"


@unittest.skipUnless(TMX.exists(), "cần ../gold_rush")
class TestApiVang(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = TestClient(api.main.app).__enter__()
        cls.b1 = doc_tmx(TMX)
        cls.b2 = doc_tmx(TILES / "man_2.tmx")

    @classmethod
    def tearDownClass(cls):
        cls.c.__exit__(None, None, None)

    def _gui_van(self, nk, man=1, ban_do="gold_rush.tmx", ma=None):
        ma = ma or str(uuid.uuid4())
        than = {"ma_van": ma, "phien_ban_app": "1.3.0", "man": man, "ban_do": ban_do, **nk}
        self.assertEqual(self.c.post("/api/nhat-ky", json=than).status_code, 201)
        return ma

    def _phieu(self, ma, vi=VI):
        return self.c.post("/api/vang/phieu", json={"ma_van": ma, "vi": vi})

    def test_cau_hinh_va_danh_sach_man(self):
        j = self.c.get("/api/vang/cau-hinh").json()
        self.assertEqual(j["trong_tai"], "0x70997970C51812dc3A010C7d01b50e0d17dc79C8")
        ds = self.c.get("/api/man").json()["man"]
        self.assertEqual([m["id"] for m in ds], [1, 2, 3, 4, 5, 6])
        self.assertEqual(ds[1]["thuong_toi_da"], ds[1]["so_xu"] + ds[1]["thuong"])

    def test_luyen_tap_xin_lai_thi_ky_lai_cung_noi_dung(self):
        ma = self._gui_van(van_that(self.b1, 5))
        r = self._phieu(ma)
        self.assertEqual(r.status_code, 200, r.text)
        p = r.json()["phieu"]
        self.assertEqual((p["man"], p["ve"], p["soVang"]), (1, 0, 5))
        time.sleep(1.1)
        r2 = self._phieu(ma)                                  # app mất phiếu / phiếu hết hạn → xin lại
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(r2.json()["phieu"]["maVan"], p["maVan"])
        self.assertEqual(r2.json()["phieu"]["soVang"], 5)
        self.assertGreater(r2.json()["phieu"]["hanChot"], p["hanChot"])
        self.assertEqual(self._phieu(ma, "0x" + "1" * 40).status_code, 409)   # ví khác: không

    def test_man_co_coc_tron_luong(self):
        ma = str(uuid.uuid4())
        bd = self.c.post("/api/man/bat-dau", json={"ma_van": ma, "vi": VI, "man": 2, "ve": 1})
        self.assertEqual(bd.status_code, 201, bd.text)
        # cùng vé không bắt đầu lần hai (không "chơi lại tới khi thắng")
        lai = self.c.post("/api/man/bat-dau", json={"ma_van": str(uuid.uuid4()), "vi": VI, "man": 2, "ve": 1})
        self.assertEqual(lai.status_code, 409)
        self.assertTrue(self.c.get("/api/man/ve", params={"vi": VI, "ve": 1}).json()["da_dung"])
        self.assertFalse(self.c.get("/api/man/ve", params={"vi": VI, "ve": 99}).json()["da_dung"])

        nk = van_that(self.b2, 18, ket_qua="thang")
        so_ve = trong_tai.SoVe(config.SO_VE)       # giả lập: ván bắt đầu từ (thời lượng + 5) giây trước
        ban_ghi = so_ve._doc()
        for v in ban_ghi:
            if v["ma_van"] == ma:
                v["bat_dau"] -= nk["giay"] + 5
        so_ve.tep.write_text("".join(json.dumps(v) + "\n" for v in ban_ghi))
        self._gui_van(nk, man=2, ban_do="man_2.tmx", ma=ma)
        r = self._phieu(ma)
        self.assertEqual(r.status_code, 200, r.text)
        p = r.json()["phieu"]
        self.assertEqual((p["man"], p["ve"], p["soVang"]), (2, 1, 18 + 5))

        cho = self.c.get("/api/vang/cho-nhan", params={"vi": VI}).json()["phieu"]
        self.assertIn(ma, [x["ma_van"] for x in cho])

    def test_man_co_coc_nop_ngay_bi_dong_ho_bat(self):
        ma = str(uuid.uuid4())
        self.c.post("/api/man/bat-dau", json={"ma_van": ma, "vi": VI, "man": 2, "ve": 2})
        self._gui_van(van_that(self.b2, 18, ket_qua="thang"), man=2, ban_do="man_2.tmx", ma=ma)
        r = self._phieu(ma)                    # tự khai ~60 s nhưng nộp ngay sau khi bắt đầu
        self.assertEqual(r.status_code, 422)
        self.assertIn("kể từ lúc bắt đầu", r.text)

    def test_man_co_coc_thieu_dang_ky_hoac_thua(self):
        ma = self._gui_van(van_that(self.b2, 18, ket_qua="thang"), man=2, ban_do="man_2.tmx")
        self.assertEqual(self._phieu(ma).status_code, 422)            # không có bat-dau
        self.assertEqual(self.c.post("/api/man/bat-dau",
                                     json={"ma_van": str(uuid.uuid4()), "vi": VI, "man": 1, "ve": 9}).status_code,
                         422)                                         # màn luyện tập không cần vé
        ma2 = self._gui_van(van_that(self.b2, 3), man=2, ban_do="man_1_gia.tmx")
        self.assertEqual(self._phieu(ma2).status_code, 422)           # bản đồ không khớp màn

    def test_gui_lai_nhat_ky_khong_luu_trung(self):
        nk = van_that(self.b1, 3)
        ma = self._gui_van(nk)
        self._gui_van({**nk, "diem": 9999}, ma=ma)          # lần gửi lại KHÔNG ghi đè bản đầu
        r = self._phieu(ma)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["phieu"]["soVang"], 3)

    def test_van_gian_bi_tu_choi(self):
        nk = van_that(self.b1, 6)
        for e in nk["su_kien"]:
            e["giay"] /= 4
        self.assertEqual(self._phieu(self._gui_van(nk)).status_code, 422)

    def test_van_khong_ton_tai_va_vi_sai(self):
        self.assertEqual(self._phieu("khong-co-van").status_code, 404)
        self.assertEqual(self._phieu("abcdefgh", "0x12").status_code, 422)


if __name__ == "__main__":
    unittest.main()
