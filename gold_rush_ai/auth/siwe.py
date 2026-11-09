"""Gold Rush's canonical EIP-4361 profile and EIP-191 EOA verification.

No Database, env loading, random nonce generation, RPC, cookie or session I/O.
The service supplies an unpredictable nonce and a trusted SiweChallenge copied
from storage, never from the verify request. A successful signature check is
NOT a login: the service must still check browser binding and atomically
consume the unexpired, unused challenge together with session/grant issuance.
Repeated verification here is deliberately stateless, not replay protection.

This is a parser for OUR generated profile, not all optional EIP-4361 forms:
explicit http(s) scheme from AuthConfig's URI, checksum EOA, fixed statement,
Version 1, canonical decimal chain, ASCII alphanumeric nonce (8..64), and
mandatory issuance/expiry in canonical RFC-3339 UTC (microseconds preserved).
LF only; no terminal LF, Resources, Not Before, Request ID or other fields.
The explicit scheme avoids treating local HTTP as implicit HTTPS under SIWE.
Limits match the existing Auth schemas/models: 4096 bytes, domain <=255,
URI <=2048, uint256 chain. A challenge may not exceed the configured TTL.

Only recoverable EOA signatures are supported, not EIP-1271 contract wallets,
counterfactual/delegated-wallet verification or EIP-7702 account-state policy.
Without RPC this module does not determine whether an address has code.
Do not log message/signature, dataclasses.asdict() or exception frame locals.

References: https://eips.ethereum.org/EIPS/eip-4361
https://eips.ethereum.org/EIPS/eip-191
https://eth-account.readthedocs.io/en/stable/eth_account.html
"""
from __future__ import annotations

import hmac
import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from urllib.parse import urlsplit

from eth_account import Account
from eth_account.messages import encode_defunct
from eth_utils import is_checksum_address, to_checksum_address

from .config import AuthConfig

__all__ = [
    "SiweError", "SiweChallenge", "ParsedSiweMessage", "build_siwe_message",
    "parse_siwe_message", "verify_siwe_signature",
]

_STATEMENT = "Sign in to Gold Rush. This request does not transfer assets."
_HEADER = " wants you to sign in with your Ethereum account:"
_MAX_MESSAGE_BYTES = 4096
_MAX_CHAIN_ID = 2**256 - 1
_ERRORS = {
    "CONFIG_INVALID": "Cấu hình SIWE không hợp lệ.",
    "WALLET_INVALID": "Địa chỉ ví SIWE không hợp lệ.",
    "CHAIN_NOT_ALLOWED": "Chain ID SIWE không được phép.",
    "NONCE_INVALID": "Nonce SIWE phải có từ 8 đến 64 ký tự ASCII chữ hoặc số.",
    "TIMESTAMP_INVALID": "Thời gian SIWE phải có timezone và thời hạn hợp lệ.",
    "MESSAGE_INVALID": "Thông điệp không đúng định dạng SIWE của Gold Rush.",
    "MESSAGE_MISMATCH": "Thông điệp không khớp challenge đã lưu.",
    "CHALLENGE_INVALID": "Dữ liệu challenge SIWE không hợp lệ hoặc không khớp cấu hình.",
    "CHALLENGE_EXPIRED": "Challenge SIWE đã hết hạn.",
    "ISSUED_AT_FUTURE": "Challenge SIWE có thời gian phát hành ở tương lai.",
    "CLOCK_SKEW_INVALID": "Sai lệch đồng hồ cho phép phải từ 0 đến 30 giây.",
    "SIGNATURE_INVALID": "Chữ ký EOA không hợp lệ.",
    "SIGNER_MISMATCH": "Chữ ký không thuộc địa chỉ ví của challenge.",
}


class SiweError(ValueError):
    """Stable code and fixed message; never retain message/signature input."""

    def __init__(self, code: str) -> None:
        if code not in _ERRORS:
            raise ValueError("Unknown SIWE error code.")
        self.code = code
        super().__init__(_ERRORS[code])


@dataclass(frozen=True, slots=True, kw_only=True, repr=False)
class SiweChallenge:
    """Explicit storage snapshot. Merely constructing it grants no authority.

    Service copies exactly these fields from the selected stored challenge;
    message is the original text, not reconstructed from request fields.
    Browser binding, consumed_at and atomic consumption remain service-owned.
    """

    wallet_address: str
    chain_id: int
    nonce: str
    domain: str
    uri: str
    issued_at: datetime
    expires_at: datetime
    message: str

    def __repr__(self) -> str:
        return "<SiweChallenge>"


@dataclass(frozen=True, slots=True, kw_only=True, repr=False)
class ParsedSiweMessage:
    """Structurally valid fields, not proof of ownership or an authenticated session."""

    scheme: str
    domain: str
    wallet_address: str  # Exact EIP-55 representation in the signed text.
    uri: str
    chain_id: int
    nonce: str
    issued_at: datetime
    expires_at: datetime

    def __repr__(self) -> str:
        return "<ParsedSiweMessage>"


def _config(config: AuthConfig) -> str:
    if not isinstance(config, AuthConfig):
        raise SiweError("CONFIG_INVALID")
    # AuthConfig already validates authority/URI and their matching origins.
    if len(config.siwe_domain) > 255 or len(config.siwe_uri) > 2048:
        raise SiweError("CONFIG_INVALID")
    return urlsplit(config.siwe_uri).scheme


def _wallet(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", value):
        raise SiweError("WALLET_INVALID")
    return to_checksum_address(value)


def _chain(value: int, config: AuthConfig) -> int:
    if type(value) is not int or not 1 <= value <= _MAX_CHAIN_ID or value not in config.allowed_chain_ids:
        raise SiweError("CHAIN_NOT_ALLOWED")
    return value


def _nonce(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9]{8,64}", value):
        raise SiweError("NONCE_INVALID")
    return value


def _utc(value: datetime) -> datetime:
    try:
        if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
            raise SiweError("TIMESTAMP_INVALID")
        return value.astimezone(UTC)
    except (OverflowError, ValueError):
        raise SiweError("TIMESTAMP_INVALID") from None


def _time_text(value: datetime) -> str:
    precision = "microseconds" if value.microsecond else "seconds"
    return value.isoformat(timespec=precision).replace("+00:00", "Z")


def _parse_time(value: str) -> datetime:
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{6})?Z", value):
        raise SiweError("TIMESTAMP_INVALID")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        raise SiweError("TIMESTAMP_INVALID") from None
    if _time_text(parsed) != value:
        raise SiweError("TIMESTAMP_INVALID")
    return parsed


def _lifetime(issued: datetime, expires: datetime, config: AuthConfig) -> None:
    if not timedelta(0) < expires - issued <= timedelta(seconds=config.challenge_ttl_seconds):
        raise SiweError("TIMESTAMP_INVALID")


def _message_bytes(value: str) -> bytes:
    if not isinstance(value, str) or not 1 <= len(value) <= _MAX_MESSAGE_BYTES:
        raise SiweError("MESSAGE_INVALID")
    try:
        encoded = value.encode("ascii")
    except UnicodeEncodeError:
        # The generated profile is ASCII: URI/config and statement are ASCII.
        raise SiweError("MESSAGE_INVALID") from None
    if any(character != 10 and not 32 <= character <= 126 for character in encoded):
        raise SiweError("MESSAGE_INVALID")
    return encoded


def build_siwe_message(
    config: AuthConfig, *, wallet_address: str, chain_id: int, nonce: str,
    issued_at: datetime, expires_at: datetime | None = None,
) -> str:
    """Deterministic text; nonce/issuance come from the service, never the client.

    An omitted expiry is issuance + AuthConfig.challenge_ttl_seconds. An
    explicit expiry may shorten, but never extend, that lifetime. No clock is
    read and no nonce is generated here. Preserve this exact return value.
    """
    scheme = _config(config)
    wallet = _wallet(wallet_address)
    chain = _chain(chain_id, config)
    nonce = _nonce(nonce)
    issued = _utc(issued_at)
    try:
        expires = issued + timedelta(seconds=config.challenge_ttl_seconds) if expires_at is None else _utc(expires_at)
    except OverflowError:
        raise SiweError("TIMESTAMP_INVALID") from None
    _lifetime(issued, expires, config)
    message = "\n".join((
        f"{scheme}://{config.siwe_domain}{_HEADER}", wallet, "", _STATEMENT, "",
        f"URI: {config.siwe_uri}", "Version: 1", f"Chain ID: {chain}",
        f"Nonce: {nonce}", f"Issued At: {_time_text(issued)}",
        f"Expiration Time: {_time_text(expires)}",
    ))
    _message_bytes(message)
    return message


def parse_siwe_message(message: str, *, config: AuthConfig) -> ParsedSiweMessage:
    """Parse the complete canonical server profile against trusted config.

    Full line count, positions, fixed labels and canonical scalar values are
    checked; no substring matching, permissive whole-message regex or ignored
    suffixes. Optional forms outside our profile are rejected, not discarded.
    Parsing does not inspect a signature, a clock or stored nonce usage.
    """
    scheme = _config(config)
    _message_bytes(message)
    lines = message.split("\n")
    if len(lines) != 11 or (
        lines[0] != f"{scheme}://{config.siwe_domain}{_HEADER}"
        or lines[2] != "" or lines[3] != _STATEMENT or lines[4] != ""
        or lines[5] != f"URI: {config.siwe_uri}" or lines[6] != "Version: 1"
    ):
        raise SiweError("MESSAGE_INVALID")
    wallet = _wallet(lines[1])
    if not is_checksum_address(lines[1]) or wallet != lines[1]:
        raise SiweError("WALLET_INVALID")
    prefixes = ("Chain ID: ", "Nonce: ", "Issued At: ", "Expiration Time: ")
    values = []
    for line, prefix in zip(lines[7:], prefixes, strict=True):
        if not line.startswith(prefix):
            raise SiweError("MESSAGE_INVALID")
        values.append(line[len(prefix):])
    if not re.fullmatch(r"[1-9][0-9]{0,77}", values[0]):
        raise SiweError("CHAIN_NOT_ALLOWED")
    chain = _chain(int(values[0]), config)
    nonce = _nonce(values[1])
    issued, expires = _parse_time(values[2]), _parse_time(values[3])
    _lifetime(issued, expires, config)
    return ParsedSiweMessage(
        scheme=scheme, domain=config.siwe_domain, wallet_address=wallet,
        uri=config.siwe_uri, chain_id=chain, nonce=nonce,
        issued_at=issued, expires_at=expires,
    )


def verify_siwe_signature(
    message: str, signature: str, *, challenge: SiweChallenge, config: AuthConfig,
    now: datetime | None = None, clock_skew_seconds: int = 30,
) -> str:
    """Return the matched signer in lowercase, not a session or login grant.

    Up to 30 seconds' issuance skew is allowed (caller may reduce to zero).
    Expiry is absolute: now == expires_at is expired, with no expiry leeway.
    Service must atomically consume the nonce AFTER this succeeds; never use
    the signature itself as a replay key. Input message must be stored text.
    """
    parsed = parse_siwe_message(message, config=config)
    if not isinstance(challenge, SiweChallenge):
        raise SiweError("CHALLENGE_INVALID")
    if challenge.domain != config.siwe_domain or challenge.uri != config.siwe_uri:
        raise SiweError("CHALLENGE_INVALID")
    # Validate snapshot fields too, then prove that the stored original text
    # agrees with them. Equality to that original text is checked separately.
    canonical = build_siwe_message(
        config, wallet_address=challenge.wallet_address, chain_id=challenge.chain_id,
        nonce=challenge.nonce, issued_at=challenge.issued_at, expires_at=_utc(challenge.expires_at),
    )
    stored = _message_bytes(challenge.message)
    if not hmac.compare_digest(stored, canonical.encode("ascii")):
        raise SiweError("CHALLENGE_INVALID")
    if not hmac.compare_digest(_message_bytes(message), stored):
        raise SiweError("MESSAGE_MISMATCH")
    if type(clock_skew_seconds) is not int or not 0 <= clock_skew_seconds <= 30:
        raise SiweError("CLOCK_SKEW_INVALID")
    current = _utc(datetime.now(UTC) if now is None else now)
    if current >= parsed.expires_at:
        raise SiweError("CHALLENGE_EXPIRED")
    if parsed.issued_at - current > timedelta(seconds=clock_skew_seconds):
        raise SiweError("ISSUED_AT_FUTURE")
    if not isinstance(signature, str) or not re.fullmatch(r"0x[0-9a-fA-F]{130}", signature):
        raise SiweError("SIGNATURE_INVALID")
    raw_signature = bytes.fromhex(signature[2:])
    # personal_sign providers encode parity as 0/1 or 27/28, not EIP-155 v.
    if raw_signature[-1] not in (0, 1, 27, 28):
        raise SiweError("SIGNATURE_INVALID")
    try:
        signer = Account.recover_message(encode_defunct(text=message), signature=raw_signature)
    except Exception:
        # Do not propagate library messages containing the input signature.
        raise SiweError("SIGNATURE_INVALID") from None
    if not hmac.compare_digest(signer.lower(), parsed.wallet_address.lower()):
        raise SiweError("SIGNER_MISMATCH")
    return signer.lower()
