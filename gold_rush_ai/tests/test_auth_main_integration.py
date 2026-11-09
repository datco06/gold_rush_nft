"""Auth on the real api/main.py app, with real lifespan, SIWE and migrations.

Each test loads the actual composition root under a private module name. This
avoids reloading/mutating the app and config used by legacy unittest modules.
No replacement FastAPI app or authentication dependency override is used.
SQLite, telemetry and voucher files are restricted to tmp_path. Network access,
create_all and automatic migrations during startup are forbidden.

TestClient is an in-process ASGI transport, not a browser or real HTTP server:
these tests cannot establish MetaMask popup behavior, browser SameSite/CORS
enforcement, PostgreSQL support, or protection of legacy player endpoints.
Run from gold_rush_ai: python -m pytest tests/test_auth_main_integration.py -q
The legacy test_api/test_api_vang classes additionally require a valid Auth
environment and a separately migrated temporary SQLite DB for a full-suite run;
this module intentionally does not change their fixtures or global environment.
"""
from __future__ import annotations

import ast
import importlib.util
import io
import os
import secrets
import socket
import sqlite3
import sys
import warnings
from collections.abc import Callable, Iterator
from contextlib import ExitStack
from dataclasses import dataclass, field
from datetime import datetime
from email.utils import parsedate_to_datetime
from hashlib import sha256
from http.cookies import SimpleCookie
from pathlib import Path
from threading import Lock
from types import ModuleType
from unittest.mock import Mock, patch
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi.testclient import TestClient
from sqlalchemy import MetaData, event, func, select, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import InvalidRequestError
from sqlalchemy.orm import Session

from auth.models import AuthChallenge, AuthSession, User


_BACKEND = Path(__file__).resolve().parents[1]
_ORIGIN = "http://localhost:5000"
_BOOTSTRAP = {"Origin": _ORIGIN, "X-Gold-Rush-Auth": "1"}
_AUTH_ROUTES = {
    "/api/auth/challenge": "post", "/api/auth/verify": "post",
    "/api/auth/register": "post", "/api/me": "get", "/api/auth/logout": "post",
}
_PUBLIC_USER = {"id", "wallet_address", "username", "avatar", "created_at"}


def _load_file(name: str, path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_main() -> ModuleType:
    # config.py is real too, evaluated under this test's temporary environment.
    # Restore the shared module and sys.path even if import raises.
    config = _load_file("_main_integration_config", _BACKEND / "config.py")
    previous_path = sys.path[:]
    absent = object()
    previous_config = sys.modules.get("config", absent)
    try:
        # Restore only config, not the entire import cache: NumPy's C modules
        # loaded by main must remain cached and cannot be imported a second time.
        sys.modules["config"] = config
        return _load_file("_main_integration_" + uuid4().hex, _BACKEND / "api/main.py")
    finally:
        if previous_config is absent:
            sys.modules.pop("config", None)
        else:
            sys.modules["config"] = previous_config
        sys.path[:] = previous_path


def _legacy_routes() -> dict[str, str]:
    """Read the actual declared routes, rather than inventing legacy paths."""
    tree = ast.parse((_BACKEND / "api/main.py").read_text(encoding="utf-8"))
    result = {}
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for decorator in node.decorator_list:
                if (isinstance(decorator, ast.Call) and isinstance(decorator.func, ast.Attribute)
                        and isinstance(decorator.func.value, ast.Name)
                        and decorator.func.value.id == "app"
                        and decorator.func.attr in {"get", "post"}):
                    result[ast.literal_eval(decorator.args[0])] = decorator.func.attr
    return result


@dataclass(repr=False)
class _Main:
    module: ModuleType
    path: Path
    secret: str
    stack: ExitStack
    engines: list[Engine] = field(default_factory=list)
    disposed: list[Engine] = field(default_factory=list)
    factories: list[Callable] = field(default_factory=list)
    sessions: list[Session] = field(default_factory=list)
    original_routes: tuple = ()

    def client(self, *, secure=False) -> TestClient:
        return self.stack.enter_context(TestClient(
            self.module.app, base_url="https://localhost:8000" if secure else "http://localhost:8000",
            raise_server_exceptions=False,
        ))

    def count(self, model) -> int:
        with self.module.app.state.auth_session_factory() as db:
            return db.scalar(select(func.count()).select_from(model))

    def session(self, token: str) -> AuthSession:
        with self.module.app.state.auth_session_factory() as db:
            row = db.scalar(select(AuthSession).where(AuthSession.token_hash == _hash(token)))
            assert row is not None
            return row

    def challenge(self, challenge_id: str) -> AuthChallenge:
        with self.module.app.state.auth_session_factory() as db:
            row = db.get(AuthChallenge, UUID(challenge_id))
            assert row is not None
            return row


def _hash(value: str) -> str:
    return sha256(value.encode("ascii")).hexdigest()


def _cookie(response, name):
    found = []
    for header in response.headers.get_list("set-cookie"):
        jar = SimpleCookie()
        jar.load(header)
        if name in jar:
            found.append(jar[name])
    assert len(found) == 1
    return found[0]


def _error(response, status: int, code: str) -> None:
    assert response.status_code == status, response.text
    assert response.json()["detail"]["code"] == code
    assert response.headers["Cache-Control"] == "no-store"
    assert "set-cookie" not in response.headers


def _challenge(client, wallet, *, headers=None):
    response = client.post("/api/auth/challenge", headers=headers or _BOOTSTRAP, json={
        "wallet_address": wallet.address, "chain_id": 31337,
    })
    assert response.status_code == 201, response.text
    return response


def _signed(wallet, challenge):
    return {
        "challenge_id": challenge["challenge_id"], "message": challenge["message"],
        "signature": "0x" + wallet.sign_message(encode_defunct(text=challenge["message"])).signature.hex(),
    }


def _grant(client, wallet=None, *, headers=None):
    wallet = wallet or Account.create()
    challenge = _challenge(client, wallet, headers=headers)
    response = client.post("/api/auth/verify", headers=headers or _BOOTSTRAP,
                           json=_signed(wallet, challenge.json()))
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "registration_required"
    return wallet, response


def _register(client, grant, *, headers=None):
    return client.post("/api/auth/register", json={"username": "Nhà Thám Hiểm"}, headers={
        "Origin": _ORIGIN, "X-CSRF-Token": grant.json()["csrf_token"],
    } | (headers or {}))


def _me(client, *, token=None, origin=_ORIGIN):
    headers = {"Origin": origin}
    if token is not None:
        headers["Cookie"] = "gr_session=" + token
    return client.get("/api/me", headers=headers)


@pytest.fixture(autouse=True)
def isolated_io(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    blocked = Mock(side_effect=AssertionError("Main integration tests forbid network/create_all."))
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
            "Only this test's temporary SQLite files may be opened."
        )
        connection = original(database, *args, **kwargs)
        with lock:
            connections.append(connection)
        return connection

    monkeypatch.setattr(sqlite3, "connect", connect)
    monkeypatch.setattr(sqlite3.dbapi2, "connect", connect)
    try:
        yield
        blocked.assert_not_called()
    finally:
        for connection in connections:
            connection.close()


@pytest.fixture
def h(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[_Main]:
    path = (tmp_path / "auth.sqlite3").resolve()
    secret = secrets.token_hex(32)
    # Remove inherited Auth values without loading .env or exposing real secrets.
    for name in list(os.environ):
        if name.startswith("AUTH_"):
            monkeypatch.delenv(name)
    values = {
        "AUTH_DATABASE_URL": "sqlite:///" + str(path), "AUTH_CSRF_SECRET": secret,
        "CORS_ORIGINS": "http://localhost:8501,http://localhost:5173,http://localhost:5000",
        "APP_ROOT": str(_BACKEND), "APP_FLUTTER": str(_BACKEND.parent / "gold_rush"),
        "NHAT_KY_DIR": str(tmp_path / "nhat_ky"), "SO_PHIEU": str(tmp_path / "phieu.jsonl"),
        "SO_VE": str(tmp_path / "ve.jsonl"), "TRONG_TAI_KHOA": "", "HOP_DONG_CUA_HANG": "",
        "CHAIN_ID": "31337", "MAX_NHAT_KY_KB": "64",
        "ENABLED": "do_kho,tro_ly,ban_do,nhat_ky,vang",
        "MO_HINH_DO_KHO": str(_BACKEND / "artifacts/do_kho/do_kho_v1.json"),
        "KB_DIR": str(_BACKEND / "data/kb"),
        "BAN_DO_DIR": str(_BACKEND.parent / "gold_rush/assets/tiles"),
        "MAN_CHOI": str(_BACKEND.parent / "gold_rush/assets/tiles/man_choi.json"),
    }
    for name, value in values.items():
        monkeypatch.setenv(name, value)
    # The composition root may import definitions, but not initialize an Engine.
    with patch.object(Engine, "__init__", side_effect=AssertionError("Engine created on import")):
        main = _load_main()
    assert not path.exists() and not main.STATE
    assert not hasattr(main.app.state, "auth_engine")
    assert not main.app.dependency_overrides
    with patch("logging.config.fileConfig"):
        command.upgrade(Config(str(_BACKEND / "alembic.ini"), stdout=io.StringIO()), "head")
    automatic_migration = Mock(side_effect=AssertionError("Startup must not run migrations."))
    monkeypatch.setattr(command, "upgrade", automatic_migration)
    monkeypatch.setattr(command, "downgrade", automatic_migration)
    with ExitStack() as stack:
        harness = _Main(main, path, secret, stack, original_routes=tuple(main.app.routes))
        real_engine = main.create_auth_engine
        real_factory = main.create_session_factory
        lock = Lock()

        def engine_factory(*args, **kwargs):
            engine = real_engine(*args, **kwargs)
            harness.engines.append(engine)
            event.listen(engine, "engine_disposed", harness.disposed.append)
            return engine

        def session_factory(*args, **kwargs):
            maker = real_factory(*args, **kwargs)

            def fresh_session():
                session = maker()
                with lock:
                    harness.sessions.append(session)
                return session

            harness.factories.append(fresh_session)
            return fresh_session

        # Observe real resource creation; do not replace its result or guards.
        monkeypatch.setattr(main, "create_auth_engine", engine_factory)
        monkeypatch.setattr(main, "create_session_factory", session_factory)
        try:
            yield harness
        finally:
            try:
                stack.close()
                assert harness.disposed == harness.engines
                assert not main.STATE and tuple(main.app.routes) == harness.original_routes
                for name in ("auth_config", "auth_engine", "auth_session_factory"):
                    assert not hasattr(main.app.state, name)
                assert all(engine.pool.checkedout() == 0 for engine in harness.engines)
                automatic_migration.assert_not_called()
            finally:
                for db in harness.sessions:
                    db.close()
                for engine in harness.engines:
                    if engine not in harness.disposed:
                        engine.dispose()


@pytest.fixture
def client(h: _Main) -> TestClient:
    return h.client()


def test_import_is_inert_and_does_not_replace_shared_main_or_config(h):
    before = {name: sys.modules.get(name) for name in ("config", "api.main")}
    with patch.object(Engine, "__init__", side_effect=AssertionError("Engine on import")), \
            patch.object(sqlite3.dbapi2, "connect", side_effect=AssertionError("DB on import")):
        imported = _load_main()
    assert imported.app is not h.module.app
    assert not imported.STATE and not hasattr(imported.app.state, "auth_config")
    assert not h.engines and not h.factories
    assert {name: sys.modules.get(name) for name in before} == before
    assert imported.app.router.lifespan_context is imported.lifespan


def test_exact_auth_paths_methods_and_no_duplicate_operations(h, client):
    with warnings.catch_warnings(record=True) as caught:
        schema = h.module.app.openapi()
    assert not caught
    assert set(schema["paths"]) == set(_legacy_routes()) | set(_AUTH_ROUTES)
    for path, method in _AUTH_ROUTES.items():
        assert set(schema["paths"][path]) == {method}
    ids = [operation["operationId"] for methods in schema["paths"].values() for operation in methods.values()]
    assert len(ids) == len(set(ids))
    assert "/api/auth/me" not in schema["paths"]
    assert all("/api/api/" not in path and "/auth/auth/" not in path for path in schema["paths"])
    assert client.get("/api/auth/me", headers={"Origin": _ORIGIN}).status_code == 404


def test_lifespan_owns_one_engine_and_fresh_closed_sessions(h, client):
    assert len(h.engines) == len(h.factories) == 1
    assert h.module.app.state.auth_engine is h.engines[0]
    assert h.module.app.state.auth_session_factory is h.factories[0]
    for _ in range(2):
        _error(_me(client, token="e1" * 32), 401, "SESSION_INVALID")
    _grant(client)
    assert len(h.engines) == len(h.factories) == 1
    assert h.sessions and len({id(db) for db in h.sessions}) == len(h.sessions)
    assert h.engines[0].pool.checkedout() == 0
    for db in h.sessions:
        assert not db.in_transaction()
        with pytest.raises(InvalidRequestError):
            db.execute(text("SELECT 1"))


def test_shutdown_and_reenter_refresh_resources_without_duplicate_routes(h):
    route_counts = []
    for _ in range(2):
        with TestClient(h.module.app, base_url="http://localhost:8000") as client:
            route_counts.append(len(h.module.app.routes))
            assert _me(client).status_code == 401
            assert h.module.STATE.keys() >= {"do_kho", "tro_ly", "man_choi"}
            assert set(h.module.app.openapi()["paths"]) == set(_legacy_routes()) | set(_AUTH_ROUTES)
        assert not h.module.STATE and tuple(h.module.app.routes) == h.original_routes
        assert not hasattr(h.module.app.state, "auth_engine")
    assert route_counts[0] == route_counts[1]
    assert len(h.engines) == len(h.factories) == 2 and h.engines[0] is not h.engines[1]
    assert h.disposed == h.engines


def test_restart_restores_account_and_session_from_same_migrated_database(h):
    with TestClient(h.module.app, base_url="http://localhost:8000") as client:
        _, grant = _grant(client)
        registered = _register(client, grant)
        assert registered.status_code == 201
        token = _cookie(registered, "gr_session").value
        user = registered.json()["user"]
    with TestClient(h.module.app, base_url="http://localhost:8000") as client:
        response = _me(client, token=token)
        assert response.status_code == 200 and response.json()["user"] == user
        assert h.count(User) == 1


@pytest.mark.parametrize("mode", ["missing_secret", "invalid_secret", "wildcard_origin", "https_insecure", "bad_url"])
def test_invalid_config_fails_startup_without_authority_or_sensitive_error(h, monkeypatch, mode, capsys, caplog):
    marker = "synthetic-config-secret-marker"
    if mode == "missing_secret":
        monkeypatch.delenv("AUTH_CSRF_SECRET")
    elif mode == "invalid_secret":
        monkeypatch.setenv("AUTH_CSRF_SECRET", marker)
    elif mode == "wildcard_origin":
        monkeypatch.setenv("CORS_ORIGINS", "*")
    elif mode == "https_insecure":
        monkeypatch.setenv("AUTH_SIWE_DOMAIN", "game.example")
        monkeypatch.setenv("AUTH_SIWE_URI", "https://game.example")
        monkeypatch.setenv("CORS_ORIGINS", "https://game.example")
    else:
        monkeypatch.setenv("AUTH_DATABASE_URL", marker)
    with pytest.raises(RuntimeError, match="AUTH_CONFIG_INVALID") as caught:
        with TestClient(h.module.app):
            pytest.fail("Invalid AuthConfig was accepted.")
    assert not h.engines and not h.factories
    captured = capsys.readouterr()
    output = str(caught.value) + captured.out + captured.err + caplog.text
    assert marker not in output and h.secret not in output
    # Even a client incorrectly skipping lifespan cannot obtain fake authority.
    client = TestClient(h.module.app, raise_server_exceptions=False)
    try:
        _error(_me(client), 503, "AUTH_UNAVAILABLE")
    finally:
        client.close()


@pytest.mark.parametrize("mode", ["absent_file", "empty_schema", "missing_table", "wrong_revision", "missing_column"])
def test_missing_schema_fails_closed_disposes_engine_and_never_migrates(h, mode):
    with sqlite3.connect(h.path) as db:
        if mode == "empty_schema":
            for name in ("game_run_owners", "auth_sessions", "auth_challenges", "users", "alembic_version"):
                db.execute('DROP TABLE "' + name + '"')
        elif mode == "missing_table":
            db.execute("DROP TABLE auth_challenges")
        elif mode == "wrong_revision":
            db.execute("UPDATE alembic_version SET version_num='missing_revision'")
        elif mode == "missing_column":
            db.execute("ALTER TABLE auth_challenges RENAME COLUMN message TO renamed_message")
        before = db.execute("SELECT sql FROM sqlite_master ORDER BY name").fetchall()
    if mode == "absent_file":
        # Only this test's own file, before an app Engine has opened it.
        h.path.unlink()
    with pytest.raises(RuntimeError, match="AUTH_DATABASE_NOT_READY"):
        with TestClient(h.module.app):
            pytest.fail("Missing schema was accepted.")
    assert len(h.engines) == 1 and h.disposed == h.engines and not h.factories
    if mode == "absent_file":
        assert not h.path.exists()
    else:
        with sqlite3.connect(h.path) as db:
            assert db.execute("SELECT sql FROM sqlite_master ORDER BY name").fetchall() == before


def test_startup_preserves_migrated_schema_and_unrelated_table(h):
    with sqlite3.connect(h.path) as db:
        db.execute("CREATE TABLE unrelated_test_data (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
        db.execute("INSERT INTO unrelated_test_data VALUES (1, 'preserve me')")
        before = db.execute("SELECT sql FROM sqlite_master ORDER BY name").fetchall()
    with TestClient(h.module.app) as client:
        assert client.get("/api/health").status_code == 200
    with sqlite3.connect(h.path) as db:
        assert db.execute("SELECT sql FROM sqlite_master ORDER BY name").fetchall() == before
        assert db.execute("SELECT value FROM unrelated_test_data").fetchone() == ("preserve me",)


@pytest.mark.parametrize("origin", [_ORIGIN, "http://localhost:8501", "http://localhost:5173"])
def test_configured_origins_have_explicit_credential_cors(client, origin):
    response = client.get("/api/health", headers={"Origin": origin})
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == origin != "*"
    assert response.headers["Access-Control-Allow-Credentials"] == "true"
    assert "Origin" in response.headers["Vary"]


@pytest.mark.parametrize("method", ["GET", "POST", "OPTIONS"])
def test_preflight_allows_auth_headers_without_session_or_business_writes(h, client, method):
    response = client.options("/api/auth/challenge", headers={
        "Origin": _ORIGIN, "Access-Control-Request-Method": method,
        "Access-Control-Request-Headers": "Content-Type,X-CSRF-Token,X-Gold-Rush-Auth",
    })
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == _ORIGIN
    assert response.headers["Access-Control-Allow-Credentials"] == "true"
    assert set(response.headers["Access-Control-Allow-Methods"].split(", ")) == {"GET", "POST", "OPTIONS"}
    headers = {value.strip().lower() for value in response.headers["Access-Control-Allow-Headers"].split(",")}
    assert {"content-type", "x-csrf-token", "x-gold-rush-auth"} <= headers and "*" not in headers
    assert "set-cookie" not in response.headers
    assert h.count(User) == h.count(AuthChallenge) == h.count(AuthSession) == 0


@pytest.mark.parametrize("changes", [
    {"Origin": "https://evil.example"}, {"Origin": "http://127.0.0.1:5000"},
    {"Access-Control-Request-Method": "DELETE"}, {"Access-Control-Request-Headers": "X-Unapproved"},
])
def test_preflight_rejects_unapproved_origin_method_or_header(h, client, changes):
    headers = {"Origin": _ORIGIN, "Access-Control-Request-Method": "POST",
               "Access-Control-Request-Headers": "X-CSRF-Token"} | changes
    response = client.options("/api/auth/challenge", headers=headers)
    assert response.status_code == 400
    assert response.headers.get("Access-Control-Allow-Origin") != "*"
    if headers["Origin"] != _ORIGIN:
        assert "access-control-allow-origin" not in response.headers
    assert h.count(AuthChallenge) == 0


def test_full_registration_logout_and_existing_wallet_login_on_main(h, client):
    wallet = Account.create()
    challenge = _challenge(client, wallet)
    data = challenge.json()
    binding = _cookie(challenge, "gr_auth_flow").value
    row = h.challenge(data["challenge_id"])
    assert row.message == data["message"] and row.browser_binding_hash == _hash(binding)
    config = h.module.app.state.auth_config
    assert row.domain == config.siwe_domain and row.uri == config.siwe_uri
    assert row.wallet_address == wallet.address.lower() and wallet.address in row.message
    grant = client.post("/api/auth/verify", json=_signed(wallet, data), headers=_BOOTSTRAP)
    assert grant.status_code == 200 and grant.json()["status"] == "registration_required"
    grant_token = _cookie(grant, "gr_session").value
    assert h.session(grant_token).purpose == "registration" and h.count(User) == 0
    _error(_me(client), 401, "SESSION_INVALID")
    registered = _register(client, grant)
    assert registered.status_code == 201, registered.text
    token = _cookie(registered, "gr_session").value
    body = registered.json()
    user = body["user"]
    assert body["status"] == "authenticated" and user["username"] == "Nhà Thám Hiểm"
    assert user["wallet_address"] == wallet.address.lower() and set(user) == _PUBLIC_USER
    assert token != grant_token and body["csrf_token"] != grant.json()["csrf_token"]
    session = h.session(token)
    assert session.purpose == "authenticated" and str(session.user_id) == user["id"]
    assert h.session(grant_token).revoked_at is not None
    with h.module.app.state.auth_session_factory() as db:
        account = db.get(User, session.user_id)
        assert account.username == user["username"] and account.wallet_address == user["wallet_address"]
    me = _me(client)
    assert me.status_code == 200 and me.json()["user"] == user
    assert me.json()["chain_id"] == 31337 and me.json()["csrf_token"] == body["csrf_token"]
    assert me.headers["Cache-Control"] == "no-store"
    for response in (challenge, grant, registered, me):
        assert response.headers["Access-Control-Allow-Origin"] == _ORIGIN
        assert response.headers["Access-Control-Allow-Credentials"] == "true"
        assert "X-Process-Time-ms" in response.headers
        for sensitive in (token, grant_token, _hash(token), binding, wallet.key.hex(), h.secret):
            assert sensitive not in response.text
    logout = client.post("/api/auth/logout", json={}, headers={
        "Origin": _ORIGIN, "X-CSRF-Token": me.json()["csrf_token"],
    })
    assert logout.status_code == 204 and logout.content == b""
    assert h.session(token).revoked_at is not None and h.count(User) == 1
    for name in ("gr_session", "gr_auth_flow"):
        deletion = _cookie(logout, name)
        assert deletion["max-age"] == "0" and deletion["path"] == "/api"
        assert deletion["httponly"] and deletion["samesite"] == "lax"
        assert name not in client.cookies
    _error(_me(client), 401, "SESSION_REQUIRED")
    _error(_me(client, token=token), 401, "SESSION_REVOKED")
    fresh = _challenge(client, wallet).json()
    assert fresh["challenge_id"] != data["challenge_id"] and fresh["message"] != data["message"]
    login = client.post("/api/auth/verify", json=_signed(wallet, fresh), headers=_BOOTSTRAP)
    assert login.status_code == 200 and login.json()["status"] == "authenticated"
    assert login.json()["user"] == user and h.count(User) == 1
    assert str(h.session(_cookie(login, "gr_session").value).user_id) == user["id"]
    assert _me(client).json()["user"] == user


@pytest.mark.parametrize("fault,status,code", [
    ("other_signer", 401, "SIGNER_MISMATCH"), ("missing_binding", 403, "BROWSER_BINDING_INVALID"),
    ("wrong_binding", 401, "BROWSER_BINDING_INVALID"), ("message", 401, "MESSAGE_MISMATCH"),
    ("missing_bootstrap", 403, "BOOTSTRAP_REQUIRED"),
])
def test_verify_rejects_invalid_proof_on_main_without_consuming_challenge(h, client, fault, status, code):
    wallet = Account.create()
    challenge = _challenge(client, wallet).json()
    payload = _signed(Account.create() if fault == "other_signer" else wallet, challenge)
    headers = dict(_BOOTSTRAP)
    if fault == "missing_binding":
        headers["Cookie"] = "unrelated=1"
    elif fault == "wrong_binding":
        headers["Cookie"] = "gr_auth_flow=" + "a1" * 32
    elif fault == "message":
        nonce = h.challenge(challenge["challenge_id"]).nonce
        altered = nonce[:-1] + ("b" if nonce[-1] != "b" else "a")
        payload["message"] = payload["message"].replace("Nonce: " + nonce, "Nonce: " + altered)
    elif fault == "missing_bootstrap":
        headers.pop("X-Gold-Rush-Auth")
    response = client.post("/api/auth/verify", json=payload, headers=headers)
    _error(response, status, code)
    assert h.challenge(challenge["challenge_id"]).consumed_at is None
    assert h.count(User) == h.count(AuthSession) == 0
    assert payload["signature"] not in response.text


def test_used_challenge_cannot_issue_second_session_on_main(h, client):
    wallet = Account.create()
    challenge = _challenge(client, wallet).json()
    payload = _signed(wallet, challenge)
    response = client.post("/api/auth/verify", headers=_BOOTSTRAP, json=payload)
    assert response.status_code == 200
    token = _cookie(response, "gr_session").value
    _error(client.post("/api/auth/verify", headers=_BOOTSTRAP, json=payload), 409, "CHALLENGE_USED")
    assert h.count(AuthSession) == 1 and h.session(token).revoked_at is None


@pytest.mark.parametrize("origin", [None, "null", "https://evil.example", "http://127.0.0.1:5000"])
@pytest.mark.parametrize("endpoint", ["challenge", "me"])
def test_origin_guard_rejects_unknown_or_missing_origin_even_with_cookie(h, client, origin, endpoint):
    _, grant = _grant(client)
    registered = _register(client, grant)
    assert registered.status_code == 201
    headers = {"X-Gold-Rush-Auth": "1"}
    if origin is not None:
        headers["Origin"] = origin
    if endpoint == "me":
        response = client.get("/api/me", headers=headers)
    else:
        response = client.post("/api/auth/challenge", headers=headers, json={
            "wallet_address": Account.create().address, "chain_id": 31337,
        })
    _error(response, 403, "ORIGIN_FORBIDDEN")
    assert "Access-Control-Allow-Origin" not in response.headers
    assert h.count(User) == 1 and h.count(AuthChallenge) == 1


@pytest.mark.parametrize("endpoint", ["register", "logout"])
@pytest.mark.parametrize("csrf", [None, "wrong"])
def test_csrf_is_enforced_separately_from_successful_cors(h, client, endpoint, csrf):
    _, grant = _grant(client)
    if endpoint == "logout":
        registered = _register(client, grant)
        assert registered.status_code == 201
    token = client.cookies.get("gr_session")
    headers = {"Origin": _ORIGIN}
    if csrf is not None:
        headers["X-CSRF-Token"] = csrf
    response = client.post("/api/auth/" + endpoint, headers=headers,
                           json={"username": "Explorer"} if endpoint == "register" else {})
    _error(response, 403, "CSRF_INVALID")
    assert response.headers["Access-Control-Allow-Origin"] == _ORIGIN
    assert response.headers["Access-Control-Allow-Credentials"] == "true"
    assert h.session(token).revoked_at is None
    assert h.count(User) == (1 if endpoint == "logout" else 0)


@pytest.mark.parametrize("secure", [False, True])
def test_main_cookie_attributes_follow_auth_config(h, monkeypatch, secure):
    origin = _ORIGIN
    if secure:
        origin = "https://game.example"
        monkeypatch.setenv("AUTH_SIWE_DOMAIN", "game.example")
        monkeypatch.setenv("AUTH_SIWE_URI", origin)
        monkeypatch.setenv("AUTH_COOKIE_SECURE", "true")
        monkeypatch.setenv("CORS_ORIGINS", origin)
    client = h.client(secure=secure)
    headers = {"Origin": origin, "X-Gold-Rush-Auth": "1"}
    wallet = Account.create()
    challenge = _challenge(client, wallet, headers=headers)
    grant = client.post("/api/auth/verify", headers=headers, json=_signed(wallet, challenge.json()))
    assert grant.status_code == 200
    registered = _register(client, grant, headers={"Origin": origin})
    assert registered.status_code == 201
    config = h.module.app.state.auth_config
    for response, name, lifetime in (
        (challenge, "gr_auth_flow", config.challenge_ttl_seconds),
        (grant, "gr_session", config.registration_ttl_seconds),
        (registered, "gr_session", config.session_ttl_seconds),
    ):
        cookie = _cookie(response, name)
        assert cookie["httponly"] and cookie["samesite"] == "lax" and cookie["path"] == "/api"
        assert bool(cookie["secure"]) is secure and not cookie["domain"]
        assert lifetime - 5 <= int(cookie["max-age"]) <= lifetime
        expiry = datetime.fromisoformat(response.json()["expires_at"])
        assert parsedate_to_datetime(cookie["expires"]) <= expiry
    assert _me(client, origin=origin).status_code == 200


def test_localhost_cookie_is_sent_across_ports_but_not_to_127_0_0_1(client):
    _, grant = _grant(client)
    registered = _register(client, grant)
    assert registered.status_code == 201
    # Same real app, different request URL; httpx applies its host cookie rules.
    assert client.get("http://localhost:5000/api/me", headers={"Origin": _ORIGIN}).status_code == 200
    _error(client.get("http://127.0.0.1:8000/api/me", headers={"Origin": _ORIGIN}), 401, "SESSION_REQUIRED")


def test_sensitive_values_not_echoed_on_main_errors(h, client, capsys, caplog):
    wallet = Account.create()
    challenge = _challenge(client, wallet).json()
    payload = _signed(wallet, challenge)
    marker = "synthetic-sensitive-validation-marker"
    payload[marker] = marker
    response = client.post("/api/auth/verify", headers=_BOOTSTRAP, json=payload)
    _error(response, 422, "INVALID_REQUEST")
    captured = capsys.readouterr()
    output = response.text + captured.out + captured.err + caplog.text
    for value in (wallet.key.hex(), payload["signature"], payload["message"], marker, h.secret):
        assert value not in output


def test_legacy_game_routes_and_lifespan_components_remain_registered(h, client):
    paths = h.module.app.openapi()["paths"]
    declared = _legacy_routes()
    assert declared
    for path, method in declared.items():
        assert method in paths[path]
    assert {h.module.du_doan_do_kho, h.module.sinh_ban_do_moi, h.module.bat_dau_man,
            h.module.cap_phieu, h.module.phieu_cho_nhan} <= {
        route.endpoint for route in h.module.app.routes if hasattr(route, "endpoint")
    }
    assert h.module.STATE.keys() >= {"do_kho", "tro_ly", "man_choi"}
    health = client.get("/api/health")
    assert health.status_code == 200 and health.json()["da_nap"] == {"do_kho": True, "tro_ly": True}
    assert len(client.get("/api/man").json()["man"]) == 6


@pytest.mark.parametrize("feature", ["prediction", "map", "assistant", "model", "telemetry"])
def test_legacy_api_smoke_keeps_existing_contracts_without_auth(h, client, feature):
    # These are public legacy behaviors, NOT proof of ownership protection.
    if feature == "prediction":
        response = client.post("/api/do-kho/du-doan", json={"dac_trung": [.25, 1.5, 3., .25, 2.]})
        assert response.status_code == 200
        assert 0 <= response.json()["p_thua"] <= 1 and "he_so_toc_do" in response.json()
    elif feature == "map":
        response = client.get("/api/ban-do/sinh", params={"seed": 3})
        assert response.status_code == 200 and 'name="VaCham"' in response.text
        assert "ti_le_di_duoc" in response.headers["X-Chi-So"]
    elif feature == "assistant":
        response = client.post("/api/tro-ly", json={"cau_hoi": "Thủ đô của Pháp là gì?"})
        assert response.status_code == 200 and response.json()["trong_pham_vi"] is False
    elif feature == "model":
        response = client.get("/api/mo-hinh/do-kho")
        assert response.status_code == 200 and "phien_ban" in response.json()
    else:
        run = str(uuid4())
        payload = {"ma_van": run, "phien_ban_app": "1.3.0", "ket_qua": "thang", "giay": 120,
                   "diem": 480, "ten_hien_thi": "Test Explorer", "su_kien": []}
        response = client.post("/api/nhat-ky", json=payload)
        assert response.status_code == 201 and response.json()["ma_van"] == run
        assert client.get("/api/bang-xep-hang").json()["bang"][0]["ten"] == "Test Explorer"
        # The lack of cookie/Origin/CSRF is deliberate evidence of the adapter gap.
        assert h.count(User) == h.count(AuthSession) == 0
