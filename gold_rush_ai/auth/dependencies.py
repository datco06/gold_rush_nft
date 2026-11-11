"""Injectable HTTP guards for Auth; no app, Engine or env initialization.

Composition root calls make_auth_dependencies(config, session_factory, clock=)
once, retains its result, then uses e.g. Depends(guards.authenticated_session)
or Depends(guards.registration_mutation). Factory must create fresh Sessions
bound to the existing Auth Engine. AuthService owns their short transactions
and closes them BEFORE returning. Do not use make_session_dependency to wrap
service calls in an outer Session/transaction: service.py explicitly forbids
that injection. Tests may inject a test factory or override guards.get_service
using app.dependency_overrides. Never create an Engine per request.

Origin is mandatory on every protected browser endpoint, including GET /me.
Only exact configured browser-serialized origins are allowed; missing, null,
multiple headers and Host/Referer fallbacks are rejected. Preflight normally
ends at CORSMiddleware. A permitted OPTIONS preflight that reaches these
guards is short-circuited with 204 BEFORE credential checks or endpoint code;
this is not a replacement for configuring CORS response headers at app level.

Planned router wiring:
  challenge: bootstrap (no login), optional_browser_binding for reusable cookie
  verify: bootstrap + browser_binding (no login)
  register: registration_mutation -> credential.grant, credential.cookie_token
  me: authenticated_session (MeResponse), or current_user (PublicUser)
  logout: logout_mutation -> optional cookie; then service.logout and clear cookie
  gameplay writes: authenticated_mutation; ownership checks remain separate

Dependencies never grant identity from body/query/user_id/wallet. Registration
wallet comes only from the checked grant. CSRF uses the service HMAC AND a
currently valid session/grant; an expired session's valid HMAC is insufficient.
Mutation guards require POST/PUT/PATCH/DELETE and application/json. Router must
still enforce body size, payload schemas, rate limits, no-store error responses,
cookie attributes, atomic service mutation and any resource ownership policy.

Credential wrappers exclude raw cookies from model_dump/JSON and repr. Router
must explicitly call .cookie_token.get_secret_value() for service mutations;
never serialize SecretStr values manually, request headers or exception locals.
This module does not mount routes or modify the existing app/CORS configuration.
"""
from __future__ import annotations

import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from fastapi import Depends, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field, SecretStr
from sqlalchemy.orm import Session

from .config import AuthConfig
from .schemas import MeResponse, PublicUser, RegistrationRequiredResponse
from .service import AuthService, AuthServiceError

__all__ = [
    "AuthDependencies", "AuthenticatedCredential", "RegistrationCredential",
    "LogoutCredential", "make_auth_dependencies",
]

_MESSAGES = {
    "ORIGIN_FORBIDDEN": "Origin không được phép.",
    "SESSION_REQUIRED": "Bạn cần đăng nhập để tiếp tục.",
    "SESSION_INVALID": "Phiên đăng nhập không hợp lệ.",
    "SESSION_EXPIRED": "Phiên đăng nhập đã hết hạn.",
    "SESSION_REVOKED": "Phiên đăng nhập đã bị thu hồi.",
    "GRANT_INVALID": "Quyền đăng ký không hợp lệ hoặc đã được sử dụng.",
    "GRANT_EXPIRED": "Quyền đăng ký đã hết hạn.",
    "CHAIN_NOT_ALLOWED": "Mạng của phiên không còn được phép; hãy xác thực lại.",
    "CSRF_INVALID": "CSRF token bị thiếu hoặc không hợp lệ.",
    "BROWSER_BINDING_INVALID": "Browser binding không hợp lệ hoặc bị thiếu.",
    "BOOTSTRAP_REQUIRED": "Thiếu header khởi tạo xác thực hợp lệ.",
    "JSON_REQUIRED": "Yêu cầu phải sử dụng Content-Type application/json.",
    "METHOD_NOT_ALLOWED": "Thao tác này yêu cầu phương thức thay đổi dữ liệu.",
    "AUTH_UNAVAILABLE": "Hệ thống xác thực tạm thời không sẵn sàng.",
}
_INVALID_AUTH = {"SESSION_INVALID", "SESSION_EXPIRED", "SESSION_REVOKED", "GRANT_INVALID", "GRANT_EXPIRED"}


class _Credential(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    cookie_token: SecretStr = Field(exclude=True, repr=False)


class AuthenticatedCredential(_Credential):
    session: MeResponse


class RegistrationCredential(_Credential):
    grant: RegistrationRequiredResponse


class LogoutCredential(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, hide_input_in_errors=True)
    cookie_token: SecretStr | None = Field(default=None, exclude=True, repr=False)
    purpose: Literal["authenticated", "registration"] | None = None


@dataclass(frozen=True, slots=True, repr=False)
class AuthDependencies:
    """Stable callable instances to retain for Depends and dependency overrides."""

    get_service: Callable
    origin: Callable
    bootstrap: Callable
    browser_binding: Callable
    optional_browser_binding: Callable
    authenticated_session: Callable
    current_user: Callable
    registration_grant: Callable
    authenticated_mutation: Callable
    registration_mutation: Callable
    logout_mutation: Callable

    def __repr__(self) -> str:
        return "<AuthDependencies>"


def _fail(status: int, code: str) -> None:
    raise HTTPException(
        status_code=status, detail={"code": code, "message": _MESSAGES[code]},
        headers={"Cache-Control": "no-store"},
    )


def _service_error(error: AuthServiceError) -> None:
    if error.code in _INVALID_AUTH:
        _fail(401, error.code)
    if error.code == "CHAIN_NOT_ALLOWED":
        _fail(401, "CHAIN_NOT_ALLOWED")
    # Database/config/clock failures are availability errors, never evidence
    # of successful login, nor a fabricated "expired" response.
    _fail(503, "AUTH_UNAVAILABLE")


def _header(request: Request, name: str) -> str | None:
    values = request.headers.getlist(name)
    return values[0] if len(values) == 1 else None


def _cookie(request: Request, name: str, *, required: bool, code: str) -> str | None:
    # Reject duplicate/ambiguous cookies (e.g. host/path shadowing), rather than
    # relying on Request.cookies choosing whichever duplicate appears last.
    values = []
    for header in request.headers.getlist("cookie"):
        for part in header.split(";"):
            key, separator, value = part.strip().partition("=")
            if key == name:
                values.append(value if separator else "")
    if not values:
        if required:
            _fail(401 if name == "gr_session" else 403, code)
        return None
    if len(values) != 1 or re.fullmatch(r"[0-9a-f]{64}", values[0]) is None:
        invalid_code = "SESSION_INVALID" if code == "SESSION_REQUIRED" else code
        _fail(401 if name == "gr_session" else 403, invalid_code)
    return values[0]


def _json_mutation(request: Request) -> None:
    if request.method not in {"POST", "PUT", "PATCH", "DELETE"}:
        _fail(405, "METHOD_NOT_ALLOWED")
    content_type = _header(request, "content-type")
    if content_type is None or content_type.split(";", 1)[0].strip().lower() != "application/json":
        _fail(415, "JSON_REQUIRED")


def _csrf(request: Request, svc: AuthService, token: str) -> None:
    csrf = _header(request, "x-csrf-token")
    if csrf is None or not svc.verify_csrf_token(token, csrf):
        _fail(403, "CSRF_INVALID")


def make_auth_dependencies(
    config: AuthConfig, session_factory: Callable[[], Session], *,
    clock: Callable[[], datetime] | None = None,
) -> AuthDependencies:
    """Explicit composition only; does not open a Session or read environment."""
    # The service holds config/factory/clock, never a mutable per-request Session.
    service = AuthService(config, session_factory, clock=clock)

    def get_service() -> AuthService:
        return service

    def origin(request: Request, response: Response) -> str:
        response.headers["Cache-Control"] = "no-store"
        value = _header(request, "origin")
        if value is None or value == "null" or value not in config.cors_origins:
            _fail(403, "ORIGIN_FORBIDDEN")
        if request.method == "OPTIONS" and _header(request, "access-control-request-method") is not None:
            # Do not fall through to endpoint code or demand a session for preflight.
            raise HTTPException(status_code=204, headers={"Cache-Control": "no-store"})
        return value

    def bootstrap(request: Request, checked_origin: str = Depends(origin)) -> None:
        _json_mutation(request)
        if _header(request, "x-gold-rush-auth") != "1":
            _fail(403, "BOOTSTRAP_REQUIRED")

    def browser_binding(request: Request, checked_origin: str = Depends(origin)) -> SecretStr:
        value = _cookie(request, "gr_auth_flow", required=True, code="BROWSER_BINDING_INVALID")
        return SecretStr(value)

    def optional_browser_binding(request: Request, checked_origin: str = Depends(origin)) -> SecretStr | None:
        value = _cookie(request, "gr_auth_flow", required=False, code="BROWSER_BINDING_INVALID")
        return SecretStr(value) if value is not None else None

    def authenticated_session(
        request: Request, checked_origin: str = Depends(origin), svc: AuthService = Depends(get_service),
    ) -> MeResponse:
        token = _cookie(request, "gr_session", required=True, code="SESSION_REQUIRED")
        try:
            return svc.get_authenticated_session(token)
        except AuthServiceError as error:
            _service_error(error)

    def current_user(session: MeResponse = Depends(authenticated_session)) -> PublicUser:
        return session.user

    def registration_grant(
        request: Request, checked_origin: str = Depends(origin), svc: AuthService = Depends(get_service),
    ) -> RegistrationRequiredResponse:
        token = _cookie(request, "gr_session", required=True, code="GRANT_INVALID")
        try:
            return svc.get_registration_grant(token)
        except AuthServiceError as error:
            _service_error(error)

    def authenticated_mutation(
        request: Request, session: MeResponse = Depends(authenticated_session),
        svc: AuthService = Depends(get_service),
    ) -> AuthenticatedCredential:
        _json_mutation(request)
        token = _cookie(request, "gr_session", required=True, code="SESSION_REQUIRED")
        _csrf(request, svc, token)
        return AuthenticatedCredential(session=session, cookie_token=SecretStr(token))

    def registration_mutation(
        request: Request, grant: RegistrationRequiredResponse = Depends(registration_grant),
        svc: AuthService = Depends(get_service),
    ) -> RegistrationCredential:
        _json_mutation(request)
        token = _cookie(request, "gr_session", required=True, code="GRANT_INVALID")
        _csrf(request, svc, token)
        return RegistrationCredential(grant=grant, cookie_token=SecretStr(token))

    def logout_mutation(
        request: Request, checked_origin: str = Depends(origin), svc: AuthService = Depends(get_service),
    ) -> LogoutCredential:
        _json_mutation(request)
        token = _cookie(request, "gr_session", required=False, code="SESSION_INVALID")
        if token is None:
            return LogoutCredential()
        # AuthService exposes purpose-specific lookups. Only an INVALID result
        # allows checking registration; DB/config failures never bypass CSRF.
        try:
            svc.get_authenticated_session(token)
            purpose = "authenticated"
        except AuthServiceError as error:
            if error.code == "SESSION_INVALID":
                try:
                    svc.get_registration_grant(token)
                    purpose = "registration"
                except AuthServiceError as grant_error:
                    if grant_error.code not in {"GRANT_INVALID", "GRANT_EXPIRED"}:
                        _service_error(grant_error)
                    return LogoutCredential(cookie_token=SecretStr(token))
            elif error.code in {"SESSION_EXPIRED", "SESSION_REVOKED", "CHAIN_NOT_ALLOWED"}:
                # No currently usable authority; permit idempotent revocation.
                return LogoutCredential(cookie_token=SecretStr(token))
            else:
                _service_error(error)
        _csrf(request, svc, token)
        return LogoutCredential(cookie_token=SecretStr(token), purpose=purpose)

    return AuthDependencies(
        get_service=get_service, origin=origin, bootstrap=bootstrap,
        browser_binding=browser_binding, optional_browser_binding=optional_browser_binding,
        authenticated_session=authenticated_session, current_user=current_user,
        registration_grant=registration_grant, authenticated_mutation=authenticated_mutation,
        registration_mutation=registration_mutation, logout_mutation=logout_mutation,
    )
