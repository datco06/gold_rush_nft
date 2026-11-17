"""Pytest cho Database Auth; mọi DB nằm trong tmp_path hoặc :memory:.

Chạy từ gold_rush_ai: python -m pytest tests/test_auth_database.py -q
Chỉ tạo bảng thử db_probe/db_probe_child, không tạo schema Auth. Memory engine
chỉ dùng tuần tự; kiểm tra cạnh tranh luôn dùng file và các connection riêng.
Không reload module thật hoặc thay đổi cấu hình/Database của ứng dụng.
"""
from __future__ import annotations

import importlib.util
import logging
import os
import secrets
import socket
import sqlite3
import sys
from collections.abc import Callable, Iterator
from contextlib import closing
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Barrier
from types import MappingProxyType
from unittest.mock import Mock

import pytest
import sqlalchemy
from sqlalchemy import event, text
from sqlalchemy.engine import Engine, URL
from sqlalchemy.exc import IntegrityError, InvalidRequestError, OperationalError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import QueuePool

from auth import database as db
from auth.config import load_auth_config


@pytest.fixture(autouse=True)
def no_network(monkeypatch: pytest.MonkeyPatch) -> None:
    blocked = Mock(side_effect=AssertionError("Database unit test không được gọi mạng/DNS."))
    monkeypatch.setattr(socket, "create_connection", blocked)
    monkeypatch.setattr(socket, "getaddrinfo", blocked)
    monkeypatch.setattr(socket.socket, "connect", blocked)
    monkeypatch.setattr(socket.socket, "connect_ex", blocked)


@pytest.fixture
def engine_factory(tmp_path: Path) -> Iterator[Callable[..., Engine]]:
    engines: list[Engine] = []
    connections: list[sqlite3.Connection] = []

    def build(config=None, *, database_url=None, **options) -> Engine:
        if config is None and database_url is None:
            database_url = URL.create("sqlite", database=str(tmp_path / "probe.sqlite3"))
        engine = db.create_auth_engine(config, database_url=database_url, **options)
        engines.append(engine)

        def track(connection, _record) -> None:
            connections.append(connection)

        event.listen(engine, "connect", track)
        return engine

    try:
        yield build
    finally:
        # Phát hiện checkout bị giữ, vẫn dọn mọi connection kể cả test thất bại.
        leaked = []
        try:
            for engine in reversed(engines):
                if isinstance(engine.pool, QueuePool) and engine.pool.checkedout():
                    leaked.append(engine.pool.checkedout())
                engine.dispose()
        finally:
            for connection in connections:
                connection.close()
        assert not leaked, f"Connections chưa trả về pool: {leaked}"


@pytest.fixture(params=["file", "memory"])
def engine(request: pytest.FixtureRequest, engine_factory: Callable[..., Engine]) -> Engine:
    if request.param == "memory":
        return engine_factory(database_url="sqlite:///:memory:")
    return engine_factory()


@pytest.fixture
def file_engine(engine_factory: Callable[..., Engine]) -> Engine:
    return engine_factory()


def _create_probe_tables(engine: Engine) -> None:
    with engine.begin() as connection:
        connection.exec_driver_sql(
            "CREATE TABLE db_probe (id INTEGER PRIMARY KEY, label TEXT UNIQUE, "
            "quantity INTEGER NOT NULL DEFAULT 0)"
        )
        connection.exec_driver_sql(
            "CREATE TABLE db_probe_child (id INTEGER PRIMARY KEY, "
            "parent_id INTEGER REFERENCES db_probe(id) DEFERRABLE INITIALLY DEFERRED)"
        )


def _count(engine: Engine, *, child: bool = False) -> int:
    table = "db_probe_child" if child else "db_probe"
    with engine.connect() as connection:
        return connection.exec_driver_sql(f"SELECT COUNT(*) FROM {table}").scalar_one()


def _tables(engine: Engine) -> set[str]:
    with engine.connect() as connection:
        return set(connection.exec_driver_sql(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).scalars())


def _assert_closed(session: Session) -> None:
    assert not session.in_transaction()
    with pytest.raises(InvalidRequestError):
        session.execute(text("SELECT 1"))


@pytest.fixture
def probe_factory(engine: Engine) -> sessionmaker[Session]:
    _create_probe_tables(engine)
    return db.create_session_factory(engine)


def test_import_has_no_database_or_filesystem_initialization(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Tên riêng giữ nguyên identity Engine/Session/class ở các test khác.
    name = "auth._database_import_test"
    spec = importlib.util.spec_from_file_location(name, db.__file__)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    blocked = Mock(side_effect=AssertionError("Import không được tạo Engine/DB/file."))
    # Khôi phục environ trước teardown: pytest cần cập nhật PYTEST_CURRENT_TEST.
    with monkeypatch.context() as patch:
        patch.chdir(tmp_path)
        patch.setattr(sys, "dont_write_bytecode", True)
        patch.setitem(sys.modules, name, module)
        patch.setattr(os, "environ", MappingProxyType({
            "AUTH_DATABASE_URL": f"sqlite:///{tmp_path / 'must-not-exist.db'}",
        }))
        patch.setattr(sqlalchemy, "create_engine", blocked)
        patch.setattr(sqlite3, "connect", blocked)
        patch.setattr(sqlite3.dbapi2, "connect", blocked)
        for method in ("mkdir", "touch", "write_bytes", "write_text"):
            patch.setattr(Path, method, blocked)
        spec.loader.exec_module(module)

    blocked.assert_not_called()
    assert list(tmp_path.iterdir()) == []
    assert not any(isinstance(value, (Engine, Session)) for value in vars(module).values())


def test_engine_from_auth_config_resolves_default_url_in_temporary_base(
    tmp_path: Path, engine_factory: Callable[..., Engine],
) -> None:
    config = load_auth_config({"AUTH_CSRF_SECRET": secrets.token_hex(32)})
    engine = engine_factory(config, base_directory=tmp_path, create_parent_directory=True)
    target = tmp_path / "data" / "auth" / "gold_rush_auth.db"
    assert engine.url.database == str(target.resolve())
    assert target.parent.is_dir()
    assert not target.exists()
    assert _tables(engine) == set()
    assert target.is_file()


@pytest.mark.parametrize("as_url_object", [False, True])
def test_injected_database_url(
    tmp_path: Path, engine_factory: Callable[..., Engine], as_url_object: bool,
) -> None:
    path = tmp_path / "injected.sqlite3"
    url = URL.create("sqlite", database=str(path))
    engine = engine_factory(database_url=url if as_url_object else str(url))
    assert not path.exists()
    with engine.connect() as connection:
        assert connection.exec_driver_sql("SELECT 1").scalar_one() == 1
    assert path.is_file()


def test_engine_and_session_factory_are_lazy(file_engine: Engine) -> None:
    path = Path(file_engine.url.database)
    assert not path.exists()
    factory = db.create_session_factory(file_engine)
    assert isinstance(factory, sessionmaker)
    with factory() as session:
        assert isinstance(session, Session)
        assert not path.exists()
        assert session.get_bind() is file_engine
        assert file_engine.pool.checkedout() == 0
    assert not path.exists()


def test_no_tables_created_when_engine_first_connects(engine: Engine) -> None:
    assert _tables(engine) == set()


def test_parent_directory_is_not_created_without_opt_in(
    tmp_path: Path, engine_factory: Callable[..., Engine],
) -> None:
    engine_factory(database_url="sqlite:///absent/probe.db", base_directory=tmp_path)
    assert not (tmp_path / "absent").exists()


def test_relative_path_stays_fixed_after_working_directory_changes(
    tmp_path: Path, engine_factory: Callable[..., Engine], monkeypatch: pytest.MonkeyPatch,
) -> None:
    engine = engine_factory(database_url="sqlite:///fixed.sqlite3", base_directory=tmp_path)
    other = tmp_path / "other"
    other.mkdir()
    monkeypatch.chdir(other)
    assert _tables(engine) == set()
    assert (tmp_path / "fixed.sqlite3").is_file()
    assert not (other / "fixed.sqlite3").exists()


@pytest.mark.parametrize("url", [
    pytest.param("", id="empty"),
    pytest.param("not-a-url", id="missing-scheme"),
    pytest.param(" sqlite:///:memory:", id="outer-whitespace"),
    pytest.param("sqlite:///bad\npath.db", id="control-character"),
    pytest.param("sqlite://user:TEST_PASSWORD@localhost/probe", id="sqlite-credentials"),
    pytest.param("sqlite:///file:probe?uri=true", id="unsupported-uri"),
    pytest.param("sqlite+aiosqlite:///:memory:", id="unsupported-async-driver"),
    pytest.param("missing_auth_test_dialect://host/probe", id="unknown-dialect"),
])
def test_invalid_database_urls_are_rejected(url: str) -> None:
    with pytest.raises(db.AuthDatabaseError):
        db.create_auth_engine(database_url=url)


def test_missing_and_ambiguous_url_sources_are_rejected() -> None:
    with pytest.raises(db.AuthDatabaseError):
        db.create_auth_engine()
    config = load_auth_config({"AUTH_CSRF_SECRET": secrets.token_hex(32)})
    with pytest.raises(db.AuthDatabaseError):
        db.create_auth_engine(config, database_url="sqlite:///:memory:")


@pytest.mark.parametrize("options", [
    {"sqlite_busy_timeout_ms": 0},
    {"sqlite_busy_timeout_ms": -1},
    {"sqlite_busy_timeout_ms": True},
    {"sqlite_busy_timeout_ms": 1.5},
    {"sqlite_busy_timeout_ms": 2**31},
    {"sqlite_wal": "true"},
    {"create_parent_directory": 1},
])
def test_invalid_engine_options_are_rejected(options: dict[str, object]) -> None:
    with pytest.raises(db.AuthDatabaseError):
        db.create_auth_engine(database_url="sqlite:///:memory:", **options)


@pytest.mark.parametrize("url", [
    "postgresql://test:TEST_DB_PASSWORD@localhost:bad-port/probe",
    "missing_auth_test_dialect://test:TEST_DB_PASSWORD@localhost/probe",
])
def test_configuration_exceptions_do_not_reveal_credentials(
    url: str, caplog: pytest.LogCaptureFixture,
) -> None:
    with caplog.at_level(logging.INFO):
        with pytest.raises(db.AuthDatabaseError) as error:
            db.create_auth_engine(database_url=url)
    output = str(error.value) + repr(error.value) + caplog.text
    assert "TEST_DB_PASSWORD" not in output
    assert url not in output


def test_request_sessions_are_distinct(engine: Engine) -> None:
    dependency = db.make_session_dependency(db.create_session_factory(engine))
    with closing(dependency()) as first_request, closing(dependency()) as second_request:
        first, second = next(first_request), next(second_request)
        assert first is not second
        assert first.get_bind() is second.get_bind() is engine
    _assert_closed(first)
    _assert_closed(second)


def test_uncommitted_data_is_not_visible_to_other_file_session(file_engine: Engine) -> None:
    _create_probe_tables(file_engine)
    factory = db.create_session_factory(file_engine)
    with factory() as writer, factory() as reader:
        writer.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'pending')"))
        assert reader.scalar(text("SELECT COUNT(*) FROM db_probe")) == 0
        writer.rollback()
    assert _count(file_engine) == 0


def test_session_scope_commits_multiple_operations(
    engine: Engine, probe_factory: sessionmaker[Session],
) -> None:
    with db.session_scope(probe_factory) as session:
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'parent')"))
        session.execute(text("INSERT INTO db_probe_child(id,parent_id) VALUES (1,1)"))
    assert _count(engine) == _count(engine, child=True) == 1
    _assert_closed(session)


@pytest.mark.parametrize("error_type", [RuntimeError, KeyboardInterrupt])
def test_session_scope_rolls_back_and_closes_on_exception(
    engine: Engine, probe_factory: sessionmaker[Session], error_type: type[BaseException],
) -> None:
    failure = error_type("abort transaction")
    with pytest.raises(error_type) as caught:
        with db.session_scope(probe_factory) as session:
            session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'rollback')"))
            session.execute(text("INSERT INTO db_probe_child(id,parent_id) VALUES (1,1)"))
            raise failure
    assert caught.value is failure
    assert _count(engine) == _count(engine, child=True) == 0
    _assert_closed(session)


def test_commit_failure_rolls_back_closes_and_allows_recovery(
    engine: Engine, probe_factory: sessionmaker[Session],
) -> None:
    body_finished = False
    with pytest.raises(IntegrityError):
        with db.session_scope(probe_factory) as failed_session:
            failed_session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'must-rollback')"))
            # FK deferred: execute thành công, COMMIT mới bị từ chối.
            failed_session.execute(text("INSERT INTO db_probe_child(id,parent_id) VALUES (1,999)"))
            body_finished = True
    assert body_finished
    assert _count(engine) == _count(engine, child=True) == 0
    _assert_closed(failed_session)
    if isinstance(engine.pool, QueuePool):
        assert engine.pool.checkedout() == 0
    with db.session_scope(probe_factory) as recovered_session:
        recovered_session.execute(text("INSERT INTO db_probe(id,label) VALUES (2,'recovered')"))
    assert _count(engine) == 1


def test_sql_errors_return_connections_to_pool(file_engine: Engine) -> None:
    factory = db.create_session_factory(file_engine)
    for _ in range(3):
        with pytest.raises(OperationalError):
            with db.session_scope(factory) as session:
                session.execute(text("SELECT * FROM missing_probe_table"))
        _assert_closed(session)
        assert file_engine.pool.checkedout() == 0
    with db.session_scope(factory) as session:
        assert session.scalar(text("SELECT 1")) == 1
    assert file_engine.pool.checkedout() == 0


def test_request_dependency_requires_explicit_commit(
    engine: Engine, probe_factory: sessionmaker[Session],
) -> None:
    dependency = db.make_session_dependency(probe_factory)
    with closing(dependency()) as request:
        session = next(request)
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'explicit')"))
        session.commit()
        with pytest.raises(StopIteration):
            next(request)
    assert _count(engine) == 1
    _assert_closed(session)


def test_request_dependency_rolls_back_uncommitted_success(
    engine: Engine, probe_factory: sessionmaker[Session],
) -> None:
    with closing(db.make_session_dependency(probe_factory)()) as request:
        session = next(request)
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'uncommitted')"))
        with pytest.raises(StopIteration):
            next(request)
    assert _count(engine) == 0
    _assert_closed(session)


@pytest.mark.parametrize("close_early", [False, True])
def test_request_dependency_rolls_back_error_or_generator_close(
    engine: Engine, probe_factory: sessionmaker[Session], close_early: bool,
) -> None:
    with closing(db.make_session_dependency(probe_factory)()) as request:
        session = next(request)
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'aborted-request')"))
        if close_early:
            request.close()
        else:
            failure = ValueError("handler error")
            with pytest.raises(ValueError) as caught:
                request.throw(failure)
            assert caught.value is failure
    assert _count(engine) == 0
    _assert_closed(session)


def test_request_can_commit_transaction_before_teardown(
    engine: Engine, probe_factory: sessionmaker[Session],
) -> None:
    with closing(db.make_session_dependency(probe_factory)()) as request:
        session = next(request)
        with session.begin():
            session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'service-transaction')"))
        # Bản ghi đã commit trước khi generator dependency đóng.
        # Memory engine không mở connection khác khi Session còn transaction.
        assert not session.in_transaction()
        assert _count(engine) == 1
    _assert_closed(session)


@pytest.mark.parametrize("timeout_ms", [5000, 1234])
def test_sqlite_connection_policy(engine_factory: Callable[..., Engine], timeout_ms: int) -> None:
    engine = engine_factory(sqlite_busy_timeout_ms=timeout_ms)
    # Hai checkout đồng thời buộc pool tạo hai DBAPI connection khác nhau.
    with engine.connect() as first, engine.connect() as second:
        assert first.connection.driver_connection is not second.connection.driver_connection
        for connection in (first, second):
            assert connection.connection.driver_connection.autocommit is False
            assert connection.exec_driver_sql("PRAGMA foreign_keys").scalar_one() == 1
            assert connection.exec_driver_sql("PRAGMA busy_timeout").scalar_one() == timeout_ms
            assert connection.exec_driver_sql("PRAGMA synchronous").scalar_one() == 2


def test_invalid_foreign_key_is_rejected(engine: Engine) -> None:
    with engine.begin() as connection:
        connection.exec_driver_sql("CREATE TABLE db_probe (id INTEGER PRIMARY KEY)")
        connection.exec_driver_sql(
            "CREATE TABLE db_probe_child (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES db_probe(id))"
        )
    with pytest.raises(IntegrityError):
        with db.session_scope(db.create_session_factory(engine)) as session:
            session.execute(text("INSERT INTO db_probe_child(id,parent_id) VALUES (1,999)"))
    assert _count(engine, child=True) == 0


@pytest.mark.parametrize("wal", [True, False])
def test_file_wal_can_be_enabled_or_left_disabled(
    engine_factory: Callable[..., Engine], wal: bool,
) -> None:
    engine = engine_factory(sqlite_wal=wal)
    with engine.connect() as connection:
        mode = connection.exec_driver_sql("PRAGMA journal_mode").scalar_one()
        assert (mode == "wal") is wal


@pytest.mark.parametrize("wal", [True, False])
def test_memory_database_is_never_forced_to_wal(
    engine_factory: Callable[..., Engine], wal: bool,
) -> None:
    engine = engine_factory(database_url="sqlite:///:memory:", sqlite_wal=wal)
    with engine.connect() as connection:
        assert connection.exec_driver_sql("PRAGMA journal_mode").scalar_one() == "memory"
        assert connection.exec_driver_sql("PRAGMA foreign_keys").scalar_one() == 1


def test_ddl_and_savepoint_changes_are_transactional(
    engine: Engine, probe_factory: sessionmaker[Session],
) -> None:
    with pytest.raises(RuntimeError):
        with db.session_scope(probe_factory) as session:
            session.execute(text("CREATE TABLE rolled_back_probe (id INTEGER)"))
            raise RuntimeError("rollback DDL")
    assert "rolled_back_probe" not in _tables(engine)
    with db.session_scope(probe_factory) as session:
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'outer')"))
        with pytest.raises(RuntimeError):
            with session.begin_nested():
                session.execute(text("INSERT INTO db_probe(id,label) VALUES (2,'inner')"))
                raise RuntimeError("rollback savepoint")
    assert _count(engine) == 1


def test_conditional_update_rolls_back_with_rest_of_transaction(
    engine: Engine, probe_factory: sessionmaker[Session],
) -> None:
    with db.session_scope(probe_factory) as session:
        session.execute(text("INSERT INTO db_probe(id,label,quantity) VALUES (1,'stock',1)"))
    statement = text("UPDATE db_probe SET quantity=quantity-1 WHERE id=1 AND quantity>0")
    with pytest.raises(RuntimeError):
        with db.session_scope(probe_factory) as session:
            assert session.execute(statement).rowcount == 1
            raise RuntimeError("rollback conditional update")
    with db.session_scope(probe_factory) as session:
        assert session.execute(statement).rowcount == 1
        assert session.execute(statement).rowcount == 0
    with engine.connect() as connection:
        assert connection.exec_driver_sql("SELECT quantity FROM db_probe WHERE id=1").scalar_one() == 0


def test_concurrent_conditional_update_has_exactly_one_winner(file_engine: Engine) -> None:
    _create_probe_tables(file_engine)
    factory = db.create_session_factory(file_engine)
    with db.session_scope(factory) as session:
        session.execute(text("INSERT INTO db_probe(id,label,quantity) VALUES (1,'stock',1)"))
    ready = Barrier(2)

    def worker() -> int:
        # Đồng bộ trước I/O, không mở read snapshot rồi nâng cấp thành writer.
        ready.wait(timeout=5)
        with db.session_scope(factory) as session:
            return session.execute(text(
                "UPDATE db_probe SET quantity=quantity-1 WHERE id=1 AND quantity>0"
            )).rowcount

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(worker), pool.submit(worker)]
        results = [future.result(timeout=10) for future in futures]
    assert sorted(results) == [0, 1]
    with file_engine.connect() as connection:
        assert connection.exec_driver_sql("SELECT quantity FROM db_probe WHERE id=1").scalar_one() == 0
    assert file_engine.pool.checkedout() == 0


def test_connection_can_be_injected_under_external_test_transaction(file_engine: Engine) -> None:
    _create_probe_tables(file_engine)
    with file_engine.connect() as connection:
        outer = connection.begin()
        try:
            factory = db.create_session_factory(connection, join_transaction_mode="create_savepoint")
            with db.session_scope(factory) as session:
                session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'fixture')"))
            assert connection.scalar(text("SELECT COUNT(*) FROM db_probe")) == 1
        finally:
            outer.rollback()
        assert not connection.closed
    assert _count(file_engine) == 0


def test_session_factory_can_be_injected_and_closes_all_sessions(file_engine: Engine) -> None:
    closed: list[Session] = []

    class TrackingSession(Session):
        def close(self) -> None:
            try:
                super().close()
            finally:
                closed.append(self)

    factory = sessionmaker(bind=file_engine, class_=TrackingSession, close_resets_only=False)
    with db.session_scope(factory) as success:
        assert success.scalar(text("SELECT 1")) == 1
    with pytest.raises(RuntimeError):
        with db.session_scope(factory) as failure:
            assert failure.scalar(text("SELECT 1")) == 1
            raise RuntimeError("abort")
    assert closed == [success, failure]
    _assert_closed(success)
    _assert_closed(failure)


def test_bound_sensitive_values_are_hidden_in_sql_errors(
    probe_factory: sessionmaker[Session], caplog: pytest.LogCaptureFixture,
) -> None:
    marker = "TEST_VALUE_NOT_FOR_LOGS"
    with db.session_scope(probe_factory) as session:
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,:label)"), {"label": marker})
    with caplog.at_level(logging.INFO, logger="sqlalchemy.engine"):
        with pytest.raises(IntegrityError) as error:
            with db.session_scope(probe_factory) as session:
                session.execute(text("INSERT INTO db_probe(id,label) VALUES (2,:label)"), {"label": marker})
    assert marker not in str(error.value)
    assert marker not in caplog.text


@pytest.mark.parametrize("memory", [False, True])
def test_database_instances_are_isolated(
    tmp_path: Path, engine_factory: Callable[..., Engine], memory: bool,
) -> None:
    if memory:
        first = engine_factory(database_url="sqlite:///:memory:")
        second = engine_factory(database_url="sqlite:///:memory:")
    else:
        first = engine_factory(database_url=URL.create("sqlite", database=str(tmp_path / "first.db")))
        second = engine_factory(database_url=URL.create("sqlite", database=str(tmp_path / "second.db")))
    _create_probe_tables(first)
    assert _tables(second) == set()
    _create_probe_tables(second)
    with db.session_scope(db.create_session_factory(first)) as session:
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'only-in-first')"))
    assert _count(first) == 1
    assert _count(second) == 0


def test_dispose_closes_idle_connections_and_preserves_file_data(file_engine: Engine) -> None:
    _create_probe_tables(file_engine)
    with db.session_scope(db.create_session_factory(file_engine)) as session:
        session.execute(text("INSERT INTO db_probe(id,label) VALUES (1,'persisted')"))
    with file_engine.connect() as connection:
        raw = connection.connection.driver_connection
    assert file_engine.pool.checkedout() == 0
    file_engine.dispose()
    with pytest.raises(sqlite3.ProgrammingError):
        raw.execute("SELECT 1")
    assert Path(file_engine.url.database).is_file()
    # dispose giải phóng pool; Engine có thể kết nối lại mà không reset dữ liệu.
    assert _count(file_engine) == 1
