"""Kho PNG và metadata SQLite, ghi nguyên tử và hết hạn theo thời gian server.

Mỗi thao tác mở connection riêng. SQLite tuần tự hóa kiểm tra sức chứa và ghi
bằng BEGIN IMMEDIATE. Ảnh hết hạn không được trả về; don_het_han và luu mới
xóa các hàng hết hạn để SQLite tái sử dụng dung lượng trong file database.
"""
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
from .nhan_vat_ai import AnhNhanVat, KICH_THUOC_ANH_XEM_TRUOC
from .xu_ly_anh import chuan_hoa_anh


class LoiKhoAnh(RuntimeError):
    """Kho không truy cập được hoặc dữ liệu ảnh lưu bị hỏng."""


class KhoAnhDay(LoiKhoAnh):
    """Số ảnh còn hạn đã đạt giới hạn cấu hình."""


class KhoAnh:
    def __init__(self, duong_dan: str | Path, *, han_luu_giay: int = 86400,
                 so_anh_toi_da: int = 200, lay_thoi_gian: Callable[[], float] = time.time):
        """TTL 1 giây..1 năm, sức chứa 1..10000 ảnh; mặc định 24 giờ và 200 ảnh."""
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

    def luu(self, ket_qua: KetQuaTaoAnh) -> AnhNhanVat:
        """Cấp ID mới, chuẩn hóa ảnh, rồi lưu metadata và byte trong cùng transaction."""
        if not isinstance(ket_qua, KetQuaTaoAnh):
            raise ValueError("Cần kết quả tạo ảnh hợp lệ")
        image_id = f"img_{uuid4().hex}"
        metadata = AnhNhanVat(image_id=image_id, image_url=f"/api/ai/nhan-vat/anh/{image_id}",
                             width=KICH_THUOC_ANH_XEM_TRUOC, height=KICH_THUOC_ANH_XEM_TRUOC,
                             generation_source=ket_qua.generation_source)
        # Giải mã và xử lý ảnh ngoài transaction ghi để giữ khóa SQL ngắn.
        png = chuan_hoa_anh(ket_qua.png)
        checksum = sha256(png).hexdigest()
        with self._ket_noi() as conn:
            conn.execute("BEGIN IMMEDIATE")
            bay_gio = self._bay_gio()
            het_han = bay_gio + self.han_luu_giay
            if not math.isfinite(het_han) or het_han <= bay_gio:
                raise ValueError("Thời hạn ảnh không hợp lệ")
            conn.execute("DELETE FROM anh_nhan_vat WHERE expires_at <= ?", (bay_gio,))
            so_anh = conn.execute("SELECT COUNT(*) FROM anh_nhan_vat").fetchone()[0]
            if so_anh >= self.so_anh_toi_da:
                raise KhoAnhDay("Kho ảnh đã đạt giới hạn, cần dọn ảnh hết hạn trước khi lưu thêm")
            conn.execute("""INSERT INTO anh_nhan_vat(image_id, payload, png, checksum, expires_at)
                            VALUES (?, ?, ?, ?, ?)""",
                         (image_id, metadata.model_dump_json(), png, checksum, het_han))
        return metadata

    def doc(self, image_id: str) -> tuple[AnhNhanVat, bytes] | None:
        """Trả metadata/PNG còn hạn; ID chưa tồn tại hoặc đã hết hạn trả None."""
        if not isinstance(image_id, str) or re.fullmatch(r"img_[0-9a-f]{32}", image_id) is None:
            raise ValueError("ID ảnh không hợp lệ")
        with self._ket_noi() as conn:
            row = conn.execute("SELECT * FROM anh_nhan_vat WHERE image_id = ?", (image_id,)).fetchone()
        if row is None:
            return None
        het_han = row["expires_at"]
        if not isinstance(het_han, (int, float)) or not math.isfinite(het_han):
            raise LoiKhoAnh("Thời hạn ảnh đã lưu không hợp lệ")
        if het_han <= self._bay_gio():
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
        """Xóa các ảnh hết hạn, trả số hàng đã xóa; phần trống được SQLite tái sử dụng."""
        with self._ket_noi() as conn:
            conn.execute("BEGIN IMMEDIATE")
            cursor = conn.execute("DELETE FROM anh_nhan_vat WHERE expires_at <= ?", (self._bay_gio(),))
            return cursor.rowcount