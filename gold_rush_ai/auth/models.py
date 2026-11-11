"""Schema tài khoản/SIWE; chỉ khai báo metadata, không mở DB hoặc tạo bảng.

Alembic dùng ``Base.metadata`` làm target_metadata. Migration dùng hai custom
type UTCDateTime/ChainId cần import chúng từ module này khi render kiểu cột.
UUID dùng kiểu Uuid của SQLAlchemy: native UUID trên PostgreSQL, CHAR trên SQLite.

Service phải xác minh quyền sở hữu ví, chuẩn hóa wallet lowercase và tên
NFC/casefold trước khi ghi; model KHÔNG tự xác minh/chuyển đổi địa chỉ hoặc tên.
FK session chỉ bảo đảm user tồn tại: service còn phải đối chiếu ví của user,
purpose, expires_at/revoked_at và các điều kiện SIWE trước khi cấp quyền.
Hash lưu hex SHA-256 lowercase (64 ký tự); model không nhận/lưu token gốc,
private key, seed phrase hay chữ ký. Đúng định dạng hash không chứng minh rằng
caller đã hash token: trách nhiệm đó thuộc service.

Timestamp đầu vào bắt buộc có timezone, được đổi sang UTC. SQLite lưu UTC
không tzinfo, adapter gắn lại UTC khi đọc; PostgreSQL dùng TIMESTAMP WITH TIME
ZONE. Không dùng datetime naive hoặc giờ local làm thời gian xác thực.
"""
from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, MetaData, String, Text, UniqueConstraint, Uuid
from sqlalchemy.engine import Dialect
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import TypeDecorator, TypeEngine

__all__ = [
    "Base", "UTCDateTime", "ChainId", "User", "AuthChallenge", "AuthSession", "GameRunOwner",
]

_MAX_CHAIN_ID = 2**256 - 1


def _utc_now() -> datetime:
    # Callable default: chỉ chạy khi INSERT, không chạy khi import model.
    return datetime.now(UTC)


class UTCDateTime(TypeDecorator[datetime]):
    """Datetime aware-UTC ở Python, lưu UTC naive trên SQLite, timestamptz trên PG."""

    impl = DateTime
    cache_ok = True

    @property
    def python_type(self) -> type[datetime]:
        return datetime

    def load_dialect_impl(self, dialect: Dialect) -> TypeEngine:
        return dialect.type_descriptor(DateTime(timezone=dialect.name == "postgresql"))

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Timestamp Auth phải là datetime có timezone.")
        value = value.astimezone(UTC)
        return value if dialect.name == "postgresql" else value.replace(tzinfo=None)

    def process_result_value(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)


class ChainId(TypeDecorator[int]):
    """Integer 1..2^256-1, lưu 78 chữ số ASCII có zero-padding trên cả SQLite/PG.

    SQLite INTEGER chỉ có 64 bit và NUMERIC có thể chuyển số lớn sang float.
    Chuỗi cố định tránh mất chính xác, vẫn so sánh/sắp xếp đúng thứ tự số.
    Bind/query dùng int ở Python; SQL trực tiếp phải tuân cùng dạng lưu trữ.
    """

    impl = String(78)
    cache_ok = True

    @property
    def python_type(self) -> type[int]:
        return int

    def process_bind_param(self, value: int | None, dialect: Dialect) -> str | None:
        if value is None:
            return None
        if type(value) is not int or not 0 < value <= _MAX_CHAIN_ID:
            raise ValueError("chain_id phải là số nguyên từ 1 đến 2^256-1.")
        return f"{value:078d}"

    def process_result_value(self, value: str | None, dialect: Dialect) -> int | None:
        return None if value is None else int(value)


def _only_characters(expression: str, alphabet: str) -> str:
    # Tên cột/alphabet là hằng trong schema, không lấy từ request. replace()
    # dùng được trên SQLite lẫn PostgreSQL, không phụ thuộc REGEXP extension.
    for character in alphabet:
        expression = f"replace({expression}, '{character}', '')"
    return f"{expression} = ''"


def _wallet_check() -> CheckConstraint:
    return CheckConstraint(
        "length(wallet_address) = 42 AND substr(wallet_address, 1, 2) = '0x' AND "
        + _only_characters("substr(wallet_address, 3)", "0123456789abcdef"),
        name="wallet_format",
    )


def _hash_check(column: str) -> CheckConstraint:
    return CheckConstraint(
        f"length({column}) = 64 AND " + _only_characters(column, "0123456789abcdef"),
        name=f"{column}_format",
    )


def _chain_check() -> CheckConstraint:
    return CheckConstraint(
        "length(chain_id) = 78 AND " + _only_characters("chain_id", "0123456789")
        + f" AND chain_id BETWEEN '{1:078d}' AND '{_MAX_CHAIN_ID:078d}'",
        name="chain_id_range",
    )


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention={
        "pk": "pk_%(table_name)s",
        "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
        "uq": "uq_%(table_name)s_%(column_0_name)s",
        "ck": "ck_%(table_name)s_%(constraint_name)s",
        "ix": "ix_%(table_name)s_%(column_0_name)s",
    })

    def __repr__(self) -> str:
        # Không đọc thuộc tính ORM (có thể expired), không lộ nonce/message/hash
        # hoặc vô tình phát sinh truy vấn trong logging.
        return f"<{type(self).__name__}>"


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        UniqueConstraint("wallet_address"),
        UniqueConstraint("username_key"),
        _wallet_check(),
        CheckConstraint("length(username) BETWEEN 3 AND 20", name="username_length"),
        # Unicode casefold có thể mở rộng một ký tự thành nhiều code point.
        CheckConstraint("length(username_key) BETWEEN 1 AND 60", name="username_key_length"),
        CheckConstraint("length(avatar) BETWEEN 1 AND 32", name="avatar_length"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    wallet_address: Mapped[str] = mapped_column(String(42), nullable=False)
    username: Mapped[str] = mapped_column(String(20), nullable=False)
    username_key: Mapped[str] = mapped_column(String(60), nullable=False)
    avatar: Mapped[str] = mapped_column(String(32), nullable=False, default="george", server_default="george")
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False, default=_utc_now)


class AuthChallenge(Base):
    __tablename__ = "auth_challenges"
    __table_args__ = (
        UniqueConstraint("nonce"),
        _wallet_check(),
        _chain_check(),
        _hash_check("browser_binding_hash"),
        CheckConstraint("length(nonce) BETWEEN 8 AND 64", name="nonce_length"),
        CheckConstraint("length(domain) BETWEEN 1 AND 255", name="domain_length"),
        CheckConstraint("length(uri) BETWEEN 1 AND 2048", name="uri_length"),
        CheckConstraint("length(message) BETWEEN 1 AND 4096", name="message_length"),
        CheckConstraint("expires_at > issued_at", name="expiry_after_issue"),
        CheckConstraint("consumed_at IS NULL OR consumed_at >= issued_at", name="consumption_after_issue"),
        Index(None, "expires_at"),  # Cleanup challenge cũ.
        Index("ix_auth_challenges_wallet_issued", "wallet_address", "issued_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    nonce: Mapped[str] = mapped_column(String(64), nullable=False)
    wallet_address: Mapped[str] = mapped_column(String(42), nullable=False)
    chain_id: Mapped[int] = mapped_column(ChainId(), nullable=False)
    domain: Mapped[str] = mapped_column(String(255), nullable=False)
    uri: Mapped[str] = mapped_column(String(2048), nullable=False)
    message: Mapped[str] = mapped_column(Text(), nullable=False)
    browser_binding_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    # Service phải gán issued_at khớp byte-for-byte với timestamp trong message.
    issued_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)


class AuthSession(Base):
    __tablename__ = "auth_sessions"
    __table_args__ = (
        UniqueConstraint("token_hash"),
        _wallet_check(),
        _chain_check(),
        _hash_check("token_hash"),
        CheckConstraint(
            "(purpose = 'registration' AND user_id IS NULL) OR "
            "(purpose = 'authenticated' AND user_id IS NOT NULL)",
            name="purpose_user_consistency",
        ),
        CheckConstraint("expires_at > created_at", name="expiry_after_creation"),
        CheckConstraint("revoked_at IS NULL OR revoked_at >= created_at", name="revocation_after_creation"),
        Index(None, "expires_at"),
        Index(None, "user_id"),
        Index(None, "wallet_address"),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    # Không default purpose/user_id: chỉ service đã xác minh ví được cấp grant/session.
    purpose: Mapped[str] = mapped_column(String(16), nullable=False)
    wallet_address: Mapped[str] = mapped_column(String(42), nullable=False)
    chain_id: Mapped[int] = mapped_column(ChainId(), nullable=False)
    user_id: Mapped[UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False, default=_utc_now)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(UTCDateTime(), nullable=True)


class GameRunOwner(Base):
    __tablename__ = "game_run_owners"
    __table_args__ = (
        CheckConstraint("length(ma_van) BETWEEN 8 AND 64", name="ma_van_length"),
        Index(None, "user_id"),
    )

    ma_van: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False, default=_utc_now)
