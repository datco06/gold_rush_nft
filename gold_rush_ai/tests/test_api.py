"""Kiểm thử API bằng TestClient — không cần chạy server. Cần: pip install fastapi httpx"""
import os
import tempfile
import unittest
import uuid

try:
    from fastapi.testclient import TestClient
except ImportError:                                   # máy chưa cài fastapi → bỏ qua, không báo đỏ
    raise unittest.SkipTest("chưa cài fastapi/httpx")

os.environ["NHAT_KY_DIR"] = tempfile.mkdtemp()        # đặt TRƯỚC khi import app: không ghi vào dữ liệu thật
from api.main import app  # noqa: E402


class TestApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = TestClient(app).__enter__()           # __enter__ để chạy lifespan (nạp mô hình)

    @classmethod
    def tearDownClass(cls):
        cls.c.__exit__(None, None, None)

    def test_health(self):
        r = self.c.get("/api/health")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["da_nap"]["tro_ly"])

    def test_nhat_ky_hop_le_roi_xep_hang(self):
        van = {"ma_van": str(uuid.uuid4()), "phien_ban_app": "1.1.0", "ket_qua": "thang", "giay": 120,
               "diem": 480, "ten_hien_thi": "Lan",
               "su_kien": [{"loai": "trung_don", "giay": 30, "x": 300, "y": 200}]}
        self.assertEqual(self.c.post("/api/nhat-ky", json=van).status_code, 201)
        bang = self.c.get("/api/bang-xep-hang").json()["bang"]
        self.assertEqual(bang[0]["ten"], "Lan")
        sk = self.c.get("/api/su-kien").json()["su_kien"]
        self.assertEqual(len(sk), 1)

    def test_nhat_ky_sai_tra_422(self):
        self.assertEqual(self.c.post("/api/nhat-ky", json={"ma_van": "x"}).status_code, 422)

    def test_nhat_ky_qua_lon_tra_413(self):
        self.assertEqual(self.c.post("/api/nhat-ky", content=b"x" * (65 * 1024)).status_code, 413)

    def test_du_doan_do_kho(self):
        r = self.c.post("/api/do-kho/du-doan", json={"dac_trung": [0.25, 1.5, 3.0, 0.25, 2.0]})
        self.assertEqual(r.status_code, 200)
        self.assertGreater(r.json()["p_thua"], 0.5)
        self.assertLess(r.json()["he_so_toc_do"], 1.0)

    def test_du_doan_sai_so_dac_trung_tra_422(self):
        self.assertEqual(self.c.post("/api/do-kho/du-doan", json={"dac_trung": [1, 2]}).status_code, 422)

    def test_sinh_ban_do(self):
        r = self.c.get("/api/ban-do/sinh", params={"seed": 3})
        self.assertEqual(r.status_code, 200)
        self.assertIn('name="VaCham"', r.text)
        self.assertIn("ti_le_di_duoc", r.headers["X-Chi-So"])

    def test_tro_ly_tu_choi_ngoai_pham_vi(self):
        r = self.c.post("/api/tro-ly", json={"cau_hoi": "Thủ đô của Pháp là gì?"})
        self.assertFalse(r.json()["trong_pham_vi"])
