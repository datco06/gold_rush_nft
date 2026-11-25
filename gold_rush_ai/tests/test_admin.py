"""Kiểm thử trang quản trị bằng SQLite tạm, không chạm dữ liệu người chơi."""
import base64
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.admin import create_admin_router
from core.admin_session import AdminSessions, COOKIE, digest
from core.csdl import khoi_tao_csdl, lay_csdl


def _client(tmp_path: Path) -> tuple[TestClient, Path]:
    gift_db = tmp_path / "gift.sqlite3"
    khoi_tao_csdl(gift_db)
    app = FastAPI()
    app.include_router(create_admin_router(
        sessions=AdminSessions(tmp_path / "admin-sessions.sqlite3"),
        gift_db=gift_db,
    ))
    return TestClient(app, base_url="http://testserver"), gift_db


def _login(client: TestClient) -> str:
    response = client.post(
        "/api/admin/login",
        json={"username": "admin", "password": "admin123"},
        headers={"X-Admin-Request": "1", "Origin": "http://testserver"},
    )
    assert response.status_code == 200
    assert "HttpOnly" in response.headers["set-cookie"]
    assert "SameSite=strict" in response.headers["set-cookie"]
    assert client.cookies.get(COOKIE)
    return response.json()["csrf"]


def _mutation_headers(csrf: str) -> dict[str, str]:
    return {
        "X-Admin-Request": "1",
        "X-CSRF-Token": csrf,
        "Origin": "http://testserver",
    }


def test_admin_page_and_authentication(tmp_path: Path):
    client, _ = _client(tmp_path)
    page = client.get("/admin")
    assert page.status_code == 200
    assert "Gold Rush · Quản trị" in page.text
    assert "Súng Lục Mặc Định" in page.text
    assert "Giáp Hoàng Kim Cổ Đại" in page.text
    assert "Giày Phượng Hoàng Hoàng Kim" in page.text
    assert client.get("/api/admin/codes").status_code == 401

    wrong = client.post(
        "/api/admin/login",
        json={"username": "admin", "password": "sai"},
        headers={"X-Admin-Request": "1"},
    )
    assert wrong.status_code == 401
    csrf = _login(client)
    assert client.get("/api/admin/me").json()["username"] == "admin"

    assert client.post("/api/admin/logout", json={}).status_code == 403
    assert client.post(
        "/api/admin/logout", json={}, headers=_mutation_headers(csrf)
    ).status_code == 200
    assert client.get("/api/admin/me").status_code == 401


def test_create_list_and_lock_gift_qr(tmp_path: Path):
    client, gift_db = _client(tmp_path)
    csrf = _login(client)
    headers = _mutation_headers(csrf)

    response = client.post(
        "/api/admin/codes",
        json={
            "name": "Quà kiểm thử",
            "reward_type": "gold",
            "amount": 250,
            "token_id": 0,
            "max_uses": 3,
        },
        headers=headers,
    )
    assert response.status_code == 201
    result = response.json()
    assert result["code"].startswith("GR-")
    assert base64.b64decode(result["qr_png"]).startswith(b"\x89PNG\r\n\x1a\n")

    code_hash = digest(result["code"])
    with lay_csdl(gift_db) as db:
        stored = dict(db.execute(
            "SELECT * FROM gift_codes WHERE code_hash = ?", (code_hash,)
        ).fetchone())
    assert stored["name"] == "Quà kiểm thử"
    assert stored["amount"] == 250
    assert result["code"] not in str(stored)

    listed = client.get("/api/admin/codes").json()
    assert listed["summary"] == {"total": 1, "used": 0, "locked": 0}
    assert listed["codes"][0]["code_hash"] == code_hash

    locked = client.post(
        f"/api/admin/codes/{code_hash}/active",
        json={"active": False},
        headers=headers,
    )
    assert locked.status_code == 200
    assert client.get("/api/admin/codes").json()["summary"]["locked"] == 1


def test_item_token_must_match_the_27_item_catalog(tmp_path: Path):
    client, gift_db = _client(tmp_path)
    headers = _mutation_headers(_login(client))
    item = client.post(
        "/api/admin/codes",
        json={
            "name": "Súng Hắc Long",
            "reward_type": "item",
            "amount": 1,
            "token_id": 9,
            "max_uses": 1,
        },
        headers=headers,
    )
    assert item.status_code == 201
    with lay_csdl(gift_db) as db:
        stored = db.execute(
            "SELECT token_id FROM gift_codes WHERE code_hash = ?",
            (digest(item.json()["code"]),),
        ).fetchone()
    assert stored["token_id"] == 9

    invalid = client.post(
        "/api/admin/codes",
        json={
            "name": "Không có trong danh mục",
            "reward_type": "item",
            "amount": 1,
            "token_id": 28,
            "max_uses": 1,
        },
        headers=headers,
    )
    assert invalid.status_code == 422


def test_login_is_rate_limited(tmp_path: Path):
    client, _ = _client(tmp_path)
    headers = {"X-Admin-Request": "1"}
    for _ in range(5):
        response = client.post(
            "/api/admin/login",
            json={"username": "admin", "password": "sai"},
            headers=headers,
        )
        assert response.status_code == 401
    response = client.post(
        "/api/admin/login",
        json={"username": "admin", "password": "admin123"},
        headers=headers,
    )
    assert response.status_code == 429
