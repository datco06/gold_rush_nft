"""Five Auth endpoints, composed explicitly; no app/Engine/DB/env I/O on import.

Composition root: app.include_router(create_auth_router(config, session_factory)).
This returns an APIRouter with prefix /api, including /me outside /auth. Do not
mount it under another /api/auth prefix. No integration with api/main.py here.
Factory creates the existing guards/Service against the supplied Engine-backed
fresh-Session factory; service owns commit/rollback/close, never HTTP cookies.

Cookies are host-only, HttpOnly, SameSite=Lax, Path=/api; Secure comes from
validated AuthConfig. Same-site local HTTP/production HTTPS only; CORS with
explicit origins and credentials must be configured by the composition root.
Browser binding is reused across challenges/tabs. Flow cookie expiry follows
the latest challenge. Session/grant cookie expiry never exceeds DB expiry;
all successful Set-Cookie operations happen AFTER committed service results.

Only these routes receive bounded-body/error handling, preserving old APIs.
Body limit is 8 KiB on ASGI chunks before JSON parsing, even without a truthful
Content-Length. Compression is rejected, not decompressed. Validation errors
never echo message/signature/token input or arbitrary extra-field names.
Unknown errors return a fixed 500 without logging exception/body/credentials.
Errors from guards retain their 401/403/503 policy; service errors are mapped
below. 404/405 or redirects from the outer router are app-level responses.

No rate limiter exists yet: this module does NOT claim production rate-limit
protection or return fabricated 429s. Add a shared, tested limiter at the HTTP
boundary before Internet deployment. No EIP-1271, MetaMask RPC, asset transfer,
game ownership enforcement, DB migrations or application startup are done here.
"""
from __future__ import annotations

import math
import re
from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.routing import APIRoute
from pydantic import BaseModel, ConfigDict, SecretStr
from sqlalchemy.orm import Session
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import JSONResponse

from .config import AuthConfig
from .dependencies import (
    LogoutCredential, RegistrationCredential, make_auth_dependencies,
)
from .schemas import (
    AuthenticatedResponse, ChallengeRequest, ChallengeResponse, MeResponse,
    RegisterRequest, VerifyRequest, VerifyResponse,
)
from .service import AuthService, AuthServiceError, SessionIssue, new_browser_binding

__all__ = ["create_auth_router"]

_MAX_BODY_BYTES = 8192
_COOKIE_PATH = "/api"
_SERVICE_STATUS = {
    "INVALID_REQUEST": 422, "WALLET_INVALID": 422, "CHAIN_NOT_ALLOWED": 422,
    "USERNAME_INVALID": 422, "USERNAME_TAKEN": 409, "WALLET_ALREADY_REGISTERED": 409,
    "BROWSER_BINDING_INVALID": 401, "CHALLENGE_NOT_FOUND": 401,
    "CHALLENGE_INVALID": 401, "CHALLENGE_EXPIRED": 410, "CHALLENGE_USED": 409,
    "MESSAGE_INVALID": 401, "MESSAGE_MISMATCH": 401, "SIGNATURE_INVALID": 401,
    "SIGNER_MISMATCH": 401, "ISSUED_AT_FUTURE": 401,
    "SESSION_INVALID": 401, "SESSION_EXPIRED": 401, "SESSION_REVOKED": 401,
    "GRANT_INVALID": 401, "GRANT_EXPIRED": 401,
    "DATABASE_BUSY": 503, "DATABASE_ERROR": 503, "DATABASE_CONFLICT": 409,
    "CONFIG_INVALID": 500, "SESSION_FACTORY_INVALID": 500, "CLOCK_INVALID": 500,
}


def _error(status: int, code: str, message: str, *, field: str | None = None) -> JSONResponse:
    detail = {"code": code, "message": message}
    if field is not None:
        detail["field"] = field
    return JSONResponse(status_code=status, content={"detail": detail}, headers={"Cache-Control": "no-store"})


def _http(status: int, code: str, message: str) -> None:
    raise HTTPException(status_code=status, detail={"code": code, "message": message})


class _AuthRoute(APIRoute):
    def get_route_handler(self) -> Callable:
        original = super().get_route_handler()

        async def guarded(request: Request) -> Response:
            try:
                lengths = request.headers.getlist("content-length")
                if lengths:
                    if len(lengths) != 1 or not re.fullmatch(r"[0-9]{1,10}", lengths[0]):
                        _http(400, "INVALID_REQUEST", "Content-Length không hợp lệ.")
                    if int(lengths[0]) > _MAX_BODY_BYTES:
                        _http(413, "BODY_TOO_LARGE", "Nội dung yêu cầu không được vượt quá 8 KiB.")
                encodings = request.headers.getlist("content-encoding")
                if encodings and encodings != ["identity"]:
                    _http(415, "ENCODING_NOT_SUPPORTED", "Auth không hỗ trợ nội dung yêu cầu nén.")
                consumed = 0

                async def bounded_receive():
                    nonlocal consumed
                    event = await request.receive()
                    if event["type"] == "http.request":
                        consumed += len(event.get("body", b""))
                        if consumed > _MAX_BODY_BYTES:
                            _http(413, "BODY_TOO_LARGE", "Nội dung yêu cầu không được vượt quá 8 KiB.")
                    return event

                # Use public Request construction, not private body-cache writes.
                bounded = Request(request.scope, receive=bounded_receive)
                result = await original(bounded)
                result.headers["Cache-Control"] = "no-store"
                return result
            except RequestValidationError as error:
                # Do not serialize errors()/body: both may contain signatures,
                # nested input, or attacker-controlled field names/context.
                username = any(item["loc"] == ("body", "username") for item in error.errors())
                return _error(
                    422, "USERNAME_INVALID" if username else "INVALID_REQUEST",
                    "Tên nhân vật không hợp lệ." if username else "Dữ liệu yêu cầu Auth không hợp lệ.",
                    field="username" if username else None,
                )
            except AuthServiceError as error:
                status = _SERVICE_STATUS.get(error.code, 500)
                if status >= 500:
                    return _error(status, "AUTH_UNAVAILABLE", "Hệ thống xác thực tạm thời không sẵn sàng.")
                return _error(status, error.code, str(AuthServiceError(error.code)),
                              field="username" if error.code in {"USERNAME_INVALID", "USERNAME_TAKEN"} else None)
            except StarletteHTTPException as error:
                if error.status_code == 204:
                    return Response(status_code=204, headers={"Cache-Control": "no-store"})
                if isinstance(error.detail, dict) and set(error.detail) == {"code", "message"}:
                    return _error(error.status_code, error.detail["code"], error.detail["message"])
                return _error(error.status_code, "INVALID_REQUEST", "Yêu cầu Auth không hợp lệ.")
            except Exception:
                return _error(500, "AUTH_INTERNAL_ERROR", "Không thể xử lý yêu cầu xác thực.")

        return guarded


class _LogoutRequest(BaseModel):
    """The documented empty JSON object; no wallet/user/token fields allowed."""

    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)


def _previous_session(request: Request) -> str | None:
    # Bootstrap verify has no authenticated dependency. This cookie is only
    # forwarded for service revocation; it is never proof of user identity.
    values = []
    for header in request.headers.getlist("cookie"):
        for part in header.split(";"):
            key, separator, value = part.strip().partition("=")
            if key == "gr_session":
                values.append(value if separator else "")
    if not values:
        return None
    if len(values) != 1 or re.fullmatch(r"[0-9a-f]{64}", values[0]) is None:
        _http(401, "SESSION_INVALID", "Cookie phiên không hợp lệ; hãy xóa phiên trước khi xác thực lại.")
    return values[0]


def create_auth_router(
    config: AuthConfig, session_factory: Callable[[], Session], *,
    clock: Callable[[], datetime] | None = None,
) -> APIRouter:
    """Create exactly five routes; caller mounts them and owns Engine lifecycle.

    Inject a UTC-aware clock for tests, using the same clock for service and
    cookie lifetime calculations. Factory creation never opens a DB connection.
    """
    guards = make_auth_dependencies(config, session_factory, clock=clock)
    router = APIRouter(prefix="/api", tags=["Auth"], route_class=_AuthRoute)
    current_time = clock if clock is not None else lambda: datetime.now(UTC)

    def set_cookie(response: Response, name: str, token: str, expires_at: datetime) -> None:
        now = current_time()
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
            raise AuthServiceError("CLOCK_INVALID")
        seconds = math.floor((expires_at - now.astimezone(UTC)).total_seconds())
        if seconds <= 0:
            _http(401, "SESSION_EXPIRED", "Quyền xác thực đã hết hạn; hãy bắt đầu lại.")
        response.set_cookie(
            name, token, max_age=seconds, expires=expires_at.astimezone(UTC), path=_COOKIE_PATH,
            secure=config.cookie_secure, httponly=True, samesite="lax",
        )

    def session_cookie(response: Response, issue: SessionIssue) -> None:
        # Service has already committed its transaction before returning issue.
        set_cookie(response, "gr_session", issue.cookie_token.get_secret_value(), issue.response.expires_at)

    @router.post("/auth/challenge", status_code=201, response_model=ChallengeResponse,
                 dependencies=[Depends(guards.bootstrap)])
    def challenge(
        payload: ChallengeRequest, response: Response,
        binding: SecretStr | None = Depends(guards.optional_browser_binding),
        svc: AuthService = Depends(guards.get_service),
    ) -> ChallengeResponse:
        flow = binding if binding is not None else new_browser_binding()
        result = svc.create_challenge(
            wallet_address=payload.wallet_address, chain_id=payload.chain_id,
            browser_binding=flow.get_secret_value(),
        )
        # Refresh expiry with the SAME value so other tabs' challenges remain bound.
        set_cookie(response, "gr_auth_flow", flow.get_secret_value(), result.expires_at)
        return result

    @router.post("/auth/verify", response_model=VerifyResponse, dependencies=[Depends(guards.bootstrap)])
    def verify(
        payload: VerifyRequest, response: Response,
        binding: SecretStr = Depends(guards.browser_binding),
        previous_token: str | None = Depends(_previous_session),
        svc: AuthService = Depends(guards.get_service),
    ) -> Any:
        issue = svc.verify(
            challenge_id=payload.challenge_id, message=payload.message, signature=payload.signature,
            browser_binding=binding.get_secret_value(), previous_session_token=previous_token,
        )
        session_cookie(response, issue)
        return issue.response  # Never return SessionIssue/cookie_token as wire JSON.

    @router.post("/auth/register", status_code=201, response_model=AuthenticatedResponse)
    def register(
        payload: RegisterRequest, response: Response,
        credential: RegistrationCredential = Depends(guards.registration_mutation),
        svc: AuthService = Depends(guards.get_service),
    ) -> Any:
        issue = svc.register(registration_token=credential.cookie_token.get_secret_value(), username=payload.username)
        session_cookie(response, issue)
        return issue.response

    @router.get("/me", response_model=MeResponse)
    def me(session: MeResponse = Depends(guards.authenticated_session)) -> MeResponse:
        return session

    @router.post("/auth/logout", status_code=204, response_class=Response, response_model=None)
    def logout(
        payload: _LogoutRequest, credential: LogoutCredential = Depends(guards.logout_mutation),
        svc: AuthService = Depends(guards.get_service),
    ) -> Response:
        svc.logout(credential.cookie_token.get_secret_value() if credential.cookie_token is not None else None)
        response = Response(status_code=204, headers={"Cache-Control": "no-store"})
        for name in ("gr_session", "gr_auth_flow"):
            response.delete_cookie(
                name, path=_COOKIE_PATH, secure=config.cookie_secure, httponly=True, samesite="lax",
            )
        return response

    return router
