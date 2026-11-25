"""Phiên quản trị độc lập với phiên SIWE; SQLite dùng chung giữa các worker."""
from contextlib import contextmanager
import hashlib
import hmac
import os
from pathlib import Path
import secrets
import sqlite3
import time

from fastapi import HTTPException

TTL = 8 * 60 * 60
COOKIE = "gold_rush_admin"
# PBKDF2 của mật khẩu khởi tạo được yêu cầu. Không gửi giá trị này xuống frontend.
DEFAULT_HASH = "5dcd88c7c5087b5ae49615202f7487523eb42bbb5382d9befc4b45bf04336584"


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


class AdminSessions:
    def __init__(self, path: Path, *, clock=time.time):
        self.path = path
        self.clock = clock

    @contextmanager
    def database(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            db.execute("CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, csrf TEXT NOT NULL, expires REAL NOT NULL, credentials TEXT NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS attempts (client TEXT PRIMARY KEY, count INTEGER NOT NULL, expires REAL NOT NULL)")
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM sessions WHERE expires <= ?", (self.clock(),))
            db.execute("DELETE FROM attempts WHERE expires <= ?", (self.clock(),))
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    def credentials(self):
        username = os.environ.get("GOLD_RUSH_ADMIN_USER", "admin")
        password_hash = os.environ.get("GOLD_RUSH_ADMIN_PASSWORD_HASH", DEFAULT_HASH)
        return username, password_hash, digest(username + ":" + password_hash)

    def login(self, username: str, password: str, client: str, previous: str):
        configured_user, configured_hash, fingerprint = self.credentials()
        with self.database() as db:
            attempt = db.execute("SELECT count FROM attempts WHERE client = ?", (client,)).fetchone()
            if attempt and attempt["count"] >= 5:
                raise HTTPException(429, "Đăng nhập sai quá nhiều lần. Thử lại sau 15 phút.", headers={"Retry-After": "900"})
            actual = hashlib.pbkdf2_hmac("sha256", password.encode(), b"gold-rush-admin-v1", 600000).hex()
            valid_password = hmac.compare_digest(actual, configured_hash)
            valid_user = hmac.compare_digest(username.encode(), configured_user.encode())
            if not (valid_password and valid_user):
                db.execute("INSERT INTO attempts VALUES (?, 1, ?) ON CONFLICT(client) DO UPDATE SET count = count + 1", (client, self.clock() + 900))
                # Commit trước khi trả lỗi để không mất bộ đếm.
                db.commit()
                raise HTTPException(401, "Tài khoản hoặc mật khẩu không đúng.")
            token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
            db.execute("DELETE FROM attempts WHERE client = ?", (client,))
            db.execute("DELETE FROM sessions WHERE token = ?", (digest(previous),))
            db.execute("INSERT INTO sessions VALUES (?, ?, ?, ?)", (digest(token), csrf, self.clock() + TTL, fingerprint))
            return token, csrf

    def verify(self, token: str):
        with self.database() as db:
            row = db.execute("SELECT * FROM sessions WHERE token = ?", (digest(token),)).fetchone()
            username, _, fingerprint = self.credentials()
            if not row or not hmac.compare_digest(row["credentials"], fingerprint):
                raise HTTPException(401, "Phiên quản trị hết hạn. Vui lòng đăng nhập lại.")
            return {"username": username, "csrf": row["csrf"]}

    def logout(self, token: str):
        with self.database() as db:
            db.execute("DELETE FROM sessions WHERE token = ?", (digest(token),))
