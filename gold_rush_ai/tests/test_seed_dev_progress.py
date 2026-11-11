from __future__ import annotations

import json
from pathlib import Path
import sqlite3
import uuid

import pytest

from core.tien_trinh_storage import KhoTienTrinh
from scripts.seed_dev_progress import (
    cap_tien_trinh_fixture,
    kiem_tra_moi_truong_an_toan,
    tim_nguoi_dung_trong_auth_db,
    xoa_fixture_tien_trinh,
)


def test_kiem_tra_moi_truong_an_toan_production(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    with pytest.raises(SystemExit) as exc:
        kiem_tra_moi_truong_an_toan()
    assert "LOCAL DEV/TEST" in str(exc.value)


def test_kiem_tra_moi_truong_an_toan_chain_id(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("CHAIN_ID", "1")
    with pytest.raises(SystemExit) as exc:
        kiem_tra_moi_truong_an_toan()
    assert "Chain ID 31337" in str(exc.value)


def test_tim_nguoi_dung_trong_auth_db(tmp_path: Path):
    auth_db = tmp_path / "auth.db"
    conn = sqlite3.connect(str(auth_db))
    conn.execute("""
        CREATE TABLE users (
            id TEXT PRIMARY KEY,
            username TEXT NOT NULL,
            username_key TEXT NOT NULL,
            wallet_address TEXT NOT NULL
        )
    """)
    uid = uuid.uuid4()
    conn.execute(
        "INSERT INTO users VALUES (?, ?, ?, ?)",
        (uid.hex, "TestPlayer", "testplayer", "0x1234567890abcdef1234567890abcdef12345678"),
    )
    conn.commit()
    conn.close()

    # Tìm bằng username
    u = tim_nguoi_dung_trong_auth_db(auth_db, username="TestPlayer")
    assert u is not None
    assert u["username"] == "TestPlayer"
    assert u["wallet_address"] == "0x1234567890abcdef1234567890abcdef12345678"
    assert u["id"] == str(uid)

    # Tìm bằng casefold
    u2 = tim_nguoi_dung_trong_auth_db(auth_db, username="testplayer")
    assert u2 is not None
    assert u2["id"] == str(uid)

    # Tìm bằng ví
    u3 = tim_nguoi_dung_trong_auth_db(auth_db, wallet="0x1234567890ABCDEF1234567890ABCDEF12345678")
    assert u3 is not None
    assert u3["id"] == str(uid)


def test_cap_tien_trinh_va_xoa_fixture(tmp_path: Path):
    progress_db = tmp_path / "progress.sqlite3"
    kho = KhoTienTrinh(progress_db)

    user_info = {
        "id": str(uuid.uuid4()),
        "username": "Hero",
        "username_key": "hero",
        "wallet_address": "0x1111111111111111111111111111111111111111",
    }

    # 1. Trước khi cấp
    completed_before = kho.lay_cac_man_hoan_thanh(user_info["id"])
    assert len(completed_before) == 0

    # 2. Cấp fixture 6/6
    new_count = cap_tien_trinh_fixture(kho, user_info)
    assert new_count == 6

    completed_after = kho.lay_cac_man_hoan_thanh(user_info["id"])
    assert completed_after == frozenset({1, 2, 3, 4, 5, 6})

    # Bản ghi có verification_source là dev_test_fixture
    bg1 = kho.lay_ban_ghi(user_info["id"], 1)
    assert bg1 is not None
    assert bg1.verification_source == "dev_test_fixture"
    assert bg1.completion_evidence["fixture"] is True

    # 3. Chạy lại lần 2 (idempotent, không tạo thêm)
    new_count_2 = cap_tien_trinh_fixture(kho, user_info)
    assert new_count_2 == 0

    # 4. Giả sử người chơi thắng thật ở màn 2 bằng referee
    # Xóa bản ghi fixture màn 2 và thay bằng referee thật
    with kho._ket_noi() as conn:
        conn.execute("DELETE FROM tien_trinh_man WHERE owner_user_id = ? AND stage_id = 2", (user_info["id"],))
    kho.ghi_nhan_hoan_thanh(
        owner_user_id=user_info["id"],
        verified_wallet_address=user_info["wallet_address"],
        stage_id=2,
        completion_status="completed",
        verification_source="referee_validation",
        completion_evidence={"ma_van": "van-real-123"},
        replay_key="referee:van-real-123",
    )

    # 5. Dọn dẹp fixture
    deleted = xoa_fixture_tien_trinh(progress_db, user_info["id"])
    assert deleted == 5  # Chỉ xóa 5 màn fixture (1, 3, 4, 5, 6)

    # Màn 2 thật vẫn được bảo toàn nguyên vẹn
    bg2 = kho.lay_ban_ghi(user_info["id"], 2)
    assert bg2 is not None
    assert bg2.verification_source == "referee_validation"

    # Các màn fixture đã bị xóa
    bg1_after = kho.lay_ban_ghi(user_info["id"], 1)
    assert bg1_after is None

