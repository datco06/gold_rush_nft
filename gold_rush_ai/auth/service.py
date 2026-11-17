"""Transactional Auth business logic; no Engine/Database/env I/O on import.

Compose AuthService with AuthConfig and a factory returning a FRESH Session
bound to one Engine from create_auth_engine(). The service owns each Session,
transaction, commit and close. Do not inject a shared Session, a Connection
with an outer transaction, or a factory spanning several Engines: results may
only leave the service AFTER a real commit. Do not wrap calls in session_scope.

Verify reads a trusted snapshot in a short read transaction and verifies SIWE
outside that transaction. A fresh write transaction starts with a conditional
UPDATE (no preceding SELECT), matching ALL snapshot fields, unused state,
expiry and binding. It must affect exactly one row; creating a grant/session
and revoking the previous cookie then commit together. This avoids SQLite WAL
read-snapshot-to-writer upgrades; no PostgreSQL-style row-lock assumptions or
process-local locks. Registration similarly claims its grant as the FIRST SQL
statement. UNIQUE constraints remain the final arbiter of user identity.
Lock/serialization failures fail closed; there is no hidden transaction retry.

Router must validate Origin, JSON/body limits, bootstrap header, rate limits
and CSRF BEFORE mutations. It owns HttpOnly cookies and cookie deletion.
Return SessionIssue.response as JSON; use cookie_token.get_secret_value() ONLY
to set the cookie after this call returns. cookie_token is a SecretStr excluded
from result serialization/repr. Never log DTO dumps, tokens, signatures,
exception locals or raw SQLAlchemy errors. Binding and session cookies use
32 random bytes encoded as 64 lowercase hex characters; only SHA-256 is stored.
CSRF is a separate domain-separated HMAC over the exact session cookie value.

No EIP-1271/RPC, username availability promise outside a transaction, avatar
selection, game ownership adapter, retention cleanup or HTTP endpoints here.
"""
from __future__ import annotations

import hashlib
import hmac
import re
import secrets
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, SecretStr, ValidationError
from sqlalchemy import case, select, update
from sqlalchemy.engine import Engine
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from .config import AuthConfig
from .models import AuthChallenge, AuthSession, User
from .schemas import (
    AuthenticatedResponse, ChallengeRequest, ChallengeResponse, MeResponse,
    PublicUser, RegisterRequest, RegistrationRequiredResponse, VerifyRequest, VerifyResponse,
)
from .siwe import SiweChallenge, SiweError, build_siwe_message, verify_siwe_signature

__all__ = ["AuthServiceError", "SessionIssue", "AuthService", "new_browser_binding"]

_ERRORS = {
    "CONFIG_INVALID": "Cấu hình Auth không hợp lệ.",
    "SESSION_FACTORY_INVALID": "Auth cần session factory độc lập với một Engine.",
    "CLOCK_INVALID": "Đồng hồ Auth phải trả thời gian UTC có timezone hợp lệ.",
    "INVALID_REQUEST": "Dữ liệu yêu cầu Auth không hợp lệ.",
    "WALLET_INVALID": "Địa chỉ ví không hợp lệ.",
    "CHAIN_NOT_ALLOWED": "Chain ID không được phép.",
    "USERNAME_INVALID": "Tên nhân vật không hợp lệ.",
    "USERNAME_TAKEN": "Tên nhà thám hiểm đã được sử dụng.",
    "WALLET_ALREADY_REGISTERED": "Ví đã có tài khoản; hãy xác thực ví lại để đăng nhập.",
    "BROWSER_BINDING_INVALID": "Browser binding không hợp lệ hoặc không khớp.",
    "CHALLENGE_NOT_FOUND": "Không tìm thấy challenge.",
    "CHALLENGE_INVALID": "Challenge không hợp lệ hoặc đã thay đổi.",
    "CHALLENGE_EXPIRED": "Challenge đã hết hạn.",
    "CHALLENGE_USED": "Challenge đã được sử dụng.",
    "MESSAGE_INVALID": "Thông điệp SIWE không hợp lệ.",
    "MESSAGE_MISMATCH": "Thông điệp không khớp challenge đã lưu.",
    "SIGNATURE_INVALID": "Chữ ký xác thực không hợp lệ.",
    "SIGNER_MISMATCH": "Chữ ký không thuộc ví của challenge.",
    "ISSUED_AT_FUTURE": "Challenge được phát hành ở tương lai ngoài sai lệch cho phép.",
    "SESSION_INVALID": "Phiên đăng nhập không hợp lệ.",
    "SESSION_EXPIRED": "Phiên đăng nhập đã hết hạn.",
    "SESSION_REVOKED": "Phiên đăng nhập đã bị thu hồi.",
    "GRANT_INVALID": "Quyền đăng ký không hợp lệ hoặc đã được sử dụng.",
    "GRANT_EXPIRED": "Quyền đăng ký đã hết hạn.",
    "DATABASE_CONFLICT": "Dữ liệu Auth xung đột; hãy thử lại với yêu cầu hợp lệ.",
    "DATABASE_BUSY": "Database Auth đang bận; hãy thử lại.",
    "DATABASE_ERROR": "Không thể hoàn tất giao dịch Auth.",
}


class AuthServiceError(ValueError):
    """Fixed public message and stable code; no raw input/DB error is retained."""

    def __init__(self, code: str) -> None:
        if code not in _ERRORS:
            raise ValueError("Unknown Auth service error code.")
        self.code = code
        super().__init__(_ERRORS[code])


class SessionIssue(BaseModel):
    """Committed result: public response plus an excluded, masked cookie value."""

    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    response: VerifyResponse
    cookie_token: SecretStr = Field(exclude=True, repr=False)


def new_browser_binding() -> SecretStr:
    """Router calls once if no valid flow cookie exists, not per challenge/tab."""
    return SecretStr(secrets.token_hex(32))


def _valid_token(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _token_hash(value: str, code: str) -> str:
    if not _valid_token(value):
        raise AuthServiceError(code)
    return hashlib.sha256(value.encode("ascii")).hexdigest()


def _integrity_code(error: IntegrityError) -> str:
    # Only inspect known constraint identifiers. Never expose error/params.
    constraint = getattr(getattr(error.orig, "diag", None), "constraint_name", None)
    if constraint == "uq_users_username_key" or str(error.orig) == "UNIQUE constraint failed: users.username_key":
        return "USERNAME_TAKEN"
    if constraint == "uq_users_wallet_address" or str(error.orig) == "UNIQUE constraint failed: users.wallet_address":
        return "WALLET_ALREADY_REGISTERED"
    return "DATABASE_CONFLICT"


class AuthService:
    def __init__(
        self, config: AuthConfig, session_factory: Callable[[], Session], *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        if not isinstance(config, AuthConfig):
            raise AuthServiceError("CONFIG_INVALID")
        if not callable(session_factory):
            raise AuthServiceError("SESSION_FACTORY_INVALID")
        if clock is not None and not callable(clock):
            raise AuthServiceError("CLOCK_INVALID")
        self._config = config
        self._factory = session_factory
        self._clock = clock if clock is not None else lambda: datetime.now(UTC)

    def __repr__(self) -> str:
        return "<AuthService>"

    def _now(self) -> datetime:
        try:
            value = self._clock()
            if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
                raise ValueError
            return value.astimezone(UTC)
        except Exception:
            raise AuthServiceError("CLOCK_INVALID") from None

    @staticmethod
    def _expires(now: datetime, seconds: int) -> datetime:
        try:
            return now + timedelta(seconds=seconds)
        except OverflowError:
            raise AuthServiceError("CLOCK_INVALID") from None

    @contextmanager
    def _transaction(self) -> Iterator[Session]:
        try:
            session = self._factory()
            if not isinstance(session, Session):
                raise AuthServiceError("SESSION_FACTORY_INVALID")
            with session:
                bind = session.get_bind()
                if session.in_transaction() or not isinstance(bind, Engine) or any(
                    session.get_bind(mapper=model) is not bind for model in (User, AuthSession, AuthChallenge)
                ):
                    raise AuthServiceError("SESSION_FACTORY_INVALID")
                with session.begin():
                    yield session
            # Successful exit includes commit and close, not just flush.
        except AuthServiceError:
            raise
        except IntegrityError as error:
            raise AuthServiceError(_integrity_code(error)) from None
        except OperationalError:
            # SQLite busy/snapshot or PostgreSQL serialization/connect errors:
            # no partial result is returned and no unsafe in-place retry occurs.
            raise AuthServiceError("DATABASE_BUSY") from None
        except Exception:
            raise AuthServiceError("DATABASE_ERROR") from None

    def _csrf(self, token: str) -> str:
        return hmac.new(
            self._config.csrf_secret, b"gold-rush-auth-csrf-v1\x00" + token.encode("ascii"), hashlib.sha256,
        ).hexdigest()

    def verify_csrf_token(self, session_token: str, csrf_token: str) -> bool:
        """Pure HMAC check; dependencies must also validate Origin and session."""
        if not _valid_token(session_token) or not _valid_token(csrf_token):
            return False
        return hmac.compare_digest(self._csrf(session_token), csrf_token)

    def create_challenge(self, *, wallet_address: str, chain_id: int, browser_binding: str) -> ChallengeResponse:
        binding_hash = _token_hash(browser_binding, "BROWSER_BINDING_INVALID")
        try:
            request = ChallengeRequest(wallet_address=wallet_address, chain_id=chain_id)
        except ValidationError as error:
            fields = {item["loc"][0] for item in error.errors(include_input=False, include_context=False)}
            raise AuthServiceError("WALLET_INVALID" if "wallet_address" in fields else "CHAIN_NOT_ALLOWED") from None
        now = self._now()
        expires = self._expires(now, self._config.challenge_ttl_seconds)
        nonce = secrets.token_hex(16)
        try:
            message = build_siwe_message(
                self._config, wallet_address=request.wallet_address, chain_id=request.chain_id,
                nonce=nonce, issued_at=now, expires_at=expires,
            )
        except SiweError as error:
            raise AuthServiceError(error.code if error.code in _ERRORS else "CHALLENGE_INVALID") from None
        with self._transaction() as db:
            row = AuthChallenge(
                id=uuid4(), nonce=nonce, wallet_address=request.wallet_address, chain_id=request.chain_id,
                domain=self._config.siwe_domain, uri=self._config.siwe_uri, message=message,
                browser_binding_hash=binding_hash, issued_at=now, expires_at=expires,
            )
            db.add(row)
            db.flush()
            response = ChallengeResponse(challenge_id=row.id, message=row.message, expires_at=row.expires_at)
        return response

    @staticmethod
    def _snapshot(row: AuthChallenge) -> SiweChallenge:
        return SiweChallenge(
            wallet_address=row.wallet_address, chain_id=row.chain_id, nonce=row.nonce,
            domain=row.domain, uri=row.uri, issued_at=row.issued_at,
            expires_at=row.expires_at, message=row.message,
        )

    @staticmethod
    def _challenge_time(snapshot: SiweChallenge, now: datetime) -> None:
        if snapshot.expires_at <= now:
            raise AuthServiceError("CHALLENGE_EXPIRED")
        if snapshot.issued_at - now > timedelta(seconds=30):
            raise AuthServiceError("ISSUED_AT_FUTURE")

    def _check_challenge(self, row: AuthChallenge | None, binding_hash: str, now: datetime) -> SiweChallenge:
        if row is None:
            raise AuthServiceError("CHALLENGE_NOT_FOUND")
        if not hmac.compare_digest(row.browser_binding_hash, binding_hash):
            raise AuthServiceError("BROWSER_BINDING_INVALID")
        if row.consumed_at is not None:
            raise AuthServiceError("CHALLENGE_USED")
        snapshot = self._snapshot(row)
        self._challenge_time(snapshot, now)
        return snapshot

    @staticmethod
    def _revoke(db: Session, token_hash: str | None, now: datetime) -> None:
        if token_hash is not None:
            db.execute(update(AuthSession).where(
                AuthSession.token_hash == token_hash, AuthSession.revoked_at.is_(None),
            ).values(revoked_at=case(
                (AuthSession.created_at > now, AuthSession.created_at), else_=now,
            )).execution_options(synchronize_session=False))

    def _issue(
        self, db: Session, *, wallet_address: str, chain_id: int, user: User | None, now: datetime,
    ) -> SessionIssue:
        token = secrets.token_hex(32)
        authenticated = user is not None
        expiry = self._expires(now, self._config.session_ttl_seconds if authenticated else self._config.registration_ttl_seconds)
        db.add(AuthSession(
            id=uuid4(), token_hash=_token_hash(token, "SESSION_INVALID"),
            purpose="authenticated" if authenticated else "registration",
            wallet_address=wallet_address, chain_id=chain_id,
            user_id=user.id if authenticated else None, created_at=now, expires_at=expiry,
        ))
        db.flush()
        if authenticated:
            response = AuthenticatedResponse(
                status="authenticated", user=PublicUser.model_validate(user),
                expires_at=expiry, csrf_token=self._csrf(token),
            )
        else:
            response = RegistrationRequiredResponse(
                status="registration_required", wallet_address=wallet_address,
                expires_at=expiry, csrf_token=self._csrf(token),
            )
        return SessionIssue(response=response, cookie_token=SecretStr(token))

    def verify(
        self, *, challenge_id: UUID | str, message: str, signature: str,
        browser_binding: str, previous_session_token: str | None = None,
    ) -> SessionIssue:
        binding_hash = _token_hash(browser_binding, "BROWSER_BINDING_INVALID")
        try:
            request = VerifyRequest(challenge_id=challenge_id, message=message, signature=signature)
        except ValidationError as error:
            fields = {item["loc"][0] for item in error.errors(include_input=False, include_context=False)}
            code = "SIGNATURE_INVALID" if "signature" in fields else "MESSAGE_INVALID" if "message" in fields else "INVALID_REQUEST"
            raise AuthServiceError(code) from None
        with self._transaction() as db:
            snapshot = self._check_challenge(db.get(AuthChallenge, request.challenge_id), binding_hash, self._now())
        try:
            wallet = verify_siwe_signature(
                request.message, request.signature, challenge=snapshot, config=self._config, now=self._now(),
            )
        except SiweError as error:
            raise AuthServiceError(error.code if error.code in _ERRORS else "SIGNATURE_INVALID") from None
        with self._transaction() as db:
            now = self._now()
            # FIRST SQL in the write transaction. Include the verified snapshot
            # so a concurrent modification can never authenticate different data.
            result = db.execute(update(AuthChallenge).where(
                AuthChallenge.id == request.challenge_id, AuthChallenge.consumed_at.is_(None),
                AuthChallenge.expires_at > now, AuthChallenge.browser_binding_hash == binding_hash,
                AuthChallenge.wallet_address == snapshot.wallet_address, AuthChallenge.chain_id == snapshot.chain_id,
                AuthChallenge.nonce == snapshot.nonce, AuthChallenge.domain == snapshot.domain,
                AuthChallenge.uri == snapshot.uri, AuthChallenge.message == snapshot.message,
                AuthChallenge.issued_at == snapshot.issued_at, AuthChallenge.expires_at == snapshot.expires_at,
            ).values(consumed_at=max(now, snapshot.issued_at)).execution_options(synchronize_session=False))
            if result.rowcount != 1:
                self._check_challenge(db.get(AuthChallenge, request.challenge_id), binding_hash, self._now())
                raise AuthServiceError("CHALLENGE_INVALID")
            # A writer may have waited for a lock. Recheck expiry with a fresh
            # clock; failure rolls back the claim as well as session issuance.
            now = self._now()
            self._challenge_time(snapshot, now)
            user = db.scalar(select(User).where(User.wallet_address == wallet))
            previous_hash = _token_hash(previous_session_token, "SESSION_INVALID") if _valid_token(previous_session_token) else None
            self._revoke(db, previous_hash, now)
            issue = self._issue(db, wallet_address=wallet, chain_id=snapshot.chain_id, user=user, now=now)
        return issue

    def _check_session(self, row: AuthSession | None, purpose: str, now: datetime, *, claimed: bool = False) -> AuthSession:
        registration = purpose == "registration"
        invalid = "GRANT_INVALID" if registration else "SESSION_INVALID"
        if row is None or row.purpose != purpose or (row.user_id is None) != registration:
            raise AuthServiceError(invalid)
        if row.revoked_at is not None and not claimed:
            raise AuthServiceError("GRANT_INVALID" if registration else "SESSION_REVOKED")
        if row.expires_at <= now:
            raise AuthServiceError("GRANT_EXPIRED" if registration else "SESSION_EXPIRED")
        if row.created_at > now:
            raise AuthServiceError(invalid)
        if row.chain_id not in self._config.allowed_chain_ids:
            raise AuthServiceError("CHAIN_NOT_ALLOWED")
        return row

    def register(self, *, registration_token: str, username: str) -> SessionIssue:
        token_hash = _token_hash(registration_token, "GRANT_INVALID")
        try:
            request = RegisterRequest(username=username)
        except ValidationError:
            raise AuthServiceError("USERNAME_INVALID") from None
        with self._transaction() as db:
            now = self._now()
            # Claim BEFORE reading: concurrent requests for the same grant can
            # never both create a user/session, including on SQLite WAL.
            result = db.execute(update(AuthSession).where(
                AuthSession.token_hash == token_hash, AuthSession.purpose == "registration",
                AuthSession.user_id.is_(None), AuthSession.revoked_at.is_(None),
                AuthSession.expires_at > now, AuthSession.created_at <= now,
            ).values(revoked_at=now).execution_options(synchronize_session=False))
            grant = db.scalar(select(AuthSession).where(AuthSession.token_hash == token_hash))
            if result.rowcount != 1:
                self._check_session(grant, "registration", self._now())
                raise AuthServiceError("GRANT_INVALID")
            now = self._now()
            grant = self._check_session(grant, "registration", now, claimed=True)
            if db.scalar(select(User.id).where(User.wallet_address == grant.wallet_address)) is not None:
                raise AuthServiceError("WALLET_ALREADY_REGISTERED")
            if db.scalar(select(User.id).where(User.username_key == request.username_key)) is not None:
                raise AuthServiceError("USERNAME_TAKEN")
            user = User(
                id=uuid4(), wallet_address=grant.wallet_address, username=request.username,
                username_key=request.username_key, avatar="george", created_at=now,
            )
            db.add(user)
            db.flush()  # UNIQUE constraints decide races, even after prechecks.
            issue = self._issue(db, wallet_address=grant.wallet_address, chain_id=grant.chain_id, user=user, now=now)
        return issue

    def get_authenticated_session(self, session_token: str) -> MeResponse:
        token_hash = _token_hash(session_token, "SESSION_INVALID")
        with self._transaction() as db:
            now = self._now()
            row = self._check_session(
                db.scalar(select(AuthSession).where(AuthSession.token_hash == token_hash)), "authenticated", now,
            )
            user = db.get(User, row.user_id)
            if user is None or user.wallet_address != row.wallet_address:
                raise AuthServiceError("SESSION_INVALID")
            response = MeResponse(
                user=PublicUser.model_validate(user), chain_id=row.chain_id,
                expires_at=row.expires_at, csrf_token=self._csrf(session_token),
            )
        return response

    def get_registration_grant(self, registration_token: str) -> RegistrationRequiredResponse:
        token_hash = _token_hash(registration_token, "GRANT_INVALID")
        with self._transaction() as db:
            row = self._check_session(
                db.scalar(select(AuthSession).where(AuthSession.token_hash == token_hash)), "registration", self._now(),
            )
            response = RegistrationRequiredResponse(
                status="registration_required", wallet_address=row.wallet_address,
                expires_at=row.expires_at, csrf_token=self._csrf(registration_token),
            )
        return response

    def logout(self, session_token: str | None) -> None:
        """Idempotent revoke for authenticated sessions or registration grants."""
        if not _valid_token(session_token):
            return
        token_hash = _token_hash(session_token, "SESSION_INVALID")
        with self._transaction() as db:
            self._revoke(db, token_hash, self._now())
