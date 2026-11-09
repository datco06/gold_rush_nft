"""Unit test cấu hình Auth; chạy từ gold_rush_ai:

    python -m pytest tests/test_auth_config.py -q

Chỉ cần pytest và thư viện chuẩn, không cần FastAPI/SQLAlchemy/MetaMask.
Secret thử nghiệm được sinh riêng từng test, không có khóa thật. Mọi cấu hình
đều inject env; test os.environ dùng đối tượng thay thế tạm, không setenv.
Import thử dưới tên module riêng để không reload/làm đổi identity class thật.
"""
from __future__ import annotations

import importlib.util
import os
import secrets
import socket
import sqlite3
import sys
from dataclasses import FrozenInstanceError, replace
from pathlib import Path
from types import MappingProxyType, ModuleType
from unittest.mock import Mock

import pytest

from auth import config as auth_config
from auth.config import AuthConfig, AuthConfigError, load_auth_config


@pytest.fixture
def secret_hex() -> str:
    return secrets.token_hex(32)


@pytest.fixture
def local_env(secret_hex: str) -> dict[str, str]:
    return {"AUTH_CSRF_SECRET": secret_hex}


@pytest.fixture
def production_env(local_env: dict[str, str]) -> dict[str, str]:
    return {
        **local_env,
        "AUTH_SIWE_DOMAIN": "game.example.com",
        "AUTH_SIWE_URI": "https://game.example.com",
        "AUTH_COOKIE_SECURE": "true",
        "CORS_ORIGINS": "https://game.example.com",
    }


@pytest.fixture(autouse=True)
def blocked_io(monkeypatch: pytest.MonkeyPatch) -> Mock:
    """Không cho bất kỳ test trong file này mở DB/socket hoặc tra DNS."""
    blocked = Mock(side_effect=AssertionError("Unit test Auth không được dùng DB/mạng."))
    monkeypatch.setattr(sqlite3, "connect", blocked)
    monkeypatch.setattr(sqlite3.dbapi2, "connect", blocked)
    monkeypatch.setattr(socket, "create_connection", blocked)
    monkeypatch.setattr(socket, "getaddrinfo", blocked)
    monkeypatch.setattr(socket.socket, "connect", blocked)
    monkeypatch.setattr(socket.socket, "connect_ex", blocked)
    return blocked


def _fresh_import(monkeypatch: pytest.MonkeyPatch) -> ModuleType:
    """Execute source thật, cô lập sys.modules và tắt ghi bytecode của import này."""
    name = "_gold_rush_auth_config_import_check"
    spec = importlib.util.spec_from_file_location(name, auth_config.__file__)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    monkeypatch.setitem(sys.modules, name, module)
    monkeypatch.setattr(sys, "dont_write_bytecode", True)
    spec.loader.exec_module(module)
    return module


def test_local_defaults(local_env: dict[str, str], secret_hex: str) -> None:
    config = load_auth_config(local_env)
    assert isinstance(config, AuthConfig)
    assert config.database_url == "sqlite:///./data/auth/gold_rush_auth.db"
    assert config.siwe_domain == "localhost:5000"
    assert config.siwe_uri == "http://localhost:5000"
    assert config.allowed_chain_ids == (31337,)
    assert config.challenge_ttl_seconds == 300
    assert config.registration_ttl_seconds == 600
    assert config.session_ttl_seconds == 28800
    assert config.cookie_secure is False
    # Giữ mặc định giống config.py cũ, có cả cổng 5173.
    assert config.cors_origins == (
        "http://localhost:8501", "http://localhost:5173", "http://localhost:5000",
    )
    assert config.csrf_secret == bytes.fromhex(secret_hex)


def test_explicit_local_configuration(local_env: dict[str, str]) -> None:
    env = {
        **local_env,
        "AUTH_DATABASE_URL": "sqlite:///./data/auth/local.db",
        "AUTH_SIWE_DOMAIN": "localhost:5000",
        "AUTH_SIWE_URI": "http://localhost:5000/login",
        "AUTH_ALLOWED_CHAIN_IDS": "31337, 11155111",
        "AUTH_CHALLENGE_TTL_SECONDS": "120",
        "AUTH_REGISTRATION_TTL_SECONDS": "240",
        "AUTH_SESSION_TTL_SECONDS": "3600",
        "AUTH_COOKIE_SECURE": "false",
        "CORS_ORIGINS": "http://localhost:5000, http://localhost:8501",
    }
    config = load_auth_config(env)
    assert config.database_url == env["AUTH_DATABASE_URL"]
    assert config.siwe_uri == env["AUTH_SIWE_URI"]
    assert config.allowed_chain_ids == (31337, 11155111)
    assert (config.challenge_ttl_seconds, config.registration_ttl_seconds,
            config.session_ttl_seconds) == (120, 240, 3600)
    assert config.cookie_secure is False
    assert config.cors_origins == ("http://localhost:5000", "http://localhost:8501")


def test_config_is_immutable(local_env: dict[str, str]) -> None:
    config = load_auth_config(local_env)
    with pytest.raises(FrozenInstanceError):
        config.cookie_secure = True
    with pytest.raises(FrozenInstanceError):
        config.allowed_chain_ids += (1,)
    assert isinstance(config.allowed_chain_ids, tuple)
    assert isinstance(config.cors_origins, tuple)


def test_injected_env_is_independent_and_not_modified(
    local_env: dict[str, str], monkeypatch: pytest.MonkeyPatch,
) -> None:
    original = os.environ
    before = dict(original)
    injected = MappingProxyType(dict(local_env))
    with monkeypatch.context() as patch:
        patch.setattr(os, "environ", MappingProxyType({
            "AUTH_CSRF_SECRET": "invalid-machine-secret",
            "AUTH_SESSION_TTL_SECONDS": "-1",
            "CORS_ORIGINS": "*",
        }))
        assert load_auth_config(injected).session_ttl_seconds == 28800
    assert dict(injected) == local_env
    assert os.environ is original
    assert dict(original) == before


def test_default_loader_reads_env_at_call_time_without_mutating_it(
    local_env: dict[str, str], monkeypatch: pytest.MonkeyPatch,
) -> None:
    original = os.environ
    before = dict(original)
    with monkeypatch.context() as patch:
        fake_env = {**local_env, "AUTH_SESSION_TTL_SECONDS": "900"}
        patch.setattr(os, "environ", MappingProxyType(fake_env))
        assert load_auth_config().session_ttl_seconds == 900
        fake_env["AUTH_SESSION_TTL_SECONDS"] = "1800"
        assert load_auth_config().session_ttl_seconds == 1800
        assert load_auth_config(local_env).session_ttl_seconds == 28800
    assert os.environ is original
    assert dict(original) == before


def test_explicit_empty_env_does_not_fall_back_to_real_env(
    local_env: dict[str, str], monkeypatch: pytest.MonkeyPatch,
) -> None:
    original = os.environ
    with monkeypatch.context() as patch:
        patch.setattr(os, "environ", MappingProxyType(local_env))
        with pytest.raises(AuthConfigError, match="AUTH_CSRF_SECRET"):
            load_auth_config({})
    assert os.environ is original


def test_invalid_load_does_not_modify_injected_or_real_env(local_env: dict[str, str]) -> None:
    env = {**local_env, "AUTH_CHALLENGE_TTL_SECONDS": "0"}
    injected_before, real_before = dict(env), dict(os.environ)
    with pytest.raises(AuthConfigError, match="AUTH_CHALLENGE_TTL_SECONDS"):
        load_auth_config(env)
    assert env == injected_before
    assert dict(os.environ) == real_before


def test_missing_secret_is_a_configuration_error() -> None:
    with pytest.raises(AuthConfigError, match="AUTH_CSRF_SECRET"):
        load_auth_config({})


@pytest.mark.parametrize("secret", [
    pytest.param("", id="empty"),
    pytest.param("not-a-hex-secret", id="nonhex"),
    pytest.param("g" * 64, id="nonhex-long"),
    pytest.param("12" * 31, id="decoded-31-bytes"),
    pytest.param("12" * 16, id="decoded-16-bytes"),
    pytest.param("a" * 65, id="odd-length"),
    pytest.param("00" * 32, id="zero-bytes"),
    pytest.param("abcd" * 16, id="repeated-pattern"),
    pytest.param(" 12" * 32, id="whitespace"),
])
def test_invalid_secrets_are_rejected(secret: str) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_CSRF_SECRET") as error:
        load_auth_config({"AUTH_CSRF_SECRET": secret})
    if secret:
        assert secret not in str(error.value)
        assert secret not in repr(error.value)


@pytest.mark.parametrize("size", [32, 64])
def test_valid_secret_decodes_without_rotation(size: int) -> None:
    secret = secrets.token_hex(size)
    env = {"AUTH_CSRF_SECRET": secret}
    first, second = load_auth_config(env), load_auth_config(env)
    assert first.csrf_secret == second.csrf_secret == bytes.fromhex(secret)
    assert len(first.csrf_secret) == size
    assert load_auth_config({"AUTH_CSRF_SECRET": secret.upper()}).csrf_secret == first.csrf_secret


def test_secret_is_hidden_in_config_repr_and_validation_error(
    local_env: dict[str, str], secret_hex: str,
) -> None:
    config = load_auth_config(local_env)
    for output in (repr(config), str(config)):
        assert secret_hex not in output
        assert repr(config.csrf_secret) not in output
    with pytest.raises(AuthConfigError, match="AUTH_ALLOWED_CHAIN_IDS") as error:
        load_auth_config({**local_env, "AUTH_ALLOWED_CHAIN_IDS": "-1"})
    assert secret_hex not in str(error.value)
    assert repr(config.csrf_secret) not in repr(error.value)


def test_database_credentials_are_hidden_in_repr(local_env: dict[str, str]) -> None:
    config = load_auth_config({
        **local_env, "AUTH_DATABASE_URL": "postgresql://test:TEST_DB_PASSWORD@localhost/test",
    })
    assert "TEST_DB_PASSWORD" not in repr(config)


@pytest.mark.parametrize("raw, expected", [
    ("31337", (31337,)),
    ("31337, 11155111", (31337, 11155111)),
    ("11155111,31337", (11155111, 31337)),
    ("00031337", (31337,)),
    (str(2**256 - 1), (2**256 - 1,)),
])
def test_valid_chain_ids(local_env: dict[str, str], raw: str, expected: tuple[int, ...]) -> None:
    config = load_auth_config({**local_env, "AUTH_ALLOWED_CHAIN_IDS": raw})
    assert config.allowed_chain_ids == expected
    assert all(type(chain) is int for chain in config.allowed_chain_ids)


@pytest.mark.parametrize("raw", [
    pytest.param("", id="empty"),
    pytest.param("-1", id="negative"),
    pytest.param("0", id="zero"),
    pytest.param("31337,-2", id="negative-in-list"),
    pytest.param("31337,", id="empty-item"),
    pytest.param("31337,31337", id="duplicate"),
    pytest.param("true", id="boolean"),
    pytest.param("1.5", id="float"),
    pytest.param("1e3", id="scientific"),
    pytest.param("0x7a69", id="hex"),
    pytest.param("１２３", id="unicode-digits"),
    pytest.param(str(2**256), id="overflow"),
    pytest.param("9" * 5000, id="huge-number"),
])
def test_invalid_chain_ids(local_env: dict[str, str], raw: str) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_ALLOWED_CHAIN_IDS"):
        load_auth_config({**local_env, "AUTH_ALLOWED_CHAIN_IDS": raw})


@pytest.mark.parametrize("env_key, attribute", [
    ("AUTH_CHALLENGE_TTL_SECONDS", "challenge_ttl_seconds"),
    ("AUTH_REGISTRATION_TTL_SECONDS", "registration_ttl_seconds"),
    ("AUTH_SESSION_TTL_SECONDS", "session_ttl_seconds"),
])
@pytest.mark.parametrize("value", [1, 900, 2**31 - 1])
def test_valid_ttls(local_env: dict[str, str], env_key: str, attribute: str, value: int) -> None:
    config = load_auth_config({**local_env, env_key: str(value)})
    assert getattr(config, attribute) == value


@pytest.mark.parametrize("env_key", [
    "AUTH_CHALLENGE_TTL_SECONDS", "AUTH_REGISTRATION_TTL_SECONDS", "AUTH_SESSION_TTL_SECONDS",
])
@pytest.mark.parametrize("raw", [
    pytest.param("0", id="zero"),
    pytest.param("-5", id="negative"),
    pytest.param("", id="empty"),
    pytest.param("false", id="boolean"),
    pytest.param("1.5", id="float"),
    pytest.param(str(2**31), id="overflow"),
])
def test_invalid_ttls(local_env: dict[str, str], env_key: str, raw: str) -> None:
    with pytest.raises(AuthConfigError, match=env_key):
        load_auth_config({**local_env, env_key: raw})


@pytest.mark.parametrize("host", ["localhost", "127.0.0.1", "[::1]"])
def test_valid_local_siwe_authority_and_uri(local_env: dict[str, str], host: str) -> None:
    uri = f"http://{host}:5000"
    config = load_auth_config({
        **local_env, "AUTH_SIWE_DOMAIN": f"{host}:5000",
        "AUTH_SIWE_URI": uri, "CORS_ORIGINS": uri,
    })
    assert config.siwe_uri == uri
    assert config.cookie_secure is False


def test_siwe_uri_allows_path_and_encoded_query(local_env: dict[str, str]) -> None:
    uri = "http://localhost:5000/login?mode=sign%20in"
    assert load_auth_config({**local_env, "AUTH_SIWE_URI": uri}).siwe_uri == uri


@pytest.mark.parametrize("domain", [
    "", "http://localhost:5000", "localhost:5000/path", "user@localhost:5000",
    "localhost:0", "localhost:65536", "localhost:", "local host:5000",
    "localhost:5000\n", "[::1]suffix",
])
def test_invalid_siwe_domains(local_env: dict[str, str], domain: str) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_SIWE_DOMAIN"):
        load_auth_config({**local_env, "AUTH_SIWE_DOMAIN": domain})


@pytest.mark.parametrize("uri", [
    "", "/relative", "localhost:5000", "ftp://localhost:5000",
    "http://user:password@localhost:5000", "http://localhost:5000/#fragment",
    "http://localhost:5000/\n", "http://localhost:5000/%xy",
    "http://localhost:5000/ space", "http://localhost:5000\\evil",
])
def test_invalid_siwe_uris(local_env: dict[str, str], uri: str) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_SIWE_URI"):
        load_auth_config({**local_env, "AUTH_SIWE_URI": uri})


@pytest.mark.parametrize("domain, uri", [
    ("localhost:8000", "http://localhost:5000"),
    ("127.0.0.1:5000", "http://localhost:5000"),
    ("localhost", "http://localhost:5000"),
])
def test_siwe_host_or_port_mismatch(local_env: dict[str, str], domain: str, uri: str) -> None:
    with pytest.raises(AuthConfigError, match="host/port"):
        load_auth_config({**local_env, "AUTH_SIWE_DOMAIN": domain, "AUTH_SIWE_URI": uri})


@pytest.mark.parametrize("host", ["game.example.com", "localhost.evil.com"])
def test_non_loopback_http_is_rejected(local_env: dict[str, str], host: str) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_SIWE_URI"):
        load_auth_config({
            **local_env, "AUTH_SIWE_DOMAIN": host,
            "AUTH_SIWE_URI": f"http://{host}", "CORS_ORIGINS": f"http://{host}",
        })


def test_https_production_with_secure_cookie(production_env: dict[str, str]) -> None:
    config = load_auth_config(production_env)
    assert config.siwe_uri == "https://game.example.com"
    assert config.cookie_secure is True
    assert config.cors_origins == ("https://game.example.com",)


def test_https_production_without_secure_cookie_is_rejected(production_env: dict[str, str]) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_COOKIE_SECURE"):
        load_auth_config({**production_env, "AUTH_COOKIE_SECURE": "false"})


def test_https_cors_also_requires_secure_cookie(local_env: dict[str, str]) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_COOKIE_SECURE"):
        load_auth_config({
            **local_env, "CORS_ORIGINS": "http://localhost:5000,https://dashboard.example.com",
        })


@pytest.mark.parametrize("raw, expected", [("true", True), ("TRUE", True), ("false", False)])
def test_cookie_secure_boolean(local_env: dict[str, str], raw: str, expected: bool) -> None:
    assert load_auth_config({**local_env, "AUTH_COOKIE_SECURE": raw}).cookie_secure is expected


@pytest.mark.parametrize("raw", ["", "1", "0", "yes", "on"])
def test_invalid_cookie_boolean(local_env: dict[str, str], raw: str) -> None:
    with pytest.raises(AuthConfigError, match="AUTH_COOKIE_SECURE"):
        load_auth_config({**local_env, "AUTH_COOKIE_SECURE": raw})


@pytest.mark.parametrize("domain, uri, origins, expected", [
    ("localhost:5000", "http://localhost:5000", "http://LOCALHOST:5000, http://localhost:8501",
     ("http://localhost:5000", "http://localhost:8501")),
    ("localhost:80", "http://localhost", "http://LOCALHOST:80", ("http://localhost",)),
    ("[::1]:5000", "http://[::1]:5000", "http://[0:0:0:0:0:0:0:1]:5000",
     ("http://[::1]:5000",)),
])
def test_cors_normalizes_browser_origins(
    local_env: dict[str, str], domain: str, uri: str, origins: str, expected: tuple[str, ...],
) -> None:
    config = load_auth_config({
        **local_env, "AUTH_SIWE_DOMAIN": domain, "AUTH_SIWE_URI": uri, "CORS_ORIGINS": origins,
    })
    assert config.cors_origins == expected


@pytest.mark.parametrize("origins", [
    "", "*", "null", "http://localhost:5000/", "http://localhost:5000/path",
    "http://localhost:5000?query=1", "http://localhost:5000/#fragment",
    "http://localhost:5000,", "http://localhost:8501",
    "http://localhost:5000,http://LOCALHOST:5000",
])
def test_invalid_cors_origins(local_env: dict[str, str], origins: str) -> None:
    with pytest.raises(AuthConfigError, match="CORS_ORIGINS"):
        load_auth_config({**local_env, "CORS_ORIGINS": origins})


@pytest.mark.parametrize("overrides, field_name", [
    ({"allowed_chain_ids": (True,)}, "AUTH_ALLOWED_CHAIN_IDS"),
    ({"allowed_chain_ids": [31337]}, "AUTH_ALLOWED_CHAIN_IDS"),
    ({"session_ttl_seconds": True}, "AUTH_SESSION_TTL_SECONDS"),
    ({"session_ttl_seconds": 1.5}, "AUTH_SESSION_TTL_SECONDS"),
    ({"cookie_secure": "false"}, "AUTH_COOKIE_SECURE"),
    ({"cors_origins": ["http://localhost:5000"]}, "CORS_ORIGINS"),
    ({"csrf_secret": bytearray(range(32))}, "AUTH_CSRF_SECRET"),
])
def test_direct_constructor_cannot_bypass_type_validation(
    local_env: dict[str, str], overrides: dict[str, object], field_name: str,
) -> None:
    config = load_auth_config(local_env)
    with pytest.raises(AuthConfigError, match=field_name):
        replace(config, **overrides)


def test_import_does_not_open_database_or_network(
    monkeypatch: pytest.MonkeyPatch, blocked_io: Mock,
) -> None:
    # Bắt cả việc tự nạp DB driver ngoài stdlib; test không cần cài các gói này.
    import builtins

    original_import = builtins.__import__

    def guarded_import(name: str, *args: object, **kwargs: object) -> object:
        if name.split(".")[0] in {"sqlalchemy", "aiosqlite", "psycopg", "psycopg2"}:
            pytest.fail("Import cấu hình không được tự nạp DB driver.")
        return original_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", guarded_import)
    assert _fresh_import(monkeypatch).AuthConfig is not AuthConfig
    blocked_io.assert_not_called()


def test_import_does_not_read_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    class ForbiddenEnv(dict):
        def get(self, *args: object, **kwargs: object) -> str:
            pytest.fail("Import cấu hình không được đọc env.")

        def __getitem__(self, key: str) -> str:
            pytest.fail("Import cấu hình không được đọc env.")

    original = os.environ
    with monkeypatch.context() as patch:
        patch.setattr(os, "environ", ForbiddenEnv())
        _fresh_import(patch)
    assert os.environ is original


def test_import_and_loading_do_not_generate_new_secrets(
    local_env: dict[str, str], secret_hex: str, monkeypatch: pytest.MonkeyPatch,
) -> None:
    generator = Mock(side_effect=AssertionError("Auth config không được tự sinh secret."))
    for name in ("token_hex", "token_bytes", "token_urlsafe"):
        monkeypatch.setattr(secrets, name, generator)
    monkeypatch.setattr(os, "urandom", generator)
    module = _fresh_import(monkeypatch)
    for _ in range(2):
        assert module.load_auth_config(local_env).csrf_secret == bytes.fromhex(secret_hex)
    with pytest.raises(module.AuthConfigError, match="AUTH_CSRF_SECRET"):
        module.load_auth_config({})
    generator.assert_not_called()


def test_import_does_not_create_files(monkeypatch: pytest.MonkeyPatch) -> None:
    # Không chặn đọc source; chặn tạo file/thư mục ở giai đoạn import.
    import builtins
    import io

    builtin_open, io_open = builtins.open, io.open

    def guard_open(original):
        def open_readonly(file, mode="r", *args, **kwargs):
            if any(flag in mode for flag in "wax+"):
                pytest.fail("Import cấu hình không được ghi file.")
            return original(file, mode, *args, **kwargs)
        return open_readonly

    monkeypatch.setattr(builtins, "open", guard_open(builtin_open))
    monkeypatch.setattr(io, "open", guard_open(io_open))
    monkeypatch.setattr(Path, "mkdir", Mock(side_effect=AssertionError("Không tạo thư mục.")))
    monkeypatch.setattr(Path, "touch", Mock(side_effect=AssertionError("Không tạo file.")))
    _fresh_import(monkeypatch)
