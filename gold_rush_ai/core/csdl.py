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

CREATE TABLE IF NOT EXISTS weekly_rank_runs (
    chain_id INTEGER NOT NULL,
    ma_van TEXT NOT NULL,
    wallet TEXT NOT NULL,
    ten TEXT NOT NULL,
    man INTEGER NOT NULL CHECK(man BETWEEN 1 AND 20),
    diem INTEGER NOT NULL CHECK(diem > 0),
    duration_ms INTEGER NOT NULL CHECK(duration_ms > 0),
    thich_ung INTEGER NOT NULL CHECK(thich_ung IN (0, 1)),
    verified_at TEXT NOT NULL,
    PRIMARY KEY(chain_id, ma_van)
);
CREATE INDEX IF NOT EXISTS ix_weekly_rank_period
    ON weekly_rank_runs(chain_id, thich_ung, verified_at, man, wallet);

CREATE TABLE IF NOT EXISTS achievement_progress (
    player_id TEXT NOT NULL,
    achievement_id INTEGER NOT NULL,
    stage_id INTEGER NOT NULL,
    ma_van TEXT NOT NULL,
    eligible_at TEXT NOT NULL,
    claimed_at TEXT,
    UNIQUE(player_id, achievement_id),
    UNIQUE(player_id, ma_van),
    FOREIGN KEY(player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS gift_codes (
    code_hash TEXT PRIMARY KEY,
    reward_type TEXT NOT NULL,
    token_id INTEGER NOT NULL DEFAULT 0,
    amount INTEGER NOT NULL,
    name TEXT NOT NULL,
    image_url TEXT NOT NULL DEFAULT '',
    rarity TEXT NOT NULL DEFAULT '',
    expires_at REAL,
    max_uses INTEGER NOT NULL DEFAULT 1,
    used_count INTEGER NOT NULL DEFAULT 0,
    per_wallet_limit INTEGER NOT NULL DEFAULT 1,
    active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS gift_claims (
    claim_id TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    wallet_address TEXT NOT NULL,
    reward_type TEXT NOT NULL,
    token_id INTEGER NOT NULL,
    amount INTEGER NOT NULL,
    name TEXT NOT NULL,
    image_url TEXT NOT NULL DEFAULT '',
    rarity TEXT NOT NULL DEFAULT '',
    balance_before TEXT NOT NULL DEFAULT '0',
    status TEXT NOT NULL,
    transaction_hash TEXT,
    error_message TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(code_hash, wallet_address, status)
);

CREATE INDEX IF NOT EXISTS idx_inventory_player ON inventory(player_id);
CREATE INDEX IF NOT EXISTS idx_quests_player_status ON quests(player_id, status);
CREATE INDEX IF NOT EXISTS idx_match_player ON match_results(player_id);
CREATE INDEX IF NOT EXISTS idx_stage_rewards_player ON stage_rewards(player_id);
CREATE INDEX IF NOT EXISTS idx_achievement_progress_player ON achievement_progress(player_id);
CREATE INDEX IF NOT EXISTS idx_gift_claims_code_wallet ON gift_claims(code_hash, wallet_address);
CREATE INDEX IF NOT EXISTS idx_gift_claims_status ON gift_claims(status);

CREATE TABLE IF NOT EXISTS sepolia_faucet_claims (
    claim_id TEXT PRIMARY KEY,
    wallet_address TEXT NOT NULL,
    day_utc TEXT NOT NULL,
    amount_wei TEXT NOT NULL,
    nonce INTEGER NOT NULL,
    status TEXT NOT NULL,
    transaction_hash TEXT,
    raw_transaction TEXT,
    error_code TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    confirmed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_sepolia_faucet_wallet_day
    ON sepolia_faucet_claims(wallet_address, day_utc);
CREATE INDEX IF NOT EXISTS idx_sepolia_faucet_day_status
    ON sepolia_faucet_claims(day_utc, status);
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
        cur.execute("PRAGMA table_info(sepolia_faucet_claims)")
        faucet_cols = {row[1] for row in cur.fetchall()}
        if "raw_transaction" not in faucet_cols:
            cur.execute("ALTER TABLE sepolia_faucet_claims ADD COLUMN raw_transaction TEXT")
        if "verified_wallet" not in cols:
            cur.execute("ALTER TABLE match_results ADD COLUMN verified_wallet TEXT DEFAULT ''")
