"""Real Auth guards with TestClient and migrated tmp_path SQLite, no external I/O.

Run from gold_rush_ai: python -m pytest tests/test_auth_dependencies.py -q
The test app is not auth/router.py or api/main.py. Its explicit CORS setup
proves middleware/guard cooperation only. Actual HTTP resource ownership and
production cookie attributes/rate limiting remain future integration work.
Database/config failures currently map to 503 AUTH_UNAVAILABLE; unhandled
endpoint errors map to 500. Neither is an authentication success.
"""
from __future__ import annotations

import importlib.util
import io
import os
import secrets
import socket
import sqlite3
import sys
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from threading import Barrier, Lock, get_ident
from types import MappingProxyType
from unittest.mock import Mock, patch

import pytest
import sqlalchemy
from alembic import command
from alembic.config import Config
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.testclient import TestClient
from sqlalchemy import MetaData, event
from sqlalchemy.engine import Engine, URL
from sqlalchemy.exc import InvalidRequestError, OperationalError
from sqlalchemy.orm import Session

from auth import dependencies
from auth.config import AuthConfig
from auth.database import create_auth_engine, create_session_factory
from auth.service import AuthService, SessionIssue, new_browser_binding


_BACKEND = Path(__file__).resolve().parents[1]
_ORIGIN = "http://localhost:5000"


@dataclass(repr=False)
class _Actor:
    issue: SessionIssue
    binding: str
    wallet: object

    @property
    def token(self) -> str:
        return self.issue.cookie_token.get_secret_value()

    @property
    def csrf(self) -> str:
        return self.issue.response.csrf_token


@dataclass(repr=False)
class _App:
    config: AuthConfig
    engine: Engine
    factory: object
    clock: list[datetime]
    service: AuthService
    guards: dependencies.AuthDependencies
    app: FastAPI
    sessions: list[Session]
    hits: list[str] = field(default_factory=list)

    def actor(self, purpose="authenticated", username="Explorer") -> _Actor:
        wallet = Account.create()
        binding = new_browser_binding().get_secret_value()
        challenge = self.service.create_challenge(
            wallet_address=wallet.address, chain_id=31337, browser_binding=binding,
        )
        signature = "0x" + wallet.sign_message(encode_defunct(text=challenge.message)).signature.hex()
        issue = self.service.verify(
            challenge_id=challenge.challenge_id, message=challenge.message,
            signature=signature, browser_binding=binding,
        )
        if purpose == "authenticated":
            issue = self.service.register(registration_token=issue.cookie_token.get_secret_value(), username=username)
        else:
            assert purpose == "registration"
        return _Actor(issue, binding, wallet)


def _headers(actor: _Actor | None = None, *, csrf=False, origin: str | None = _ORIGIN) -> dict[str, str]:
    result = {"Origin": origin} if origin is not None else {}
    if actor is not None:
        result["Cookie"] = "gr_session=" + actor.token
        if csrf:
            result["X-CSRF-Token"] = actor.csrf
    return result


def _error(response, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["detail"]["code"] == code
    assert isinstance(response.json()["detail"]["message"], str)
    assert response.headers["Cache-Control"] == "no-store"


def _assert_closed(h: _App, sessions: list[Session]) -> None:
    assert sessions and len({id(db) for db in sessions}) == len(sessions)
    assert h.engine.pool.checkedout() == 0
    for db in sessions:
        assert not db.in_transaction()
        with pytest.raises(InvalidRequestError):
            db.execute(sqlalchemy.text("SELECT 1"))


@pytest.fixture(autouse=True)
def isolated_io(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    blocked = Mock(side_effect=AssertionError("Dependency tests must not use network or create_all."))
    for name in ("create_connection", "getaddrinfo"):
        monkeypatch.setattr(socket, name, blocked)
    for name in ("connect", "connect_ex"):
        monkeypatch.setattr(socket.socket, name, blocked)
    monkeypatch.setattr(MetaData, "create_all", blocked)
    original = sqlite3.dbapi2.connect
    connections = []
    lock = Lock()

    def connect(database, *args, **kwargs):
        path = Path(database)
        assert path.is_absolute() and path.resolve().is_relative_to(tmp_path.resolve()), (
            "Database outside this test's tmp_path is forbidden."
        )
        value = original(database, *args, **kwargs)
        with lock:
            connections.append(value)
        return value

    monkeypatch.setattr(sqlite3, "connect", connect)
    monkeypatch.setattr(sqlite3.dbapi2, "connect", connect)
    try:
        yield
        blocked.assert_not_called()
    finally:
        for connection in connections:
            connection.close()


@pytest.fixture
def h(tmp_path: Path) -> Iterator[_App]:
    url = URL.create("sqlite", database=str((tmp_path / "dependencies.sqlite3").resolve()))
    config = AuthConfig(database_url=url.render_as_string(), csrf_secret=secrets.token_bytes(32))
    environment = {"AUTH_DATABASE_URL": config.database_url, "AUTH_CSRF_SECRET": config.csrf_secret.hex()}
    with patch.object(os, "environ", environment), patch("logging.config.fileConfig"):
        command.upgrade(Config(str(_BACKEND / "alembic.ini"), stdout=io.StringIO()), "head")
    engine = create_auth_engine(config)
    maker = create_session_factory(engine)
    sessions = []
    lock = Lock()

    def factory():
        db = maker()
        with lock:
            sessions.append(db)
        return db

    clock = [datetime(2026, 11, 8, 3, 0, 0, 123456, tzinfo=UTC)]
    service = AuthService(config, factory, clock=lambda: clock[0])
    guards = dependencies.make_auth_dependencies(config, factory, clock=lambda: clock[0])
    app = FastAPI()
    harness = _App(config, engine, factory, clock, service, guards, app, sessions)

    @app.get("/me")
    def me(session=Depends(guards.authenticated_session)):
        harness.hits.append("me")
        return session

    @app.post("/profile")
    def profile(user=Depends(guards.current_user)):
        harness.hits.append("profile")
        return user

    @app.get("/grant")
    def grant(value=Depends(guards.registration_grant)):
        return value

    @app.api_route("/write", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    def write(credential=Depends(guards.authenticated_mutation)):
        harness.hits.append("write")
        return credential

    @app.post("/register-guard")
    def register_guard(credential=Depends(guards.registration_mutation)):
        harness.hits.append("register")
        return credential

    @app.post("/bootstrap")
    def bootstrap(checked=Depends(guards.bootstrap)):
        harness.hits.append("bootstrap")
        return {"ok": True}

    @app.post("/verify-bootstrap")
    def verify_bootstrap(checked=Depends(guards.bootstrap), binding=Depends(guards.browser_binding)):
        harness.hits.append("verify-bootstrap")
        return {"has_binding": binding is not None}

    @app.get("/optional-binding")
    def optional_binding(binding=Depends(guards.optional_browser_binding)):
        return {"has_binding": binding is not None}

    @app.post("/logout")
    def logout(credential=Depends(guards.logout_mutation), svc=Depends(guards.get_service)):
        svc.logout(credential.cookie_token.get_secret_value() if credential.cookie_token else None)
        harness.hits.append("logout")
        return {"purpose": credential.purpose}

    @app.get("/crash")
    def crash(session=Depends(guards.authenticated_session)):
        raise RuntimeError("TEST_ENDPOINT_INTERNAL_MARKER")

    try:
        yield harness
    finally:
        app.dependency_overrides.clear()
        checked_out = engine.pool.checkedout()
        engine.dispose()
        assert checked_out == 0
        assert all(not db.in_transaction() for db in sessions)


@pytest.fixture
def client(h: _App) -> Iterator[TestClient]:
    with TestClient(h.app, raise_server_exceptions=False) as value:
        yield value


def test_import_is_inert_with_empty_environment(tmp_path, monkeypatch) -> None:
    name = "auth._dependencies_import_test"
    spec = importlib.util.spec_from_file_location(name, dependencies.__file__)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    blocked = Mock(side_effect=AssertionError("Import must not create an Engine/Session."))
    with monkeypatch.context() as local:
        local.setitem(sys.modules, name, module)
        local.setattr(sys, "dont_write_bytecode", True)
        local.setattr(os, "environ", MappingProxyType({}))
        local.setattr(Engine, "connect", blocked)
        local.setattr(Session, "__init__", blocked)
        local.chdir(tmp_path)
        spec.loader.exec_module(module)
    blocked.assert_not_called()
    assert list(tmp_path.iterdir()) == []


def test_authenticated_cookie_returns_verified_user(h, client) -> None:
    actor = h.actor()
    response = client.get("/me", headers=_headers(actor))
    assert response.status_code == 200 and response.headers["Cache-Control"] == "no-store"
    assert response.json()["user"]["id"] == str(actor.issue.response.user.id)
    assert response.json()["user"]["wallet_address"] == actor.wallet.address.lower()
    assert actor.token not in response.text and "cookie_token" not in response.json()


def test_missing_cookie_is_401(client) -> None:
    _error(client.get("/me", headers=_headers()), 401, "SESSION_REQUIRED")


@pytest.mark.parametrize("cookie", ["bad", "", "f" * 64, "A" * 64, '"' + "a" * 64 + '"'])
def test_invalid_session_cookie_is_401(client, cookie) -> None:
    _error(client.get("/me", headers=_headers() | {"Cookie": "gr_session=" + cookie}), 401, "SESSION_INVALID")


@pytest.mark.parametrize("source", ["query", "bearer", "json"])
def test_token_not_accepted_outside_cookie(h, client, source) -> None:
    actor = h.actor()
    if source == "query":
        response = client.get("/me", params={"gr_session": actor.token}, headers=_headers())
    elif source == "bearer":
        response = client.get("/me", headers=_headers() | {"Authorization": "Bearer " + actor.token})
    else:
        response = client.post("/profile", json={"gr_session": actor.token}, headers=_headers())
    _error(response, 401, "SESSION_REQUIRED")


@pytest.mark.parametrize("state", ["expired", "logout"])
def test_expired_or_revoked_authenticated_cookie_is_rejected(h, client, state) -> None:
    actor = h.actor()
    if state == "expired":
        h.clock[0] = actor.issue.response.expires_at
    else:
        h.service.logout(actor.token)
    _error(client.get("/me", headers=_headers(actor)), 401,
           "SESSION_EXPIRED" if state == "expired" else "SESSION_REVOKED")


def test_registration_cannot_read_authenticated_profile(h, client) -> None:
    actor = h.actor("registration")
    _error(client.get("/me", headers=_headers(actor)), 401, "SESSION_INVALID")


def test_body_and_query_cannot_select_another_player(h, client) -> None:
    left, right = h.actor(username="Left Hero"), h.actor(username="Right Hero")
    response = client.post("/profile", headers=_headers(left),
                           params={"user_id": str(right.issue.response.user.id), "wallet_address": right.wallet.address},
                           json={"user_id": str(right.issue.response.user.id), "wallet_address": right.wallet.address})
    assert response.status_code == 200
    assert response.json()["id"] == str(left.issue.response.user.id)
    assert response.json()["wallet_address"] == left.wallet.address.lower()
    assert str(right.issue.response.user.id) not in response.text


@pytest.mark.parametrize("duplicate_headers", [False, True])
def test_ambiguous_duplicate_session_cookies_rejected(h, client, duplicate_headers) -> None:
    actor = h.actor()
    header = "gr_session=" + actor.token
    headers = [("Origin", _ORIGIN), ("Cookie", header), ("Cookie", header)] if duplicate_headers else (
        _headers() | {"Cookie": header + "; " + header}
    )
    _error(client.get("/me", headers=headers), 401, "SESSION_INVALID")


def test_valid_grant_is_registration_only_and_wallet_cannot_be_changed(h, client) -> None:
    actor = h.actor("registration")
    assert client.get("/grant", headers=_headers(actor)).status_code == 200
    response = client.post("/register-guard", headers=_headers(actor, csrf=True),
                           json={"wallet_address": "0x" + "2" * 40, "is_admin": True},
                           params={"wallet_address": "0x" + "3" * 40})
    assert response.status_code == 200
    assert response.json()["grant"]["wallet_address"] == actor.wallet.address.lower()
    assert "cookie_token" not in response.json() and actor.token not in response.text
    _error(client.post("/write", json={}, headers=_headers(actor, csrf=True)), 401, "SESSION_INVALID")


def test_missing_registration_grant_is_401(client) -> None:
    _error(client.get("/grant", headers=_headers()), 401, "GRANT_INVALID")


@pytest.mark.parametrize("state", ["expired", "revoked", "consumed"])
def test_expired_or_used_grant_is_rejected(h, client, state) -> None:
    actor = h.actor("registration")
    if state == "expired":
        h.clock[0] = actor.issue.response.expires_at
    elif state == "revoked":
        h.service.logout(actor.token)
    else:
        h.service.register(registration_token=actor.token, username="Created Hero")
    _error(client.post("/register-guard", json={}, headers=_headers(actor, csrf=True)), 401,
           "GRANT_EXPIRED" if state == "expired" else "GRANT_INVALID")


def test_authenticated_cookie_cannot_be_used_as_grant(h, client) -> None:
    actor = h.actor()
    _error(client.get("/grant", headers=_headers(actor)), 401, "GRANT_INVALID")


@pytest.mark.parametrize("purpose,path", [("authenticated", "/write"), ("registration", "/register-guard")])
def test_valid_csrf_mutation_is_accepted(h, client, purpose, path) -> None:
    actor = h.actor(purpose)
    response = client.post(path, json={}, headers=_headers(actor, csrf=True))
    assert response.status_code == 200 and response.headers["Cache-Control"] == "no-store"
    assert actor.token not in response.text


@pytest.mark.parametrize("purpose,path", [("authenticated", "/write"), ("registration", "/register-guard")])
@pytest.mark.parametrize("csrf_case", ["missing", "wrong", "tampered", "other_cookie", "duplicate"])
def test_csrf_must_match_exact_current_cookie(h, client, purpose, path, csrf_case) -> None:
    actor = h.actor(purpose)
    headers = _headers(actor)
    if csrf_case == "wrong":
        headers["X-CSRF-Token"] = "f" * 64
    elif csrf_case == "tampered":
        headers["X-CSRF-Token"] = ("0" if actor.csrf[0] != "0" else "1") + actor.csrf[1:]
    elif csrf_case == "other_cookie":
        other = h.actor("registration")
        headers["X-CSRF-Token"] = other.csrf
    elif csrf_case == "duplicate":
        headers = list(headers.items()) + [("X-CSRF-Token", actor.csrf), ("X-CSRF-Token", actor.csrf)]
    before = list(h.hits)
    _error(client.post(path, json={}, headers=headers), 403, "CSRF_INVALID")
    assert h.hits == before


@pytest.mark.parametrize("state", ["expired", "revoked"])
def test_matching_hmac_does_not_bypass_session_expiry_or_revoke(h, client, state) -> None:
    actor = h.actor()
    if state == "expired":
        h.clock[0] = actor.issue.response.expires_at
    else:
        h.service.logout(actor.token)
    assert h.service.verify_csrf_token(actor.token, actor.csrf)  # Pure HMAC only.
    _error(client.post("/write", json={}, headers=_headers(actor, csrf=True)), 401,
           "SESSION_EXPIRED" if state == "expired" else "SESSION_REVOKED")


@pytest.mark.parametrize("method", ["POST", "PUT", "PATCH", "DELETE"])
def test_every_supported_mutating_method_requires_csrf(h, client, method) -> None:
    actor = h.actor()
    _error(client.request(method, "/write", json={}, headers=_headers(actor)), 403, "CSRF_INVALID")
    assert client.request(method, "/write", json={}, headers=_headers(actor, csrf=True)).status_code == 200


@pytest.mark.parametrize("content_type", [None, "application/x-www-form-urlencoded", "text/plain", "multipart/form-data"])
def test_mutation_requires_json_content_type(h, client, content_type) -> None:
    actor = h.actor()
    headers = _headers(actor, csrf=True)
    if content_type:
        headers["Content-Type"] = content_type
    _error(client.post("/write", content="{}", headers=headers), 415, "JSON_REQUIRED")


def test_safe_get_cannot_execute_mutation_guard(h, client) -> None:
    actor = h.actor()
    _error(client.get("/write", headers=_headers(actor, csrf=True)), 405, "METHOD_NOT_ALLOWED")


@pytest.mark.parametrize("origin", [None, "null", "*", "https://evil.invalid", "http://localhost:5000/", "http://localhost:5000.evil.invalid", "http://127.0.0.1:5000"])
def test_origin_must_be_exact_allowlisted_browser_origin(h, client, origin) -> None:
    actor = h.actor()
    _error(client.get("/me", headers=_headers(actor, origin=origin)), 403, "ORIGIN_FORBIDDEN")
    assert "me" not in h.hits


@pytest.mark.parametrize("origin", [_ORIGIN, "http://localhost:8501", "http://localhost:5173"])
def test_each_configured_origin_is_accepted(h, client, origin) -> None:
    actor = h.actor()
    assert origin in h.config.cors_origins
    assert client.get("/me", headers=_headers(actor, origin=origin)).status_code == 200


def test_multiple_origin_headers_rejected(h, client) -> None:
    actor = h.actor()
    _error(client.get("/me", headers=[("Origin", _ORIGIN), ("Origin", _ORIGIN),
                                     ("Cookie", "gr_session=" + actor.token)]), 403, "ORIGIN_FORBIDDEN")


@pytest.mark.parametrize("origin", [None, "https://evil.invalid"])
def test_host_forwarded_host_and_referer_cannot_replace_origin(h, client, origin) -> None:
    actor = h.actor()
    headers = _headers(actor, origin=origin) | {"Host": "localhost:5000", "X-Forwarded-Host": "localhost:5000",
                                               "Referer": _ORIGIN + "/login"}
    _error(client.get("/me", headers=headers), 403, "ORIGIN_FORBIDDEN")


def test_spoofed_host_does_not_select_user_or_override_valid_origin(h, client) -> None:
    actor = h.actor()
    response = client.get("/me", headers=_headers(actor) | {"Host": "evil.invalid", "X-Forwarded-Host": "evil.invalid"})
    assert response.status_code == 200
    assert response.json()["user"]["id"] == str(actor.issue.response.user.id)


def test_bootstrap_does_not_require_login_or_csrf(client) -> None:
    response = client.post("/bootstrap", json={}, headers=_headers() | {"X-Gold-Rush-Auth": "1"})
    assert response.status_code == 200 and response.json() == {"ok": True}


@pytest.mark.parametrize("value", [None, "0", "true"])
def test_bootstrap_requires_custom_header(client, value) -> None:
    headers = _headers()
    if value is not None:
        headers["X-Gold-Rush-Auth"] = value
    _error(client.post("/bootstrap", json={}, headers=headers), 403, "BOOTSTRAP_REQUIRED")


def test_bootstrap_rejects_form_without_requiring_session(client) -> None:
    _error(client.post("/bootstrap", content="x=y", headers=_headers() | {
        "X-Gold-Rush-Auth": "1", "Content-Type": "application/x-www-form-urlencoded",
    }), 415, "JSON_REQUIRED")


def test_verify_bootstrap_requires_browser_binding_not_authenticated_cookie(h, client) -> None:
    _error(client.post("/verify-bootstrap", json={}, headers=_headers() | {"X-Gold-Rush-Auth": "1"}),
           403, "BROWSER_BINDING_INVALID")
    binding = new_browser_binding().get_secret_value()
    response = client.post("/verify-bootstrap", json={}, headers=_headers() | {
        "X-Gold-Rush-Auth": "1", "Cookie": "gr_auth_flow=" + binding,
    })
    assert response.status_code == 200 and response.json() == {"has_binding": True}
    assert binding not in response.text


@pytest.mark.parametrize("cookie", ["gr_auth_flow=bad", "gr_auth_flow", "gr_auth_flow=" + "a" * 64 + "; gr_auth_flow=" + "a" * 64])
def test_invalid_or_ambiguous_browser_binding_rejected(client, cookie) -> None:
    _error(client.post("/verify-bootstrap", json={}, headers=_headers() | {
        "X-Gold-Rush-Auth": "1", "Cookie": cookie,
    }), 403, "BROWSER_BINDING_INVALID")


def test_optional_binding_supports_reusing_existing_flow_cookie(client) -> None:
    response = client.get("/optional-binding", headers=_headers())
    assert response.status_code == 200 and response.json() == {"has_binding": False}
    binding = new_browser_binding().get_secret_value()
    response = client.get("/optional-binding", headers=_headers() | {"Cookie": "gr_auth_flow=" + binding})
    assert response.status_code == 200 and response.json() == {"has_binding": True}


def test_guard_preflight_short_circuits_before_session_and_endpoint(h, client) -> None:
    before = len(h.sessions)
    response = client.options("/write", headers=_headers() | {"Access-Control-Request-Method": "POST"})
    assert response.status_code == 204 and response.content == b""
    assert len(h.sessions) == before and "write" not in h.hits


def test_explicit_test_app_cors_preflight_has_no_login_requirement(h) -> None:
    h.app.add_middleware(
        CORSMiddleware, allow_origins=list(h.config.cors_origins), allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type", "X-CSRF-Token", "X-Gold-Rush-Auth"],
    )
    before = len(h.sessions)
    with TestClient(h.app) as client:
        response = client.options("/write", headers=_headers() | {
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type,x-csrf-token",
        })
        assert response.status_code == 200
        assert response.headers["access-control-allow-origin"] == _ORIGIN != "*"
        assert response.headers["access-control-allow-credentials"] == "true"
        assert "x-csrf-token" in response.headers["access-control-allow-headers"].lower()
        denied = client.options("/write", headers={"Origin": "https://evil.invalid", "Access-Control-Request-Method": "POST"})
        assert denied.status_code == 400
        assert "access-control-allow-origin" not in denied.headers
    assert len(h.sessions) == before and "write" not in h.hits


@pytest.mark.parametrize("purpose", ["authenticated", "registration"])
def test_logout_requires_csrf_for_active_cookie_and_revokes_in_database(h, client, purpose) -> None:
    actor = h.actor(purpose)
    _error(client.post("/logout", json={}, headers=_headers(actor)), 403, "CSRF_INVALID")
    response = client.post("/logout", json={}, headers=_headers(actor, csrf=True))
    assert response.status_code == 200 and response.json()["purpose"] == purpose
    response = client.post("/logout", json={}, headers=_headers(actor))
    assert response.status_code == 200  # Already revoked: idempotent, no authority.
    path = "/me" if purpose == "authenticated" else "/grant"
    _error(client.get(path, headers=_headers(actor)), 401,
           "SESSION_REVOKED" if purpose == "authenticated" else "GRANT_INVALID")


def test_logout_without_cookie_is_idempotent_but_still_checks_origin(client) -> None:
    assert client.post("/logout", json={}, headers=_headers()).status_code == 200
    _error(client.post("/logout", json={}, headers={}), 403, "ORIGIN_FORBIDDEN")


@pytest.mark.parametrize("purpose", ["authenticated", "registration"])
def test_expired_cookie_logout_is_idempotent(h, client, purpose) -> None:
    actor = h.actor(purpose)
    h.clock[0] = actor.issue.response.expires_at
    assert client.post("/logout", json={}, headers=_headers(actor)).status_code == 200


def test_each_request_gets_a_new_closed_session_and_reuses_engine(h, client, monkeypatch) -> None:
    actor = h.actor()
    blocked = Mock(side_effect=AssertionError("HTTP guards must reuse the configured Engine."))
    monkeypatch.setattr(sqlalchemy, "create_engine", blocked)
    begin = len(h.sessions)
    for _ in range(2):
        assert client.get("/me", headers=_headers(actor)).status_code == 200
    used = h.sessions[begin:]
    assert len(used) == 2 and all(db.get_bind() is h.engine for db in used)
    _assert_closed(h, used)
    blocked.assert_not_called()


def test_endpoint_500_does_not_leave_database_session_open_or_leak_details(h, client) -> None:
    actor = h.actor()
    begin = len(h.sessions)
    response = client.get("/crash", headers=_headers(actor))
    assert response.status_code == 500
    for secret in (actor.token, actor.csrf, h.config.csrf_secret.hex(), h.config.database_url, "TEST_ENDPOINT_INTERNAL_MARKER"):
        assert secret not in response.text
    _assert_closed(h, h.sessions[begin:])


@pytest.mark.parametrize("path,method", [("/me", "GET"), ("/grant", "GET"), ("/logout", "POST")])
def test_real_database_failure_returns_sanitized_503_not_auth_success(h, client, path, method) -> None:
    actor = h.actor("registration" if path == "/grant" else "authenticated")
    marker = "TEST_DATABASE_CREDENTIAL_MARKER"

    def broken_execute(connection, cursor, statement, parameters, context, many):
        raise OperationalError("TEST_SQL", {"token": actor.token}, RuntimeError(marker + h.config.database_url))

    begin = len(h.sessions)
    event.listen(h.engine, "before_cursor_execute", broken_execute)
    try:
        response = client.request(method, path, headers=_headers(actor, csrf=True), **({"json": {}} if method == "POST" else {}))
    finally:
        event.remove(h.engine, "before_cursor_execute", broken_execute)
    # Actual policy in dependencies.py is 503, not the requested generic 500.
    _error(response, 503, "AUTH_UNAVAILABLE")
    for value in (marker, actor.token, actor.csrf, h.config.database_url, "Traceback"):
        assert value not in response.text
    _assert_closed(h, h.sessions[begin:])


def test_dependency_override_uses_real_service_with_injected_clock(h, client) -> None:
    actor = h.actor()
    later = actor.issue.response.expires_at
    replacement = AuthService(h.config, h.factory, clock=lambda: later)
    h.app.dependency_overrides[h.guards.get_service] = lambda: replacement
    try:
        _error(client.get("/me", headers=_headers(actor)), 401, "SESSION_EXPIRED")
    finally:
        h.app.dependency_overrides.clear()
    assert client.get("/me", headers=_headers(actor)).status_code == 200


def test_credentials_and_errors_do_not_leak_raw_cookie_csrf_or_secret(h, client, caplog) -> None:
    actor = h.actor()
    response = client.post("/write", json={}, headers=_headers(actor))
    _error(response, 403, "CSRF_INVALID")
    valid = client.post("/write", json={}, headers=_headers(actor, csrf=True))
    assert valid.status_code == 200
    wrapper = dependencies.AuthenticatedCredential(
        session=h.service.get_authenticated_session(actor.token), cookie_token=actor.issue.cookie_token,
    )
    assert actor.token not in wrapper.model_dump_json() and "cookie_token" not in wrapper.model_dump()
    for value in (wrapper, actor.issue.cookie_token, h.guards):
        assert actor.token not in repr(value) and actor.csrf not in repr(value)
    for value in (actor.token, actor.csrf, h.config.csrf_secret.hex(), h.config.database_url):
        assert value not in response.text + caplog.text
    assert "Traceback" not in response.text


def test_concurrent_requests_use_independent_sessions_and_return_own_identity(h) -> None:
    left, right = h.actor(username="Left Hero"), h.actor(username="Right Hero")
    barrier = Barrier(2)
    lock = Lock()
    connections = []

    def synchronize(connection, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith("SELECT AUTH_SESSIONS."):
            with lock:
                connections.append((get_ident(), id(connection.connection.dbapi_connection)))
            barrier.wait(timeout=10)

    def lookup(actor):
        with TestClient(h.app) as worker:
            response = worker.get("/me", headers=_headers(actor))
            assert response.status_code == 200
            return response.json()["user"]["id"]

    begin = len(h.sessions)
    event.listen(h.engine, "before_cursor_execute", synchronize)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            identities = list(pool.map(lookup, [left, right]))
    finally:
        event.remove(h.engine, "before_cursor_execute", synchronize)
    assert identities == [str(left.issue.response.user.id), str(right.issue.response.user.id)]
    assert len(connections) == 2 and len({connection for thread, connection in connections}) == 2
    assert len({thread for thread, connection in connections}) == 2
    _assert_closed(h, h.sessions[begin:])


def test_injected_dependencies_do_not_read_or_modify_real_environment(h, client, monkeypatch) -> None:
    actor = h.actor()
    environment = {"AUTH_DATABASE_URL": "TEST_CALLER_DATABASE", "AUTH_CSRF_SECRET": "TEST_CALLER_SECRET"}
    monkeypatch.setattr(os, "environ", environment)
    assert client.get("/me", headers=_headers(actor)).status_code == 200
    assert os.environ is environment
    assert environment == {"AUTH_DATABASE_URL": "TEST_CALLER_DATABASE", "AUTH_CSRF_SECRET": "TEST_CALLER_SECRET"}
