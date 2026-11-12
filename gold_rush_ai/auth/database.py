"""Engine/session SQLAlchemy cho Auth; không đọc env hoặc mở DB lúc import.

Ví dụ khi ứng dụng khởi tạo Auth (chưa gắn vào FastAPI ở bước này)::

    engine = create_auth_engine(config, create_parent_directory=True)
    factory = create_session_factory(engine)
    get_session = make_session_dependency(factory)
    # Sau khi kết thúc mọi request: engine.dispose()

Với worker/CLI, ``with session_scope(factory) as session: ...`` tự commit.
Với request, dependency chỉ quản lý vòng đời; service dùng ``session.begin()``
hoặc commit/rollback rõ ràng TRƯỚC khi trả response/Set-Cookie. Không commit
từng bước của một nghiệp vụ cần nguyên tử. Không chia sẻ Session giữa request.
Không tạo bảng, migration, singleton engine hay cấu hình logging ở module này.

SQLite dùng transaction control của sqlite3 Python >=3.12 (autocommit=False).
PRAGMA được đặt ngoài transaction trên từng DBAPI connection mới. Tham chiếu:
https://docs.sqlalchemy.org/en/20/dialects/sqlite.html
"""
from __future__ import annotations

import sqlite3
from collections.abc import Callable, Iterator
from contextlib import closing, contextmanager
from pathlib import Path
from typing import Literal

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Connection, Engine, URL, make_url
from sqlalchemy.exc import ArgumentError
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from .config import AuthConfig

__all__ = [
    "AuthDatabaseError",
    "create_auth_engine",
    "create_session_factory",
    "session_scope",
    "make_session_dependency",
]


class AuthDatabaseError(ValueError):
    """Lỗi cấu hình/khởi tạo, không đưa URL hoặc credentials vào thông báo."""


def _sqlite_url(
    url: URL, base_directory: str | Path | None, create_parent_directory: bool,
) -> tuple[URL, bool]:
    if url.get_driver_name() != "pysqlite":
        raise AuthDatabaseError("SQLite Auth chỉ hỗ trợ driver đồng bộ pysqlite.")
    if url.username is not None or url.password is not None or url.host is not None or url.port is not None:
        raise AuthDatabaseError("SQLite URL không được chứa host hoặc credentials.")
    # URI mode=memory/ro/immutable cần chính sách pooling/WAL riêng; không diễn
    # giải chúng thành tên file thông thường hoặc vô tình tạo sai database.
    if url.query or (url.database or "").startswith("file:"):
        raise AuthDatabaseError("SQLite URI/query chưa được hỗ trợ; dùng đường dẫn file hoặc :memory:.")
    memory = url.database in (None, "", ":memory:")
    if memory:
        return url, True
    try:
        path = Path(url.database)
        if not path.is_absolute():
            base = Path.cwd() if base_directory is None else Path(base_directory)
            path = base / path
        path = path.resolve()
        if path.is_dir():
            raise AuthDatabaseError("Đường dẫn SQLite phải là file, không phải thư mục.")
        if create_parent_directory:
            path.parent.mkdir(parents=True, exist_ok=True)
    except (OSError, RuntimeError, TypeError, ValueError):
        raise AuthDatabaseError("Không chuẩn bị được đường dẫn SQLite; kiểm tra thư mục và quyền truy cập.") from None
    return url.set(database=str(path)), False


def _configure_sqlite(
    connection: sqlite3.Connection, busy_timeout_ms: int, enable_wal: bool,
) -> None:
    """Được gọi bởi connect event, trước khi connection được giao cho ứng dụng."""
    previous_autocommit = connection.autocommit
    try:
        connection.autocommit = True
        with closing(connection.cursor()) as cursor:
            cursor.execute(f"PRAGMA busy_timeout={busy_timeout_ms}")
            cursor.execute("PRAGMA foreign_keys=ON")
            if cursor.execute("PRAGMA foreign_keys").fetchone() != (1,):
                raise AuthDatabaseError("SQLite không bật được foreign keys.")
            if enable_wal:
                mode = cursor.execute("PRAGMA journal_mode").fetchone()[0]
                if mode.lower() != "wal":
                    mode = cursor.execute("PRAGMA journal_mode=WAL").fetchone()[0]
                if mode.lower() != "wal":
                    raise AuthDatabaseError("SQLite không bật được WAL; kiểm tra filesystem hoặc tắt sqlite_wal.")
            # Giữ độ bền commit, không đổi synchronous sang NORMAL/OFF.
            cursor.execute("PRAGMA synchronous=FULL")
        connection.autocommit = previous_autocommit
    except BaseException:
        # Connect hook thất bại: connection chưa checkout không được bỏ mở.
        connection.close()
        raise


def create_auth_engine(
    config: AuthConfig | None = None,
    *,
    database_url: str | URL | None = None,
    base_directory: str | Path | None = None,
    create_parent_directory: bool = False,
    sqlite_busy_timeout_ms: int = 5000,
    sqlite_wal: bool = True,
) -> Engine:
    """Tạo Engine lazy từ đúng một nguồn: AuthConfig hoặc database_url inject.

    Không mở connection, không tạo file DB/bảng. Chỉ tạo thư mục cha khi bật
    create_parent_directory. Đường dẫn SQLite tương đối được cố định theo CWD
    tại lúc gọi, hoặc base_directory inject; không phụ thuộc CWD về sau.

    File SQLite dùng pool mặc định SQLAlchemy, WAL mặc định bật (có thể tắt
    cho filesystem không hỗ trợ). :memory: dùng StaticPool giữ một connection,
    CHỈ phù hợp truy cập tuần tự/test; không dùng cho request đồng thời.
    SQLite URI/query/async driver chưa được hỗ trợ. Non-SQLite không nhận
    PRAGMA hoặc connect_args SQLite; PostgreSQL cần cài driver riêng sau này.
    """
    if config is not None and not isinstance(config, AuthConfig):
        raise AuthDatabaseError("config phải là AuthConfig.")
    if (config is None) == (database_url is None):
        raise AuthDatabaseError("Cung cấp đúng một trong config hoặc database_url.")
    if type(sqlite_busy_timeout_ms) is not int or not 0 < sqlite_busy_timeout_ms <= 2_147_483_647:
        raise AuthDatabaseError("sqlite_busy_timeout_ms phải là số nguyên từ 1 đến 2147483647.")
    if type(sqlite_wal) is not bool or type(create_parent_directory) is not bool:
        raise AuthDatabaseError("sqlite_wal và create_parent_directory phải là bool.")
    source = config.database_url if config is not None else database_url
    if not isinstance(source, (str, URL)) or (isinstance(source, str) and (
        not source or source != source.strip() or any(ord(c) < 32 or ord(c) == 127 for c in source)
    )):
        raise AuthDatabaseError("database_url phải là URL SQLAlchemy hợp lệ.")
    try:
        url = make_url(source)
    except (ArgumentError, TypeError, ValueError):
        raise AuthDatabaseError("Không phân tích được database_url.") from None

    sqlite = url.get_backend_name() == "sqlite"
    memory = False
    if sqlite:
        if not hasattr(sqlite3.Connection, "autocommit"):
            raise AuthDatabaseError("SQLite Auth cần Python >=3.12 với sqlite3.autocommit.")
        url, memory = _sqlite_url(url, base_directory, create_parent_directory)
    elif base_directory is not None or create_parent_directory:
        raise AuthDatabaseError("Tùy chọn thư mục chỉ áp dụng cho SQLite dạng file.")

    options = {"echo": False, "echo_pool": False, "hide_parameters": True, "pool_pre_ping": True}
    if sqlite:
        options["connect_args"] = {
            "autocommit": False,
            "check_same_thread": False,
            "timeout": sqlite_busy_timeout_ms / 1000,
        }
        if memory:
            options["poolclass"] = StaticPool
    try:
        engine = create_engine(url, **options)
    except (ArgumentError, ImportError, TypeError, ValueError):
        raise AuthDatabaseError("Không tạo được Engine; kiểm tra URL và driver đồng bộ đã cài.") from None
    if engine.dialect.is_async:
        engine.dispose()
        raise AuthDatabaseError("Auth database hiện chỉ hỗ trợ Engine đồng bộ.")
    if sqlite:
        def on_connect(connection: sqlite3.Connection, _record: object) -> None:
            _configure_sqlite(connection, sqlite_busy_timeout_ms, sqlite_wal and not memory)

        event.listen(engine, "connect", on_connect)
    return engine


def create_session_factory(
    bind: Engine | Connection,
    *,
    join_transaction_mode: Literal[
        "conditional_savepoint", "create_savepoint", "control_fully", "rollback_only"
    ] = "conditional_savepoint",
) -> sessionmaker[Session]:
    """Factory tạo Session mới mỗi lần gọi; không checkout connection ở đây.

    Có thể inject Engine/Connection test. Với Connection nằm trong transaction
    test ngoài, chọn join_transaction_mode='create_savepoint' để cô lập commit.
    Engine được inject chịu trách nhiệm cấu hình driver/PRAGMA riêng.
    autoflush=False: service gọi flush() khi cần kiểm tra constraint trước commit.
    Đóng Session là kết thúc vĩnh viễn instance đó, không tái dùng cho request sau.
    """
    return sessionmaker(
        bind=bind,
        autoflush=False,
        expire_on_commit=False,
        close_resets_only=False,
        join_transaction_mode=join_transaction_mode,
    )


@contextmanager
def session_scope(factory: Callable[[], Session]) -> Iterator[Session]:
    """Một transaction tự commit/rollback, luôn đóng Session kể cả commit lỗi.

    Inject factory trả Session test được. Helper sở hữu Session được trả về;
    không đưa Session đang dùng ở nơi khác vào factory này. Không tự commit
    hoặc rollback trong block; để session.begin() quản lý toàn bộ transaction.
    Session.execute() hỗ trợ conditional UPDATE và kiểm tra rowcount ở service.
    """
    with factory() as session:
        with session.begin():
            yield session


def make_session_dependency(factory: Callable[[], Session]) -> Callable[[], Iterator[Session]]:
    """Trả generator dependency để dùng với FastAPI Depends, không import FastAPI.

    Mỗi request có Session riêng. Thành công KHÔNG tự commit: service phải dùng
    transaction tường minh trước khi trả response. Exception rollback; khi đóng,
    transaction chưa commit cũng bị rollback. Có thể override dependency/factory
    trong test. Dùng engine.dispose() ở lifecycle shutdown, sau mọi request.
    """
    def get_session() -> Iterator[Session]:
        with factory() as session:
            try:
                yield session
            except BaseException:
                session.rollback()
                raise

    return get_session
