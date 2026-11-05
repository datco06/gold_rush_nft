from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
import re
import sqlite3

from .nhiem_vu import NhiemVu


class LoiKhoNhiemVu(RuntimeError):
    pass


class XungDotYeuCauNhiemVu(ValueError):
    pass


class LichSuNhiemVuDaThayDoi(RuntimeError):
    pass


def _kiem_tra_id(value: str):
    if not isinstance(value, str) or re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value) is None:
        raise ValueError("Player ID và request ID cần 1..64 ký tự chữ, số, gạch nối hoặc gạch dưới")


def _kiem_tra_man(stage_id: int):
    if type(stage_id) is not int or not 1 <= stage_id <= 1000:
        raise ValueError("ID màn phải là số nguyên trong 1..1000")


class KhoNhiemVu:
    def __init__(self, duong_dan: str | Path):
        if str(duong_dan) == ":memory:":
            raise ValueError("Kho nhiệm vụ cần đường dẫn file SQLite để lưu qua các connection")
        self.duong_dan = Path(duong_dan)
        try:
            self.duong_dan.parent.mkdir(parents=True, exist_ok=True)
        except OSError:
            raise LoiKhoNhiemVu("Không tạo được thư mục lưu nhiệm vụ") from None
        with self._ket_noi() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS nhiem_vu (
                    so_thu_tu INTEGER PRIMARY KEY AUTOINCREMENT,
                    player_id TEXT NOT NULL,
                    request_id TEXT NOT NULL,
                    stage_id INTEGER NOT NULL,
                    do_kho TEXT NOT NULL,
                    quest_id TEXT NOT NULL UNIQUE,
                    payload TEXT NOT NULL,
                    UNIQUE(player_id, request_id)
                );
                CREATE INDEX IF NOT EXISTS ix_nhiem_vu_lich_su
                    ON nhiem_vu(player_id, stage_id, so_thu_tu DESC);
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
            raise LoiKhoNhiemVu("Không đọc/ghi được kho nhiệm vụ") from None
        finally:
            if conn is not None:
                conn.close()

    @staticmethod
    def _doc(row: sqlite3.Row) -> NhiemVu:
        try:
            nv = NhiemVu.model_validate_json(row["payload"])
        except (ValueError, TypeError):
            raise LoiKhoNhiemVu("Dữ liệu nhiệm vụ đã lưu không hợp lệ") from None
        if (nv.id, nv.stage_id, nv.difficulty) != (row["quest_id"], row["stage_id"], row["do_kho"]):
            raise LoiKhoNhiemVu("Metadata nhiệm vụ không khớp dữ liệu đã lưu")
        return nv

    def _tim(self, conn, player_id, request_id, stage_id, do_kho) -> NhiemVu | None:
        row = conn.execute("SELECT * FROM nhiem_vu WHERE player_id = ? AND request_id = ?",
                           (player_id, request_id)).fetchone()
        if row is None:
            return None
        if (row["stage_id"], row["do_kho"]) != (stage_id, do_kho):
            raise XungDotYeuCauNhiemVu("Request ID đã được dùng cho màn hoặc độ khó khác")
        return self._doc(row)

    def lay_theo_yeu_cau(self, player_id: str, request_id: str, stage_id: int,
                        do_kho: str) -> NhiemVu | None:
        _kiem_tra_id(player_id)
        _kiem_tra_id(request_id)
        _kiem_tra_man(stage_id)
        if do_kho not in ("easy", "medium", "hard"):
            raise ValueError("Độ khó không được hỗ trợ")
        with self._ket_noi() as conn:
            return self._tim(conn, player_id, request_id, stage_id, do_kho)

    def lich_su(self, player_id: str, stage_id: int, *, limit: int = 5) -> list[NhiemVu]:
        _kiem_tra_id(player_id)
        _kiem_tra_man(stage_id)
        if type(limit) is not int or not 1 <= limit <= 100:
            raise ValueError("Limit lịch sử phải là số nguyên trong 1..100")
        with self._ket_noi() as conn:
            rows = conn.execute("""SELECT * FROM nhiem_vu WHERE player_id = ? AND stage_id = ?
                                   ORDER BY so_thu_tu DESC LIMIT ?""", (player_id, stage_id, limit)).fetchall()
            return [self._doc(row) for row in reversed(rows)]

    def luu(self, player_id: str, request_id: str, nhiem_vu: NhiemVu,
            *, sau_nhiem_vu_id: str | None) -> NhiemVu:
        _kiem_tra_id(player_id)
        _kiem_tra_id(request_id)
        nv = NhiemVu.model_validate_json(nhiem_vu.model_dump_json())
        with self._ket_noi() as conn:
            conn.execute("BEGIN IMMEDIATE")
            cu = self._tim(conn, player_id, request_id, nv.stage_id, nv.difficulty)
            if cu is not None:
                return cu
            moi_nhat = conn.execute("""SELECT quest_id FROM nhiem_vu WHERE player_id = ? AND stage_id = ?
                                      ORDER BY so_thu_tu DESC LIMIT 1""", (player_id, nv.stage_id)).fetchone()
            if (moi_nhat["quest_id"] if moi_nhat else None) != sau_nhiem_vu_id:
                raise LichSuNhiemVuDaThayDoi("Lịch sử đã thay đổi, cần sinh lại nhiệm vụ")
            conn.execute("""INSERT INTO nhiem_vu(player_id, request_id, stage_id, do_kho, quest_id, payload)
                            VALUES (?, ?, ?, ?, ?, ?)""",
                         (player_id, request_id, nv.stage_id, nv.difficulty, nv.id, nv.model_dump_json()))
            return nv
