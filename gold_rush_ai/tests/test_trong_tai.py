"""Kiểm thử trọng tài: ván thật được duyệt, ván gian bị chặn, phiếu ký đúng."""
import tempfile
import unittest
from pathlib import Path

from core.eth_ky import bam_eip712, phuc_hoi
from core.luoi import doc_tmx, tim_duong
from core import man_choi
from core.trong_tai import (PHIEU, SoPhieu, SoVe, kiem_dinh, kiem_dong_ho, ky_phieu, la_dia_chi,
                            ma_van_bytes32)

TILES = Path(__file__).resolve().parents[2] / "gold_rush" / "assets" / "tiles"
TMX = TILES / "gold_rush.tmx"
KHOA = bytes.fromhex("59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d")  # Hardhat #1
VI = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"                                                  # Hardhat #2
HOP_DONG = "0x5FbDB2315678afecb367f032d93F642f64180aa3"


def van_that(b, so_xu=5, he_so=1.1, ket_qua="thua"):
    """Mô phỏng một người chơi thật: đi theo A* tới xu gần nhất, tốc độ 74 px/s."""
    cur, t, ev, con = b.cac_diem("george")[0], 0.0, [], list(b.cac_diem("coin"))
    for _ in range(so_xu):
        nxt = min(con, key=lambda c: len(tim_duong(b, cur, c) or range(9999)))
        con.remove(nxt)
        t += len(tim_duong(b, cur, nxt)) * 16 / 74 * he_so
        ev.append({"loai": "nhat_xu", "giay": round(t, 2), "x": nxt[0] * 16 + 11, "y": nxt[1] * 16 + 4})
        cur = nxt
    return {"su_kien": ev, "diem": 20 * so_xu, "giay": t + 3, "ket_qua": ket_qua}


@unittest.skipUnless(TMX.exists(), "cần ../gold_rush")
class TestKiemDinh(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.b = doc_tmx(TMX)

    def test_van_that_duoc_duyet(self):
        for n in (1, 5, 12):
            kq = kiem_dinh(van_that(self.b, n), self.b)
            self.assertTrue(kq.hop_le, kq.ly_do)
            self.assertEqual(kq.so_vang, n)

    def test_chay_nhanh_hon_suc_nguoi_bi_chan(self):
        nk = van_that(self.b, 6)
        for e in nk["su_kien"]:
            e["giay"] /= 3                      # chạy nhanh gấp 3 lần George
        self.assertFalse(kiem_dinh(nk, self.b).hop_le)

    def test_xu_khong_ton_tai_bi_chan(self):
        nk = van_that(self.b, 3)
        nk["su_kien"].append({"loai": "nhat_xu", "giay": nk["giay"] - 1, "x": 5, "y": 5})
        nk["diem"] += 20
        self.assertFalse(kiem_dinh(nk, self.b).hop_le)

    def test_nhat_mot_xu_hai_lan_bi_chan(self):
        nk = van_that(self.b, 2)
        nk["su_kien"].append({**nk["su_kien"][-1], "giay": nk["giay"] - 0.5})
        nk["diem"] += 20
        self.assertFalse(kiem_dinh(nk, self.b).hop_le)

    def test_diem_khong_khop_so_xu(self):
        nk = van_that(self.b, 4)
        nk["diem"] = 480
        self.assertFalse(kiem_dinh(nk, self.b).hop_le)


@unittest.skipUnless((TILES / "man_choi.json").exists(), "cần ../gold_rush")
class TestManCoCoc(unittest.TestCase):
    """Màn có cọc: chỉ trả vàng khi HOÀN THÀNH; hoàn thành thì cộng thưởng."""

    @classmethod
    def setUpClass(cls):
        cls.ds = man_choi.doc(TILES / "man_choi.json")
        cls.m2 = cls.ds[2]
        cls.b2 = doc_tmx(TILES / cls.m2.tep)

    def test_hoan_thanh_duoc_xu_cong_thuong(self):
        nk = van_that(self.b2, self.m2.so_xu, ket_qua="thang")
        self.assertLessEqual(nk["giay"], self.m2.gioi_han_giay, "giới hạn thời gian phải đủ cho người chơi thật")
        kq = kiem_dinh(nk, self.b2, self.m2)
        self.assertTrue(kq.hop_le, kq.ly_do)
        self.assertEqual(kq.so_vang, self.m2.so_xu + self.m2.thuong)
        self.assertLessEqual(kq.so_vang, self.m2.thuong_toi_da)

    def test_khong_hoan_thanh_thi_khong_co_phieu(self):
        for nk in (van_that(self.b2, self.m2.so_xu - 1, ket_qua="thua"),        # chết khi còn 1 xu
                   van_that(self.b2, self.m2.so_xu, ket_qua="bo")):              # bỏ ngang
            self.assertFalse(kiem_dinh(nk, self.b2, self.m2).hop_le)

    def test_qua_gio_bi_tu_choi(self):
        nk = van_that(self.b2, self.m2.so_xu, ket_qua="thang")
        nk["giay"] = self.m2.gioi_han_giay + 5
        kq = kiem_dinh(nk, self.b2, self.m2)
        self.assertFalse(kq.hop_le)
        self.assertIn("chỉ cho", kq.ly_do[0])

    def test_man_luyen_tap_thua_van_duoc_xu_khong_thuong(self):
        m1, b1 = self.ds[1], doc_tmx(TMX)
        kq = kiem_dinh(van_that(b1, 4), b1, m1)
        self.assertTrue(kq.hop_le, kq.ly_do)
        self.assertEqual(kq.so_vang, 4)

    def test_moi_man_deu_hoan_thanh_duoc_trong_gioi_han(self):
        for m in self.ds.values():
            if m.mien_phi:
                continue
            b = doc_tmx(TILES / m.tep)
            nk = van_that(b, m.so_xu, ket_qua="thang")
            kq = kiem_dinh(nk, b, m)
            self.assertTrue(kq.hop_le, (m.id, kq.ly_do))


class TestSoVeVaDongHo(unittest.TestCase):
    def test_moi_ve_bat_dau_mot_lan(self):
        with tempfile.TemporaryDirectory() as d:
            so = SoVe(Path(d) / "ve.jsonl")
            so.bat_dau("van-a", VI, 2, 1)
            with self.assertRaises(ValueError):
                so.bat_dau("van-b", VI.lower(), 2, 1)          # cùng vé → chơi lại tới khi thắng: chặn
            with self.assertRaises(ValueError):
                so.bat_dau("van-a", VI, 2, 2)                  # cùng mã ván
            so.bat_dau("van-c", VI, 3, 2)
            self.assertEqual(so.lay_theo_van("van-c")["ve"], 2)

    def test_dong_ho_may_chu(self):
        m = man_choi.ManChoi(2, "x", "", "man_2.tmx", 100, 1.0, 5, 5, 18, 2)
        ve = {"bat_dau": 1_900_000_000}
        from datetime import datetime, timezone

        def nk(giay, sau):
            luc = datetime.fromtimestamp(1_900_000_000 + sau, timezone.utc).isoformat(timespec="seconds")
            return {"giay": giay, "nhan_luc": luc}
        self.assertEqual(kiem_dong_ho(ve, nk(80, 85), m), [])
        self.assertTrue(kiem_dong_ho(ve, nk(80, 20), m))      # tự khai 80 s mà 20 s sau đã nộp
        self.assertTrue(kiem_dong_ho(ve, nk(80, 900), m))     # nộp sau 15 phút
        self.assertTrue(kiem_dong_ho(ve, {"giay": 1}, m))     # thiếu nhan_luc


class TestPhieu(unittest.TestCase):
    def test_phieu_ky_boi_trong_tai(self):
        p = ky_phieu(VI.lower(), 2, 7, 23, "van-mau-0001", KHOA, 31337, HOP_DONG, bay_gio=1_900_000_000)
        self.assertEqual(p["phieu"]["nguoiChoi"], VI)                    # chuẩn hoá checksum
        self.assertEqual((p["phieu"]["man"], p["phieu"]["ve"]), (2, 7))
        self.assertEqual(p["phieu"]["hanChot"], 1_900_000_900)
        mien = {"name": "GoldRush", "version": "2", "chainId": 31337, "verifyingContract": HOP_DONG}
        bam = bam_eip712(mien, "PhieuVang", PHIEU, p["phieu"])
        self.assertEqual("0x" + bam.hex(), p["bam"])
        self.assertEqual(phuc_hoi(bam, bytes.fromhex(p["chu_ky"][2:])), p["trong_tai"])

    def test_chuoi_kieu_khop_solidity(self):
        from core.eth_ky import chuoi_kieu
        self.assertEqual(chuoi_kieu("PhieuVang", PHIEU),
                         "PhieuVang(address nguoiChoi,uint256 man,uint256 ve,uint256 soVang,"
                         "bytes32 maVan,uint256 hanChot)")

    def test_tu_choi_so_vang_vo_ly(self):
        for man, ve, so_vang in ((1, 0, 0), (0, 0, 5), (2, -1, 5)):
            with self.assertRaises(ValueError):
                ky_phieu(VI, man, ve, so_vang, "van-mau-0001", KHOA, 31337, HOP_DONG)

    def test_ma_van_bytes32(self):
        self.assertEqual(len(ma_van_bytes32("abc")), 66)
        self.assertNotEqual(ma_van_bytes32("abc"), ma_van_bytes32("abd"))

    def test_so_phieu_moi_van_mot_lan_va_gioi_han_ngay(self):
        with tempfile.TemporaryDirectory() as d:
            so = SoPhieu(Path(d) / "p.jsonl")
            self.assertFalse(so.da_cap("v1"))
            so.ghi("v1", VI, 24)
            so.ghi("v2", VI.lower(), 23, man=2, ve=1)
            self.assertTrue(so.da_cap("v1"))
            self.assertEqual(so.vang_hom_nay(VI), 47)
            self.assertEqual(so.lay("v2")["ve"], 1)
            self.assertEqual([p["ma_van"] for p in so.cua_vi(VI.lower())], ["v1", "v2"])

    def test_la_dia_chi(self):
        self.assertTrue(la_dia_chi(VI))
        self.assertFalse(la_dia_chi("0x123"))
        self.assertFalse(la_dia_chi("0x" + "g" * 40))


if __name__ == "__main__":
    unittest.main()
