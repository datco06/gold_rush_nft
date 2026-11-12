"""Canonical Gold Rush SIWE profile and real EIP-191 recovery, entirely offline.

Run from gold_rush_ai: python -m pytest tests/test_auth_siwe.py -q
Accounts are ephemeral eth-account fixtures, never player keys. Every expiry
test injects time; there are no sleeps. This suite tests signature/content
validation, not MetaMask UI, contract-wallet state or atomic nonce consumption.
The future service must enforce browser binding and consume a nonce once.
"""
from __future__ import annotations

import importlib.util
import os
import secrets
import socket
import sqlite3
import sys
import traceback
from collections.abc import Callable, Iterator
from dataclasses import FrozenInstanceError, replace
from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path
from types import MappingProxyType
from unittest.mock import Mock
from uuid import UUID

import pytest
import sqlalchemy
from eth_account import Account
from eth_account.messages import encode_defunct
from eth_utils import is_checksum_address
from sqlalchemy import MetaData
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from auth import models, siwe
from auth.config import AuthConfig
from auth.schemas import ChallengeResponse, VerifyRequest


@pytest.fixture(autouse=True)
def no_external_side_effects(monkeypatch: pytest.MonkeyPatch) -> Iterator[Mock]:
    blocked = Mock(side_effect=AssertionError("SIWE must not access Database/network or create Auth records."))
    for name in ("create_connection", "getaddrinfo"):
        monkeypatch.setattr(socket, name, blocked)
    for name in ("connect", "connect_ex"):
        monkeypatch.setattr(socket.socket, name, blocked)
    monkeypatch.setattr(sqlite3, "connect", blocked)
    monkeypatch.setattr(sqlite3.dbapi2, "connect", blocked)
    monkeypatch.setattr(sqlalchemy, "create_engine", blocked)
    monkeypatch.setattr(Engine, "connect", blocked)
    monkeypatch.setattr(MetaData, "create_all", blocked)
    for name in ("__init__", "execute", "add", "commit", "flush"):
        monkeypatch.setattr(Session, name, blocked)
    for model in (models.User, models.AuthChallenge, models.AuthSession, models.GameRunOwner):
        monkeypatch.setattr(model, "__init__", blocked)
    yield blocked
    blocked.assert_not_called()


@pytest.fixture
def config() -> AuthConfig:
    return AuthConfig(csrf_secret=secrets.token_bytes(32), allowed_chain_ids=(31337, 11155111, 2**256 - 1))


@pytest.fixture
def issued() -> datetime:
    return datetime(2026, 11, 8, 3, 0, 0, 123456, tzinfo=UTC)


@pytest.fixture
def wallet():
    return Account.create()


@pytest.fixture
def other_wallet():
    return Account.create()


@pytest.fixture
def build_args(wallet, issued: datetime) -> dict:
    return {
        "wallet_address": wallet.address.lower(), "chain_id": 31337,
        "nonce": "7d82b0539c4a6f219b08a175e6d24310", "issued_at": issued,
    }


@pytest.fixture
def message(config: AuthConfig, build_args: dict) -> str:
    return siwe.build_siwe_message(config, **build_args)


@pytest.fixture
def challenge(config: AuthConfig, build_args: dict, message: str) -> siwe.SiweChallenge:
    return siwe.SiweChallenge(
        **build_args, domain=config.siwe_domain, uri=config.siwe_uri,
        expires_at=build_args["issued_at"] + timedelta(seconds=config.challenge_ttl_seconds),
        message=message,
    )


def _sign(wallet, message: str) -> str:
    return "0x" + wallet.sign_message(encode_defunct(text=message)).signature.hex()


@pytest.fixture
def signature(wallet, message: str) -> str:
    return _sign(wallet, message)


@pytest.fixture
def verify(config: AuthConfig, challenge: siwe.SiweChallenge, signature: str, issued: datetime) -> Callable:
    def run(**overrides):
        arguments = {
            "message": challenge.message, "signature": signature,
            "challenge": challenge, "config": config, "now": issued,
        }
        return siwe.verify_siwe_signature(**(arguments | overrides))
    return run


def _line(message: str, index: int, replacement: str) -> str:
    lines = message.split("\n")
    lines[index] = replacement
    return "\n".join(lines)


def test_import_does_not_read_auth_env_generate_accounts_or_write_files(tmp_path, monkeypatch) -> None:
    name = "auth._siwe_import_test"
    spec = importlib.util.spec_from_file_location(name, siwe.__file__)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    blocked = Mock(side_effect=AssertionError("Import must not generate an account or nonce."))
    with monkeypatch.context() as local:
        local.setitem(sys.modules, name, module)
        local.setattr(sys, "dont_write_bytecode", True)
        local.setattr(os, "environ", MappingProxyType({}))
        local.setattr(Account, "create", blocked)
        local.setattr(secrets, "token_hex", blocked)
        local.setattr(secrets, "token_bytes", blocked)
        local.chdir(tmp_path)
        spec.loader.exec_module(module)
    blocked.assert_not_called()
    assert list(tmp_path.iterdir()) == []


def test_build_exact_eip4361_profile(config, build_args, wallet, message) -> None:
    expected = "\n".join((
        "http://localhost:5000 wants you to sign in with your Ethereum account:",
        wallet.address, "", "Sign in to Gold Rush. This request does not transfer assets.", "",
        "URI: http://localhost:5000", "Version: 1", "Chain ID: 31337",
        "Nonce: 7d82b0539c4a6f219b08a175e6d24310",
        "Issued At: 2026-11-08T03:00:00.123456Z",
        "Expiration Time: 2026-11-08T03:05:00.123456Z",
    ))
    assert message == expected
    assert siwe.build_siwe_message(config, **build_args) == expected
    assert len(message.encode("utf-8")) <= 4096
    assert not message.endswith("\n") and "\r" not in message
    assert is_checksum_address(message.split("\n")[1])


@pytest.mark.parametrize("domain,uri,origins,secure,scheme", [
    ("localhost:5000", "http://localhost:5000", ("http://localhost:5000",), False, "http"),
    ("[::1]:5000", "http://[::1]:5000", ("http://[::1]:5000",), False, "http"),
    ("game.example", "https://game.example/login", ("https://game.example",), True, "https"),
])
def test_domain_uri_and_scheme_come_from_trusted_config(config, build_args, domain, uri, origins, secure, scheme) -> None:
    trusted = replace(config, siwe_domain=domain, siwe_uri=uri, cors_origins=origins, cookie_secure=secure)
    built = siwe.build_siwe_message(trusted, **build_args)
    parsed = siwe.parse_siwe_message(built, config=trusted)
    assert built.startswith(f"{scheme}://{domain} wants you to sign in")
    assert parsed.domain == domain and parsed.uri == uri and parsed.scheme == scheme


def test_parse_all_canonical_fields(config, challenge, message, wallet, issued) -> None:
    parsed = siwe.parse_siwe_message(message, config=config)
    assert isinstance(parsed, siwe.ParsedSiweMessage)
    assert (parsed.domain, parsed.uri, parsed.scheme) == (config.siwe_domain, config.siwe_uri, "http")
    assert parsed.wallet_address == wallet.address
    assert parsed.chain_id == challenge.chain_id and parsed.nonce == challenge.nonce
    assert parsed.issued_at == issued and parsed.expires_at == challenge.expires_at
    assert parsed.issued_at.tzinfo is UTC and parsed.expires_at.tzinfo is UTC


def test_generated_message_fits_existing_json_contracts(message, signature, challenge) -> None:
    identifier = UUID("c21ad4be-b54e-4ecb-9c99-62dbdcedc677")
    assert ChallengeResponse(challenge_id=identifier, message=message, expires_at=challenge.expires_at).message == message
    assert VerifyRequest(challenge_id=identifier, message=message, signature=signature).signature == signature


@pytest.mark.parametrize("nonce", ["Ab123456", "a" * 64])
def test_nonce_length_boundaries(config, build_args, nonce: str) -> None:
    built = siwe.build_siwe_message(config, **(build_args | {"nonce": nonce}))
    assert siwe.parse_siwe_message(built, config=config).nonce == nonce


@pytest.mark.parametrize("nonce", ["1234567", "a" * 65, "abc defg", "abcdefg!", "á" * 8, "１２３４５６７８", None, 123])
def test_build_rejects_invalid_nonce(config, build_args, nonce) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.build_siwe_message(config, **(build_args | {"nonce": nonce}))
    assert error.value.code == "NONCE_INVALID"


@pytest.mark.parametrize("nonce,code", [
    ("1234567", "NONCE_INVALID"), ("a" * 65, "NONCE_INVALID"),
    ("abc defg", "NONCE_INVALID"), ("abcdefgh ", "NONCE_INVALID"),
    ("á" * 8, "MESSAGE_INVALID"),  # The ASCII profile check runs first.
])
def test_parser_rejects_invalid_nonce(config, message, nonce: str, code: str) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message(_line(message, 8, f"Nonce: {nonce}"), config=config)
    assert error.value.code == code


@pytest.mark.parametrize("chain", [31337, 11155111, 2**256 - 1])
def test_allowed_uint256_chain_roundtrip(config, build_args, chain: int) -> None:
    built = siwe.build_siwe_message(config, **(build_args | {"chain_id": chain}))
    assert siwe.parse_siwe_message(built, config=config).chain_id == chain


@pytest.mark.parametrize("chain", [1, 0, -1, True, False, "31337", 31337.0, 2**256, None])
def test_build_rejects_disallowed_or_noninteger_chain(config, build_args, chain) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.build_siwe_message(config, **(build_args | {"chain_id": chain}))
    assert error.value.code == "CHAIN_NOT_ALLOWED"


@pytest.mark.parametrize("chain,code", [
    ("1", "CHAIN_NOT_ALLOWED"), ("0", "CHAIN_NOT_ALLOWED"), ("-1", "CHAIN_NOT_ALLOWED"),
    ("031337", "CHAIN_NOT_ALLOWED"), ("+31337", "CHAIN_NOT_ALLOWED"),
    ("31337 ", "CHAIN_NOT_ALLOWED"), ("３１３３７", "MESSAGE_INVALID"),
    ("9" * 79, "CHAIN_NOT_ALLOWED"),
])
def test_parser_rejects_noncanonical_or_disallowed_chain(config, message, chain: str, code: str) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message(_line(message, 7, f"Chain ID: {chain}"), config=config)
    assert error.value.code == code


@pytest.mark.parametrize("bad_wallet", ["0x123", "0x" + "z" * 40, "0X" + "a" * 40, "0x" + "a" * 41, 123, None])
def test_build_rejects_malformed_wallet(config, build_args, bad_wallet) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.build_siwe_message(config, **(build_args | {"wallet_address": bad_wallet}))
    assert error.value.code == "WALLET_INVALID"


def test_parser_requires_eip55_checksum(config, message, wallet) -> None:
    # Flip one alphabetic checksum character, rather than assuming that an
    # arbitrary random address always has mixed case in its canonical form.
    # Use a known public EIP-55 example if the random address has no letters.
    address = wallet.address
    if not any(character in "abcdefABCDEF" for character in address[2:]):
        address = "0x52908400098527886E0F7030069857D2E4169EE7"
    index = next(index for index in range(2, len(address)) if address[index].isalpha())
    invalid = address[:index] + address[index].swapcase() + address[index + 1:]
    assert not is_checksum_address(invalid)
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message(_line(message, 1, invalid), config=config)
    assert error.value.code == "WALLET_INVALID"


@pytest.mark.parametrize("index,replacement", [
    (0, "http://evil.invalid wants you to sign in with your Ethereum account:"),
    (0, "localhost:5000 wants you to sign in with your Ethereum account:"),
    (0, "https://localhost:5000 wants you to sign in with your Ethereum account:"),
    (1, "0x123"), (2, "not empty"), (3, "Transfer assets."), (4, "not empty"),
    (5, "URI: http://localhost:5000/other"), (5, "URI:  http://localhost:5000"),
    (6, "Version: 2"), (6, "version: 1"), (7, "chain id: 31337"),
    (8, "nonce: abcdefgh"), (9, "issued at: 2026-11-08T03:00:00Z"),
    (10, "Not Before: 2026-11-08T03:05:00Z"),
])
def test_parser_rejects_wrong_fixed_fields(config, message, index, replacement) -> None:
    with pytest.raises(siwe.SiweError):
        siwe.parse_siwe_message(_line(message, index, replacement), config=config)


@pytest.mark.parametrize("index", range(11))
def test_parser_rejects_missing_line(config, message, index: int) -> None:
    lines = message.split("\n")
    del lines[index]
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message("\n".join(lines), config=config)
    assert error.value.code == "MESSAGE_INVALID"


@pytest.mark.parametrize("index", range(5, 11))
def test_parser_rejects_duplicate_field(config, message, index: int) -> None:
    lines = message.split("\n")
    lines.insert(index, lines[index])
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message("\n".join(lines), config=config)
    assert error.value.code == "MESSAGE_INVALID"


@pytest.mark.parametrize("first,second", [(5, 6), (7, 8), (9, 10)])
def test_parser_rejects_wrong_field_order(config, message, first: int, second: int) -> None:
    lines = message.split("\n")
    lines[first], lines[second] = lines[second], lines[first]
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message("\n".join(lines), config=config)
    assert error.value.code == "MESSAGE_INVALID"


@pytest.mark.parametrize("suffix", ["\n", " ", "\nResources:\n- https://example.invalid", "\nRequest ID: test", "\nNot Before: 2026-11-08T03:00:00Z", "\nNonce: duplicate", "\x00", "\t"])
def test_parser_rejects_trailing_or_optional_content(config, message, suffix: str) -> None:
    with pytest.raises(siwe.SiweError):
        siwe.parse_siwe_message(message + suffix, config=config)


@pytest.mark.parametrize("message", ["", "x" * 4097, "é", "\ud800", b"text", None])
def test_parser_enforces_message_type_size_and_ascii_profile(config, message) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message(message, config=config)
    assert error.value.code == "MESSAGE_INVALID"


def test_parser_does_not_normalize_crlf(config, message) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message(message.replace("\n", "\r\n"), config=config)
    assert error.value.code == "MESSAGE_INVALID"


@pytest.mark.parametrize("timestamp", [
    "2026-11-08T03:00:00", "2026-11-08 03:00:00.123456Z",
    "2026-11-08T03:00:00.123456+00:00", "2026-11-08T03:00:00.1234567Z",
    "2026-02-30T03:00:00.123456Z", "2026-11-08T03:00:60.123456Z", "invalid",
])
def test_parser_rejects_invalid_or_nonprofile_timestamp(config, message, timestamp: str) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message(_line(message, 9, f"Issued At: {timestamp}"), config=config)
    assert error.value.code == "TIMESTAMP_INVALID"


@pytest.mark.parametrize("microsecond", [0, 1, 123456, 999999])
def test_seconds_microseconds_and_timezone_conversion_are_lossless(config, build_args, issued, microsecond) -> None:
    utc_time = issued.replace(microsecond=microsecond)
    local = utc_time.astimezone(timezone(timedelta(hours=7)))
    built = siwe.build_siwe_message(config, **(build_args | {"issued_at": local}))
    assert built == siwe.build_siwe_message(config, **(build_args | {"issued_at": utc_time}))
    assert siwe.parse_siwe_message(built, config=config).issued_at == utc_time


def test_explicit_expiry_may_shorten_configured_ttl(config, build_args, issued) -> None:
    expiry = issued + timedelta(seconds=10)
    built = siwe.build_siwe_message(config, **build_args, expires_at=expiry)
    assert siwe.parse_siwe_message(built, config=config).expires_at == expiry


@pytest.mark.parametrize("seconds", [0, -1, 301])
def test_build_rejects_nonpositive_or_excessive_lifetime(config, build_args, issued, seconds) -> None:
    with pytest.raises(siwe.SiweError) as error:
        siwe.build_siwe_message(config, **build_args, expires_at=issued + timedelta(seconds=seconds))
    assert error.value.code == "TIMESTAMP_INVALID"


def test_naive_issuance_expiry_and_overflow_fail_safely(config, build_args, issued) -> None:
    with pytest.raises(siwe.SiweError):
        siwe.build_siwe_message(config, **(build_args | {"issued_at": issued.replace(tzinfo=None)}))
    with pytest.raises(siwe.SiweError):
        siwe.build_siwe_message(config, **build_args, expires_at=issued.replace(tzinfo=None))
    with pytest.raises(siwe.SiweError) as error:
        siwe.build_siwe_message(config, **(build_args | {"issued_at": datetime.max.replace(tzinfo=UTC)}))
    assert error.value.code == "TIMESTAMP_INVALID"


def test_parser_rejects_excessive_lifetime(config, message) -> None:
    changed = _line(message, 10, "Expiration Time: 2026-11-08T03:05:01.123456Z")
    with pytest.raises(siwe.SiweError) as error:
        siwe.parse_siwe_message(changed, config=config)
    assert error.value.code == "TIMESTAMP_INVALID"


def test_invalid_config_type_is_rejected(build_args, message) -> None:
    for action in (
        lambda: siwe.build_siwe_message(None, **build_args),
        lambda: siwe.parse_siwe_message(message, config={}),
    ):
        with pytest.raises(siwe.SiweError) as error:
            action()
        assert error.value.code == "CONFIG_INVALID"


def test_uri_exceeding_storage_limit_is_rejected(config, build_args) -> None:
    long_uri = config.siwe_uri + "/" + "a" * 2048
    with pytest.raises(siwe.SiweError) as error:
        siwe.build_siwe_message(replace(config, siwe_uri=long_uri), **build_args)
    assert error.value.code == "CONFIG_INVALID"


def test_wallet_a_signs_and_backend_recovers_wallet_a(verify, wallet, message, signature) -> None:
    recovered = Account.recover_message(encode_defunct(text=message), signature=bytes.fromhex(signature[2:]))
    assert recovered == wallet.address
    result = verify()
    assert type(result) is str and result == wallet.address.lower()


def test_wallet_b_cannot_sign_for_wallet_a(verify, other_wallet, message) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(signature=_sign(other_wallet, message))
    assert error.value.code == "SIGNER_MISMATCH"


def test_localhost_http_signed_message_verifies(verify, message, wallet) -> None:
    assert message.startswith("http://localhost:5000 wants you to sign in")
    assert verify() == wallet.address.lower()


def test_one_changed_nonce_character_rejected_before_crypto(verify, message, challenge, monkeypatch) -> None:
    changed_nonce = "A" + challenge.nonce[1:]
    changed = message.replace(challenge.nonce, changed_nonce)
    blocked = Mock(side_effect=AssertionError("Mismatched message must fail before recovery."))
    monkeypatch.setattr(siwe.Account, "recover_message", blocked)
    with pytest.raises(siwe.SiweError) as error:
        verify(message=changed)
    assert error.value.code == "MESSAGE_MISMATCH"
    blocked.assert_not_called()


def test_changed_signature_with_zero_r_is_invalid(verify, signature) -> None:
    raw = bytes.fromhex(signature[2:])
    changed = "0x" + (bytes(32) + raw[32:]).hex()
    with pytest.raises(siwe.SiweError) as error:
        verify(signature=changed)
    assert error.value.code == "SIGNATURE_INVALID"


@pytest.mark.parametrize("signature", ["", "0x" + "ab" * 64, "0x" + "ab" * 66, "ab" * 65, "0X" + "ab" * 65, "0x" + "zz" * 65, "0x" + "00" * 65, b"signature", 123, None])
def test_empty_malformed_or_unrecoverable_signature_rejected(verify, signature) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(signature=signature)
    assert error.value.code == "SIGNATURE_INVALID"


@pytest.mark.parametrize("v", [2, 26, 29, 35, 255])
def test_non_personal_sign_recovery_byte_rejected(verify, signature, v) -> None:
    raw = bytes.fromhex(signature[2:])
    with pytest.raises(siwe.SiweError) as error:
        verify(signature="0x" + (raw[:-1] + bytes([v])).hex())
    assert error.value.code == "SIGNATURE_INVALID"


def test_personal_sign_parity_normalization_is_supported(verify, signature, wallet) -> None:
    raw = bytes.fromhex(signature[2:])
    assert raw[-1] in (27, 28)
    equivalent = "0x" + (raw[:-1] + bytes([raw[-1] - 27])).hex()
    assert verify(signature=equivalent) == wallet.address.lower()


def test_signature_over_a_manually_prefixed_message_is_not_accepted(verify, wallet, message) -> None:
    prefixed = "\x19Ethereum Signed Message:\n" + str(len(message.encode("utf-8"))) + message
    with pytest.raises(siwe.SiweError) as error:
        verify(signature=_sign(wallet, prefixed))
    assert error.value.code == "SIGNER_MISMATCH"


@pytest.mark.parametrize("field,value", [
    ("nonce", "anothernonce0001"), ("chain_id", 11155111),
    ("domain", "evil.invalid"), ("uri", "http://localhost:5000/other"),
])
def test_message_must_match_all_stored_challenge_fields(verify, challenge, field, value) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(challenge=replace(challenge, **{field: value}))
    assert error.value.code == "CHALLENGE_INVALID"


def test_message_must_match_stored_wallet(verify, challenge, other_wallet) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(challenge=replace(challenge, wallet_address=other_wallet.address.lower()))
    assert error.value.code == "CHALLENGE_INVALID"


@pytest.mark.parametrize("field,delta", [("issued_at", 1), ("expires_at", -1)])
def test_message_must_match_exact_stored_times(verify, challenge, field, delta) -> None:
    changed = replace(challenge, **{field: getattr(challenge, field) + timedelta(microseconds=delta)})
    with pytest.raises(siwe.SiweError) as error:
        verify(challenge=changed)
    assert error.value.code == "CHALLENGE_INVALID"


def test_missing_stored_expiry_does_not_fall_back_to_default_ttl(verify, challenge) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(challenge=replace(challenge, expires_at=None))
    assert error.value.code == "TIMESTAMP_INVALID"


def test_stored_original_text_is_checked_not_just_parsed_fields(verify, challenge) -> None:
    changed = replace(challenge, message=challenge.message + "\n")
    with pytest.raises(siwe.SiweError) as error:
        verify(challenge=changed)
    assert error.value.code == "CHALLENGE_INVALID"


def test_changing_message_and_snapshot_still_requires_a_matching_signature(verify, challenge, message) -> None:
    nonce = "anothernonce0001"
    changed_message = message.replace(challenge.nonce, nonce)
    changed_snapshot = replace(challenge, nonce=nonce, message=changed_message)
    with pytest.raises(siwe.SiweError) as error:
        verify(message=changed_message, challenge=changed_snapshot)
    assert error.value.code == "SIGNER_MISMATCH"


@pytest.mark.parametrize("snapshot", [None, {}, "not a stored snapshot"])
def test_verify_requires_explicit_trusted_challenge_type(verify, snapshot) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(challenge=snapshot)
    assert error.value.code == "CHALLENGE_INVALID"


def test_changed_server_allowlist_invalidates_old_chain(verify, config) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(config=replace(config, allowed_chain_ids=(11155111,)))
    assert error.value.code == "CHAIN_NOT_ALLOWED"


@pytest.mark.parametrize("microseconds_after", [0, 1, 30_000_000])
def test_expiry_has_no_leeway(verify, challenge, microseconds_after) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(now=challenge.expires_at + timedelta(microseconds=microseconds_after))
    assert error.value.code == "CHALLENGE_EXPIRED"


def test_one_microsecond_before_expiry_is_valid(verify, challenge, wallet) -> None:
    assert verify(now=challenge.expires_at - timedelta(microseconds=1)) == wallet.address.lower()


def test_exact_30_second_issuance_skew_is_valid(verify, issued, wallet) -> None:
    assert verify(now=issued - timedelta(seconds=30)) == wallet.address.lower()


def test_future_issuance_beyond_30_seconds_is_rejected(verify, issued) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(now=issued - timedelta(seconds=30, microseconds=1))
    assert error.value.code == "ISSUED_AT_FUTURE"


def test_zero_skew_policy_rejects_any_future_issuance(verify, issued) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(now=issued - timedelta(microseconds=1), clock_skew_seconds=0)
    assert error.value.code == "ISSUED_AT_FUTURE"


@pytest.mark.parametrize("skew", [True, -1, 31, 1.0, "30", None])
def test_invalid_clock_skew_policy_rejected(verify, skew) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(clock_skew_seconds=skew)
    assert error.value.code == "CLOCK_SKEW_INVALID"


def test_verification_clock_requires_timezone(verify, issued) -> None:
    with pytest.raises(siwe.SiweError) as error:
        verify(now=issued.replace(tzinfo=None))
    assert error.value.code == "TIMESTAMP_INVALID"


def test_non_utc_verification_clock_is_normalized(verify, issued, wallet) -> None:
    assert verify(now=issued.astimezone(timezone(timedelta(hours=7)))) == wallet.address.lower()


def test_injected_time_and_nonce_are_not_regenerated(config, challenge, signature, wallet, monkeypatch) -> None:
    blocked = Mock(side_effect=AssertionError("Injected verification must not generate time, nonce or wallet."))

    class NoClock(datetime):
        @classmethod
        def now(cls, tz=None):
            return blocked()

    # Match the substitute datetime type used by isinstance in the module.
    trusted = replace(
        challenge, issued_at=NoClock.fromisoformat(challenge.issued_at.isoformat()),
        expires_at=NoClock.fromisoformat(challenge.expires_at.isoformat()),
    )
    monkeypatch.setattr(siwe, "datetime", NoClock)
    monkeypatch.setattr(secrets, "token_hex", blocked)
    monkeypatch.setattr(secrets, "token_bytes", blocked)
    monkeypatch.setattr(Account, "create", blocked)
    result = siwe.verify_siwe_signature(
        trusted.message, signature, challenge=trusted, config=config, now=trusted.issued_at,
    )
    assert result == wallet.address.lower()
    assert trusted.message == challenge.message and trusted.nonce == challenge.nonce
    blocked.assert_not_called()


def test_verification_does_not_consume_nonce_or_grant_session(verify, challenge, wallet, no_external_side_effects) -> None:
    original = replace(challenge)
    first, second = verify(), verify()
    # The pure verifier accepts twice; this is NOT cross-request replay safety.
    assert type(first) is str and first == second == wallet.address.lower()
    assert challenge == original
    no_external_side_effects.assert_not_called()


def test_snapshots_and_parse_results_are_immutable_and_redacted(challenge, config, wallet, signature) -> None:
    parsed = siwe.parse_siwe_message(challenge.message, config=config)
    for value in (challenge, parsed):
        assert wallet.key.hex() not in repr(value)
        assert signature not in repr(value) and challenge.nonce not in repr(value)
        assert challenge.message not in repr(value)
        with pytest.raises(FrozenInstanceError):
            value.nonce = "changed"


def test_library_failure_does_not_expose_signature_key_or_message(verify, wallet, signature, message, config, monkeypatch) -> None:
    marker = "TEST_PRIVATE_LIBRARY_ERROR"
    recover = Mock(side_effect=ValueError(marker + wallet.key.hex() + signature + message))
    monkeypatch.setattr(siwe.Account, "recover_message", recover)
    with pytest.raises(siwe.SiweError) as caught:
        verify()
    assert caught.value.code == "SIGNATURE_INVALID"
    rendered = "".join(traceback.format_exception(caught.value))
    for secret in (marker, wallet.key.hex(), signature, message, config.csrf_secret.hex()):
        assert secret not in str(caught.value)
        assert secret not in repr(caught.value)
        assert secret not in rendered


def test_siwe_error_has_stable_code_and_fixed_message() -> None:
    error = siwe.SiweError("SIGNATURE_INVALID")
    assert isinstance(error, ValueError) and error.code == "SIGNATURE_INVALID"
    assert str(error) == "Chữ ký EOA không hợp lệ."
    with pytest.raises(ValueError, match="Unknown SIWE error code"):
        siwe.SiweError("TEST_UNSUPPORTED_CODE")
