"""Module lưu trữ tiến trình màn chơi (1–6) bền vững của người chơi SIWE (Giai đoạn 8).

Đặc tả bảo mật:
- Mỗi bản ghi tiến trình gắn chặt với `owner_user_id` và `verified_wallet_address` từ phiên SIWE thật.
- Không tin cậy client tự khai báo user_id, ví hoặc cờ completed.
- Phân lập dữ liệu hoàn toàn giữa các tài khoản: ví A không thể đọc/ghi đè tiến trình của ví B.
- Chống tấn công Replay Attack: mỗi bằng chứng hoàn thành (mã ván trọng tài hoặc tx hash blockchain)
  được gán một `replay_key` duy nhất (UNIQUE) trên toàn hệ thống.
- Bền vững qua khởi động lại: lưu trữ SQLite với cơ chế WAL (Write-Ahead Logging).
"""
from __future__ import annotations

from contextlib import contextmanager
from datetime import UTC, datetime
import json
import logging
from pathlib import Path
import sqlite3
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

log = logging.getLogger(__name__)


class LoiKhoTienTrinh(RuntimeError):
    """Lỗi cơ sở dữ liệu kho tiến trình."""
    pass


class LoiReplayTienTrinh(LoiKhoTienTrinh):
    """Bằng chứng hoàn thành màn đã được sử dụng trước đó (chống replay)."""
    pass


class LoiQuyenTienTrinh(LoiKhoTienTrinh):
    """Không có quyền truy cập hoặc ghi đè tiến trình của người chơi khác."""
    pass


class BanGhiTienTrinh(BaseModel):
    """Mô hình dữ liệu một màn chơi đã hoàn thành của người chơi."""
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    id: int | None = None
    owner_user_id: str = Field(min_length=1, max_length=64)
    verified_wallet_address: str = Field(pattern=r"^0x[0-9a-fA-F]{40}$")
    stage_id: int = Field(ge=1, le=6)
    completion_status: Literal["completed", "unlocked", "locked"] = "completed"
    verification_source: str = Field(min_length=1, max_length=64)
    completion_evidence: dict[str, Any] = Field(default_factory=dict)
    replay_key: str = Field(min_length=1, max_length=128)
    completed_at: str = Field(min_length=1, max_length=64)
    created_at: str = Field(min_length=1, max_length=64)


class KhoTienTrinh:
    """Hệ thống lưu trữ SQLite quản lý tiến trình vượt màn có xác minh."""

    def __init__(self, db_path: Path | str):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._khoi_tao()

    @contextmanager
    def _ket_noi(self):
        conn = sqlite3.connect(str(self.db_path), timeout=30.0)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA foreign_keys=ON")
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def _khoi_tao(self) -> None:
        with self._ket_noi() as conn:
            conn.execute("""
            CREATE TABLE IF NOT EXISTS tien_trinh_man (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_user_id TEXT NOT NULL,
                verified_wallet_address TEXT NOT NULL,
                stage_id INTEGER NOT NULL CHECK(stage_id >= 1 AND stage_id <= 6),
                completion_status TEXT NOT NULL,
                verification_source TEXT NOT NULL,
                completion_evidence TEXT NOT NULL,
                replay_key TEXT NOT NULL UNIQUE,
                completed_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(owner_user_id, stage_id)
            )
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_tien_trinh_user ON tien_trinh_man(owner_user_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_tien_trinh_wallet ON tien_trinh_man(verified_wallet_address)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_tien_trinh_replay ON tien_trinh_man(replay_key)")

    def _row_to_model(self, row: sqlite3.Row) -> BanGhiTienTrinh:
        raw_ev = row["completion_evidence"]
        evidence = json.loads(raw_ev) if raw_ev else {}
        return BanGhiTienTrinh(
            id=row["id"],
            owner_user_id=row["owner_user_id"],
            verified_wallet_address=row["verified_wallet_address"],
            stage_id=row["stage_id"],
            completion_status=row["completion_status"],
            verification_source=row["verification_source"],
            completion_evidence=evidence,
            replay_key=row["replay_key"],
            completed_at=row["completed_at"],
            created_at=row["created_at"],
        )

    def ghi_nhan_hoan_thanh(
        self,
        *,
        owner_user_id: str,
        verified_wallet_address: str,
        stage_id: int,
        completion_status: str = "completed",
        verification_source: str,
        completion_evidence: dict[str, Any],
        replay_key: str,
        completed_at: str | None = None,
    ) -> BanGhiTienTrinh:
        """Ghi nhận hoàn thành màn có kiểm tra chống replay attack."""
        if stage_id < 1 or stage_id > 6:
            raise ValueError(f"stage_id phải từ 1 đến 6 (nhận được: {stage_id})")

        now_str = datetime.now(UTC).isoformat(timespec="seconds")
        c_at = completed_at or now_str
        ev_json = json.dumps(completion_evidence, ensure_ascii=False)
        wallet = verified_wallet_address.lower()

        with self._ket_noi() as conn:
            # 1. Chống replay attack: kiểm tra replay_key trên toàn hệ thống
            row_replay = conn.execute(
                "SELECT * FROM tien_trinh_man WHERE replay_key = ?",
                (replay_key,),
            ).fetchone()
            if row_replay is not None:
                # Nếu cùng chính user này và cùng stage_id -> idempotent
                if row_replay["owner_user_id"] == owner_user_id and row_replay["stage_id"] == stage_id:
                    return self._row_to_model(row_replay)
                # Đã được dùng bởi người chơi khác hoặc màn khác
                raise LoiReplayTienTrinh(f"Bằng chứng '{replay_key}' đã được sử dụng trước đó")

            # 2. Kiểm tra nếu user đã có bản ghi hoàn thành màn này
            row_existing = conn.execute(
                "SELECT * FROM tien_trinh_man WHERE owner_user_id = ? AND stage_id = ?",
                (owner_user_id, stage_id),
            ).fetchone()
            if row_existing is not None:
                # Đã hoàn thành trước đó -> giữ nguyên bản ghi chính thức ban đầu
                return self._row_to_model(row_existing)

            # 3. Ghi nhận mới
            try:
                cur = conn.execute(
                    """
                    INSERT INTO tien_trinh_man (
                        owner_user_id, verified_wallet_address, stage_id, completion_status,
                        verification_source, completion_evidence, replay_key, completed_at, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        owner_user_id, wallet, stage_id, completion_status,
                        verification_source, ev_json, replay_key, c_at, now_str,
                    ),
                )
                rec_id = cur.lastrowid
                row_new = conn.execute("SELECT * FROM tien_trinh_man WHERE id = ?", (rec_id,)).fetchone()
                return self._row_to_model(row_new)
            except sqlite3.IntegrityError as e:
                if "replay_key" in str(e):
                    raise LoiReplayTienTrinh(f"Bằng chứng '{replay_key}' đã được sử dụng") from None
                raise LoiKhoTienTrinh(f"Không thể ghi nhận tiến trình ({type(e).__name__})") from None

    def lay_tien_trinh(self, owner_user_id: str) -> list[BanGhiTienTrinh]:
        """Lấy toàn bộ bản ghi tiến trình của một người chơi cụ thể."""
        with self._ket_noi() as conn:
            rows = conn.execute(
                "SELECT * FROM tien_trinh_man WHERE owner_user_id = ? ORDER BY stage_id ASC",
                (owner_user_id,),
            ).fetchall()
            return [self._row_to_model(r) for r in rows]

    def lay_cac_man_hoan_thanh(self, owner_user_id: str) -> frozenset[int]:
        """Lấy tập hợp các ID màn đã hoàn thành hợp lệ (1–6) của người chơi."""
        with self._ket_noi() as conn:
            rows = conn.execute(
                "SELECT stage_id FROM tien_trinh_man WHERE owner_user_id = ? AND completion_status = 'completed'",
                (owner_user_id,),
            ).fetchall()
            return frozenset(row["stage_id"] for row in rows)

    def lay_ban_ghi(self, owner_user_id: str, stage_id: int) -> BanGhiTienTrinh | None:
        """Lấy chi tiết tiến trình một màn cụ thể của người chơi."""
        with self._ket_noi() as conn:
            row = conn.execute(
                "SELECT * FROM tien_trinh_man WHERE owner_user_id = ? AND stage_id = ?",
                (owner_user_id, stage_id),
            ).fetchone()
            return self._row_to_model(row) if row else None

    def da_su_dung_replay_key(self, replay_key: str) -> bool:
        """Kiểm tra một replay_key đã tồn tại trong database hay chưa."""
        with self._ket_noi() as conn:
            row = conn.execute("SELECT 1 FROM tien_trinh_man WHERE replay_key = ?", (replay_key,)).fetchone()
            return row is not None

