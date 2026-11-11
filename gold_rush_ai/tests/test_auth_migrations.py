"""Exercise real Alembic commands against SQLite files owned by tmp_path.

No metadata.create_all, project Database, .env file or online PostgreSQL is
used. PostgreSQL coverage emits SQL only and does not prove online support.
Run from gold_rush_ai: python -m pytest tests/test_auth_migrations.py -q
"""
from __future__ import annotations

import hashlib
import io
import os
import secrets
import socket
import sqlite3
from collections.abc import Iterator
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import Mock, patch
from uuid import uuid4

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import CheckConstraint, MetaData, UniqueConstraint, inspect, insert, select, text
from sqlalchemy.engine import Engine, URL
from sqlalchemy.exc import IntegrityError

from auth import models
from auth.database import create_auth_engine


_BACKEND = Path(__file__).resolve().parents[1]
_INI = _BACKEND / "alembic.ini"
_TABLES = ("users", "auth_challenges", "auth_sessions", "game_run_owners")


def _config(*, output: io.StringIO | None = None) -> Config:
    return Config(str(_INI), stdout=io.StringIO(), output_buffer=output)


@dataclass
class _MigrationDatabase:
    path: Path
    engine: Engine
    environment: dict[str, str] = field(repr=False)

    def run(self, action: str) -> None:
        # The runner never accepts an arbitrary URL, target or online dialect.
        expected = URL.create("sqlite", database=str(self.path)).render_as_string()
        assert self.environment["AUTH_DATABASE_URL"] == expected
        assert action in {"upgrade", "downgrade", "check"}
        # env.py calls fileConfig on execution. Isolate that process-wide logging
        # change while leaving migration execution and Auth validation intact.
        with patch.object(os, "environ", self.environment.copy()), patch("logging.config.fileConfig"):
            config = _config()
            if action == "upgrade":
                command.upgrade(config, "head")
            elif action == "downgrade":
                command.downgrade(config, "base")
            else:
                command.check(config)


@pytest.fixture(autouse=True)
def isolated_io(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Enforce temporary SQLite only, even if migration configuration regresses."""
    blocked = Mock(side_effect=AssertionError("Migration tests must not access network or create_all."))
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
    finally:
        # Also clean up connections if an assertion interrupts a test.
        for connection in connections:
            connection.close()


@pytest.fixture
def migration_db(tmp_path: Path) -> Iterator[_MigrationDatabase]:
    path = (tmp_path / "auth-migrations.sqlite3").resolve()
    assert not path.exists()
    url = URL.create("sqlite", database=str(path))
    environment = {
        "AUTH_DATABASE_URL": url.render_as_string(),
        "AUTH_CSRF_SECRET": secrets.token_hex(32),
    }
    engine = create_auth_engine(database_url=url)
    try:
        yield _MigrationDatabase(path, engine, environment)
    finally:
        checked_out = engine.pool.checkedout()
        engine.dispose()
        assert checked_out == 0, "Test retained a checked-out SQLite connection."


@pytest.fixture
def migrated_db(migration_db: _MigrationDatabase) -> _MigrationDatabase:
    migration_db.run("upgrade")
    return migration_db


@pytest.fixture
def rows() -> dict[str, dict]:
    moment = datetime(2026, 11, 6, 3, 0, 0, 123456, tzinfo=UTC)
    user_id = uuid4()
    wallet = "0x" + "1" * 40
    return {
        "users": {
            "id": user_id, "wallet_address": wallet, "username": "Explorer",
            "username_key": "explorer", "created_at": moment,
        },
        "auth_challenges": {
            "id": uuid4(), "nonce": secrets.token_hex(16), "wallet_address": wallet,
            "chain_id": 2**256 - 1, "domain": "localhost:5000",
            "uri": "http://localhost:5000", "message": "Test-only SIWE message\nexact bytes",
            "browser_binding_hash": hashlib.sha256(b"test browser binding").hexdigest(),
            "issued_at": moment, "expires_at": moment + timedelta(minutes=5),
        },
        "auth_sessions": {
            "id": uuid4(), "token_hash": hashlib.sha256(b"test session token").hexdigest(),
            "purpose": "authenticated", "wallet_address": wallet, "chain_id": 31337,
            "user_id": user_id, "created_at": moment,
            "expires_at": moment + timedelta(hours=8),
        },
        "game_run_owners": {"ma_van": "test-run-0001", "user_id": user_id, "created_at": moment},
    }


@pytest.fixture
def populated_db(migrated_db: _MigrationDatabase, rows: dict[str, dict]) -> _MigrationDatabase:
    with migrated_db.engine.begin() as connection:
        for name in _TABLES:
            connection.execute(insert(models.Base.metadata.tables[name]), rows[name])
    return migrated_db


def _tables(engine: Engine) -> set[str]:
    with engine.connect() as connection:
        return set(inspect(connection).get_table_names())


def test_alembic_configuration_and_root_revision() -> None:
    config = _config()
    assert Path(config.get_main_option("script_location")).resolve() == _BACKEND / "migrations"
    assert config.get_main_option("sqlalchemy.url") is None
    script = ScriptDirectory.from_config(config)
    assert script.get_bases() == script.get_heads() == ["0001_auth"]
    revision = script.get_revision("0001_auth")
    assert Path(revision.path).name == "0001_auth.py"
    assert revision.down_revision is None
    assert revision.module.branch_labels is None
    assert revision.module.depends_on is None


def test_upgrade_creates_exact_auth_tables_and_version(migrated_db: _MigrationDatabase) -> None:
    assert _tables(migrated_db.engine) == set(_TABLES) | {"alembic_version"}
    with migrated_db.engine.connect() as connection:
        assert connection.scalar(text("SELECT version_num FROM alembic_version")) == "0001_auth"
        assert connection.scalar(text("PRAGMA foreign_keys")) == 1


@pytest.mark.parametrize("name", _TABLES)
def test_columns_types_nullability_and_defaults(migrated_db: _MigrationDatabase, name: str) -> None:
    table = models.Base.metadata.tables[name]
    with migrated_db.engine.connect() as connection:
        actual = inspect(connection).get_columns(name)
        assert [(column["name"], column["nullable"]) for column in actual] == [
            (column.name, column.nullable) for column in table.columns
        ]
        assert [str(column["type"].compile(dialect=connection.dialect)) for column in actual] == [
            str(column.type.compile(dialect=connection.dialect)) for column in table.columns
        ]
        for column in actual:
            assert column["default"] == ("'george'" if name == "users" and column["name"] == "avatar" else None)


@pytest.mark.parametrize("name", _TABLES)
def test_primary_unique_and_foreign_keys(migrated_db: _MigrationDatabase, name: str) -> None:
    table = models.Base.metadata.tables[name]
    with migrated_db.engine.connect() as connection:
        inspector = inspect(connection)
        pk = inspector.get_pk_constraint(name)
        assert (pk["name"], pk["constrained_columns"]) == (
            table.primary_key.name, [column.name for column in table.primary_key],
        )
        assert {(c["name"], tuple(c["column_names"])) for c in inspector.get_unique_constraints(name)} == {
            (str(c.name), tuple(column.name for column in c.columns))
            for c in table.constraints if isinstance(c, UniqueConstraint)
        }
        assert {
            (c["name"], tuple(c["constrained_columns"]), c["referred_table"],
             tuple(c["referred_columns"]), c["options"].get("ondelete"))
            for c in inspector.get_foreign_keys(name)
        } == {
            (str(c.name), tuple(column.name for column in c.columns), c.elements[0].column.table.name,
             tuple(element.column.name for element in c.elements), c.ondelete)
            for c in table.foreign_key_constraints
        }


@pytest.mark.parametrize("name", _TABLES)
def test_check_constraints_and_indexes_match_models(migrated_db: _MigrationDatabase, name: str) -> None:
    table = models.Base.metadata.tables[name]
    with migrated_db.engine.connect() as connection:
        inspector = inspect(connection)
        # Autogenerate does not fully compare CHECK constraints; inspect their
        # names and SQL independently instead of relying only on an empty diff.
        assert {c["name"]: c["sqltext"] for c in inspector.get_check_constraints(name)} == {
            str(c.name): str(c.sqltext) for c in table.constraints if isinstance(c, CheckConstraint)
        }
        assert {(i["name"], tuple(i["column_names"]), bool(i["unique"])) for i in inspector.get_indexes(name)} == {
            (str(i.name), tuple(column.name for column in i.columns), bool(i.unique)) for i in table.indexes
        }


def test_valid_rows_roundtrip_with_custom_types(populated_db: _MigrationDatabase, rows: dict[str, dict]) -> None:
    with populated_db.engine.connect() as connection:
        for name in _TABLES:
            table = models.Base.metadata.tables[name]
            loaded = connection.execute(select(table)).mappings().one()
            for key, expected in rows[name].items():
                assert loaded[key] == expected
        user = connection.execute(select(models.User.__table__)).mappings().one()
        assert user["avatar"] == "george"
        assert user["created_at"].utcoffset() == timedelta(0)
        challenge = connection.execute(select(models.AuthChallenge.__table__)).mappings().one()
        assert type(challenge["chain_id"]) is int
        assert challenge["chain_id"] == 2**256 - 1
        assert challenge["consumed_at"] is None


@pytest.mark.parametrize("field", ["wallet_address", "username_key"])
def test_duplicate_user_identity_rejected(populated_db: _MigrationDatabase, rows, field: str) -> None:
    values = rows["users"] | {
        "id": uuid4(), "wallet_address": "0x" + "2" * 40, "username_key": "other explorer",
    }
    values[field] = rows["users"][field]
    with pytest.raises(IntegrityError):
        with populated_db.engine.begin() as connection:
            connection.execute(insert(models.User), values)


@pytest.mark.parametrize("name,field", [("auth_challenges", "nonce"), ("auth_sessions", "token_hash")])
def test_unique_challenge_nonce_and_session_hash(populated_db: _MigrationDatabase, rows, name, field) -> None:
    values = rows[name] | {"id": uuid4()}
    assert values[field] == rows[name][field]
    with pytest.raises(IntegrityError):
        with populated_db.engine.begin() as connection:
            connection.execute(insert(models.Base.metadata.tables[name]), values)


@pytest.mark.parametrize("purpose,has_user", [
    ("authenticated", False), ("registration", True), ("administrator", False),
])
def test_session_purpose_user_check(populated_db: _MigrationDatabase, rows, purpose, has_user) -> None:
    values = rows["auth_sessions"] | {
        "id": uuid4(), "token_hash": hashlib.sha256(b"another test token").hexdigest(),
        "purpose": purpose, "user_id": rows["users"]["id"] if has_user else None,
    }
    with pytest.raises(IntegrityError, match="ck_auth_sessions_purpose_user_consistency"):
        with populated_db.engine.begin() as connection:
            connection.execute(insert(models.AuthSession), values)


def test_registration_session_without_user_is_valid(populated_db: _MigrationDatabase, rows) -> None:
    values = rows["auth_sessions"] | {
        "id": uuid4(), "purpose": "registration", "user_id": None,
        "token_hash": hashlib.sha256(b"registration test token").hexdigest(),
    }
    with populated_db.engine.begin() as connection:
        connection.execute(insert(models.AuthSession), values)
    with populated_db.engine.connect() as connection:
        assert connection.scalar(select(models.AuthSession.user_id).where(models.AuthSession.id == values["id"])) is None


@pytest.mark.parametrize("name", ["auth_sessions", "game_run_owners"])
def test_orphan_foreign_key_rejected(migrated_db: _MigrationDatabase, rows, name: str) -> None:
    with pytest.raises(IntegrityError, match="FOREIGN KEY constraint failed"):
        with migrated_db.engine.begin() as connection:
            connection.execute(insert(models.Base.metadata.tables[name]), rows[name] | {"user_id": uuid4()})


@pytest.mark.parametrize("name", ["users", "game_run_owners"])
def test_duplicate_primary_key_rejected(populated_db: _MigrationDatabase, rows, name: str) -> None:
    values = dict(rows[name])
    if name == "users":
        values.update(wallet_address="0x" + "2" * 40, username_key="another explorer")
    with pytest.raises(IntegrityError):
        with populated_db.engine.begin() as connection:
            connection.execute(insert(models.Base.metadata.tables[name]), values)


# Bypass Python type validation with raw SQL to exercise each Database CHECK.
@pytest.mark.parametrize("table,suffix,column,value", [
    ("users", "wallet_format", "wallet_address", "bad"),
    ("users", "avatar_length", "avatar", ""),
    ("users", "username_length", "username", "ab"),
    ("users", "username_key_length", "username_key", ""),
    ("auth_challenges", "wallet_format", "wallet_address", "bad"),
    ("auth_challenges", "chain_id_range", "chain_id", "0" * 78),
    ("auth_challenges", "browser_binding_hash_format", "browser_binding_hash", "invalid"),
    ("auth_challenges", "nonce_length", "nonce", "bad"),
    ("auth_challenges", "domain_length", "domain", ""),
    ("auth_challenges", "uri_length", "uri", ""),
    ("auth_challenges", "message_length", "message", ""),
    ("auth_challenges", "expiry_after_issue", "expires_at", "2000-01-01 00:00:00"),
    ("auth_challenges", "consumption_after_issue", "consumed_at", "2000-01-01 00:00:00"),
    ("auth_sessions", "wallet_format", "wallet_address", "bad"),
    ("auth_sessions", "chain_id_range", "chain_id", "0" * 78),
    ("auth_sessions", "token_hash_format", "token_hash", "invalid"),
    ("auth_sessions", "purpose_user_consistency", "purpose", "administrator"),
    ("auth_sessions", "expiry_after_creation", "expires_at", "2000-01-01 00:00:00"),
    ("auth_sessions", "revocation_after_creation", "revoked_at", "2000-01-01 00:00:00"),
    ("game_run_owners", "ma_van_length", "ma_van", "bad"),
])
def test_database_check_rejects_invalid_raw_sql(populated_db, table, suffix, column, value) -> None:
    assert table in _TABLES and column in models.Base.metadata.tables[table].columns
    with pytest.raises(IntegrityError, match=f"ck_{table}_{suffix}"):
        with populated_db.engine.begin() as connection:
            connection.exec_driver_sql(f"UPDATE {table} SET {column}=?", (value,))


def test_user_delete_restricted_by_dependents(populated_db: _MigrationDatabase) -> None:
    with pytest.raises(IntegrityError, match="FOREIGN KEY constraint failed"):
        with populated_db.engine.begin() as connection:
            connection.execute(text("DELETE FROM users"))


def test_upgrade_again_preserves_schema_and_all_data(populated_db: _MigrationDatabase) -> None:
    def snapshot():
        with populated_db.engine.connect() as connection:
            return {name: connection.execute(select(models.Base.metadata.tables[name])).all() for name in _TABLES}

    before = snapshot()
    populated_db.run("upgrade")
    assert snapshot() == before
    assert _tables(populated_db.engine) == set(_TABLES) | {"alembic_version"}


def test_schema_has_no_unexpected_drift(populated_db: _MigrationDatabase) -> None:
    with populated_db.engine.connect() as connection:
        context = MigrationContext.configure(connection, opts={"compare_type": True, "compare_server_default": True})
        assert compare_metadata(context, models.Base.metadata) == []
    populated_db.run("check")


def test_downgrade_removes_auth_tables(migrated_db: _MigrationDatabase) -> None:
    migrated_db.run("downgrade")
    assert _tables(migrated_db.engine) == {"alembic_version"}
    with migrated_db.engine.connect() as connection:
        assert connection.scalar(text("SELECT count(*) FROM alembic_version")) == 0


def test_downgrade_preserves_preexisting_unrelated_table_and_reupgrade(migration_db, rows) -> None:
    # Create the unrelated table BEFORE Auth's first upgrade.
    with migration_db.engine.begin() as connection:
        connection.exec_driver_sql("CREATE TABLE outside_auth (value TEXT NOT NULL)")
        connection.exec_driver_sql("INSERT INTO outside_auth VALUES ('keep this fake data')")
    migration_db.run("upgrade")
    with migration_db.engine.begin() as connection:
        for name in _TABLES:
            connection.execute(insert(models.Base.metadata.tables[name]), rows[name])
    migration_db.run("check")
    migration_db.run("downgrade")
    assert _tables(migration_db.engine) == {"outside_auth", "alembic_version"}
    with migration_db.engine.connect() as connection:
        assert connection.scalar(text("SELECT value FROM outside_auth")) == "keep this fake data"
    migration_db.run("upgrade")
    assert _tables(migration_db.engine) == set(_TABLES) | {"outside_auth", "alembic_version"}
    with migration_db.engine.connect() as connection:
        assert connection.scalar(text("SELECT value FROM outside_auth")) == "keep this fake data"
        assert connection.scalar(text("SELECT version_num FROM alembic_version")) == "0001_auth"
        assert all(connection.scalar(select(table.c[next(iter(table.primary_key)).name])) is None
                   for table in models.Base.metadata.tables.values())
    migration_db.run("check")


def test_migration_environment_is_restored(migration_db, monkeypatch: pytest.MonkeyPatch) -> None:
    # Use synthetic caller env, so a failed assertion cannot expose real env.
    caller_env = {"AUTH_DATABASE_URL": "TEST_CALLER_VALUE", "AUTH_CSRF_SECRET": "TEST_CALLER_SECRET"}
    monkeypatch.setattr(os, "environ", caller_env)
    migration_db.run("upgrade")
    assert os.environ is caller_env
    assert caller_env == {"AUTH_DATABASE_URL": "TEST_CALLER_VALUE", "AUTH_CSRF_SECRET": "TEST_CALLER_SECRET"}


def test_postgresql_sql_generation_is_offline_only(migration_db, monkeypatch: pytest.MonkeyPatch) -> None:
    blocked = Mock(side_effect=AssertionError("Offline PostgreSQL must not open an Engine connection."))
    monkeypatch.setattr(Engine, "connect", blocked)
    url = "postgresql://test_user:TEST_ONLY_PASSWORD@example.invalid/auth_test"
    output = io.StringIO()
    environment = migration_db.environment | {"AUTH_DATABASE_URL": url}
    with patch.object(os, "environ", environment), patch("logging.config.fileConfig"):
        command.upgrade(_config(output=output), "head", sql=True)
    sql = output.getvalue()
    for name in _TABLES:
        assert f"CREATE TABLE {name} (" in sql
    assert "CREATE TABLE alembic_version" in sql
    assert "TIMESTAMP WITH TIME ZONE" in sql
    assert "VARCHAR(78)" in sql
    assert " UUID " in sql
    assert "'0001_auth'" in sql
    assert "TEST_ONLY_PASSWORD" not in sql and "example.invalid" not in sql
    blocked.assert_not_called()
    assert not migration_db.path.exists()
