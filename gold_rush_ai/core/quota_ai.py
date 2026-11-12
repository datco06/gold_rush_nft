from __future__ import annotations

from collections.abc import Callable
from contextlib import contextmanager
import math
from pathlib import Path
import re
import sqlite3
import time
from typing import Literal


class LoiQuotaAI(RuntimeError):
    pass


class VuotQuotaAI(RuntimeError):
    def __init__(self, cho_lai_sau: int):
        super().__init__("Đã hết lượt gọi AI trong ngày")
        self.cho_lai_sau = cho_lai_sau


def kiem_tra_gioi_han(value: int) -> int:
    if type(value) is not int or not 0 <= value <= 10000:
        raise ValueError("Giới hạn AI cần số nguyên trong 0..10000")
    return value


class KhoQuotaAI:
    def __init__(self, duong_dan: str | Path, *, lay_thoi_gian: Callable[[], float] = time.time):
        if str(duong_dan) == ":memory:" or not callable(lay_thoi_gian):
            raise ValueError("Quota cần file SQLite và đồng hồ server hợp lệ")
        self.duong_dan = Path(duong_dan)
        self.lay_thoi_gian = lay_thoi_gian
        try:
            self.duong_dan.parent.mkdir(parents=True, exist_ok=True)
        except OSError:
            raise LoiQuotaAI("Không tạo được kho quota AI") from None
        with self._ket_noi() as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS quota_ai (
                player_id TEXT NOT NULL,
                loai TEXT NOT NULL,
                ngay INTEGER NOT NULL,
                so_luot INTEGER NOT NULL,
                PRIMARY KEY(player_id, loai, ngay)
            )""")

    @contextmanager
    def _ket_noi(self):
        conn = None
        try:
            conn = sqlite3.connect(self.duong_dan, timeout=5)
            with conn:
                yield conn
        except sqlite3.Error:
            raise LoiQuotaAI("Không đọc/ghi được quota AI") from None
        finally:
            if conn is not None:
                conn.close()

    def tieu_thu(self, player_id: str, loai: Literal["image", "quest"], gioi_han: int) -> None:
        if (not isinstance(player_id, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,64}", player_id) is None
                or loai not in ("image", "quest")):
            raise ValueError("Danh tính hoặc loại quota AI không hợp lệ")
        kiem_tra_gioi_han(gioi_han)
        with self._ket_noi() as conn:
            conn.execute("BEGIN IMMEDIATE")
            now = self.lay_thoi_gian()
            if (isinstance(now, bool) or not isinstance(now, (int, float))
                    or not 0 <= now <= 253402300799):
                raise LoiQuotaAI("Đồng hồ server cho quota AI không hợp lệ")
            ngay = int(now // 86400)
            row = conn.execute("SELECT so_luot FROM quota_ai WHERE player_id = ? AND loai = ? AND ngay = ?",
                               (player_id, loai, ngay)).fetchone()
            da_dung = row[0] if row else 0
            if type(da_dung) is not int or da_dung < 0:
                raise LoiQuotaAI("Dữ liệu quota AI đã lưu không hợp lệ")
            if da_dung >= gioi_han:
                raise VuotQuotaAI(max(1, math.ceil((ngay + 1) * 86400 - now)))
            conn.execute("""INSERT INTO quota_ai(player_id, loai, ngay, so_luot) VALUES (?, ?, ?, 1)
                            ON CONFLICT(player_id, loai, ngay) DO UPDATE SET so_luot = so_luot + 1""",
                         (player_id, loai, ngay))
            conn.execute("DELETE FROM quota_ai WHERE ngay < ?", (ngay - 1,))
