"""Quản lý Cơ sở dữ liệu SQLite cho Gold Rush (Tiến trình, Kho đồ, Nhiệm vụ, Lịch sử ván).

Dùng SQLite từ thư viện chuẩn Python (sqlite3), không cần cài thêm dependency.
Tệp CSDL mặc định: `gold_rush_ai/data/gold_rush.db`.
"""
from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Generator

from config import CSDL_PATH

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS players (
    player_id TEXT PRIMARY KEY,
    wallet_address TEXT UNIQUE,
    ten_hien_thi TEXT DEFAULT '',
    created_at TEXT NOT NULL,
    last_login TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS player_progress (
    player_id TEXT PRIMARY KEY,
    level INTEGER NOT NULL DEFAULT 1,
    exp INTEGER NOT NULL DEFAULT 0,
    unlocked_stage_ids TEXT NOT NULL DEFAULT '[1]',
    completed_stage_ids TEXT NOT NULL DEFAULT '[]',
    equipped_weapon_id TEXT NOT NULL DEFAULT 'kiem_go',
    equipped_character_id TEXT NOT NULL DEFAULT 'george',
    unlocked_characters TEXT NOT NULL DEFAULT '["george"]',
    updated_at TEXT NOT NULL,
    FOREIGN KEY(player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS inventory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    item_type TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    metadata TEXT NOT NULL DEFAULT '{}',
    acquired_at TEXT NOT NULL,
    UNIQUE(player_id, item_id),
    FOREIGN KEY(player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS quests (
    quest_id TEXT PRIMARY KEY,
    player_id TEXT NOT NULL,
    quest_type TEXT NOT NULL DEFAULT 'story',
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_count INTEGER NOT NULL DEFAULT 1,
    current_count INTEGER NOT NULL DEFAULT 0,
    reward_exp INTEGER NOT NULL DEFAULT 0,
    reward_gold INTEGER NOT NULL DEFAULT 0,
    reward_items TEXT NOT NULL DEFAULT '[]',
    status TEXT NOT NULL DEFAULT 'dang_lam',
    created_at TEXT NOT NULL,
    expires_at TEXT,
    FOREIGN KEY(player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS match_results (
    ma_van TEXT PRIMARY KEY,
    player_id TEXT NOT NULL,
    man INTEGER NOT NULL,
    seed INTEGER,
    ket_qua TEXT NOT NULL,
    so_xu INTEGER NOT NULL DEFAULT 0,
    giay REAL NOT NULL DEFAULT 0.0,
    hop_le INTEGER NOT NULL DEFAULT 1,
    ly_do_tu_choi TEXT DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_inventory_player ON inventory(player_id);
CREATE INDEX IF NOT EXISTS idx_quests_player_status ON quests(player_id, status);
CREATE INDEX IF NOT EXISTS idx_match_player ON match_results(player_id);
"""


def bay_gio_iso() -> str:
    """Thời gian hiện tại UTC theo định dạng ISO 8601."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def ket_noi(duong_dan: Path | str | None = None) -> sqlite3.Connection:
    """Mở kết nối tới CSDL SQLite, trả về Row dict-like."""
    p = Path(duong_dan or CSDL_PATH)
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(p), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn


@contextmanager
def lay_csdl(duong_dan: Path | str | None = None) -> Generator[sqlite3.Connection, None, None]:
    """Context manager tự động commit và đóng kết nối an toàn."""
    conn = ket_noi(duong_dan)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def khoi_tao_csdl(duong_dan: Path | str | None = None) -> None:
    """Khởi tạo toàn bộ các bảng trong CSDL nếu chưa có."""
    with lay_csdl(duong_dan) as conn:
        conn.executescript(SCHEMA_SQL)

