"""Auth business flows on migrated temporary SQLite files, entirely offline.

Run from gold_rush_ai: python -m pytest tests/test_auth_service.py -q
Each test owns its file/Engine and uses fresh Sessions. Concurrency tests use
barriers before SQL execution and independent DBAPI connections, never sleep
or :memory:. They do not prove PostgreSQL/multiprocess or HTTP protection.
Only ephemeral eth-account wallets are used; no real keys/cookies/.env files.
"""
from __future__ import annotations

import hashlib
import importlib.util
import io
import os
import re
import secrets
import socket
import sqlite3
import sys
import traceback
from collections.abc import Callable, Iterator
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from threading import Barrier, Lock, get_ident
from types import MappingProxyType
from unittest.mock import Mock, patch
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from eth_account import Account
from eth_account.messages import encode_defunct
from pydantic import SecretStr
from sqlalchemy import MetaData, event, func, select, update
from sqlalchemy.engine import Engine, URL
from sqlalchemy.orm import Session

from auth import service
from auth.config import AuthConfig
from auth.database import create_auth_engine, create_session_factory
from auth.models import AuthChallenge, AuthSession, GameRunOwner, User
from auth.schemas import AuthenticatedResponse, RegistrationRequiredResponse
from auth.siwe import parse_siwe_message


_BACKEND = Path(__file__).resolve().parents[1]


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def _cookie(issue: service.SessionIssue) -> str:
    return issue.cookie_token.get_secret_value()


@dataclass
class _Clock:
    value: datetime

    def __call__(self) -> datetime:
        return self.value


@dataclass(repr=False)
class _Flow:
    wallet: object
    challenge: object
    signature: str
    binding: str

    def request(self) -> dict:
        return {
            "challenge_id": self.challenge.challenge_id, "message": self.challenge.message,
            "signature": self.signature, "browser_binding": self.binding,
        }


@dataclass(repr=False)
class _Harness:
    config: AuthConfig
    engine: Engine
    factory: Callable[[], Session]
    clock: _Clock
    svc: service.AuthService
    sessions: list[Session] = field(repr=False)

    def flow(self, wallet=None, *, chain_id=31337, binding=None) -> _Flow:
        wallet = wallet if wallet is not None else Account.create()
        binding = binding if binding is not None else service.new_browser_binding().get_secret_value()
        challenge = self.svc.create_challenge(
            wallet_address=wallet.address, chain_id=chain_id, browser_binding=binding,
        )
        signature = "0x" + wallet.sign_message(encode_defunct(text=challenge.message)).signature.hex()
        return _Flow(wallet, challenge, signature, binding)

    def grant(self, wallet=None):
        flow = self.flow(wallet)
        return flow, self.svc.verify(**flow.request())

    def register_user(self, username="Explorer", wallet=None):
        flow, grant = self.grant(wallet)
        issue = self.svc.register(registration_token=_cookie(grant), username=username)
        return flow, grant, issue

    def count(self, model) -> int:
        with self.factory() as db:
            return db.scalar(select(func.count()).select_from(model))

    def challenge_row(self, identifier: UUID) -> dict:
        with self.factory() as db:
            return dict(db.execute(select(AuthChallenge.__table__).where(AuthChallenge.id == identifier)).mappings().one())

    def session_row(self, token: str) -> dict:
        with self.factory() as db:
            return dict(db.execute(select(AuthSession.__table__).where(AuthSession.token_hash == _hash(token))).mappings().one())

    def at(self, moment: datetime) -> service.AuthService:
        return service.AuthService(self.config, self.factory, clock=lambda: moment)


@pytest.fixture(autouse=True)
def isolated_io(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    blocked = Mock(side_effect=AssertionError("Service tests forbid network and metadata.create_all."))
    for name in ("create_connection", "getaddrinfo"):
        monkeypatch.setattr(socket, name, blocked)
    for name in ("connect", "connect_ex"):
        monkeypatch.setattr(socket.socket, name, blocked)
    monkeypatch.setattr(MetaData, "create_all", blocked)
    original_connect = sqlite3.dbapi2.connect
    connections: list[sqlite3.Connection] = []

    def connect(database, *args, **kwargs):
        path = Path(database)
        assert path.is_absolute() and path.resolve().is_relative_to(tmp_path.resolve()), (
            "SQLite connection outside this test's tmp_path is forbidden."
        )
        connection = original_connect(database, *args, **kwargs)
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
def h(tmp_path: Path) -> Iterator[_Harness]:
    path = (tmp_path / "auth-service.sqlite3").resolve()
    config = AuthConfig(
        csrf_secret=secrets.token_bytes(32),
        database_url=URL.create("sqlite", database=str(path)).render_as_string(),
        allowed_chain_ids=(31337, 11155111),
    )
    environment = {"AUTH_DATABASE_URL": config.database_url, "AUTH_CSRF_SECRET": config.csrf_secret.hex()}
    # Substitute the mapping, not the user's real os.environ contents. Also
    # avoid env.py reconfiguring the process-wide pytest logging handlers.
    with patch.object(os, "environ", environment), patch("logging.config.fileConfig"):
        command.upgrade(Config(str(_BACKEND / "alembic.ini"), stdout=io.StringIO()), "head")
    engine = create_auth_engine(config)
    maker = create_session_factory(engine)
    sessions: list[Session] = []

    def factory():
        session = maker()
        sessions.append(session)
        return session

    clock = _Clock(datetime(2026, 11, 8, 3, 0, 0, 123456, tzinfo=UTC))
    try:
        yield _Harness(config, engine, factory, clock, service.AuthService(config, factory, clock=clock), sessions)
    finally:
        checked_out = engine.pool.checkedout()
        engine.dispose()
        assert checked_out == 0, "Service retained checked-out connections."
        assert all(not session.in_transaction() for session in sessions)


@contextmanager
def _failing_commit(h: _Harness, transaction_number: int, failure_text="TEST_COMMIT_FAILURE"):
    calls = 0

    def factory():
        nonlocal calls
        calls += 1
        session = h.factory()
        session.info["auth_test_fail_commit"] = calls == transaction_number
        return session

    def fail(session):
        if session.info.get("auth_test_fail_commit"):
            raise RuntimeError(failure_text)

    event.listen(Session, "before_commit", fail)
    try:
        yield service.AuthService(h.config, factory, clock=h.clock)
    finally:
        event.remove(Session, "before_commit", fail)


def _race(h: _Harness, table: str, actions: list[Callable]):
    """Both workers own a connection before either attempts its claim UPDATE."""
    barrier = Barrier(2)
    lock = Lock()
    attempts, rowcounts = [], []
    prefix = f"UPDATE {table} ".upper()

    def before(connection, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith(prefix):
            with lock:
                attempts.append((get_ident(), id(connection.connection.dbapi_connection)))
            barrier.wait(timeout=10)

    def after(connection, cursor, statement, parameters, context, many):
        if statement.lstrip().upper().startswith(prefix):
            with lock:
                rowcounts.append(cursor.rowcount)

    def run(action):
        try:
            return "ok", action()
        except service.AuthServiceError as error:
            return "error", error.code

    start = len(h.sessions)
    event.listen(h.engine, "before_cursor_execute", before)
    event.listen(h.engine, "after_cursor_execute", after)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(run, actions))
    finally:
        event.remove(h.engine, "before_cursor_execute", before)
        event.remove(h.engine, "after_cursor_execute", after)
    assert len(attempts) == 2
    assert len({thread for thread, connection in attempts}) == 2
    assert len({connection for thread, connection in attempts}) == 2
    used_sessions = h.sessions[start:]
    assert len(used_sessions) >= 2 and len({id(session) for session in used_sessions}) == len(used_sessions)
    return outcomes, sorted(rowcounts)


def test_import_has_no_database_network_or_auth_env_io(tmp_path, monkeypatch) -> None:
    name = "auth._service_import_test"
    spec = importlib.util.spec_from_file_location(name, service.__file__)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    blocked = Mock(side_effect=AssertionError("Import must not create Database, session or credentials."))
    with monkeypatch.context() as local:
        local.setitem(sys.modules, name, module)
        local.setattr(sys, "dont_write_bytecode", True)
        local.setattr(os, "environ", MappingProxyType({}))
        local.setattr(Engine, "connect", blocked)
        local.setattr(Session, "__init__", blocked)
        local.setattr(secrets, "token_hex", blocked)
        local.chdir(tmp_path)
        spec.loader.exec_module(module)
    blocked.assert_not_called()
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("chain_id", [31337, 11155111])
def test_challenge_stores_canonical_siwe_and_hashed_browser_binding(h, chain_id) -> None:
    flow = h.flow(chain_id=chain_id)
    row = h.challenge_row(flow.challenge.challenge_id)
    parsed = parse_siwe_message(row["message"], config=h.config)
    assert isinstance(row["id"], UUID) and row["wallet_address"] == flow.wallet.address.lower()
    assert parsed.wallet_address == flow.wallet.address and parsed.chain_id == chain_id
    assert parsed.domain == h.config.siwe_domain and parsed.uri == h.config.siwe_uri
    assert row["message"] == flow.challenge.message
    assert row["issued_at"] == h.clock.value
    assert row["expires_at"] == h.clock.value + timedelta(seconds=h.config.challenge_ttl_seconds)
    assert row["consumed_at"] is None
    assert row["browser_binding_hash"] == _hash(flow.binding) != flow.binding
    assert h.count(User) == h.count(AuthSession) == 0


def test_challenges_have_independent_secure_nonces(h, monkeypatch) -> None:
    random_hex = Mock(wraps=secrets.token_hex)
    monkeypatch.setattr(service.secrets, "token_hex", random_hex)
    first = h.flow()
    second = h.flow(first.wallet, binding=first.binding)
    left, right = h.challenge_row(first.challenge.challenge_id), h.challenge_row(second.challenge.challenge_id)
    assert left["id"] != right["id"] and left["nonce"] != right["nonce"]
    assert all(re.fullmatch(r"[0-9a-f]{32}", row["nonce"]) for row in (left, right))
    assert sum(call.args == (16,) for call in random_hex.call_args_list) == 2


@pytest.mark.parametrize("field,value,code", [
    ("wallet_address", "bad", "WALLET_INVALID"), ("wallet_address", "0x" + "g" * 40, "WALLET_INVALID"),
    ("chain_id", 1, "CHAIN_NOT_ALLOWED"), ("chain_id", True, "CHAIN_NOT_ALLOWED"),
    ("chain_id", 0, "CHAIN_NOT_ALLOWED"), ("chain_id", "31337", "CHAIN_NOT_ALLOWED"),
    ("browser_binding", "bad", "BROWSER_BINDING_INVALID"),
])
def test_invalid_challenge_request_cannot_issue_access(h, field, value, code) -> None:
    args = {"wallet_address": Account.create().address, "chain_id": 31337,
            "browser_binding": service.new_browser_binding().get_secret_value()}
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.create_challenge(**(args | {field: value}))
    assert error.value.code == code
    assert h.count(AuthChallenge) == h.count(User) == h.count(AuthSession) == 0


def test_valid_signature_issues_registration_grant_not_authenticated_session(h) -> None:
    flow, issue = h.grant()
    row = h.session_row(_cookie(issue))
    assert isinstance(issue.response, RegistrationRequiredResponse)
    assert row["purpose"] == "registration" and row["user_id"] is None
    assert row["wallet_address"] == flow.wallet.address.lower() and row["chain_id"] == 31337
    assert row["expires_at"] == h.clock.value + timedelta(seconds=h.config.registration_ttl_seconds)
    assert h.count(User) == 0 and h.count(AuthSession) == 1
    assert h.svc.get_registration_grant(_cookie(issue)).wallet_address == flow.wallet.address.lower()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.get_authenticated_session(_cookie(issue))
    assert error.value.code == "SESSION_INVALID"


@pytest.mark.parametrize("attack,code", [
    ("other_signer", "SIGNER_MISMATCH"), ("signature_format", "SIGNATURE_INVALID"),
    ("message_nonce", "MESSAGE_MISMATCH"), ("message_chain", "MESSAGE_MISMATCH"),
    ("message_domain", "MESSAGE_INVALID"), ("message_uri", "MESSAGE_INVALID"),
    ("browser_binding", "BROWSER_BINDING_INVALID"), ("missing_challenge", "CHALLENGE_NOT_FOUND"),
])
def test_invalid_verify_does_not_consume_challenge_or_issue_session(h, attack, code) -> None:
    flow = h.flow()
    args = flow.request()
    if attack == "other_signer":
        args["signature"] = "0x" + Account.create().sign_message(encode_defunct(text=args["message"])).signature.hex()
    elif attack == "signature_format":
        args["signature"] = "TEST_INVALID_SIGNATURE"
    elif attack == "message_nonce":
        nonce = h.challenge_row(flow.challenge.challenge_id)["nonce"]
        args["message"] = args["message"].replace(nonce, "A" + nonce[1:])
    elif attack == "message_chain":
        args["message"] = args["message"].replace("Chain ID: 31337", "Chain ID: 11155111")
    elif attack == "message_domain":
        args["message"] = args["message"].replace("localhost:5000 wants", "evil.invalid wants")
    elif attack == "message_uri":
        args["message"] = args["message"].replace("URI: http://localhost:5000", "URI: http://localhost:5000/other")
    elif attack == "browser_binding":
        args["browser_binding"] = secrets.token_hex(32)
    else:
        args["challenge_id"] = uuid4()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.verify(**args)
    assert error.value.code == code
    assert h.challenge_row(flow.challenge.challenge_id)["consumed_at"] is None
    assert h.count(AuthSession) == h.count(User) == 0


def test_expired_challenge_cannot_be_consumed(h) -> None:
    flow = h.flow()
    with pytest.raises(service.AuthServiceError) as error:
        h.at(flow.challenge.expires_at).verify(**flow.request())
    assert error.value.code == "CHALLENGE_EXPIRED"
    assert h.challenge_row(flow.challenge.challenge_id)["consumed_at"] is None
    assert h.count(AuthSession) == 0


def test_challenge_is_consumed_once_and_only_target_row_changes(h) -> None:
    first, second = h.flow(), h.flow()
    h.svc.verify(**first.request())
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.verify(**first.request())
    assert error.value.code == "CHALLENGE_USED"
    assert h.challenge_row(first.challenge.challenge_id)["consumed_at"] == h.clock.value
    assert h.challenge_row(second.challenge.challenge_id)["consumed_at"] is None
    assert h.count(AuthSession) == 1


@pytest.mark.parametrize("existing_user", [False, True])
def test_concurrent_verifies_have_one_conditional_update_winner(h, existing_user) -> None:
    if existing_user:
        prior_flow, prior_grant, prior_session = h.register_user()
        flow = h.flow(prior_flow.wallet)
    else:
        flow = h.flow()
    before = h.count(AuthSession)
    outcomes, rowcounts = _race(h, "auth_challenges", [
        lambda: h.svc.verify(**flow.request()), lambda: h.svc.verify(**flow.request()),
    ])
    assert [value for kind, value in outcomes if kind == "error"] == ["CHALLENGE_USED"]
    winners = [value for kind, value in outcomes if kind == "ok"]
    assert len(winners) == 1 and rowcounts == [0, 1]
    assert winners[0].response.status == ("authenticated" if existing_user else "registration_required")
    assert h.count(AuthSession) == before + 1
    assert h.challenge_row(flow.challenge.challenge_id)["consumed_at"] == h.clock.value


def test_signed_snapshot_changed_after_crypto_cannot_be_claimed(h, monkeypatch) -> None:
    flow = h.flow()
    original = service.verify_siwe_signature

    def mutate(*args, **kwargs):
        signer = original(*args, **kwargs)
        with h.factory() as db, db.begin():
            db.execute(update(AuthChallenge).where(AuthChallenge.id == flow.challenge.challenge_id).values(nonce="changednonce0001"))
        return signer

    monkeypatch.setattr(service, "verify_siwe_signature", mutate)
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.verify(**flow.request())
    assert error.value.code == "CHALLENGE_INVALID"
    assert h.challenge_row(flow.challenge.challenge_id)["consumed_at"] is None
    assert h.count(AuthSession) == 0


def test_expiry_after_claim_rolls_back_nonce(h) -> None:
    flow = h.flow()
    times = iter([h.clock.value, h.clock.value, h.clock.value, flow.challenge.expires_at])
    expiring = service.AuthService(h.config, h.factory, clock=lambda: next(times))
    with pytest.raises(service.AuthServiceError) as error:
        expiring.verify(**flow.request())
    assert error.value.code == "CHALLENGE_EXPIRED"
    assert h.challenge_row(flow.challenge.challenge_id)["consumed_at"] is None
    assert h.count(AuthSession) == 0


def test_registration_creates_normalized_user_and_rotates_credentials(h) -> None:
    flow, grant = h.grant()
    issue = h.svc.register(registration_token=_cookie(grant), username="  Đa\u0323t   123  ")
    assert isinstance(issue.response, AuthenticatedResponse)
    user = issue.response.user
    assert isinstance(user.id, UUID) and user.wallet_address == flow.wallet.address.lower()
    assert user.username == "Đạt 123" and user.avatar == "george" and user.created_at == h.clock.value
    with h.factory() as db:
        stored = db.get(User, user.id)
        assert stored.username_key == "đạt 123"
    assert h.session_row(_cookie(grant))["revoked_at"] == h.clock.value
    assert h.session_row(_cookie(issue))["purpose"] == "authenticated"
    assert h.session_row(_cookie(issue))["user_id"] == user.id
    assert _cookie(issue) != _cookie(grant) and issue.response.csrf_token != grant.response.csrf_token


@pytest.mark.parametrize("token", [None, "bad", "f" * 64])
def test_unverified_cookie_cannot_register(h, token) -> None:
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.register(registration_token=token, username="Explorer")
    assert error.value.code == "GRANT_INVALID"
    assert h.count(User) == h.count(AuthSession) == 0


def test_browser_binding_cookie_is_not_registration_grant(h) -> None:
    flow = h.flow()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.register(registration_token=flow.binding, username="Explorer")
    assert error.value.code == "GRANT_INVALID"
    assert h.count(User) == h.count(AuthSession) == 0


@pytest.mark.parametrize("username", ["ab", "x" * 21, "bad😀", "---", None])
def test_invalid_username_preserves_registration_grant(h, username) -> None:
    flow, grant = h.grant()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.register(registration_token=_cookie(grant), username=username)
    assert error.value.code == "USERNAME_INVALID"
    assert h.session_row(_cookie(grant))["revoked_at"] is None
    assert h.count(User) == 0 and h.count(AuthSession) == 1


def test_duplicate_casefolded_username_preserves_grant_for_retry(h) -> None:
    h.register_user("Đạt")
    flow, grant = h.grant()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.register(registration_token=_cookie(grant), username="ĐẠT")
    assert error.value.code == "USERNAME_TAKEN"
    assert h.session_row(_cookie(grant))["revoked_at"] is None
    assert h.svc.get_registration_grant(_cookie(grant)).status == "registration_required"
    issue = h.svc.register(registration_token=_cookie(grant), username="Another Hero")
    assert issue.response.user.username == "Another Hero"
    assert h.count(User) == 2


def test_duplicate_wallet_requires_fresh_siwe_instead_of_second_user(h) -> None:
    wallet = Account.create()
    first_flow, first = h.grant(wallet)
    second_flow, second = h.grant(wallet)
    initial = h.svc.register(registration_token=_cookie(first), username="First Hero")
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.register(registration_token=_cookie(second), username="Second Hero")
    assert error.value.code == "WALLET_ALREADY_REGISTERED" and h.count(User) == 1
    fresh = h.flow(wallet)
    logged_in = h.svc.verify(**fresh.request())
    assert logged_in.response.user.id == initial.response.user.id


@pytest.mark.parametrize("state", ["expired", "revoked", "consumed"])
def test_invalid_registration_grant_cannot_create_another_account(h, state) -> None:
    flow, grant = h.grant()
    svc = h.svc
    if state == "expired":
        svc = h.at(grant.response.expires_at)
    elif state == "revoked":
        h.svc.logout(_cookie(grant))
    else:
        h.svc.register(registration_token=_cookie(grant), username="Original Hero")
    before = h.count(User), h.count(AuthSession)
    with pytest.raises(service.AuthServiceError) as error:
        svc.register(registration_token=_cookie(grant), username="Another Hero")
    assert error.value.code == ("GRANT_EXPIRED" if state == "expired" else "GRANT_INVALID")
    assert (h.count(User), h.count(AuthSession)) == before


@pytest.mark.parametrize("field", ["user_id", "wallet_address", "avatar", "is_admin", "permissions"])
def test_register_has_no_client_identity_or_permission_parameters(h, field) -> None:
    flow, grant = h.grant()
    with pytest.raises(TypeError):
        h.svc.register(**{"registration_token": _cookie(grant), "username": "Explorer", field: "TEST_INJECTION"})
    assert h.count(User) == 0 and h.session_row(_cookie(grant))["revoked_at"] is None


def test_concurrent_same_grant_creates_one_user_and_authenticated_session(h) -> None:
    flow, grant = h.grant()
    outcomes, rowcounts = _race(h, "auth_sessions", [
        lambda: h.svc.register(registration_token=_cookie(grant), username="First Racer"),
        lambda: h.svc.register(registration_token=_cookie(grant), username="Second Racer"),
    ])
    assert len([value for kind, value in outcomes if kind == "ok"]) == 1
    assert [value for kind, value in outcomes if kind == "error"] == ["GRANT_INVALID"]
    assert rowcounts == [0, 1] and h.count(User) == 1 and h.count(AuthSession) == 2


@pytest.mark.parametrize("conflict", ["wallet", "username"])
def test_concurrent_distinct_grants_respect_unique_user_constraints(h, conflict) -> None:
    wallet = Account.create()
    left_flow, left = h.grant(wallet)
    right_flow, right = h.grant(wallet if conflict == "wallet" else None)
    names = ["First Racer", "Second Racer"] if conflict == "wallet" else ["Shared Hero", "Shared Hero"]
    tokens = [_cookie(left), _cookie(right)]
    outcomes, rowcounts = _race(h, "auth_sessions", [
        lambda: h.svc.register(registration_token=tokens[0], username=names[0]),
        lambda: h.svc.register(registration_token=tokens[1], username=names[1]),
    ])
    assert len([value for kind, value in outcomes if kind == "ok"]) == 1
    assert [value for kind, value in outcomes if kind == "error"] == [
        "WALLET_ALREADY_REGISTERED" if conflict == "wallet" else "USERNAME_TAKEN",
    ]
    assert rowcounts == [1, 1] and h.count(User) == 1 and h.count(AuthSession) == 3
    loser_index = next(index for index, outcome in enumerate(outcomes) if outcome[0] == "error")
    assert h.session_row(tokens[loser_index])["revoked_at"] is None
    if conflict == "username":
        assert h.svc.register(registration_token=tokens[loser_index], username="Name Retry").response.status == "authenticated"


def test_registered_wallet_login_preserves_identity_and_issues_fresh_session(h) -> None:
    flow, grant, first = h.register_user()
    fresh = h.flow(flow.wallet, chain_id=11155111)
    second = h.svc.verify(**fresh.request())
    assert isinstance(second.response, AuthenticatedResponse)
    assert second.response.user.id == first.response.user.id and h.count(User) == 1
    row = h.session_row(_cookie(second))
    assert row["user_id"] == first.response.user.id and row["chain_id"] == 11155111
    assert row["expires_at"] == h.clock.value + timedelta(seconds=h.config.session_ttl_seconds)
    assert h.svc.get_authenticated_session(_cookie(second)).chain_id == 11155111
    assert _cookie(first) != _cookie(second)


def test_different_registered_wallets_get_unique_ids_and_own_profiles(h) -> None:
    left_flow, left_grant, left = h.register_user("Left Hero")
    right_flow, right_grant, right = h.register_user("Right Hero")
    assert left.response.user.id != right.response.user.id
    assert h.svc.get_authenticated_session(_cookie(left)).user.id == left.response.user.id
    assert h.svc.get_authenticated_session(_cookie(right)).user.id == right.response.user.id
    with pytest.raises(TypeError):
        h.svc.get_authenticated_session(_cookie(left), user_id=right.response.user.id)


def test_session_tokens_are_secure_random_hash_only_credentials(h, monkeypatch) -> None:
    random_hex = Mock(wraps=secrets.token_hex)
    monkeypatch.setattr(service.secrets, "token_hex", random_hex)
    first_flow, first = h.grant()
    second_flow, second = h.grant()
    tokens = [_cookie(first), _cookie(second)]
    assert tokens[0] != tokens[1]
    assert all(re.fullmatch(r"[0-9a-f]{64}", token) for token in tokens)
    assert any(call.args == (32,) for call in random_hex.call_args_list)
    for token in tokens:
        row = h.session_row(token)
        assert row["token_hash"] == _hash(token) != token
        assert token not in str(row)


@pytest.mark.parametrize("fake", [None, "bad", "f" * 64])
def test_fake_session_cookie_does_not_access_profile(h, fake) -> None:
    h.register_user()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.get_authenticated_session(fake)
    assert error.value.code == "SESSION_INVALID"


def test_database_token_hash_cannot_be_used_as_cookie(h) -> None:
    flow, grant, issue = h.register_user()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.get_authenticated_session(h.session_row(_cookie(issue))["token_hash"])
    assert error.value.code == "SESSION_INVALID"


@pytest.mark.parametrize("state", ["expired", "revoked"])
def test_expired_or_revoked_session_is_rejected(h, state) -> None:
    flow, grant, issue = h.register_user()
    svc = h.at(issue.response.expires_at) if state == "expired" else h.svc
    if state == "revoked":
        h.svc.logout(_cookie(issue))
    with pytest.raises(service.AuthServiceError) as error:
        svc.get_authenticated_session(_cookie(issue))
    assert error.value.code == ("SESSION_EXPIRED" if state == "expired" else "SESSION_REVOKED")


def test_authenticated_session_cannot_be_used_as_registration_grant(h) -> None:
    flow, grant, issue = h.register_user()
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.get_registration_grant(_cookie(issue))
    assert error.value.code == "GRANT_INVALID"


def test_session_wallet_must_match_linked_user(h) -> None:
    left_flow, left_grant, left = h.register_user("Left Hero")
    right_flow, right_grant, right = h.register_user("Right Hero")
    with h.factory() as db, db.begin():
        db.execute(update(AuthSession).where(AuthSession.token_hash == _hash(_cookie(left))).values(wallet_address=right_flow.wallet.address.lower()))
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.get_authenticated_session(_cookie(left))
    assert error.value.code == "SESSION_INVALID"


def test_fresh_verify_revokes_previous_cookie_atomically(h) -> None:
    flow, grant, old = h.register_user()
    fresh = h.flow(flow.wallet)
    issue = h.svc.verify(**fresh.request(), previous_session_token=_cookie(old))
    assert h.session_row(_cookie(old))["revoked_at"] == h.clock.value
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.get_authenticated_session(_cookie(old))
    assert error.value.code == "SESSION_REVOKED"
    assert h.svc.get_authenticated_session(_cookie(issue)).user.id == old.response.user.id


def test_logout_is_idempotent_and_preserves_user_and_game_owner(h) -> None:
    flow, grant, issue = h.register_user()
    with h.factory() as db, db.begin():
        db.add(GameRunOwner(ma_van="logout-run-0001", user_id=issue.response.user.id, created_at=h.clock.value))
    for token in (_cookie(issue), _cookie(issue), None, "bad", "f" * 64):
        assert h.svc.logout(token) is None
    assert h.count(User) == h.count(GameRunOwner) == 1
    assert h.session_row(_cookie(issue))["revoked_at"] == h.clock.value
    with pytest.raises(service.AuthServiceError):
        h.svc.get_authenticated_session(_cookie(issue))


def test_logout_revokes_registration_grant(h) -> None:
    flow, grant = h.grant()
    h.svc.logout(_cookie(grant))
    assert h.session_row(_cookie(grant))["revoked_at"] == h.clock.value
    with pytest.raises(service.AuthServiceError) as error:
        h.svc.get_registration_grant(_cookie(grant))
    assert error.value.code == "GRANT_INVALID" and h.count(User) == 0


def test_verify_commit_failure_rolls_back_claim_session_and_old_cookie_revoke(h) -> None:
    old_flow, old_grant, old = h.register_user()
    fresh = h.flow(old_flow.wallet)
    count = h.count(AuthSession)
    with _failing_commit(h, 2) as failing:
        with pytest.raises(service.AuthServiceError) as error:
            failing.verify(**fresh.request(), previous_session_token=_cookie(old))
    assert error.value.code == "DATABASE_ERROR"
    assert h.challenge_row(fresh.challenge.challenge_id)["consumed_at"] is None
    assert h.count(AuthSession) == count and h.session_row(_cookie(old))["revoked_at"] is None
    assert h.svc.get_authenticated_session(_cookie(old)).user.id == old.response.user.id
    assert h.svc.verify(**fresh.request()).response.status == "authenticated"


def test_registration_commit_failure_restores_grant_and_removes_partial_user_session(h) -> None:
    flow, grant = h.grant()
    with _failing_commit(h, 1) as failing:
        with pytest.raises(service.AuthServiceError) as error:
            failing.register(registration_token=_cookie(grant), username="Rollback Hero")
    assert error.value.code == "DATABASE_ERROR"
    assert h.count(User) == 0 and h.count(AuthSession) == 1
    assert h.session_row(_cookie(grant))["revoked_at"] is None
    assert h.svc.register(registration_token=_cookie(grant), username="Rollback Hero").response.status == "authenticated"


def test_real_unique_failure_after_user_flush_rolls_back_entire_registration(h, monkeypatch) -> None:
    existing_flow, existing = h.grant()
    flow, grant = h.grant()
    with monkeypatch.context() as local:
        local.setattr(service.secrets, "token_hex", lambda size: _cookie(existing))
        with pytest.raises(service.AuthServiceError) as error:
            h.svc.register(registration_token=_cookie(grant), username="Collision Hero")
    assert error.value.code == "DATABASE_CONFLICT"
    assert h.count(User) == 0 and h.count(AuthSession) == 2
    assert h.session_row(_cookie(grant))["revoked_at"] is None


def test_expired_grant_after_claim_rolls_back_revoke(h) -> None:
    flow, grant = h.grant()
    times = iter([h.clock.value, grant.response.expires_at])
    expiring = service.AuthService(h.config, h.factory, clock=lambda: next(times))
    with pytest.raises(service.AuthServiceError) as error:
        expiring.register(registration_token=_cookie(grant), username="Expired Hero")
    assert error.value.code == "GRANT_EXPIRED"
    assert h.session_row(_cookie(grant))["revoked_at"] is None
    assert h.count(User) == 0 and h.count(AuthSession) == 1


def test_csrf_hmac_is_bound_to_exact_cookie_and_config_secret(h) -> None:
    left_flow, left_grant, left = h.register_user("Left Hero")
    right_flow, right_grant, right = h.register_user("Right Hero")
    csrf = left.response.csrf_token
    assert h.svc.verify_csrf_token(_cookie(left), csrf)
    assert not h.svc.verify_csrf_token(_cookie(right), csrf)
    assert not h.svc.verify_csrf_token(_cookie(left), ("0" if csrf[0] != "0" else "1") + csrf[1:])
    other = service.AuthService(replace(h.config, csrf_secret=secrets.token_bytes(32)), h.factory, clock=h.clock)
    assert not other.verify_csrf_token(_cookie(left), csrf)


@pytest.mark.parametrize("token,csrf", [(None, None), ("bad", "f" * 64), ("f" * 64, "bad"), ("f" * 64, "x\r\ny"), ("f" * 64, "á" * 64)])
def test_csrf_malformed_values_fail_closed(h, token, csrf) -> None:
    assert h.svc.verify_csrf_token(token, csrf) is False


@pytest.mark.parametrize("state", ["expired", "revoked"])
def test_csrf_check_does_not_replace_session_lifetime_or_revocation_checks(h, state) -> None:
    flow, grant, issue = h.register_user()
    svc = h.at(issue.response.expires_at) if state == "expired" else h.svc
    if state == "revoked":
        h.svc.logout(_cookie(issue))
    # The helper is a pure HMAC check. Dependencies must check session AND Origin.
    assert svc.verify_csrf_token(_cookie(issue), issue.response.csrf_token)
    with pytest.raises(service.AuthServiceError):
        svc.get_authenticated_session(_cookie(issue))


def test_credentials_are_masked_or_excluded_from_reprs_json_and_errors(h, caplog) -> None:
    flow, grant = h.grant()
    token = _cookie(grant)
    assert isinstance(grant.cookie_token, SecretStr)
    for value in (grant, grant.cookie_token, h.svc):
        assert token not in repr(value) and h.config.csrf_secret.hex() not in repr(value)
    assert "cookie_token" not in grant.model_dump() and token not in grant.model_dump_json()
    assert token not in grant.model_dump_json(include={"cookie_token"})
    marker = "TEST_INTERNAL_FAILURE"
    detail = marker + token + flow.signature + flow.wallet.key.hex() + h.config.csrf_secret.hex()
    with _failing_commit(h, 1, detail) as failing:
        with pytest.raises(service.AuthServiceError) as caught:
            failing.register(registration_token=token, username="Error Hero")
    formatted = str(caught.value) + repr(caught.value) + "".join(traceback.format_exception(caught.value)) + caplog.text
    for secret in (marker, token, flow.signature, flow.wallet.key.hex(), h.config.csrf_secret.hex()):
        assert secret not in formatted


def test_no_raw_cookie_binding_key_or_csrf_secret_saved_in_database(h) -> None:
    flow, grant, issue = h.register_user()
    with h.factory() as db:
        dump = "".join(str(db.execute(select(table)).all()) for table in (User.__table__, AuthSession.__table__, AuthChallenge.__table__))
    for secret in (_cookie(grant), _cookie(issue), flow.binding, flow.wallet.key.hex(), h.config.csrf_secret.hex()):
        assert secret not in dump


def test_injected_config_does_not_read_or_modify_user_environment(h, monkeypatch) -> None:
    caller_env = {"AUTH_DATABASE_URL": "TEST_CALLER_DATABASE", "AUTH_CSRF_SECRET": "TEST_CALLER_SECRET"}
    monkeypatch.setattr(os, "environ", caller_env)
    flow = h.flow()
    assert h.svc.verify(**flow.request()).response.status == "registration_required"
    assert os.environ is caller_env
    assert caller_env == {"AUTH_DATABASE_URL": "TEST_CALLER_DATABASE", "AUTH_CSRF_SECRET": "TEST_CALLER_SECRET"}


def test_external_transaction_cannot_be_misrepresented_as_committed_result(h) -> None:
    with h.engine.connect() as connection, connection.begin():
        external = service.AuthService(h.config, lambda: Session(bind=connection), clock=h.clock)
        with pytest.raises(service.AuthServiceError) as error:
            external.create_challenge(wallet_address=Account.create().address, chain_id=31337,
                                      browser_binding=service.new_browser_binding().get_secret_value())
        assert error.value.code == "SESSION_FACTORY_INVALID"
    assert h.count(AuthChallenge) == h.count(AuthSession) == h.count(User) == 0


def test_naive_clock_is_rejected_without_creating_challenge(h) -> None:
    invalid = h.at(h.clock.value.replace(tzinfo=None))
    with pytest.raises(service.AuthServiceError) as error:
        invalid.create_challenge(wallet_address=Account.create().address, chain_id=31337,
                                 browser_binding=service.new_browser_binding().get_secret_value())
    assert error.value.code == "CLOCK_INVALID" and h.count(AuthChallenge) == 0
