from __future__ import annotations

from collections.abc import Callable
from contextlib import contextmanager
from hashlib import sha256
import math
from pathlib import Path
import re
import sqlite3
import time
from uuid import uuid4

from .ai_nhan_vat import KetQuaTaoAnh
from .nhan_vat_ai import AnhNhanVat, KICH_THUOC_ANH_XEM_TRUOC, YeuCauTaoNhanVat
from .xu_ly_anh import chuan_hoa_anh


class LoiKhoAnh(RuntimeError):
    pass


class KhoAnhDay(LoiKhoAnh):
    pass


class XungDotYeuCauAnh(ValueError):
    pass


_SQL_YEU_CAU = """SELECT a.*, y.fingerprint AS request_fingerprint
                   FROM yeu_cau_anh y JOIN anh_nhan_vat a ON a.image_id = y.image_id
                   WHERE y.player_id = ? AND y.request_id = ?"""


def _ma_hop_le(value: str) -> None:
    if not isinstance(value, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value) is None:
        raise ValueError("M? ng??i ch?i v? request c?n 1..64 ch?, s?, g?ch n?i ho?c g?ch d??i")


def _fingerprint(player_id: str, request_id: str, yeu_cau: YeuCauTaoNhanVat) -> str:
    _ma_hop_le(player_id)
    _ma_hop_le(request_id)
    if not isinstance(yeu_cau, YeuCauTaoNhanVat):
        raise ValueError("C?n y?u c?u t?o nh?n v?t h?p l?")
    yc = YeuCauTaoNhanVat.model_validate(yeu_cau.model_dump(warnings=False), strict=True)
    return sha256(yc.model_dump_json().encode("utf-8")).hexdigest()


class KhoAnh:
    def __init__(self, duong_dan: str | Path, *, han_luu_giay: int = 86400,
                 so_anh_toi_da: int = 200, lay_thoi_gian: Callable[[], float] = time.time):
        if str(duong_dan) == ":memory:":
            raise ValueError("Kho ảnh cần đường dẫn file SQLite")
        if type(han_luu_giay) is not int or not 1 <= han_luu_giay <= 31536000:
            raise ValueError("Thời hạn lưu ảnh phải là số nguyên trong 1..31536000 giây")
        if type(so_anh_toi_da) is not int or not 1 <= so_anh_toi_da <= 10000:
            raise ValueError("Sức chứa kho ảnh phải là số nguyên trong 1..10000")
        if not callable(lay_thoi_gian):
            raise ValueError("Cần hàm lấy thời gian server")
        self.duong_dan = Path(duong_dan)
        self.han_luu_giay = han_luu_giay
        self.so_anh_toi_da = so_anh_toi_da
        self.lay_thoi_gian = lay_thoi_gian
        try:
            self.duong_dan.parent.mkdir(parents=True, exist_ok=True)
        except OSError:
            raise LoiKhoAnh("Không tạo được thư mục kho ảnh") from None
        with self._ket_noi() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS anh_nhan_vat (
                    image_id TEXT PRIMARY KEY,
                    payload TEXT NOT NULL,
                    png BLOB NOT NULL,
                    checksum TEXT NOT NULL,
                    expires_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS ix_anh_het_han ON anh_nhan_vat(expires_at);
                CREATE TABLE IF NOT EXISTS yeu_cau_anh (
                    player_id TEXT NOT NULL,
                    request_id TEXT NOT NULL,
                    fingerprint TEXT NOT NULL,
                    image_id TEXT NOT NULL UNIQUE,
                    PRIMARY KEY(player_id, request_id)
                );
            """)

    @contextmanager
    def _ket_noi(self):
        conn = None
        try:
            conn = sqlite3.connect(self.duong_dan, timeout=5)
            conn.row_factory = sqlite3.Row
            with conn:
                yield conn
        except sqlite3.Error:
            raise LoiKhoAnh("Không đọc/ghi được kho ảnh") from None
        finally:
            if conn is not None:
                conn.close()

    def _bay_gio(self) -> float:
        value = self.lay_thoi_gian()
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("Thời gian server không hợp lệ")
        try:
            value = float(value)
        except OverflowError:
            raise ValueError("Thời gian server không hợp lệ") from None
        if not math.isfinite(value) or value < 0:
            raise ValueError("Thời gian server không hợp lệ")
        return value

    @staticmethod
    def _chuan_bi_anh(ket_qua: KetQuaTaoAnh) -> tuple[AnhNhanVat, bytes, str]:
        if not isinstance(ket_qua, KetQuaTaoAnh):
            raise ValueError("C?n k?t qu? t?o ?nh h?p l?")
        image_id = f"img_{uuid4().hex}"
        metadata = AnhNhanVat(image_id=image_id, image_url=f"/api/ai/nhan-vat/anh/{image_id}",
                             width=KICH_THUOC_ANH_XEM_TRUOC, height=KICH_THUOC_ANH_XEM_TRUOC,
                             generation_source=ket_qua.generation_source)
        png = chuan_hoa_anh(ket_qua.png)
        return metadata, png, sha256(png).hexdigest()

    @staticmethod
    def _don(conn: sqlite3.Connection, bay_gio: float) -> int:
        count = conn.execute("DELETE FROM anh_nhan_vat WHERE expires_at <= ?", (bay_gio,)).rowcount
        conn.execute("""DELETE FROM yeu_cau_anh WHERE NOT EXISTS
                        (SELECT 1 FROM anh_nhan_vat a WHERE a.image_id = yeu_cau_anh.image_id)""")
        return count

    def _kiem_tra_suc_chua(self, conn: sqlite3.Connection) -> None:
        if conn.execute("SELECT COUNT(*) FROM anh_nhan_vat").fetchone()[0] >= self.so_anh_toi_da:
            raise KhoAnhDay("Kho ảnh đã đạt giới hạn, cần dọn ảnh hết hạn trước khi lưu thêm")

    def _ghi_anh(self, conn, metadata, png, checksum, bay_gio) -> None:
        het_han = bay_gio + self.han_luu_giay
        if not math.isfinite(het_han) or het_han <= bay_gio:
            raise ValueError("Th?i h?n ?nh kh?ng h?p l?")
        self._kiem_tra_suc_chua(conn)
        conn.execute("""INSERT INTO anh_nhan_vat(image_id, payload, png, checksum, expires_at)
                        VALUES (?, ?, ?, ?, ?)""",
                     (metadata.image_id, metadata.model_dump_json(), png, checksum, het_han))

    def luu(self, ket_qua: KetQuaTaoAnh) -> AnhNhanVat:
        metadata, png, checksum = self._chuan_bi_anh(ket_qua)
        with self._ket_noi() as conn:
            conn.execute("BEGIN IMMEDIATE")
            bay_gio = self._bay_gio()
            self._don(conn, bay_gio)
            self._ghi_anh(conn, metadata, png, checksum, bay_gio)
        return metadata

    def _cache(self, row, fingerprint: str, bay_gio: float) -> AnhNhanVat | None:
        if row is None:
            return None
        anh = self._doc_dong(row, row["image_id"], bay_gio)
        if anh is None:
            return None
        cu = row["request_fingerprint"]
        if not isinstance(cu, str) or re.fullmatch(r"[0-9a-f]{64}", cu) is None:
            raise LoiKhoAnh("D? li?u request ?nh ?? l?u kh?ng h?p l?")
        if cu != fingerprint:
            raise XungDotYeuCauAnh("Request ID ?? ???c d?ng cho m? t? kh?c")
        return anh[0]

    def lay_theo_yeu_cau(self, player_id: str, request_id: str,
                        yeu_cau: YeuCauTaoNhanVat) -> AnhNhanVat | None:
        fingerprint = _fingerprint(player_id, request_id, yeu_cau)
        with self._ket_noi() as conn:
            row = conn.execute(_SQL_YEU_CAU, (player_id, request_id)).fetchone()
        return self._cache(row, fingerprint, self._bay_gio())

    def tao_theo_yeu_cau(self, player_id: str, request_id: str, yeu_cau: YeuCauTaoNhanVat,
                         sinh_anh: Callable[[], KetQuaTaoAnh]) -> AnhNhanVat:
        fingerprint = _fingerprint(player_id, request_id, yeu_cau)
        with self._ket_noi() as conn:
            conn.execute("BEGIN IMMEDIATE")
            bay_gio = self._bay_gio()
            self._don(conn, bay_gio)
            row = conn.execute(_SQL_YEU_CAU, (player_id, request_id)).fetchone()
            cu = self._cache(row, fingerprint, bay_gio)
            if cu is not None:
                return cu
            self._kiem_tra_suc_chua(conn)
            metadata, png, checksum = self._chuan_bi_anh(sinh_anh())
            self._ghi_anh(conn, metadata, png, checksum, self._bay_gio())
            conn.execute("""INSERT INTO yeu_cau_anh(player_id, request_id, fingerprint, image_id)
                            VALUES (?, ?, ?, ?)""", (player_id, request_id, fingerprint, metadata.image_id))
        return metadata

    def luu_theo_yeu_cau(self, player_id: str, request_id: str, yeu_cau: YeuCauTaoNhanVat,
                         ket_qua: KetQuaTaoAnh) -> AnhNhanVat:
        return self.tao_theo_yeu_cau(player_id, request_id, yeu_cau, lambda: ket_qua)

    def doc(self, image_id: str) -> tuple[AnhNhanVat, bytes] | None:
        if not isinstance(image_id, str) or re.fullmatch(r"img_[0-9a-f]{32}", image_id) is None:
            raise ValueError("ID ảnh không hợp lệ")
        with self._ket_noi() as conn:
            row = conn.execute("SELECT * FROM anh_nhan_vat WHERE image_id = ?", (image_id,)).fetchone()
        return self._doc_dong(row, image_id, self._bay_gio())

    def doc_cho_nguoi(self, player_id: str, image_id: str) -> tuple[AnhNhanVat, bytes] | None:
        _ma_hop_le(player_id)
        if not isinstance(image_id, str) or re.fullmatch(r"img_[0-9a-f]{32}", image_id) is None:
            raise ValueError("ID ?nh kh?ng h?p l?")
        with self._ket_noi() as conn:
            row = conn.execute("""SELECT a.* FROM anh_nhan_vat a JOIN yeu_cau_anh y
                                  ON a.image_id = y.image_id WHERE y.player_id = ? AND a.image_id = ?""",
                               (player_id, image_id)).fetchone()
        return self._doc_dong(row, image_id, self._bay_gio())

    @staticmethod
    def _doc_dong(row, image_id: str, bay_gio: float) -> tuple[AnhNhanVat, bytes] | None:
        if row is None:
            return None
        het_han = row["expires_at"]
        if not isinstance(het_han, (int, float)) or not math.isfinite(het_han):
            raise LoiKhoAnh("Thời hạn ảnh đã lưu không hợp lệ")
        if het_han <= bay_gio:
            return None
        try:
            metadata = AnhNhanVat.model_validate_json(row["payload"])
        except (ValueError, TypeError):
            raise LoiKhoAnh("Metadata ảnh đã lưu không hợp lệ") from None
        png = row["png"]
        if (metadata.image_id != image_id or not isinstance(png, bytes)
                or sha256(png).hexdigest() != row["checksum"]):
            raise LoiKhoAnh("Dữ liệu ảnh đã lưu không khớp metadata/checksum")
        return metadata, png

    def don_het_han(self) -> int:
        with self._ket_noi() as conn:
            conn.execute("BEGIN IMMEDIATE")
            return self._don(conn, self._bay_gio())
