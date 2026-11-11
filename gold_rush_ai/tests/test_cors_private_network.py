from __future__ import annotations

from pathlib import Path
import secrets
import sqlite3

import pytest
from fastapi import FastAPI
from starlette.testclient import TestClient

from api.main import _LifespanCORSMiddleware, _cho_phep_private_network, app
from api.nhan_vat_ai import router as router_nhan_vat_ai
from auth.config import load_auth_config
from auth.database import create_auth_engine, create_session_factory
from auth.service import AuthService
from api.auth_adapter import tich_hop_auth_vao_app


@pytest.fixture
def test_app_factory(tmp_path: Path):
    """Fixture tạo FastAPI app với _LifespanCORSMiddleware độc lập, không làm ô nhiễm app singleton."""
    def _create(
        *,
        cookie_secure: bool = False,
        siwe_domain: str = "localhost:5000",
        siwe_uri: str = "http://localhost:5000",
        cors_origins: str = "http://localhost:5000,http://localhost:5173,http://localhost:8501",
    ) -> FastAPI:
        auth_db_path = tmp_path / f"auth_{secrets.token_hex(4)}.db"
        conn = sqlite3.connect(str(auth_db_path))
        conn.execute("""
            CREATE TABLE users (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL,
                username_key TEXT NOT NULL,
                wallet_address TEXT NOT NULL,
                avatar TEXT DEFAULT 'george',
                created_at TEXT
            )
        """)
        conn.execute("""
            CREATE TABLE auth_sessions (
                id TEXT PRIMARY KEY,
                token_hash TEXT UNIQUE NOT NULL,
                wallet_address TEXT NOT NULL,
                chain_id TEXT NOT NULL,
                user_id TEXT,
                purpose TEXT NOT NULL,
                browser_binding_hash TEXT NOT NULL,
                issued_at TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                revoked_at TEXT
            )
        """)
        conn.commit()
        conn.close()

        secret = secrets.token_hex(32)
        auth_cfg = load_auth_config({
            "AUTH_CSRF_SECRET": secret,
            "AUTH_DATABASE_URL": f"sqlite:///{auth_db_path}",
            "AUTH_SIWE_DOMAIN": siwe_domain,
            "AUTH_SIWE_URI": siwe_uri,
            "AUTH_COOKIE_SECURE": "true" if cookie_secure else "false",
            "CORS_ORIGINS": cors_origins,
        })
        engine = create_auth_engine(auth_cfg)
        factory = create_session_factory(engine)
        svc = AuthService(auth_cfg, factory)

        test_app = FastAPI()
        test_app.add_middleware(_LifespanCORSMiddleware)
        test_app.include_router(router_nhan_vat_ai)
        tich_hop_auth_vao_app(test_app, svc, auth_cfg)
        return test_app

    return _create


def test_cors_private_network_preflight_local_dev(test_app_factory):
    """Xác nhận OPTIONS preflight cho phép Private Network trong môi trường local development."""
    test_app = test_app_factory()
    with TestClient(test_app) as client:
        headers = {
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,idempotency-key,x-csrf-token,x-gold-rush-auth",
            "Access-Control-Request-Private-Network": "true",
        }
        res = client.options("/api/ai/nhan-vat/tao", headers=headers)
        assert res.status_code == 200
        assert res.headers.get("access-control-allow-private-network") == "true"
        assert res.headers.get("access-control-allow-origin") == "http://localhost:5173"
        assert res.headers.get("access-control-allow-credentials") == "true"
        assert "access-control-allow-headers" in res.headers


def test_cors_private_network_production_not_enabled(test_app_factory, monkeypatch):
    """Xác nhận trong môi trường production, Private Network Access TUYỆT ĐỐI không được bật."""
    monkeypatch.setenv("ENVIRONMENT", "production")
    test_app = test_app_factory()
    with TestClient(test_app) as client:
        headers = {
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,idempotency-key,x-csrf-token",
            "Access-Control-Request-Private-Network": "true",
        }
        res = client.options("/api/ai/nhan-vat/tao", headers=headers)
        assert res.status_code == 400
        assert "Disallowed CORS private-network" in res.text
        assert "access-control-allow-private-network" not in res.headers


def test_cors_private_network_cookie_secure_https_not_enabled(test_app_factory):
    """Khi cấu hình HTTPS production (cookie_secure=True), Private Network không tự kích hoạt."""
    test_app = test_app_factory(
        cookie_secure=True,
        siwe_domain="game.example",
        siwe_uri="https://game.example",
        cors_origins="https://game.example",
    )
    with TestClient(test_app) as client:
        headers = {
            "Origin": "https://game.example",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,idempotency-key,x-csrf-token",
            "Access-Control-Request-Private-Network": "true",
        }
        res = client.options("/api/ai/nhan-vat/tao", headers=headers)
        assert res.status_code == 400
        assert "Disallowed CORS private-network" in res.text
        assert "access-control-allow-private-network" not in res.headers


def test_cors_private_network_explicit_env_control(test_app_factory, monkeypatch):
    """Kiểm tra biến môi trường CORS_ALLOW_PRIVATE_NETWORK."""
    test_app = test_app_factory()
    headers = {
        "Origin": "http://localhost:5173",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Private-Network": "true",
    }
    # 1. Tắt tường minh
    monkeypatch.setenv("CORS_ALLOW_PRIVATE_NETWORK", "false")
    with TestClient(test_app) as client:
        res = client.options("/api/ai/nhan-vat/tao", headers=headers)
        assert res.status_code == 400
        assert "Disallowed CORS private-network" in res.text

    # 2. Bật tường minh trong dev
    monkeypatch.setenv("CORS_ALLOW_PRIVATE_NETWORK", "true")
    with TestClient(test_app) as client:
        res = client.options("/api/ai/nhan-vat/tao", headers=headers)
        assert res.status_code == 200
        assert res.headers.get("access-control-allow-private-network") == "true"


def test_cors_disallowed_origin_fails(test_app_factory):
    """Origin không thuộc allowlist vẫn bị từ chối 400 bình thường."""
    test_app = test_app_factory()
    with TestClient(test_app) as client:
        headers = {
            "Origin": "https://evil.attacker.com",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Private-Network": "true",
        }
        res = client.options("/api/ai/nhan-vat/tao", headers=headers)
        assert res.status_code == 400
        assert "origin" in res.text


def test_cors_preflight_on_main_app_singleton():
    """Kiểm tra preflight trực tiếp trên main app singleton với CORS_ORIGINS mặc định."""
    with TestClient(app) as client:
        headers = {
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
            "Access-Control-Request-Private-Network": "true",
        }
        res = client.options("/api/nhat-ky", headers=headers)
        assert res.status_code == 200
        assert res.headers.get("access-control-allow-private-network") == "true"
        assert res.headers.get("access-control-allow-origin") == "http://localhost:5173"
