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
    is_verified INTEGER NOT NULL DEFAULT 0,
    verified_by TEXT DEFAULT '',
    verified_wallet TEXT DEFAULT '',
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS stage_rewards (
    evidence_id TEXT PRIMARY KEY,
    player_id TEXT NOT NULL,
    stage_id INTEGER NOT NULL,
    exp_awarded INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY(player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_inventory_player ON inventory(player_id);
CREATE INDEX IF NOT EXISTS idx_quests_player_status ON quests(player_id, status);
CREATE INDEX IF NOT EXISTS idx_match_player ON match_results(player_id);
CREATE INDEX IF NOT EXISTS idx_stage_rewards_player ON stage_rewards(player_id);
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
    """Context manager tự động commit, rollback và quản lý transaction an toàn.

    Sử dụng BEGIN IMMEDIATE để bảo đảm tuần tự hóa các thao tác ghi đồng thời,
    ngăn ngừa lost updates, race conditions và lock escalation deadlocks.
    """
    conn = ket_noi(duong_dan)
    try:
        if not conn.in_transaction:
            conn.execute("BEGIN IMMEDIATE")
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def khoi_tao_csdl(duong_dan: Path | str | None = None) -> None:
    """Khởi tạo toàn bộ các bảng trong CSDL nếu chưa có, hỗ trợ migration an toàn."""
    with lay_csdl(duong_dan) as conn:
        conn.executescript(SCHEMA_SQL)
        # Migration an toàn cho bảng match_results nếu cơ sở dữ liệu cũ chưa có các cột mới
        cur = conn.cursor()
        cur.execute("PRAGMA table_info(match_results)")
        cols = {row[1] for row in cur.fetchall()}
        if "is_verified" not in cols:
            cur.execute("ALTER TABLE match_results ADD COLUMN is_verified INTEGER NOT NULL DEFAULT 0")
        if "verified_by" not in cols:
            cur.execute("ALTER TABLE match_results ADD COLUMN verified_by TEXT DEFAULT ''")
        if "verified_wallet" not in cols:
            cur.execute("ALTER TABLE match_results ADD COLUMN verified_wallet TEXT DEFAULT ''")

