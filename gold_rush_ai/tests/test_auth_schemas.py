"""Auth JSON contracts: no server, wallet, cryptographic verification or DB.

Run from gold_rush_ai: python -m pytest tests/test_auth_schemas.py -q
Only structural signature checks belong here. Repr/error text redaction does
not mean model_dump or ValidationError.errors() are safe to log unfiltered.
"""
from __future__ import annotations

import importlib.util
import json
import os
import socket
import sqlite3
import sys
from collections.abc import Iterator
from copy import deepcopy
from datetime import UTC, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from types import MappingProxyType, SimpleNamespace
from unittest.mock import Mock
from uuid import UUID

import pytest
import sqlalchemy
from pydantic import TypeAdapter, ValidationError
from sqlalchemy import MetaData
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from auth import schemas
from auth.config import AuthConfig
from auth.models import User


_USER_ID = UUID("80574202-05bd-4577-8edf-d480b37cf9a2")
_CHALLENGE_ID = UUID("c21ad4be-b54e-4ecb-9c99-62dbdcedc677")
_WALLET = "0x" + "aB" * 20
_SIGNATURE = "0x" + "ab" * 65  # Synthetic bytes, not a claim of a valid signer.
_CSRF = "TEST_ONLY_CSRF_MARKER"
_REQUESTS = ("ChallengeRequest", "VerifyRequest", "RegisterRequest")
_RESPONSES = (
    "ChallengeResponse", "PublicUser", "AuthenticatedResponse",
    "RegistrationRequiredResponse", "MeResponse",
)
_FIELDS = {
    "ChallengeRequest": ("wallet_address", "chain_id"),
    "VerifyRequest": ("challenge_id", "message", "signature"),
    "RegisterRequest": ("username",),
    "ChallengeResponse": ("challenge_id", "message", "expires_at"),
    "PublicUser": ("id", "wallet_address", "username", "avatar", "created_at"),
    "AuthenticatedResponse": ("status", "user", "expires_at", "csrf_token"),
    "RegistrationRequiredResponse": ("status", "wallet_address", "expires_at", "csrf_token"),
    "MeResponse": ("user", "chain_id", "expires_at", "csrf_token"),
}
_TIMESTAMPS = (
    ("ChallengeResponse", "expires_at"), ("PublicUser", "created_at"),
    ("AuthenticatedResponse", "expires_at"), ("RegistrationRequiredResponse", "expires_at"),
    ("MeResponse", "expires_at"),
)


@pytest.fixture(autouse=True)
def no_external_io(monkeypatch: pytest.MonkeyPatch) -> Iterator[Mock]:
    blocked = Mock(side_effect=AssertionError("Schema tests must not access Database or network."))
    for name in ("create_connection", "getaddrinfo"):
        monkeypatch.setattr(socket, name, blocked)
    for name in ("connect", "connect_ex"):
        monkeypatch.setattr(socket.socket, name, blocked)
    monkeypatch.setattr(sqlite3, "connect", blocked)
    monkeypatch.setattr(sqlite3.dbapi2, "connect", blocked)
    monkeypatch.setattr(sqlalchemy, "create_engine", blocked)
    monkeypatch.setattr(Engine, "connect", blocked)
    monkeypatch.setattr(MetaData, "create_all", blocked)
    monkeypatch.setattr(Session, "execute", blocked)
    monkeypatch.setattr(Session, "get", blocked)
    yield blocked
    blocked.assert_not_called()


@pytest.fixture
def moment() -> datetime:
    return datetime(2026, 11, 8, 3, 0, 0, 123456, tzinfo=UTC)


@pytest.fixture
def payloads(moment: datetime) -> dict[str, dict]:
    user = {
        "id": str(_USER_ID), "wallet_address": _WALLET,
        "username": "Nhà Thám Hiểm", "avatar": "george", "created_at": moment,
    }
    message = (
        f"localhost:5000 wants you to sign in with your Ethereum account:\n{_WALLET}\n\n"
        "Sign in to Gold Rush. This request does not transfer assets.\n\n"
        "URI: http://localhost:5000\nVersion: 1\nChain ID: 31337\n"
        "Nonce: 7d82b0539c4a6f219b08a175e6d24310\n"
        "Issued At: 2026-11-08T03:00:00Z\nExpiration Time: 2026-11-08T03:05:00Z"
    )
    return {
        "ChallengeRequest": {"wallet_address": _WALLET, "chain_id": 31337},
        "VerifyRequest": {"challenge_id": str(_CHALLENGE_ID), "message": message, "signature": _SIGNATURE},
        "RegisterRequest": {"username": "Nhà Thám Hiểm"},
        "ChallengeResponse": {"challenge_id": str(_CHALLENGE_ID), "message": message,
                              "expires_at": moment + timedelta(minutes=5)},
        "PublicUser": dict(user),
        "AuthenticatedResponse": {"status": "authenticated", "user": dict(user),
                                  "expires_at": moment + timedelta(hours=8), "csrf_token": _CSRF},
        "RegistrationRequiredResponse": {"status": "registration_required", "wallet_address": _WALLET,
                                         "expires_at": moment + timedelta(minutes=10), "csrf_token": _CSRF},
        "MeResponse": {"user": dict(user), "chain_id": 31337,
                       "expires_at": moment + timedelta(hours=8), "csrf_token": _CSRF},
    }


@pytest.fixture
def result_adapter() -> TypeAdapter:
    return TypeAdapter(schemas.VerifyResponse)


def test_import_needs_no_auth_env_database_or_files(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    name = "auth._schemas_import_test"
    spec = importlib.util.spec_from_file_location(name, schemas.__file__)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    with monkeypatch.context() as local:
        local.setattr(os, "environ", MappingProxyType({}))
        local.setattr(sys, "dont_write_bytecode", True)
        local.chdir(tmp_path)
        local.setitem(sys.modules, name, module)
        spec.loader.exec_module(module)
        assert module.RegisterRequest(username="Explorer").username_key == "explorer"
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("name", _REQUESTS + _RESPONSES)
def test_contract_accepts_valid_payload_and_json_roundtrip(name: str, payloads) -> None:
    model = getattr(schemas, name)
    value = model.model_validate(payloads[name])
    serialized = value.model_dump_json()
    assert set(json.loads(serialized)) == set(_FIELDS[name])
    assert model.model_validate_json(serialized) == value


def test_challenge_wallet_is_validated_and_lowercased(payloads) -> None:
    request = schemas.ChallengeRequest(**payloads["ChallengeRequest"])
    assert request.wallet_address == _WALLET.lower()
    assert set(request.model_dump()) == {"wallet_address", "chain_id"}


@pytest.mark.parametrize("wallet", [
    "", "0x123", "0x" + "1" * 39, "0x" + "1" * 41, "1" * 40,
    "0X" + "1" * 40, "0x" + "g" * 40, "0x" + "1" * 39 + "\n",
    " " + _WALLET, _WALLET + " ", b"0x" + b"1" * 40, 123, None,
])
def test_challenge_rejects_bad_wallet(wallet, payloads) -> None:
    with pytest.raises(ValidationError):
        schemas.ChallengeRequest(**(payloads["ChallengeRequest"] | {"wallet_address": wallet}))


@pytest.mark.parametrize("chain_id", [1, 31337, 11155111, 2**256 - 1])
@pytest.mark.parametrize("name", ["ChallengeRequest", "MeResponse"])
def test_chain_id_accepts_positive_uint256(name, chain_id, payloads) -> None:
    value = getattr(schemas, name)(**(payloads[name] | {"chain_id": chain_id}))
    assert type(value.chain_id) is int and value.chain_id == chain_id


@pytest.mark.parametrize("chain_id", [0, -1, False, True, 2**256, "31337", 31337.0, Decimal(31337), None])
@pytest.mark.parametrize("name", ["ChallengeRequest", "MeResponse"])
def test_chain_id_rejects_invalid_or_coerced_values(name, chain_id, payloads) -> None:
    with pytest.raises(ValidationError):
        getattr(schemas, name)(**(payloads[name] | {"chain_id": chain_id}))


def test_challenge_does_not_apply_config_allowlist(payloads) -> None:
    # An allowlist is runtime service policy, not a hardcoded schema default.
    assert AuthConfig.__dataclass_fields__["allowed_chain_ids"].default == (31337,)
    assert schemas.ChallengeRequest(wallet_address=_WALLET, chain_id=1).chain_id == 1


@pytest.mark.parametrize("identifier", [_CHALLENGE_ID, str(_CHALLENGE_ID), str(_CHALLENGE_ID).upper()])
def test_verify_accepts_canonical_uuid_or_uuid_instance(identifier, payloads) -> None:
    assert schemas.VerifyRequest(**(payloads["VerifyRequest"] | {"challenge_id": identifier})).challenge_id == _CHALLENGE_ID


@pytest.mark.parametrize("identifier", ["invalid", _CHALLENGE_ID.hex, _CHALLENGE_ID.bytes, "{" + str(_CHALLENGE_ID) + "}", 123, True, None])
def test_verify_rejects_noncanonical_uuid(identifier, payloads) -> None:
    with pytest.raises(ValidationError):
        schemas.VerifyRequest(**(payloads["VerifyRequest"] | {"challenge_id": identifier}))


@pytest.mark.parametrize("message", ["x" * 4096, "é" * 2048, "界" * 1365 + "x", "😀" * 1024])
def test_verify_accepts_exact_utf8_byte_limit(message, payloads) -> None:
    assert len(message.encode("utf-8")) == 4096
    assert schemas.VerifyRequest(**(payloads["VerifyRequest"] | {"message": message})).message == message


@pytest.mark.parametrize("message", ["", "x" * 4097, "é" * 2049, "界" * 1366, "😀" * 1025, "\ud800", b"text", None])
def test_verify_rejects_empty_oversized_or_non_utf8_message(message, payloads) -> None:
    with pytest.raises(ValidationError):
        schemas.VerifyRequest(**(payloads["VerifyRequest"] | {"message": message}))


def test_verify_preserves_message_bytes_and_signature_case(payloads) -> None:
    message = "  exact SIWE bytes\r\nĐa\u0323t\n "
    signature = "0x" + "aB" * 65
    parsed = schemas.VerifyRequest(**(payloads["VerifyRequest"] | {"message": message, "signature": signature}))
    assert parsed.message.encode("utf-8") == message.encode("utf-8")
    assert parsed.signature == signature


@pytest.mark.parametrize("signature", [
    "0x" + "ab" * 64, "0x" + "ab" * 66, "ab" * 65,
    "0X" + "ab" * 65, "0x" + "zz" * 65, _SIGNATURE + "\n", b"0x" + b"ab" * 65, None,
])
def test_verify_rejects_malformed_signature(signature, payloads) -> None:
    with pytest.raises(ValidationError):
        schemas.VerifyRequest(**(payloads["VerifyRequest"] | {"signature": signature}))


def test_verify_is_not_cryptographic_authentication(payloads, monkeypatch: pytest.MonkeyPatch) -> None:
    from eth_account import Account

    recover = Mock(side_effect=AssertionError("Schemas must not recover a signer."))
    monkeypatch.setattr(Account, "recover_message", recover)
    parsed = schemas.VerifyRequest(**(payloads["VerifyRequest"] | {
        "message": "Not a parsed SIWE message", "signature": "0x" + "00" * 65,
    }))
    assert set(parsed.model_dump()) == {"challenge_id", "message", "signature"}
    recover.assert_not_called()


@pytest.mark.parametrize("raw,expected", [
    ("Nhà Thám Hiểm", "Nhà Thám Hiểm"), ("  Đạt  ", "Đạt"),
    ("Nhà    Thám   Hiểm", "Nhà Thám Hiểm"), (" Đa\u0323t   123 ", "Đạt 123"),
    ("A_B-C", "A_B-C"), ("玩家１２３", "玩家１２３"), ("Đạt ١٢", "Đạt ١٢"),
    ("abc", "abc"), ("a" * 20, "a" * 20), ("e\u0301" * 20, "é" * 20),
    ("q\u0301" * 10, "q\u0301" * 10), ("123", "123"),
])
def test_username_normalization_and_unicode_boundaries(raw: str, expected: str) -> None:
    request = schemas.RegisterRequest(username=raw)
    assert request.username == expected
    assert schemas.normalize_username(raw) == expected


@pytest.mark.parametrize("username", ["", "ab", "a" * 21, "q\u0301" * 11, "   ", "___", "---", "\u0301" * 3, 123, b"Explorer", None])
def test_username_requires_length_and_letter_or_digit(username) -> None:
    with pytest.raises(ValidationError):
        schemas.RegisterRequest(username=username)


@pytest.mark.parametrize("character", [
    "\n", "\t", "\x00", "\x7f", "\u200b", "\u200d", "\u202e", "\ufeff", "\u00a0",
    "\u034f", "\u115f", "\u1160", "\u17b4", "\u180b", "\u180f", "\u3164",
    "\ufe0f", "\uffa0", "\U000e0100", "😀", "👩‍💻", "\u20e3", "/", "<", ".",
])
def test_username_rejects_controls_invisibles_emoji_and_other_characters(character: str) -> None:
    with pytest.raises(ValidationError):
        schemas.RegisterRequest(username="Đạt" + character)


def test_username_raw_limit_is_checked_before_normalization() -> None:
    assert schemas.RegisterRequest(username=" " * 253 + "Đạt").username == "Đạt"
    with pytest.raises(ValidationError):
        schemas.RegisterRequest(username=" " * 254 + "Đạt")


@pytest.mark.parametrize("raw,expected", [
    (" EXPLORER ", "explorer"), ("Straße", "strasse"),
    ("Đa\u0323t", "đạt"), ("İda", "i\u0307da"), ("ﬃ" * 20, "ffi" * 20),
])
def test_username_key_casefold_nfc_and_not_a_wire_field(raw: str, expected: str) -> None:
    request = schemas.RegisterRequest(username=raw)
    assert request.username_key == schemas.normalize_username_key(raw) == expected
    assert request.model_dump() == {"username": request.username}
    assert "username_key" not in json.loads(request.model_dump_json())


def test_username_key_keeps_vietnamese_accents_significant() -> None:
    assert schemas.normalize_username_key("Đạt") != schemas.normalize_username_key("Dat")


@pytest.mark.parametrize("field", ["user_id", "wallet_address", "is_admin", "roles", "permissions", "username_key", "avatar"])
def test_registration_cannot_inject_identity_or_permissions(field: str) -> None:
    with pytest.raises(ValidationError):
        schemas.RegisterRequest.model_validate({"username": "Explorer", field: "TEST_INJECTION"})


def test_username_validation_does_not_query_database(no_external_io: Mock) -> None:
    assert schemas.RegisterRequest(username="Đạt").username_key == "đạt"
    no_external_io.assert_not_called()


@pytest.mark.parametrize("name,field", [(name, field) for name, fields in _FIELDS.items() for field in fields])
def test_required_fields_do_not_have_fabricated_defaults(name, field, payloads) -> None:
    data = deepcopy(payloads[name])
    del data[field]
    with pytest.raises(ValidationError) as error:
        getattr(schemas, name).model_validate(data)
    assert any(item["type"] == "missing" and item["loc"] == (field,) for item in error.value.errors())


@pytest.mark.parametrize("name", _REQUESTS + _RESPONSES)
def test_extra_fields_are_forbidden(name: str, payloads) -> None:
    with pytest.raises(ValidationError) as error:
        getattr(schemas, name).model_validate(payloads[name] | {"unexpected": "TEST_VALUE"})
    assert any(item["type"] == "extra_forbidden" for item in error.value.errors())


@pytest.mark.parametrize("name,field", _TIMESTAMPS)
def test_timestamps_require_timezone(name, field, payloads, moment: datetime) -> None:
    with pytest.raises(ValidationError):
        getattr(schemas, name).model_validate(payloads[name] | {field: moment.replace(tzinfo=None)})
    with pytest.raises(ValidationError):
        getattr(schemas, name).model_validate(payloads[name] | {field: "2026-11-08T03:00:00"})


@pytest.mark.parametrize("name,field", _TIMESTAMPS)
def test_aware_datetime_and_iso_string_are_normalized_to_utc(name, field, payloads, moment: datetime) -> None:
    local = moment.astimezone(timezone(timedelta(hours=7)))
    for value in (local, local.isoformat()):
        parsed = getattr(schemas, name).model_validate(payloads[name] | {field: value})
        assert getattr(parsed, field) == moment
        assert getattr(parsed, field).tzinfo is UTC


@pytest.mark.parametrize("value", [True, 123, 123.0, "123", "2026-11-08", "invalid", b"2026-11-08T03:00:00Z", None])
def test_timestamp_does_not_coerce_epochs_or_other_values(value, payloads) -> None:
    with pytest.raises(ValidationError):
        schemas.PublicUser(**(payloads["PublicUser"] | {"created_at": value}))


@pytest.mark.parametrize("name,expected", [
    ("AuthenticatedResponse", schemas.AuthenticatedResponse),
    ("RegistrationRequiredResponse", schemas.RegistrationRequiredResponse),
])
def test_verify_union_selects_status_and_roundtrips_json(name, expected, payloads, result_adapter) -> None:
    parsed = result_adapter.validate_python(payloads[name])
    assert isinstance(parsed, expected)
    assert result_adapter.validate_json(result_adapter.dump_json(parsed)) == parsed


@pytest.mark.parametrize("status", ["administrator", "registration", "", None, True])
def test_verify_union_rejects_unknown_status(status, payloads, result_adapter) -> None:
    with pytest.raises(ValidationError):
        result_adapter.validate_python(payloads["AuthenticatedResponse"] | {"status": status})


def test_verify_union_requires_discriminator(payloads, result_adapter) -> None:
    data = dict(payloads["AuthenticatedResponse"])
    del data["status"]
    with pytest.raises(ValidationError) as error:
        result_adapter.validate_python(data)
    assert error.value.errors()[0]["type"] == "union_tag_not_found"


def test_registration_cannot_masquerade_as_authenticated(payloads, result_adapter) -> None:
    grant = payloads["RegistrationRequiredResponse"]
    with pytest.raises(ValidationError):
        schemas.AuthenticatedResponse.model_validate(grant)
    with pytest.raises(ValidationError):
        result_adapter.validate_python(grant | {"status": "authenticated"})
    with pytest.raises(ValidationError):
        result_adapter.validate_python(payloads["AuthenticatedResponse"] | {"status": "registration_required"})
    with pytest.raises(ValidationError):
        schemas.RegistrationRequiredResponse(**(grant | {"user": payloads["PublicUser"]}))
    assert "user" not in result_adapter.validate_python(grant).model_dump()


def test_authenticated_response_validates_nested_public_user(payloads) -> None:
    data = deepcopy(payloads["AuthenticatedResponse"])
    data["user"]["token_hash"] = "TEST_HASH"
    with pytest.raises(ValidationError):
        schemas.AuthenticatedResponse.model_validate(data)


@pytest.mark.parametrize("avatar", ["https://example.invalid/avatar.png", "george_hiep_si", "../avatar", None])
def test_public_user_only_accepts_current_server_avatar(avatar, payloads) -> None:
    with pytest.raises(ValidationError):
        schemas.PublicUser(**(payloads["PublicUser"] | {"avatar": avatar}))


def test_public_user_projects_only_public_orm_attributes(payloads, moment: datetime) -> None:
    source = SimpleNamespace(**payloads["PublicUser"], token_hash="TEST_INTERNAL_HASH", private_key="TEST_INTERNAL_FIELD")
    public = schemas.PublicUser.model_validate(source)
    assert set(public.model_dump()) == set(_FIELDS["PublicUser"])
    assert "TEST_INTERNAL" not in public.model_dump_json()
    # Constructing a model in memory does not connect to SQLAlchemy's Engine.
    user = User(id=_USER_ID, wallet_address=_WALLET.lower(), username="Explorer", username_key="explorer",
                avatar="george", created_at=moment)
    assert schemas.PublicUser.model_validate(user).id == _USER_ID


@pytest.mark.parametrize("name", _RESPONSES)
def test_response_has_no_internal_secret_fields(name: str, payloads) -> None:
    forbidden = {"token", "session_token", "raw_token", "token_hash", "nonce", "browser_binding_hash", "private_key", "seed_phrase", "csrf_secret"}

    def keys(value):
        if isinstance(value, dict):
            for key, nested in value.items():
                yield key
                yield from keys(nested)
        elif isinstance(value, list):
            for nested in value:
                yield from keys(nested)

    model = getattr(schemas, name).model_validate(payloads[name])
    assert forbidden.isdisjoint(keys(json.loads(model.model_dump_json())))
    with pytest.raises(ValidationError):
        getattr(schemas, name).model_validate(payloads[name] | {"session_token": "TEST_RAW_TOKEN"})


@pytest.mark.parametrize("name", ["VerifyRequest", "ChallengeResponse"])
def test_sensitive_message_and_signature_hidden_from_repr(name: str, payloads) -> None:
    data = payloads[name] | {"message": "TEST_SENSITIVE_MESSAGE_MARKER"}
    value = getattr(schemas, name).model_validate(data)
    assert "TEST_SENSITIVE_MESSAGE_MARKER" not in repr(value)
    assert "TEST_SENSITIVE_MESSAGE_MARKER" not in str(value)
    assert _SIGNATURE not in repr(value) and _SIGNATURE not in str(value)
    assert json.loads(value.model_dump_json())["message"] == data["message"]
    if name == "VerifyRequest":
        assert json.loads(value.model_dump_json())["signature"] == _SIGNATURE


@pytest.mark.parametrize("name", ["AuthenticatedResponse", "RegistrationRequiredResponse", "MeResponse"])
def test_csrf_hidden_from_repr_but_preserved_in_wire_json(name: str, payloads) -> None:
    model = getattr(schemas, name).model_validate(payloads[name])
    assert _CSRF not in repr(model) and _CSRF not in str(model)
    assert json.loads(model.model_dump_json())["csrf_token"] == _CSRF


@pytest.mark.parametrize("csrf", ["", "x" * 1025, "a b", "a\r\nb", "nonasciiĐạt", b"token", None])
def test_csrf_requires_bounded_printable_header_text(csrf, payloads) -> None:
    with pytest.raises(ValidationError):
        schemas.AuthenticatedResponse(**(payloads["AuthenticatedResponse"] | {"csrf_token": csrf}))


@pytest.mark.parametrize("field,value", [
    ("signature", "TEST_SENSITIVE_SIGNATURE_MARKER"),
    ("message", "TEST_SENSITIVE_MESSAGE_MARKER" + "x" * 4096),
])
def test_validation_error_text_hides_input_but_structured_errors_need_filtering(field, value, payloads) -> None:
    with pytest.raises(ValidationError) as caught:
        schemas.VerifyRequest(**(payloads["VerifyRequest"] | {field: value}))
    error = caught.value
    assert "TEST_SENSITIVE" not in str(error) and "TEST_SENSITIVE" not in repr(error)
    # Document Pydantic's actual boundary: raw structured errors are not redacted.
    assert error.errors()[0]["input"] == value
    safe_errors = error.errors(include_input=False, include_context=False)
    assert "TEST_SENSITIVE" not in json.dumps(safe_errors)


def test_json_schema_describes_status_discriminator_and_utf8_cap(result_adapter) -> None:
    assert result_adapter.json_schema()["discriminator"]["propertyName"] == "status"
    assert schemas.VerifyRequest.model_json_schema()["properties"]["message"]["x-max-utf8-bytes"] == 4096


def test_validated_contract_is_frozen(payloads) -> None:
    value = schemas.VerifyRequest(**payloads["VerifyRequest"])
    with pytest.raises(ValidationError, match="frozen"):
        value.message = "late mutation"
