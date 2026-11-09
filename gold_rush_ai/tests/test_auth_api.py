"""Real HTTP Auth flows on an isolated app and Alembic-migrated tmp_path SQLite.

All success paths use real EIP-191 signatures, service transactions and CSRF.
No api.main import, external database, RPC or MetaMask extension is involved.
The optional CORS test configures middleware on this test app only; it does not
prove the main application has CORS, rate limiting or player ownership guards.
Run from gold_rush_ai: python -m pytest tests/test_auth_api.py -q
"""
from __future__ import annotations

import io
import os
import secrets
import socket
import sqlite3
import unicodedata
from collections.abc import Callable, Iterator
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from email.utils import parsedate_to_datetime
from hashlib import sha256
from http.cookies import SimpleCookie
from pathlib import Path
from threading import Barrier, Lock
from unittest.mock import Mock, patch
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.testclient import TestClient
from sqlalchemy import MetaData, event, func, select, text, update
from sqlalchemy.engine import Engine, URL
from sqlalchemy.exc import InvalidRequestError
from sqlalchemy.orm import Session

from auth import service
from auth.config import AuthConfig
from auth.database import create_auth_engine, create_session_factory
from auth.models import AuthChallenge, AuthSession, User
from auth.router import create_auth_router
from auth.siwe import parse_siwe_message


_BACKEND = Path(__file__).resolve().parents[1]
_ORIGIN = "http://localhost:5000"
_BOOTSTRAP = {"Origin": _ORIGIN, "X-Gold-Rush-Auth": "1"}
_PUBLIC_USER = {"id", "wallet_address", "username", "avatar", "created_at"}


@dataclass(repr=False)
class _Harness:
    config: AuthConfig
    engine: Engine
    factory: Callable[[], Session]
    clock: list[datetime]
    app: FastAPI
    sessions: list[Session]
    stack: ExitStack

    def client(self, *, config: AuthConfig | None = None, cors=False) -> TestClient:
        app = self.app
        if config is not None or cors:
            config = config or self.config
            app = FastAPI()
            app.include_router(create_auth_router(config, self.factory, clock=lambda: self.clock[0]))
            if cors:
                app.add_middleware(
                    CORSMiddleware, allow_origins=list(config.cors_origins),
                    allow_credentials=True, allow_methods=["GET", "POST", "OPTIONS"],
                    allow_headers=["Content-Type", "X-CSRF-Token", "X-Gold-Rush-Auth"],
                )
        secure = config.cookie_secure if config is not None else self.config.cookie_secure
        return self.stack.enter_context(TestClient(
            app, base_url="https://localhost:8000" if secure else "http://localhost:8000",
            raise_server_exceptions=False,
        ))

    def count(self, model) -> int:
        with self.factory() as db:
            return db.scalar(select(func.count()).select_from(model))

    def session(self, token: str) -> AuthSession:
        with self.factory() as db:
            row = db.scalar(select(AuthSession).where(AuthSession.token_hash == _hash(token)))
            assert row is not None
            return row

    def challenge(self, challenge_id: str) -> AuthChallenge:
        with self.factory() as db:
            row = db.get(AuthChallenge, UUID(challenge_id))
            assert row is not None
            return row


def _hash(token: str) -> str:
    return sha256(token.encode("ascii")).hexdigest()


def _cookie(response, name: str):
    found = []
    for value in response.headers.get_list("set-cookie"):
        jar = SimpleCookie()
        jar.load(value)
        if name in jar:
            found.append(jar[name])
    assert len(found) == 1
    return found[0]


def _error(response, status: int, code: str | None = None) -> None:
    assert response.status_code == status, response.text
    detail = response.json()["detail"]
    assert isinstance(detail["message"], str) and detail["message"]
    if code is not None:
        assert detail["code"] == code
    assert response.headers["Cache-Control"] == "no-store"
    assert "set-cookie" not in response.headers


def _challenge(client: TestClient, wallet, *, headers=None, chain_id=31337):
    response = client.post("/api/auth/challenge", headers=headers or _BOOTSTRAP, json={
        "wallet_address": wallet.address, "chain_id": chain_id,
    })
    assert response.status_code == 201, response.text
    return response


def _signed(wallet, challenge: dict) -> dict:
    return {
        "challenge_id": challenge["challenge_id"], "message": challenge["message"],
        "signature": "0x" + wallet.sign_message(encode_defunct(text=challenge["message"])).signature.hex(),
    }


def _verify(client: TestClient, wallet, *, headers=None, chain_id=31337):
    challenge = _challenge(client, wallet, headers=headers, chain_id=chain_id)
    response = client.post("/api/auth/verify", headers=headers or _BOOTSTRAP,
                           json=_signed(wallet, challenge.json()))
    assert response.status_code == 200, response.text
    return response


def _register(client: TestClient, grant, username="Nhà Thám Hiểm", *, headers=None):
    values = {"Origin": _ORIGIN, "X-CSRF-Token": grant.json()["csrf_token"]}
    values.update(headers or {})
    return client.post("/api/auth/register", headers=values, json={"username": username})


def _authenticated(client: TestClient, wallet=None, username="Nhà Thám Hiểm"):
    wallet = wallet or Account.create()
    grant = _verify(client, wallet)
    response = _register(client, grant, username)
    assert response.status_code == 201, response.text
    return wallet, response


def _me(client: TestClient, *, token=None, **params):
    headers = {"Origin": _ORIGIN}
    if token is not None:
        headers["Cookie"] = "gr_session=" + token
    return client.get("/api/me", headers=headers, params=params)


@pytest.fixture(autouse=True)
def isolated_io(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Fail closed if any request/migration attempts network or a non-test DB."""
    blocked = Mock(side_effect=AssertionError("API tests forbid external I/O and metadata.create_all."))
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
        assert path.is_absolute() and path.resolve().is_relative_to(tmp_path.resolve())
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
def h(tmp_path: Path) -> Iterator[_Harness]:
    url = URL.create("sqlite", database=str((tmp_path / "api.sqlite3").resolve()))
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

    # Start at real UTC so cookie jars accept expiry; move this clock, never sleep.
    clock = [datetime.now(UTC)]
    app = FastAPI()
    app.include_router(create_auth_router(config, factory, clock=lambda: clock[0]))
    with ExitStack() as stack:
        harness = _Harness(config, engine, factory, clock, app, sessions, stack)
        try:
            yield harness
        finally:
            stack.close()
            checked_out = engine.pool.checkedout()
            for db in sessions:
                db.close()
            engine.dispose()
            assert checked_out == 0, "A request leaked a connection."


@pytest.fixture
def client(h: _Harness) -> TestClient:
    return h.client()


@pytest.fixture
def wallet():
    return Account.create()


def test_router_mounts_exact_five_endpoints_without_main(h):
    paths = h.app.openapi()["paths"]
    assert {path: set(value) for path, value in paths.items()} == {
        "/api/auth/challenge": {"post"}, "/api/auth/verify": {"post"},
        "/api/auth/register": {"post"}, "/api/me": {"get"}, "/api/auth/logout": {"post"},
    }
    assert h.count(User) == h.count(AuthChallenge) == h.count(AuthSession) == 0
    assert not h.app.dependency_overrides


def test_challenge_persists_exact_siwe_and_only_binding_hash(h, client, wallet):
    response = _challenge(client, wallet)
    body = response.json()
    assert set(body) == {"challenge_id", "message", "expires_at"}
    row = h.challenge(body["challenge_id"])
    parsed = parse_siwe_message(body["message"], config=h.config)
    binding = _cookie(response, "gr_auth_flow").value
    assert row.wallet_address == wallet.address.lower()
    assert parsed.wallet_address == wallet.address
    assert parsed.domain == row.domain == h.config.siwe_domain
    assert parsed.uri == row.uri == h.config.siwe_uri
    assert parsed.chain_id == row.chain_id == 31337
    assert parsed.nonce == row.nonce and len(row.nonce) == 32
    assert row.message == body["message"]
    assert row.issued_at == h.clock[0]
    assert row.expires_at == datetime.fromisoformat(body["expires_at"])
    assert row.expires_at - row.issued_at == timedelta(seconds=h.config.challenge_ttl_seconds)
    assert row.browser_binding_hash == _hash(binding) != binding
    assert row.consumed_at is None
    assert h.count(User) == h.count(AuthSession) == 0
    assert "gr_session" not in client.cookies
    assert response.headers["Cache-Control"] == "no-store"


def test_challenges_reuse_binding_but_have_independent_nonces(h, client, wallet):
    first = _challenge(client, wallet)
    h.clock[0] += timedelta(seconds=2)
    second = _challenge(client, wallet)
    assert _cookie(first, "gr_auth_flow").value == _cookie(second, "gr_auth_flow").value
    assert first.json()["challenge_id"] != second.json()["challenge_id"]
    assert h.challenge(first.json()["challenge_id"]).nonce != h.challenge(second.json()["challenge_id"]).nonce
    # Refreshing the flow cookie must not invalidate a still-live older challenge.
    response = client.post("/api/auth/verify", headers=_BOOTSTRAP, json=_signed(wallet, first.json()))
    assert response.status_code == 200


@pytest.mark.parametrize("changes", [
    {"wallet_address": "0x123"}, {"wallet_address": "0x" + "g" * 40},
    {"wallet_address": None}, {"chain_id": 0}, {"chain_id": -1},
    {"chain_id": True}, {"chain_id": "31337"}, {"extra": "forbidden"},
])
def test_invalid_challenge_payload_is_422_without_writes(h, client, wallet, changes):
    payload = {"wallet_address": wallet.address, "chain_id": 31337} | changes
    _error(client.post("/api/auth/challenge", headers=_BOOTSTRAP, json=payload), 422, "INVALID_REQUEST")
    assert h.count(AuthChallenge) == h.count(AuthSession) == h.count(User) == 0


def test_disallowed_chain_is_422(h, client, wallet):
    response = client.post("/api/auth/challenge", headers=_BOOTSTRAP, json={
        "wallet_address": wallet.address, "chain_id": 1,
    })
    _error(response, 422, "CHAIN_NOT_ALLOWED")
    assert h.count(AuthChallenge) == 0


@pytest.mark.parametrize("origin", [None, "null", "https://evil.example", "http://localhost:5000/", "http://127.0.0.1:5000"])
@pytest.mark.parametrize("endpoint", ["challenge", "verify", "register", "me", "logout"])
def test_origin_required_on_every_endpoint(h, client, wallet, origin, endpoint):
    headers = {"X-Gold-Rush-Auth": "1"}
    if origin is not None:
        headers["Origin"] = origin
    payloads = {
        "challenge": {"wallet_address": wallet.address, "chain_id": 31337},
        "verify": {"challenge_id": str(uuid4()), "message": "test", "signature": "0x" + "00" * 65},
        "register": {"username": "Explorer"}, "logout": {},
    }
    response = (client.get("/api/me", headers=headers) if endpoint == "me" else
                client.post("/api/auth/" + endpoint, headers=headers, json=payloads[endpoint]))
    _error(response, 403, "ORIGIN_FORBIDDEN")
    assert h.count(User) == h.count(AuthChallenge) == h.count(AuthSession) == 0


@pytest.mark.parametrize("bootstrap", [None, "0", "true"])
def test_challenge_requires_bootstrap_header(client, wallet, bootstrap):
    headers = {"Origin": _ORIGIN}
    if bootstrap is not None:
        headers["X-Gold-Rush-Auth"] = bootstrap
    _error(client.post("/api/auth/challenge", headers=headers, json={
        "wallet_address": wallet.address, "chain_id": 31337,
    }), 403, "BOOTSTRAP_REQUIRED")


def test_verify_new_wallet_commits_grant_and_consumes_challenge(h, client, wallet):
    challenge = _challenge(client, wallet).json()
    response = client.post("/api/auth/verify", headers=_BOOTSTRAP, json=_signed(wallet, challenge))
    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"status", "wallet_address", "expires_at", "csrf_token"}
    assert body["status"] == "registration_required"
    assert body["wallet_address"] == wallet.address.lower()
    token = _cookie(response, "gr_session").value
    row = h.session(token)
    assert row.purpose == "registration" and row.user_id is None
    assert row.wallet_address == wallet.address.lower() and row.chain_id == 31337
    assert row.revoked_at is None
    assert row.expires_at == datetime.fromisoformat(body["expires_at"])
    assert token not in response.text and row.token_hash not in response.text
    assert h.challenge(challenge["challenge_id"]).consumed_at == h.clock[0]
    assert h.count(User) == 0 and h.count(AuthSession) == 1
    _error(_me(client), 401, "SESSION_INVALID")


@pytest.mark.parametrize("fault,status,code", [
    ("signer", 401, "SIGNER_MISMATCH"), ("message", 401, "MESSAGE_MISMATCH"),
    ("statement", 401, "MESSAGE_INVALID"),
    ("signature", 401, "SIGNATURE_INVALID"), ("binding", 401, "BROWSER_BINDING_INVALID"),
    ("missing_binding", 403, "BROWSER_BINDING_INVALID"),
    ("expired", 410, "CHALLENGE_EXPIRED"), ("unknown", 401, "CHALLENGE_NOT_FOUND"),
    ("empty_signature", 422, "INVALID_REQUEST"), ("short_signature", 422, "INVALID_REQUEST"),
    ("uuid", 422, "INVALID_REQUEST"), ("extra", 422, "INVALID_REQUEST"),
])
def test_verify_rejects_invalid_proof_without_consuming_nonce(h, client, wallet, fault, status, code):
    challenge = _challenge(client, wallet).json()
    payload = _signed(Account.create() if fault == "signer" else wallet, challenge)
    headers = dict(_BOOTSTRAP)
    if fault == "message":
        nonce = h.challenge(challenge["challenge_id"]).nonce
        changed = nonce[:-1] + ("a" if nonce[-1] != "a" else "b")
        payload["message"] = payload["message"].replace("Nonce: " + nonce, "Nonce: " + changed)
    elif fault == "statement":
        payload["message"] = payload["message"].replace("Sign in to Gold Rush.", "Sign in to Gold Rust.")
    elif fault == "signature":
        payload["signature"] = "0x" + "00" * 65
    elif fault in {"binding", "missing_binding"}:
        headers["Cookie"] = "gr_auth_flow=" + "a1" * 32 if fault == "binding" else "unrelated=1"
    elif fault == "expired":
        h.clock[0] += timedelta(seconds=h.config.challenge_ttl_seconds)
    elif fault == "unknown":
        payload["challenge_id"] = str(uuid4())
    elif fault == "empty_signature":
        payload["signature"] = ""
    elif fault == "short_signature":
        payload["signature"] = "0x" + "ab" * 64
    elif fault == "uuid":
        payload["challenge_id"] = "not-a-uuid"
    elif fault == "extra":
        payload["is_admin"] = True
    response = client.post("/api/auth/verify", headers=headers, json=payload)
    _error(response, status, code)
    assert h.challenge(challenge["challenge_id"]).consumed_at is None
    assert h.count(AuthSession) == h.count(User) == 0
    assert payload["signature"] not in response.text or not payload["signature"]


def test_nonce_replay_cannot_issue_second_session(h, client, wallet):
    challenge = _challenge(client, wallet).json()
    payload = _signed(wallet, challenge)
    first = client.post("/api/auth/verify", headers=_BOOTSTRAP, json=payload)
    assert first.status_code == 200
    token = _cookie(first, "gr_session").value
    _error(client.post("/api/auth/verify", headers=_BOOTSTRAP, json=payload), 409, "CHALLENGE_USED")
    assert h.count(AuthSession) == 1 and h.session(token).revoked_at is None


def test_concurrent_verify_has_one_committed_winner(h, client, wallet, monkeypatch):
    challenge = _challenge(client, wallet).json()
    payload = _signed(wallet, challenge)
    binding = client.cookies.get("gr_auth_flow")
    clients = [h.client(), h.client()]
    barrier = Barrier(2, timeout=15)
    original = service.verify_siwe_signature

    def verified_together(*args, **kwargs):
        # Synchronize AFTER real cryptographic verification, never bypass it.
        result = original(*args, **kwargs)
        barrier.wait()
        return result

    monkeypatch.setattr(service, "verify_siwe_signature", verified_together)

    def submit(current):
        return current.post("/api/auth/verify", headers=_BOOTSTRAP | {
            "Cookie": "gr_auth_flow=" + binding,
        }, json=payload)

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(submit, clients))
    assert sorted(response.status_code for response in responses) == [200, 409]
    loser = next(response for response in responses if response.status_code == 409)
    _error(loser, 409, "CHALLENGE_USED")
    assert h.count(AuthSession) == 1


def test_registration_normalizes_name_rotates_cookie_and_revokes_grant(h, client, wallet):
    grant = _verify(client, wallet)
    old_token = _cookie(grant, "gr_session").value
    raw = "  " + unicodedata.normalize("NFD", "Nhà") + "   Thám Hiểm  "
    response = _register(client, grant, raw)
    assert response.status_code == 201, response.text
    body = response.json()
    new_token = _cookie(response, "gr_session").value
    assert body["status"] == "authenticated"
    assert body["user"]["username"] == "Nhà Thám Hiểm"
    assert set(body["user"]) == _PUBLIC_USER
    assert body["user"]["avatar"] == "george"
    assert new_token != old_token and body["csrf_token"] != grant.json()["csrf_token"]
    assert h.session(old_token).revoked_at == h.clock[0]
    session = h.session(new_token)
    assert session.purpose == "authenticated" and str(session.user_id) == body["user"]["id"]
    with h.factory() as db:
        user = db.get(User, session.user_id)
        assert user.username_key == "nhà thám hiểm" and user.wallet_address == wallet.address.lower()
        assert user.created_at == h.clock[0]
    assert h.count(User) == 1
    me = _me(client)
    assert me.status_code == 200 and me.json()["user"] == body["user"]
    assert me.json()["csrf_token"] == body["csrf_token"]
    _error(_register(client, grant, headers={"Cookie": "gr_session=" + old_token}), 401, "GRANT_INVALID")


@pytest.mark.parametrize("extra", ["user_id", "wallet_address", "is_admin", "purpose", "avatar"])
def test_register_rejects_privilege_fields(h, client, wallet, extra):
    grant = _verify(client, wallet)
    token = _cookie(grant, "gr_session").value
    response = client.post("/api/auth/register", headers={
        "Origin": _ORIGIN, "X-CSRF-Token": grant.json()["csrf_token"],
    }, json={"username": "Explorer", extra: "client-chosen"})
    _error(response, 422, "INVALID_REQUEST")
    assert h.count(User) == 0 and h.session(token).revoked_at is None


@pytest.mark.parametrize("name", ["An", "A" * 21, "abc\u200b", "abc😀", "abc\nname"])
def test_register_invalid_username_is_field_error(h, client, wallet, name):
    grant = _verify(client, wallet)
    response = _register(client, grant, name)
    _error(response, 422, "USERNAME_INVALID")
    assert response.json()["detail"]["field"] == "username"
    assert h.count(User) == 0


@pytest.mark.parametrize("state,code", [
    ("missing", "GRANT_INVALID"), ("fake", "GRANT_INVALID"),
    ("expired", "GRANT_EXPIRED"), ("revoked", "GRANT_INVALID"),
    ("authenticated", "GRANT_INVALID"),
])
def test_registration_requires_live_registration_grant(h, client, wallet, state, code):
    grant = _verify(client, wallet)
    token = _cookie(grant, "gr_session").value
    headers = {"Cookie": "gr_session=" + token}
    if state == "missing":
        headers["Cookie"] = "unrelated=1"
    elif state == "fake":
        headers["Cookie"] = "gr_session=" + "1b" * 32
    elif state == "expired":
        h.clock[0] += timedelta(seconds=h.config.registration_ttl_seconds)
    elif state == "revoked":
        with h.factory() as db, db.begin():
            db.execute(update(AuthSession).values(revoked_at=h.clock[0]))
    elif state == "authenticated":
        registered = _register(client, grant)
        assert registered.status_code == 201
        headers["Cookie"] = "gr_session=" + _cookie(registered, "gr_session").value
    _error(_register(client, grant, headers=headers), 401, code)
    assert h.count(User) == (1 if state == "authenticated" else 0)


@pytest.mark.parametrize("endpoint", ["register", "logout"])
@pytest.mark.parametrize("csrf", [None, "wrong", "other_session"])
def test_csrf_missing_wrong_or_bound_to_another_session(h, client, wallet, endpoint, csrf):
    grant = _verify(client, wallet)
    token = _cookie(grant, "gr_session").value
    headers = {"Origin": _ORIGIN}
    if csrf == "wrong":
        headers["X-CSRF-Token"] = "wrong"
    elif csrf == "other_session":
        other = _verify(h.client(), Account.create())
        headers["X-CSRF-Token"] = other.json()["csrf_token"]
    body = {"username": "Explorer"} if endpoint == "register" else {}
    _error(client.post("/api/auth/" + endpoint, headers=headers, json=body), 403, "CSRF_INVALID")
    assert h.count(User) == 0 and h.session(token).revoked_at is None


def test_duplicate_username_409_preserves_grant_for_retry(h, client):
    _authenticated(client, username="Đạt Explorer")
    second = h.client()
    grant = _verify(second, Account.create())
    token = _cookie(grant, "gr_session").value
    response = _register(second, grant, "đẠT EXPLORER")
    _error(response, 409, "USERNAME_TAKEN")
    assert response.json()["detail"]["field"] == "username"
    assert h.count(User) == 1 and h.session(token).revoked_at is None
    assert _register(second, grant, "Another Explorer").status_code == 201
    assert h.count(User) == 2


def test_two_live_grants_same_wallet_cannot_register_twice(h, client, wallet):
    first = _verify(client, wallet)
    second_client = h.client()
    second = _verify(second_client, wallet)
    assert _register(client, first, "First Explorer").status_code == 201
    token = _cookie(second, "gr_session").value
    _error(_register(second_client, second, "Second Explorer"), 409, "WALLET_ALREADY_REGISTERED")
    assert h.count(User) == 1 and h.session(token).revoked_at is None
    assert h.count(AuthSession) == 3


def test_full_new_wallet_then_existing_wallet_http_flow(h, client, wallet):
    grant = _verify(client, wallet)
    assert grant.json()["status"] == "registration_required"
    registered = _register(client, grant)
    assert registered.status_code == 201
    first_token = _cookie(registered, "gr_session").value
    user = registered.json()["user"]
    me = _me(client)
    assert me.status_code == 200 and me.json()["user"] == user
    logout = client.post("/api/auth/logout", json={}, headers={
        "Origin": _ORIGIN, "X-CSRF-Token": me.json()["csrf_token"],
    })
    assert logout.status_code == 204 and logout.content == b""
    _error(_me(client), 401, "SESSION_REQUIRED")
    assert h.session(first_token).revoked_at is not None
    login = _verify(client, wallet)
    assert login.json()["status"] == "authenticated" and login.json()["user"] == user
    token = _cookie(login, "gr_session").value
    assert token != first_token
    assert str(h.session(token).user_id) == user["id"]
    assert _me(client).json()["user"] == user and h.count(User) == 1


def test_verify_existing_user_rotates_and_revokes_previous_authenticated_cookie(h, client, wallet):
    _, registered = _authenticated(client, wallet)
    old_token = _cookie(registered, "gr_session").value
    login = _verify(client, wallet)
    assert login.json()["status"] == "authenticated"
    assert h.session(old_token).revoked_at is not None
    assert _cookie(login, "gr_session").value != old_token
    assert h.count(User) == 1
    _error(_me(client, token=old_token), 401, "SESSION_REVOKED")


@pytest.mark.parametrize("state,code", [
    ("missing", "SESSION_REQUIRED"), ("fake", "SESSION_INVALID"),
    ("malformed", "SESSION_INVALID"), ("expired", "SESSION_EXPIRED"),
    ("revoked", "SESSION_REVOKED"), ("registration", "SESSION_INVALID"),
])
def test_me_requires_authenticated_live_cookie(h, client, state, code):
    if state == "registration":
        response = _verify(client, Account.create())
    else:
        _, response = _authenticated(client)
    token = _cookie(response, "gr_session").value
    if state == "missing":
        headers = {"Cookie": "unrelated=1"}
    elif state == "fake":
        headers = {"Cookie": "gr_session=" + "e2" * 32}
    elif state == "malformed":
        headers = {"Cookie": "gr_session=not-a-session"}
    else:
        headers = {"Cookie": "gr_session=" + token}
        if state == "expired":
            h.clock[0] = h.session(token).expires_at
        elif state == "revoked":
            with h.factory() as db, db.begin():
                db.execute(update(AuthSession).where(AuthSession.token_hash == _hash(token)).values(revoked_at=h.clock[0]))
    _error(client.get("/api/me", headers={"Origin": _ORIGIN} | headers), 401, code)


def test_me_ignores_identity_queries_and_only_returns_public_user(h, client):
    _, first = _authenticated(client, username="First Explorer")
    _, second = _authenticated(h.client(), username="Second Explorer")
    response = _me(client, user_id=second.json()["user"]["id"], wallet_address=second.json()["user"]["wallet_address"])
    assert response.status_code == 200
    assert set(response.json()) == {"user", "chain_id", "expires_at", "csrf_token"}
    assert response.json()["user"] == first.json()["user"]
    assert set(response.json()["user"]) == _PUBLIC_USER
    assert response.json()["chain_id"] == 31337
    assert response.headers["Cache-Control"] == "no-store"
    token = _cookie(first, "gr_session").value
    for secret in (token, _hash(token), h.config.csrf_secret.hex(), client.cookies.get("gr_auth_flow")):
        assert secret not in response.text


def test_query_or_bearer_token_does_not_replace_cookie(client):
    _, registered = _authenticated(client)
    token = _cookie(registered, "gr_session").value
    response = client.get("/api/me", params={"token": token}, headers={
        "Origin": _ORIGIN, "Cookie": "unrelated=1", "Authorization": "Bearer " + token,
    })
    _error(response, 401, "SESSION_REQUIRED")


@pytest.mark.parametrize("purpose", ["authenticated", "registration"])
def test_logout_revokes_authority_deletes_both_cookies_and_is_idempotent(h, client, purpose):
    response = _verify(client, Account.create())
    if purpose == "authenticated":
        response = _register(client, response)
        assert response.status_code == 201
    token = _cookie(response, "gr_session").value
    user_count = h.count(User)
    logout = client.post("/api/auth/logout", json={}, headers={
        "Origin": _ORIGIN, "X-CSRF-Token": response.json()["csrf_token"],
    })
    assert logout.status_code == 204 and logout.content == b""
    assert logout.headers["Cache-Control"] == "no-store"
    assert h.session(token).revoked_at == h.clock[0] and h.count(User) == user_count
    for name in ("gr_session", "gr_auth_flow"):
        cookie = _cookie(logout, name)
        assert cookie["max-age"] == "0" and cookie["path"] == "/api"
        assert cookie["httponly"] and cookie["samesite"] == "lax" and not cookie["secure"]
        assert not cookie["domain"] and name not in client.cookies
    _error(_me(client), 401, "SESSION_REQUIRED")
    # Both no-cookie and stale revoked-cookie logout are idempotent, no CSRF needed.
    for headers in ({"Origin": _ORIGIN}, {"Origin": _ORIGIN, "Cookie": "gr_session=" + token}):
        again = client.post("/api/auth/logout", json={}, headers=headers)
        assert again.status_code == 204 and again.content == b""


def test_authenticated_logout_rejects_csrf_and_preserves_session(h, client):
    _, registered = _authenticated(client)
    token = _cookie(registered, "gr_session").value
    _error(client.post("/api/auth/logout", json={}, headers={
        "Origin": _ORIGIN, "X-CSRF-Token": "wrong",
    }), 403, "CSRF_INVALID")
    assert h.session(token).revoked_at is None and _me(client).status_code == 200


@pytest.mark.parametrize("secure", [False, True])
def test_cookie_attributes_and_db_lifetime_for_all_authorities(h, wallet, secure):
    config = h.config if not secure else replace(
        h.config, siwe_domain="game.example", siwe_uri="https://game.example",
        cors_origins=("https://game.example",), cookie_secure=True,
    )
    client = h.client(config=config)
    headers = {"Origin": config.siwe_uri, "X-Gold-Rush-Auth": "1"}
    challenge = _challenge(client, wallet, headers=headers)
    grant = client.post("/api/auth/verify", json=_signed(wallet, challenge.json()), headers=headers)
    assert grant.status_code == 200
    registered = _register(client, grant, headers={"Origin": config.siwe_uri})
    assert registered.status_code == 201
    for response, name, lifetime in (
        (challenge, "gr_auth_flow", config.challenge_ttl_seconds),
        (grant, "gr_session", config.registration_ttl_seconds),
        (registered, "gr_session", config.session_ttl_seconds),
    ):
        cookie = _cookie(response, name)
        assert cookie["httponly"] and bool(cookie["secure"]) is secure
        assert cookie["samesite"] == "lax" and cookie["path"] == "/api" and not cookie["domain"]
        assert int(cookie["max-age"]) == lifetime
        expires = datetime.fromisoformat(response.json()["expires_at"])
        assert parsedate_to_datetime(cookie["expires"]) <= expires
        assert 0 <= (expires - parsedate_to_datetime(cookie["expires"])).total_seconds() < 1
        assert response.headers["Cache-Control"] == "no-store"
    logout = client.post("/api/auth/logout", json={}, headers={
        "Origin": config.siwe_uri, "X-CSRF-Token": registered.json()["csrf_token"],
    })
    assert logout.status_code == 204
    assert bool(_cookie(logout, "gr_session")["secure"]) is secure


@pytest.mark.parametrize("step", ["challenge", "verify", "register", "logout"])
def test_commit_failure_returns_no_success_cookie_and_rolls_back(h, client, wallet, step):
    headers = dict(_BOOTSTRAP)
    if step == "challenge":
        payload = {"wallet_address": wallet.address, "chain_id": 31337}
    elif step == "verify":
        challenge = _challenge(client, wallet).json()
        payload = _signed(wallet, challenge)
    else:
        grant = _verify(client, wallet)
        token = _cookie(grant, "gr_session").value
        headers["X-CSRF-Token"] = grant.json()["csrf_token"]
        payload = {"username": "Explorer"} if step == "register" else {}
    before = (h.count(User), h.count(AuthSession), h.count(AuthChallenge))
    synthetic_secret = "synthetic-sensitive-commit-error"

    def fail_writing_commit(db):
        # Lookups may commit too. Fail after real writes have been flushed;
        # SQLite total_changes includes the current transaction's modifications.
        raw = db.connection().connection.driver_connection
        if raw.total_changes > initial_changes.get(id(raw), raw.total_changes):
            raise RuntimeError(synthetic_secret)

    initial_changes = {}

    def baseline(connection, record, proxy):
        initial_changes[id(connection)] = connection.total_changes

    event.listen(h.engine, "checkout", baseline)
    event.listen(Session, "before_commit", fail_writing_commit)
    try:
        response = client.post("/api/auth/" + step, headers=headers, json=payload)
    finally:
        event.remove(Session, "before_commit", fail_writing_commit)
        event.remove(h.engine, "checkout", baseline)
    _error(response, 503, "AUTH_UNAVAILABLE")
    assert synthetic_secret not in response.text
    assert before == (h.count(User), h.count(AuthSession), h.count(AuthChallenge))
    if step == "verify":
        assert h.challenge(challenge["challenge_id"]).consumed_at is None
    elif step in {"register", "logout"}:
        assert h.session(token).revoked_at is None
    assert h.engine.pool.checkedout() == 0


def test_request_sessions_are_fresh_and_closed_on_success_and_failure(h, client, wallet):
    _authenticated(client, wallet)
    assert _me(client).status_code == 200
    _error(_me(client, token="d3" * 32), 401, "SESSION_INVALID")
    assert h.sessions and len({id(db) for db in h.sessions}) == len(h.sessions)
    assert h.engine.pool.checkedout() == 0
    for db in h.sessions:
        assert not db.in_transaction()
        with pytest.raises(InvalidRequestError):
            db.execute(text("SELECT 1"))


@pytest.mark.parametrize("mode", ["declared", "false_length", "chunked"])
def test_body_limit_enforced_before_validation(h, client, mode):
    body = b'{"wallet_address":"' + b"a" * 8300 + b'","chain_id":31337}'
    headers = _BOOTSTRAP | {"Content-Type": "application/json"}
    content = body
    if mode == "false_length":
        headers["Content-Length"] = "1"
    elif mode == "chunked":
        content = iter([body[:4000], body[4000:]])
    _error(client.post("/api/auth/challenge", headers=headers, content=content), 413, "BODY_TOO_LARGE")
    assert h.count(AuthChallenge) == 0


@pytest.mark.parametrize("encoding", ["gzip", "br"])
def test_compressed_body_rejected(client, wallet, encoding):
    response = client.post("/api/auth/challenge", headers=_BOOTSTRAP | {"Content-Encoding": encoding},
                           json={"wallet_address": wallet.address, "chain_id": 31337})
    _error(response, 415, "ENCODING_NOT_SUPPORTED")


@pytest.mark.parametrize("body,content_type,status", [
    ("{}", "text/plain", 415), ("{}", "application/x-www-form-urlencoded", 415),
    ("{invalid-json", "application/json", 422),
])
def test_logout_requires_json_transport_and_valid_object(client, body, content_type, status):
    response = client.post("/api/auth/logout", headers={"Origin": _ORIGIN, "Content-Type": content_type}, content=body)
    _error(response, status)


def test_errors_do_not_echo_signature_message_key_or_config_secret(h, client, wallet, capsys, caplog):
    challenge = _challenge(client, wallet).json()
    payload = _signed(wallet, challenge)
    marker = "attacker-sensitive-field-name"
    payload[marker] = "attacker-sensitive-value"
    response = client.post("/api/auth/verify", json=payload, headers=_BOOTSTRAP)
    _error(response, 422, "INVALID_REQUEST")
    captured = capsys.readouterr()
    output = response.text + captured.out + captured.err + caplog.text
    for value in (payload["signature"], payload["message"], wallet.key.hex(), marker,
                  payload[marker], h.config.csrf_secret.hex(), h.config.database_url):
        assert value not in output


def test_explicit_test_app_cors_credentials_and_preflight(h):
    client = h.client(cors=True)
    for origin, status in ((_ORIGIN, 200), ("https://evil.example", 400)):
        response = client.options("/api/auth/challenge", headers={
            "Origin": origin, "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "Content-Type,X-Gold-Rush-Auth",
        })
        assert response.status_code == status
        assert response.headers.get("Access-Control-Allow-Origin") == (_ORIGIN if status == 200 else None)
        assert response.headers.get("Access-Control-Allow-Origin") != "*"
    assert h.count(AuthChallenge) == h.count(AuthSession) == 0
    _, registered = _authenticated(client)
    response = _me(client)
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == _ORIGIN
    assert response.headers["Access-Control-Allow-Credentials"] == "true"
    assert response.json()["user"] == registered.json()["user"]
