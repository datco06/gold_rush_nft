"""Models Auth: SQLite tạm, không cần server/RPC/PostgreSQL/Supabase.

Chạy từ gold_rush_ai: python -m pytest tests/test_auth_models.py -q
Schema chỉ được tạo trong fixture với :memory: hoặc tmp_path. Mọi phép chuẩn
hóa tên/ví và xác minh SIWE vẫn thuộc service, không được giả lập thành quyền
đăng nhập trong test này. DDL PostgreSQL chỉ được biên dịch ngoại tuyến.

SQLite dùng ChainId VARCHAR(78) để giữ đủ uint256, UTCDateTime lưu UTC naive
và khôi phục timezone khi đọc, Uuid lưu CHAR(32). SQL trực tiếp phải tuân dạng
lưu trữ; kiểm tra này không thay thế integration test driver/PostgreSQL thật.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
import secrets
import socket
import sqlite3
import sys
from collections.abc import Callable, Iterator
from datetime import UTC, datetime, timedelta, timezone
from itertools import count
from pathlib import Path
from types import MappingProxyType
from unittest.mock import Mock
from uuid import UUID, uuid4

import pytest
import sqlalchemy
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import CheckConstraint, MetaData, UniqueConstraint, delete, event, insert, null, select, update
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.engine import Engine, URL
from sqlalchemy.exc import IntegrityError, StatementError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.schema import CreateIndex, CreateTable

from auth import models as models
from auth.database import create_auth_engine, create_session_factory, session_scope


def _wallet(number: int) -> str:
    return f"0x{number:040x}"


def _digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


@pytest.fixture(autouse=True)
def no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    blocked = Mock(side_effect=AssertionError("Models unit test không được gọi mạng/DNS."))
    monkeypatch.setattr(socket, "create_connection", blocked)
    monkeypatch.setattr(socket, "getaddrinfo", blocked)
    monkeypatch.setattr(socket.socket, "connect", blocked)
    monkeypatch.setattr(socket.socket, "connect_ex", blocked)


@pytest.fixture(params=["memory", "file"])
def engine(request: pytest.FixtureRequest, tmp_path: Path) -> Iterator[Engine]:
    url = "sqlite:///:memory:" if request.param == "memory" else URL.create(
        "sqlite", database=str(tmp_path / "models-test.sqlite3"),
    )
    instance = create_auth_engine(database_url=url)
    try:
        models.Base.metadata.create_all(instance)
        yield instance
    finally:
        instance.dispose()


@pytest.fixture
def factory(engine: Engine) -> sessionmaker[Session]:
    return create_session_factory(engine)


@pytest.fixture
def persist(factory: sessionmaker[Session]) -> Callable:
    def save(instance):
        with session_scope(factory) as session:
            session.add(instance)
            session.flush()
        return instance
    return save


@pytest.fixture
def moment() -> datetime:
    # Cố định thời gian logic; không lệ thuộc đồng hồ/múi giờ của máy chạy test.
    return datetime(2026, 11, 6, 3, 0, 0, 123456, tzinfo=UTC)


@pytest.fixture
def new_user() -> Callable[..., models.User]:
    sequence = count(1)

    def build(**overrides) -> models.User:
        number = next(sequence)
        values = {
            "wallet_address": _wallet(number),
            "username": f"Explorer {number}",
            "username_key": f"explorer {number}",
        }
        return models.User(**(values | overrides))
    return build


@pytest.fixture
def new_challenge(moment: datetime) -> Callable[..., models.AuthChallenge]:
    def build(**overrides) -> models.AuthChallenge:
        nonce = secrets.token_hex(16)
        expiry = moment + timedelta(minutes=5)
        message = (
            f"localhost:5000 wants you to sign in with your Ethereum account:\n{_wallet(1)}\n\n"
            "Sign in to Gold Rush. This request does not transfer assets.\n\n"
            "URI: http://localhost:5000\nVersion: 1\nChain ID: 31337\n"
            f"Nonce: {nonce}\nIssued At: {moment.isoformat().replace('+00:00', 'Z')}\n"
            f"Expiration Time: {expiry.isoformat().replace('+00:00', 'Z')}"
        )
        values = {
            "nonce": nonce, "wallet_address": _wallet(1), "chain_id": 31337,
            "domain": "localhost:5000", "uri": "http://localhost:5000", "message": message,
            "browser_binding_hash": _digest("test-only-browser-binding"),
            "issued_at": moment, "expires_at": expiry,
        }
        return models.AuthChallenge(**(values | overrides))
    return build


@pytest.fixture
def new_session(moment: datetime) -> Callable[..., models.AuthSession]:
    sequence = count(1)

    def build(**overrides) -> models.AuthSession:
        values = {
            "token_hash": _digest(f"test-only-session-{next(sequence)}"),
            "purpose": "registration", "wallet_address": _wallet(1), "chain_id": 31337,
            "created_at": moment, "expires_at": moment + timedelta(minutes=10),
        }
        return models.AuthSession(**(values | overrides))
    return build


def test_metadata_has_exact_tables_and_columns() -> None:
    expected = {
        "users": {"id", "wallet_address", "username", "username_key", "avatar", "created_at"},
        "auth_challenges": {
            "id", "nonce", "wallet_address", "chain_id", "domain", "uri", "message",
            "browser_binding_hash", "issued_at", "expires_at", "consumed_at",
        },
        "auth_sessions": {
            "id", "token_hash", "purpose", "wallet_address", "chain_id", "user_id",
            "created_at", "expires_at", "revoked_at",
        },
        "game_run_owners": {"ma_van", "user_id", "created_at"},
    }
    assert set(models.Base.metadata.tables) == set(expected)
    for name, columns in expected.items():
        assert set(models.Base.metadata.tables[name].columns.keys()) == columns


def test_primary_unique_and_foreign_keys_match_schema() -> None:
    metadata = models.Base.metadata
    for name in ("users", "auth_challenges", "auth_sessions"):
        assert [column.name for column in metadata.tables[name].primary_key] == ["id"]
    assert [column.name for column in models.GameRunOwner.__table__.primary_key] == ["ma_van"]
    for name, column in (
        ("users", "wallet_address"), ("users", "username_key"),
        ("auth_challenges", "nonce"), ("auth_sessions", "token_hash"),
    ):
        assert (column,) in {
            tuple(item.name for item in constraint.columns)
            for constraint in metadata.tables[name].constraints
            if isinstance(constraint, UniqueConstraint)
        }
    for model in (models.AuthSession, models.GameRunOwner):
        assert {fk.target_fullname for fk in model.__table__.foreign_keys} == {"users.id"}
        assert {fk.ondelete for fk in model.__table__.foreign_keys} == {"RESTRICT"}
    assert models.AuthSession.__table__.c.user_id.nullable
    assert not models.GameRunOwner.__table__.c.user_id.nullable


def test_constraints_named_and_indexes_not_duplicated() -> None:
    for table in models.Base.metadata.tables.values():
        assert all(constraint.name for constraint in table.constraints)
        unique_sets = {
            tuple(column.name for column in constraint.columns)
            for constraint in table.constraints if isinstance(constraint, UniqueConstraint)
        }
        unique_sets.add(tuple(column.name for column in table.primary_key))
        index_sets = [tuple(column.name for column in index.columns) for index in table.indexes]
        assert len(index_sets) == len(set(index_sets))
        assert all(columns not in unique_sets for columns in index_sets)
        assert all(index.name for index in table.indexes)
        assert any(isinstance(constraint, CheckConstraint) for constraint in table.constraints)


def test_import_does_not_create_engine_database_or_schema(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    name = "auth._models_import_test"
    spec = importlib.util.spec_from_file_location(name, models.__file__)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    blocked = Mock(side_effect=AssertionError("Import Models không được khởi tạo DB/schema."))
    # Khôi phục environ trước khi pytest cập nhật PYTEST_CURRENT_TEST ở teardown.
    with monkeypatch.context() as patch:
        patch.chdir(tmp_path)
        patch.setattr(sys, "dont_write_bytecode", True)
        patch.setitem(sys.modules, name, module)
        patch.setattr(os, "environ", MappingProxyType({
            "AUTH_DATABASE_URL": f"sqlite:///{tmp_path / 'must-not-exist.db'}",
        }))
        patch.setattr(sqlalchemy, "create_engine", blocked)
        patch.setattr(Engine, "connect", blocked)
        patch.setattr(MetaData, "create_all", blocked)
        patch.setattr(sqlite3, "connect", blocked)
        patch.setattr(sqlite3.dbapi2, "connect", blocked)
        for method in ("mkdir", "touch", "write_bytes", "write_text"):
            patch.setattr(Path, method, blocked)
        spec.loader.exec_module(module)
    try:
        blocked.assert_not_called()
        assert list(tmp_path.iterdir()) == []
        assert not any(isinstance(value, (Engine, Session)) for value in vars(module).values())
    finally:
        module.Base.registry.dispose()


def test_user_defaults_uuid_and_roundtrip(persist: Callable, factory, new_user: Callable) -> None:
    before = datetime.now(UTC)
    first, second = persist(new_user()), persist(new_user())
    after = datetime.now(UTC)
    assert isinstance(first.id, UUID) and isinstance(second.id, UUID)
    assert first.id != second.id
    with factory() as session:
        loaded = session.get(models.User, first.id)
        assert loaded.wallet_address == first.wallet_address
        assert loaded.username == first.username
        assert loaded.username_key == first.username_key
        assert loaded.avatar == "george"
        assert loaded.created_at.utcoffset() == timedelta(0)
        assert before <= loaded.created_at <= after


@pytest.mark.parametrize("column", ["wallet_address", "username_key"])
def test_users_unique_fields_are_enforced(
    persist: Callable, factory, new_user: Callable, column: str,
) -> None:
    first = persist(new_user())
    with pytest.raises(IntegrityError):
        persist(new_user(**{column: getattr(first, column)}))
    with factory() as session:
        assert len(session.scalars(select(models.User)).all()) == 1


def test_duplicate_user_uuid_is_rejected(persist: Callable, new_user: Callable) -> None:
    first = persist(new_user())
    # Ví/tên khác nhau để chỉ va chạm primary key, không va chạm UNIQUE khác.
    with pytest.raises(IntegrityError):
        persist(new_user(id=first.id))


@pytest.mark.parametrize("column", [
    "id", "wallet_address", "username", "username_key", "avatar", "created_at",
])
def test_user_required_columns_reject_explicit_sql_null(factory, moment: datetime, column: str) -> None:
    values = {
        "id": uuid4(), "wallet_address": _wallet(1), "username": "Explorer",
        "username_key": "explorer", "avatar": "george", "created_at": moment,
    }
    # Explicit SQL NULL tránh ORM thay None bằng default trên các cột có default.
    values[column] = null()
    with pytest.raises(IntegrityError):
        with session_scope(factory) as session:
            session.execute(insert(models.User.__table__).values(**values))


@pytest.mark.parametrize("field,value", [
    ("username", "ab"), ("username", "x" * 21),
    ("username_key", ""), ("username_key", "x" * 61),
    ("avatar", ""), ("avatar", "x" * 33),
])
def test_user_length_checks(persist: Callable, new_user: Callable, field: str, value: str) -> None:
    with pytest.raises(IntegrityError):
        persist(new_user(**{field: value}))


@pytest.mark.parametrize("model_kind", ["user", "challenge", "session"])
@pytest.mark.parametrize("wallet", ["0x123", "0x" + "A" * 40, "0x" + "g" * 40])
def test_wallet_format_rejected_without_automatic_normalization(
    persist: Callable, new_user: Callable, new_challenge: Callable, new_session: Callable,
    model_kind: str, wallet: str,
) -> None:
    builder = {"user": new_user, "challenge": new_challenge, "session": new_session}[model_kind]
    with pytest.raises(IntegrityError):
        persist(builder(wallet_address=wallet))


def test_challenge_exact_message_binding_and_unused_state(
    persist: Callable, factory, new_challenge: Callable,
) -> None:
    challenge = persist(new_challenge())
    with factory() as session:
        loaded = session.get(models.AuthChallenge, challenge.id)
        assert loaded.message == challenge.message
        assert loaded.message.encode("utf-8") == challenge.message.encode("utf-8")
        assert loaded.nonce == challenge.nonce
        assert loaded.browser_binding_hash == _digest("test-only-browser-binding")
        assert loaded.chain_id == 31337
        assert loaded.consumed_at is None
        # Lưu challenge không tự tạo tài khoản, grant hoặc phiên đăng nhập.
        assert session.scalars(select(models.AuthSession)).all() == []
        assert session.scalars(select(models.User)).all() == []


def test_nonce_is_unique(persist: Callable, new_challenge: Callable) -> None:
    first = persist(new_challenge())
    with pytest.raises(IntegrityError):
        persist(new_challenge(nonce=first.nonce))


@pytest.mark.parametrize("field,value", [
    ("nonce", "short"), ("nonce", "a" * 65),
    ("domain", ""), ("domain", "x" * 256),
    ("uri", ""), ("uri", "x" * 2049),
    ("message", ""), ("message", "x" * 4097),
])
def test_challenge_length_checks(
    persist: Callable, new_challenge: Callable, field: str, value: str,
) -> None:
    with pytest.raises(IntegrityError):
        persist(new_challenge(**{field: value}))


def test_challenge_conditional_update_prevents_second_consumption(
    persist: Callable, factory, new_challenge: Callable, moment: datetime,
) -> None:
    challenge = persist(new_challenge())
    consumed = moment + timedelta(seconds=1)
    statement = update(models.AuthChallenge).where(
        models.AuthChallenge.id == challenge.id,
        models.AuthChallenge.consumed_at.is_(None),
        models.AuthChallenge.expires_at > consumed,
    ).values(consumed_at=consumed)
    with session_scope(factory) as session:
        assert session.execute(statement).rowcount == 1
    with session_scope(factory) as session:
        assert session.execute(statement).rowcount == 0
    with factory() as session:
        assert session.get(models.AuthChallenge, challenge.id).consumed_at == consumed


def test_expired_challenge_is_excluded_by_update_condition(
    persist: Callable, factory, new_challenge: Callable, moment: datetime,
) -> None:
    challenge = persist(new_challenge())
    # Đúng biên expires_at: điều kiện > không còn cho tiêu thụ challenge.
    with session_scope(factory) as session:
        result = session.execute(update(models.AuthChallenge).where(
            models.AuthChallenge.id == challenge.id,
            models.AuthChallenge.consumed_at.is_(None),
            models.AuthChallenge.expires_at > challenge.expires_at,
        ).values(consumed_at=challenge.expires_at))
        assert result.rowcount == 0
    with factory() as session:
        assert session.get(models.AuthChallenge, challenge.id).consumed_at is None


def test_registration_session_has_no_user(persist: Callable, factory, new_session: Callable) -> None:
    grant = persist(new_session())
    with factory() as session:
        loaded = session.get(models.AuthSession, grant.id)
        assert loaded.purpose == "registration"
        assert loaded.user_id is None
        assert loaded.revoked_at is None
        assert loaded.token_hash == grant.token_hash


def test_authenticated_session_links_existing_user(
    persist: Callable, factory, new_user: Callable, new_session: Callable,
) -> None:
    user = persist(new_user())
    authenticated = persist(new_session(
        purpose="authenticated", user_id=user.id, wallet_address=user.wallet_address,
    ))
    with factory() as session:
        loaded = session.get(models.AuthSession, authenticated.id)
        assert loaded.user_id == user.id
        assert session.get(models.User, loaded.user_id).wallet_address == loaded.wallet_address


@pytest.mark.parametrize("purpose,attach_user", [
    ("authenticated", False), ("registration", True), ("administrator", False), (None, False),
])
def test_session_purpose_user_constraint(
    persist: Callable, new_user: Callable, new_session: Callable,
    purpose: str | None, attach_user: bool,
) -> None:
    user = persist(new_user()) if attach_user else None
    with pytest.raises(IntegrityError):
        persist(new_session(purpose=purpose, user_id=user.id if user else None))


def test_session_token_hash_is_unique(persist: Callable, new_session: Callable) -> None:
    first = persist(new_session())
    with pytest.raises(IntegrityError):
        persist(new_session(token_hash=first.token_hash))


@pytest.mark.parametrize("kind", ["session", "owner"])
def test_orphan_user_foreign_keys_are_rejected(
    persist: Callable, new_session: Callable, kind: str,
) -> None:
    missing_user = uuid4()
    instance = new_session(purpose="authenticated", user_id=missing_user) if kind == "session" else (
        models.GameRunOwner(ma_van="test-run-001", user_id=missing_user)
    )
    with pytest.raises(IntegrityError):
        persist(instance)


def test_revocation_and_expiry_can_be_queried(
    persist: Callable, factory, new_user: Callable, new_session: Callable, moment: datetime,
) -> None:
    user = persist(new_user())
    common = {
        "purpose": "authenticated", "user_id": user.id, "wallet_address": user.wallet_address,
        "created_at": moment - timedelta(hours=1),
    }
    active = persist(new_session(**common))
    expired = persist(new_session(**common, expires_at=moment))
    revoked = persist(new_session(**common))
    persist(new_session(wallet_address=user.wallet_address))  # grant vẫn chưa có user_id.
    with session_scope(factory) as session:
        session.execute(update(models.AuthSession).where(
            models.AuthSession.id == revoked.id,
        ).values(revoked_at=moment))
    with factory() as session:
        ids = session.scalars(select(models.AuthSession.id).where(
            models.AuthSession.purpose == "authenticated",
            models.AuthSession.user_id == user.id,
            models.AuthSession.revoked_at.is_(None),
            models.AuthSession.expires_at > moment,
        )).all()
        assert ids == [active.id]
        assert session.get(models.AuthSession, expired.id).expires_at == moment
        assert session.get(models.AuthSession, revoked.id).revoked_at == moment


@pytest.mark.parametrize("kind,field", [
    ("challenge", "expires_at"), ("challenge", "consumed_at"),
    ("session", "expires_at"), ("session", "revoked_at"),
])
def test_timestamp_chronology_checks(
    persist: Callable, new_challenge: Callable, new_session: Callable,
    moment: datetime, kind: str, field: str,
) -> None:
    value = moment if field == "expires_at" else moment - timedelta(seconds=1)
    builder = new_challenge if kind == "challenge" else new_session
    with pytest.raises(IntegrityError):
        persist(builder(**{field: value}))


def test_game_runs_link_and_query_by_owner(persist: Callable, factory, new_user: Callable) -> None:
    first, second = persist(new_user()), persist(new_user())
    for name, user in (("first-run-001", first), ("first-run-002", first), ("other-run-001", second)):
        persist(models.GameRunOwner(ma_van=name, user_id=user.id))
    with factory() as session:
        owned = session.scalars(select(models.GameRunOwner).where(
            models.GameRunOwner.user_id == first.id,
        )).all()
        assert {run.ma_van for run in owned} == {"first-run-001", "first-run-002"}
        assert all(run.created_at.utcoffset() == timedelta(0) for run in owned)


def test_same_run_cannot_be_assigned_to_two_users(persist: Callable, factory, new_user: Callable) -> None:
    first, second = persist(new_user()), persist(new_user())
    persist(models.GameRunOwner(ma_van="shared-run-001", user_id=first.id))
    with pytest.raises(IntegrityError):
        persist(models.GameRunOwner(ma_van="shared-run-001", user_id=second.id))
    with factory() as session:
        assert session.get(models.GameRunOwner, "shared-run-001").user_id == first.id


def test_run_owner_user_id_is_required(persist: Callable) -> None:
    with pytest.raises(IntegrityError):
        persist(models.GameRunOwner(ma_van="test-run-001", user_id=None))


@pytest.mark.parametrize("ma_van", ["short", "x" * 65])
def test_game_run_id_length_check(persist: Callable, new_user: Callable, ma_van: str) -> None:
    user = persist(new_user())
    with pytest.raises(IntegrityError):
        persist(models.GameRunOwner(ma_van=ma_van, user_id=user.id))


@pytest.mark.parametrize("dependent", ["session", "owner"])
def test_user_delete_is_restricted_by_foreign_keys(
    persist: Callable, factory, new_user: Callable, new_session: Callable, dependent: str,
) -> None:
    user = persist(new_user())
    if dependent == "session":
        persist(new_session(purpose="authenticated", user_id=user.id, wallet_address=user.wallet_address))
    else:
        persist(models.GameRunOwner(ma_van="test-run-001", user_id=user.id))
    with pytest.raises(IntegrityError):
        with session_scope(factory) as session:
            session.execute(delete(models.User).where(models.User.id == user.id))


@pytest.mark.parametrize("kind", ["challenge", "session"])
@pytest.mark.parametrize("bad_hash", ["ab" * 31, "AB" * 32, "g" * 64])
def test_hash_format_checks(
    persist: Callable, new_challenge: Callable, new_session: Callable, kind: str, bad_hash: str,
) -> None:
    instance = new_challenge(browser_binding_hash=bad_hash) if kind == "challenge" else (
        new_session(token_hash=bad_hash)
    )
    with pytest.raises(IntegrityError):
        persist(instance)


def test_no_raw_token_private_key_or_signature_columns() -> None:
    forbidden = {"token", "session_token", "raw_token", "private_key", "seed_phrase", "signature"}
    for table in models.Base.metadata.tables.values():
        assert forbidden.isdisjoint(table.columns.keys())
    with pytest.raises(TypeError):
        models.AuthSession(session_token="TEST_ONLY_RAW_TOKEN")
    with pytest.raises(TypeError):
        models.AuthChallenge(signature="TEST_ONLY_SIGNATURE")


@pytest.mark.parametrize("kind", ["challenge", "session"])
@pytest.mark.parametrize("chain_id", [1, 31337, 2**63, 2**256 - 1])
def test_chain_id_exact_roundtrip_and_sqlite_storage(
    persist: Callable, factory, engine: Engine, new_challenge: Callable, new_session: Callable,
    kind: str, chain_id: int,
) -> None:
    model = models.AuthChallenge if kind == "challenge" else models.AuthSession
    builder = new_challenge if kind == "challenge" else new_session
    instance = persist(builder(chain_id=chain_id))
    with factory() as session:
        loaded = session.get(model, instance.id)
        assert type(loaded.chain_id) is int
        assert loaded.chain_id == chain_id
        assert session.scalar(select(model.id).where(model.chain_id == chain_id)) == instance.id
    with engine.connect() as connection:
        # Chỉ một bản ghi trong bảng này ở test; tên bảng lấy từ hai class cố định.
        raw, storage_type = connection.exec_driver_sql(
            f"SELECT chain_id, typeof(chain_id) FROM {model.__tablename__}"
        ).one()
        assert storage_type == "text"
        assert raw == f"{chain_id:078d}"


@pytest.mark.parametrize("kind", ["challenge", "session"])
@pytest.mark.parametrize("chain_id", [0, -1, True, "31337", 2**256])
def test_chain_id_bind_validation(
    persist: Callable, new_challenge: Callable, new_session: Callable, kind: str, chain_id,
) -> None:
    builder = new_challenge if kind == "challenge" else new_session
    with pytest.raises(StatementError) as error:
        persist(builder(chain_id=chain_id))
    assert isinstance(error.value.orig, ValueError)


@pytest.mark.parametrize("raw", ["0" * 78, "9" * 78, "a" * 78, "31337"])
def test_raw_sql_cannot_bypass_chain_constraint(
    persist: Callable, engine: Engine, new_challenge: Callable, raw: str,
) -> None:
    persist(new_challenge())
    # Bỏ qua TypeDecorator để kiểm tra CHECK thực sự ở DB, không chỉ Python.
    with pytest.raises(IntegrityError):
        with engine.begin() as connection:
            connection.exec_driver_sql("UPDATE auth_challenges SET chain_id=?", (raw,))


def test_chain_id_sorting_preserves_numeric_order(persist: Callable, factory, new_challenge: Callable) -> None:
    values = [2**256 - 1, 31337, 1, 2**63]
    for value in values:
        persist(new_challenge(chain_id=value))
    with factory() as session:
        assert session.scalars(select(models.AuthChallenge.chain_id).order_by(
            models.AuthChallenge.chain_id,
        )).all() == sorted(values)


def test_timezone_offset_normalized_on_database_roundtrip(
    persist: Callable, factory, engine: Engine, new_user: Callable, moment: datetime,
) -> None:
    local_time = moment.astimezone(timezone(timedelta(hours=7)))
    user = persist(new_user(created_at=local_time))
    with factory() as session:
        loaded = session.get(models.User, user.id)
        assert loaded.created_at == moment
        assert loaded.created_at.utcoffset() == timedelta(0)
        assert loaded.created_at.microsecond == moment.microsecond
    with engine.connect() as connection:
        raw = connection.exec_driver_sql("SELECT created_at FROM users").scalar_one()
        stored = datetime.fromisoformat(raw)
        assert stored.tzinfo is None
        assert stored == moment.replace(tzinfo=None)


@pytest.mark.parametrize("kind", ["user", "challenge", "session"])
def test_naive_timestamp_is_rejected(
    persist: Callable, new_user: Callable, new_challenge: Callable, new_session: Callable,
    moment: datetime, kind: str,
) -> None:
    naive = moment.replace(tzinfo=None)
    instance = {
        "user": lambda: new_user(created_at=naive),
        "challenge": lambda: new_challenge(issued_at=naive),
        "session": lambda: new_session(created_at=naive),
    }[kind]()
    with pytest.raises(StatementError) as error:
        persist(instance)
    assert isinstance(error.value.orig, ValueError)


def test_repr_hides_values_without_loading_expired_attributes(
    persist: Callable, factory, engine: Engine, new_user: Callable, new_challenge: Callable,
    new_session: Callable,
) -> None:
    user = persist(new_user())
    with factory() as session:
        loaded = session.get(models.User, user.id)
        session.expire(loaded)
        blocked = Mock(side_effect=AssertionError("repr không được thực hiện query."))
        event.listen(engine, "before_cursor_execute", blocked)
        try:
            assert repr(loaded) == "<User>"
            blocked.assert_not_called()
        finally:
            event.remove(engine, "before_cursor_execute", blocked)
    for instance in (
        new_challenge(message="SENSITIVE_TEST_MARKER"), new_session(),
        models.GameRunOwner(ma_van="SENSITIVE_TEST_MARKER", user_id=uuid4()),
    ):
        assert repr(instance) == f"<{type(instance).__name__}>"
        assert "SENSITIVE_TEST_MARKER" not in repr(instance)


@pytest.mark.parametrize("table_name", ["users", "auth_challenges", "auth_sessions", "game_run_owners"])
def test_postgresql_ddl_compiles_offline_without_connection(
    table_name: str, monkeypatch: pytest.MonkeyPatch,
) -> None:
    table = models.Base.metadata.tables[table_name]
    blocked = Mock(side_effect=AssertionError("Compile DDL không được kết nối Database."))
    with monkeypatch.context() as patch:
        patch.setattr(Engine, "connect", blocked)
        ddl = str(CreateTable(table).compile(dialect=postgresql.dialect()))
        for index in table.indexes:
            assert "CREATE INDEX" in str(CreateIndex(index).compile(dialect=postgresql.dialect()))
    assert f"CREATE TABLE {table_name}" in ddl
    for constraint in table.constraints:
        assert constraint.name in ddl
    blocked.assert_not_called()


def test_backend_type_mapping_is_explicit() -> None:
    postgres, local = postgresql.dialect(), sqlite.dialect()
    identifier = models.User.__table__.c.id.type
    timestamp = models.User.__table__.c.created_at.type
    chain_id = models.AuthChallenge.__table__.c.chain_id.type
    assert identifier.compile(dialect=postgres) == "UUID"
    assert identifier.compile(dialect=local) == "CHAR(32)"
    assert timestamp.compile(dialect=postgres) == "TIMESTAMP WITH TIME ZONE"
    assert timestamp.compile(dialect=local) == "DATETIME"
    assert chain_id.compile(dialect=postgres) == chain_id.compile(dialect=local) == "VARCHAR(78)"
    assert timestamp.python_type is datetime
    assert chain_id.python_type is int


def test_metadata_matches_temporary_sqlite_for_alembic(engine: Engine) -> None:
    # Chỉ so sánh metadata trên DB tạm, không tạo revision hoặc file migration.
    with engine.connect() as connection:
        context = MigrationContext.configure(connection)
        assert compare_metadata(context, models.Base.metadata) == []
