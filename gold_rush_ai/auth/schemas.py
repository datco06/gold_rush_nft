"""JSON contracts for Auth; no env, Database, RPC or signature verification.

Wallets are validated then lowercased, not authenticated. Chain IDs support
1..2**256-1; the service must apply AuthConfig's allowlist. SIWE message bytes
and signature spelling are preserved. Only siwe.py may validate/recover them.

Username length counts Unicode code points AFTER NFC and ASCII-space folding.
Raw names are capped at 256 code points before normalization. Letters (L*),
decimal digits (Nd), combining marks (M*), ASCII space, '_' and '-' are allowed,
except invisible fillers/selectors and the emoji keycap mark. The key uses
NFC(casefold(name)); neither uniqueness nor ownership is checked here.

repr hides message/signature/CSRF and validation text hides input values.
model_dump/model_dump_json intentionally contain their wire values: never log
them. ValidationError.errors()/json() can still include raw input; the future
Auth router must omit input/context when formatting validation responses/logs.
Request body size, Origin/CSRF, session purpose/expiry and account authorization
are responsibilities of the future router/service, not schema validation.
"""
from __future__ import annotations

import re
import unicodedata
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import AfterValidator, AwareDatetime, BaseModel, BeforeValidator, ConfigDict, Field

__all__ = [
    "ChallengeRequest", "ChallengeResponse", "VerifyRequest", "RegisterRequest",
    "PublicUser", "AuthenticatedResponse", "RegistrationRequiredResponse",
    "VerifyResponse", "MeResponse", "normalize_username", "normalize_username_key",
]

_MAX_CHAIN_ID = 2**256 - 1
_MAX_USERNAME_RAW_LENGTH = 256
_MAX_MESSAGE_BYTES = 4096

# Default_Ignorable_Code_Point members that could pass the L*/M* whitelist.
# Other control/format/unassigned characters fail the category check below.
# Source: Unicode DerivedCoreProperties.txt, Default_Ignorable_Code_Point.
_INVISIBLE_LETTERS_OR_MARKS = (
    (0x034F, 0x034F), (0x115F, 0x1160), (0x17B4, 0x17B5),
    (0x180B, 0x180F), (0x3164, 0x3164), (0xFE00, 0xFE0F),
    (0xFFA0, 0xFFA0), (0xE0100, 0xE01EF),
)


def normalize_username(value: str) -> str:
    """Validate and normalize a name, without querying account availability."""
    if not isinstance(value, str):
        raise ValueError("Tên nhân vật phải là chuỗi.")
    if len(value) > _MAX_USERNAME_RAW_LENGTH:
        raise ValueError("Tên nhân vật thô không được vượt quá 256 ký tự.")
    for character in value:
        point = ord(character)
        category = unicodedata.category(character)
        invisible = any(start <= point <= end for start, end in _INVISIBLE_LETTERS_OR_MARKS)
        if invisible or point == 0x20E3 or not (
            category.startswith(("L", "M")) or category == "Nd" or character in " _-"
        ):
            # Reject tabs/newlines even at the edges; only ASCII space is trimmed.
            raise ValueError("Tên nhân vật chứa ký tự không được phép.")
    normalized = unicodedata.normalize("NFC", value)
    normalized = re.sub(r" +", " ", normalized.strip(" "))
    if not 3 <= len(normalized) <= 20:
        raise ValueError("Tên nhân vật phải có từ 3 đến 20 ký tự sau chuẩn hóa.")
    if not any(unicodedata.category(c).startswith("L") or unicodedata.category(c) == "Nd" for c in normalized):
        raise ValueError("Tên nhân vật phải chứa ít nhất một chữ cái hoặc chữ số.")
    return normalized


def normalize_username_key(value: str) -> str:
    """Return NFC(casefold(normalized name)); accents remain significant."""
    return unicodedata.normalize("NFC", normalize_username(value).casefold())


def _uuid_input(value: object) -> UUID:
    if isinstance(value, UUID):
        return value
    if not isinstance(value, str) or not re.fullmatch(
        r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", value,
    ):
        raise ValueError("ID phải là UUID có định dạng chuẩn.")
    return UUID(value)


def _message_bytes(value: str) -> str:
    try:
        size = len(value.encode("utf-8"))
    except UnicodeEncodeError:
        raise ValueError("Thông điệp phải mã hóa được bằng UTF-8.") from None
    if size > _MAX_MESSAGE_BYTES:
        raise ValueError("Thông điệp không được vượt quá 4096 byte UTF-8.")
    return value  # Never strip, normalize Unicode, or change newlines before signing.


def _timestamp_input(value: object) -> datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str) and len(value) <= 64:
        try:
            return datetime.fromisoformat(value)
        except ValueError:
            pass
    # In particular, do not coerce bool/int/float or numeric strings to epochs.
    raise ValueError("Thời gian phải là datetime hoặc chuỗi ISO 8601 có timezone.")


def _utc_timestamp(value: datetime) -> datetime:
    try:
        return value.astimezone(UTC)
    except (OverflowError, ValueError):
        raise ValueError("Thời gian không thể chuyển sang UTC.") from None


def _csrf_text(value: str) -> str:
    # Opaque service-issued header value, not an assumed hex/base64 encoding.
    if any(not 0x21 <= ord(character) <= 0x7E for character in value):
        raise ValueError("CSRF token phải là chuỗi ASCII không có khoảng trắng hoặc control.")
    return value


WalletAddress = Annotated[
    str, Field(strict=True, min_length=42, max_length=42, pattern=r"^0x[0-9a-fA-F]{40}$"),
    AfterValidator(str.lower),
]
ChainId = Annotated[int, Field(strict=True, ge=1, le=_MAX_CHAIN_ID)]
Identifier = Annotated[UUID, BeforeValidator(_uuid_input)]
Username = Annotated[
    str, Field(strict=True, min_length=3, max_length=20), BeforeValidator(normalize_username),
]
SiweMessage = Annotated[
    str, Field(strict=True, min_length=1, max_length=_MAX_MESSAGE_BYTES,
               json_schema_extra={"x-max-utf8-bytes": _MAX_MESSAGE_BYTES}),
    AfterValidator(_message_bytes),
]
EoaSignature = Annotated[
    str, Field(strict=True, min_length=132, max_length=132, pattern=r"^0x[0-9a-fA-F]{130}$"),
]
UtcTimestamp = Annotated[AwareDatetime, BeforeValidator(_timestamp_input), AfterValidator(_utc_timestamp)]
CsrfToken = Annotated[str, Field(strict=True, min_length=1, max_length=1024), AfterValidator(_csrf_text)]


class _AuthModel(BaseModel):
    model_config = ConfigDict(
        extra="forbid", frozen=True, hide_input_in_errors=True,
        revalidate_instances="always",
    )


class ChallengeRequest(_AuthModel):
    """A claimed wallet/chain only; allowlist and ownership belong to the service."""

    wallet_address: WalletAddress
    chain_id: ChainId


class ChallengeResponse(_AuthModel):
    challenge_id: Identifier
    message: SiweMessage = Field(repr=False)
    expires_at: UtcTimestamp


class VerifyRequest(_AuthModel):
    """Only structural checks: a well-formed signature is not proof of login."""

    challenge_id: Identifier
    message: SiweMessage = Field(repr=False)
    signature: EoaSignature = Field(repr=False)


class RegisterRequest(_AuthModel):
    username: Username

    @property
    def username_key(self) -> str:
        """Derived lookup key; never accepted from or added to the JSON request."""
        return normalize_username_key(self.username)


class PublicUser(_AuthModel):
    """Explicit public projection; from_attributes reads only these six fields."""

    model_config = ConfigDict(from_attributes=True)

    id: Identifier
    wallet_address: WalletAddress
    username: Username
    avatar: Literal["george"]
    created_at: UtcTimestamp


class AuthenticatedResponse(_AuthModel):
    status: Literal["authenticated"]
    user: PublicUser
    expires_at: UtcTimestamp
    csrf_token: CsrfToken = Field(repr=False)


class RegistrationRequiredResponse(_AuthModel):
    """Registration grant response; it does not authorize Gameplay."""

    status: Literal["registration_required"]
    wallet_address: WalletAddress
    expires_at: UtcTimestamp
    csrf_token: CsrfToken = Field(repr=False)


VerifyResponse = Annotated[
    AuthenticatedResponse | RegistrationRequiredResponse, Field(discriminator="status"),
]


class MeResponse(_AuthModel):
    user: PublicUser
    chain_id: ChainId
    expires_at: UtcTimestamp
    csrf_token: CsrfToken = Field(repr=False)
