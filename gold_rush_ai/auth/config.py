"""Cấu hình Auth độc lập, chỉ dùng thư viện chuẩn và không có I/O lúc import.

Gọi ``load_auth_config()`` khi khởi tạo Auth, hoặc truyền Mapping env để test.
Không tự nạp .env, tạo secret, mở database hay gọi RPC. CORS local mặc định
giữ cùng danh sách với config.py cũ mà không import module đó.

AUTH_CSRF_SECRET bắt buộc là hex của ít nhất 32 byte ngẫu nhiên. Sinh MỘT LẦN
bằng ``python3 -c 'import secrets; print(secrets.token_hex(32))'``, lưu trong
secret manager/env và dùng ổn định giữa các lần khởi động/các worker. Không
commit secret. Validation không thể chứng minh nguồn sinh thực sự ngẫu nhiên.
Không log env, dataclasses.asdict(config) hay truy cập trực tiếp secret để log.

Ứng dụng hiện chỉ triển khai web HTTP(S): SIWE domain là host[:port] (IPv6
dùng ngoặc vuông), URI phải cùng authority và origin nằm trong CORS_ORIGINS.
HTTP chỉ được dùng trên localhost hoặc địa chỉ IP loopback, không tra DNS.
HTTPS ở URI hoặc CORS yêu cầu cookie Secure, kể cả trên localhost.

Tham chiếu: https://eips.ethereum.org/EIPS/eip-4361
"""
from __future__ import annotations

import os
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from ipaddress import ip_address
from urllib.parse import SplitResult, urlsplit

__all__ = ["AuthConfig", "AuthConfigError", "load_auth_config"]

_LOCAL_ORIGINS = (
    "http://localhost:8501",
    "http://localhost:5173",
    "http://localhost:5000",
)
_MAX_TTL = 2_147_483_647
_MAX_CHAIN_ID = 2**256 - 1


class AuthConfigError(ValueError):
    """Cấu hình Auth không hợp lệ; thông báo không chứa giá trị env đầu vào."""


def _text(value: object, name: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise AuthConfigError(f"{name}: phải là chuỗi không rỗng, không có khoảng trắng ở hai đầu.")
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise AuthConfigError(f"{name}: không được chứa ký tự điều khiển.")
    return value


def _positive_int(value: object, name: str, maximum: int) -> int:
    # bool là subclass của int, nhưng không phải chain ID/TTL hợp lệ.
    if type(value) is not int or not 0 < value <= maximum:
        raise AuthConfigError(f"{name}: phải là số nguyên dương không vượt quá {maximum}.")
    return value


def _env_int(value: str, name: str, maximum: int) -> int:
    digits = value.strip()
    if not re.fullmatch(r"[0-9]+", digits):
        raise AuthConfigError(f"{name}: phải là số nguyên dương hệ thập phân.")
    # Giới hạn trước int() để không lộ input qua lỗi chuyển đổi số quá dài.
    digits = digits.lstrip("0") or "0"
    if len(digits) > len(str(maximum)):
        raise AuthConfigError(f"{name}: vượt giới hạn cho phép.")
    return _positive_int(int(digits), name, maximum)


def _authority(value: str, name: str) -> tuple[str, int | None]:
    """Validate authority web hẹp hơn RFC: không userinfo, DNS Unicode hay zone ID."""
    if any(ord(c) <= 32 or ord(c) >= 127 for c in value):
        raise AuthConfigError(f"{name}: dùng hostname ASCII/punycode hoặc IP hợp lệ.")
    if any(c in value for c in "/\\?#@%"):
        raise AuthConfigError(f"{name}: chỉ nhận host[:port], không scheme/path/userinfo.")
    if not re.fullmatch(r"(?:\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(?::[0-9]+)?", value):
        raise AuthConfigError(f"{name}: host hoặc port không hợp lệ.")
    try:
        parsed = urlsplit("//" + value)
        host, port = parsed.hostname, parsed.port
    except ValueError:
        raise AuthConfigError(f"{name}: host hoặc port không hợp lệ.") from None
    if not host or parsed.netloc != value or value.endswith(":") or port == 0:
        raise AuthConfigError(f"{name}: host hoặc port không hợp lệ.")
    try:
        address = ip_address(host)
    except ValueError:
        if ":" in host or re.fullmatch(r"[0-9.]+", host):
            raise AuthConfigError(f"{name}: địa chỉ IP không hợp lệ.") from None
        labels = host.split(".")
        if len(host) > 253 or any(
            not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
            for label in labels
        ):
            raise AuthConfigError(f"{name}: hostname không hợp lệ.") from None
    else:
        if address.version == 6 and not value.startswith("["):
            raise AuthConfigError(f"{name}: IPv6 phải nằm trong ngoặc vuông.")
        host = address.compressed
    return host, port


def _is_loopback(host: str) -> bool:
    if host == "localhost":
        return True
    try:
        return ip_address(host).is_loopback
    except ValueError:
        return False


def _web_url(value: object, name: str, *, origin_only: bool = False) -> SplitResult:
    text = _text(value, name)
    # urlsplit tự bỏ một số control/space; phải kiểm tra TRƯỚC khi parse.
    if not re.fullmatch(r"[A-Za-z0-9._~:/?\[\]@!$&'()*+,;=%-]+", text):
        raise AuthConfigError(f"{name}: URL phải là URI ASCII hợp lệ, không có fragment.")
    if re.search(r"%(?![0-9A-Fa-f]{2})", text):
        raise AuthConfigError(f"{name}: percent-encoding không hợp lệ.")
    try:
        parsed = urlsplit(text)
    except ValueError:
        raise AuthConfigError(f"{name}: URL không hợp lệ.") from None
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise AuthConfigError(f"{name}: phải là URL tuyệt đối http:// hoặc https://.")
    host, _ = _authority(parsed.netloc, name)
    if origin_only and (parsed.path or "?" in text):
        raise AuthConfigError(f"{name}: origin không được có path/query/fragment hoặc dấu / cuối.")
    if parsed.scheme == "http" and not _is_loopback(host):
        raise AuthConfigError(f"{name}: HTTP chỉ được phép trên loopback local; triển khai dùng HTTPS.")
    return parsed


def _origin_key(url: SplitResult) -> tuple[str, str | None, int]:
    host = url.hostname
    if host is not None:
        try:
            host = ip_address(host).compressed
        except ValueError:
            pass
    return url.scheme, host, url.port or (443 if url.scheme == "https" else 80)


def _origin_text(url: SplitResult) -> str:
    host = url.hostname or ""
    if ":" in host:
        host = f"[{ip_address(host).compressed}]"
    default_port = 443 if url.scheme == "https" else 80
    port = f":{url.port}" if url.port not in (None, default_port) else ""
    return f"{url.scheme}://{host}{port}"


def _validate_secret(value: object) -> None:
    if not isinstance(value, bytes) or len(value) < 32:
        raise AuthConfigError("AUTH_CSRF_SECRET: cần ít nhất 32 byte ngẫu nhiên sau giải mã hex.")
    # Loại một số mẫu yếu rõ ràng; đây không phải phép đo/chứng minh entropy.
    if any(
        len(value) % size == 0 and value == value[:size] * (len(value) // size)
        for size in range(1, min(16, len(value) // 2) + 1)
    ):
        raise AuthConfigError("AUTH_CSRF_SECRET: không dùng mẫu lặp; hãy sinh bằng secrets.token_hex(32).")


@dataclass(frozen=True, slots=True, kw_only=True)
class AuthConfig:
    """Snapshot đã validate; constructor trực tiếp cũng áp dụng cùng ràng buộc.

    ``csrf_secret`` là bytes đã giải mã, không phải chuỗi hex env. Cả secret
    và database URL (có thể chứa password) đều bị loại khỏi repr. TTL giới hạn
    1..2^31-1 giây, chain ID 1..2^256-1. Các collection bắt buộc dùng tuple.
    """

    csrf_secret: bytes = field(repr=False)
    database_url: str = field(default="sqlite:///./data/auth/gold_rush_auth.db", repr=False)
    siwe_domain: str = "localhost:5000"
    siwe_uri: str = "http://localhost:5000"
    allowed_chain_ids: tuple[int, ...] = (31337,)
    challenge_ttl_seconds: int = 300
    registration_ttl_seconds: int = 600
    session_ttl_seconds: int = 28800
    cookie_secure: bool = False
    cors_origins: tuple[str, ...] = _LOCAL_ORIGINS

    def __post_init__(self) -> None:
        _validate_secret(self.csrf_secret)
        database = _text(self.database_url, "AUTH_DATABASE_URL")
        # Chỉ kiểm tra hình dạng URL SQLAlchemy; dialect/driver được xác minh
        # ở module database sau này. Không parse credentials vào thông báo lỗi.
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9+.-]*://\S+", database):
            raise AuthConfigError("AUTH_DATABASE_URL: cần URL kết nối database hợp lệ.")
        domain = _text(self.siwe_domain, "AUTH_SIWE_DOMAIN")
        domain_host, domain_port = _authority(domain, "AUTH_SIWE_DOMAIN")
        uri = _web_url(self.siwe_uri, "AUTH_SIWE_URI")
        expected_port = domain_port or (443 if uri.scheme == "https" else 80)
        if (domain_host, expected_port) != _origin_key(uri)[1:]:
            raise AuthConfigError("AUTH_SIWE_DOMAIN và AUTH_SIWE_URI: host/port phải khớp nhau.")
        if type(self.allowed_chain_ids) is not tuple or not self.allowed_chain_ids:
            raise AuthConfigError("AUTH_ALLOWED_CHAIN_IDS: cần tuple chain ID không rỗng.")
        for chain_id in self.allowed_chain_ids:
            _positive_int(chain_id, "AUTH_ALLOWED_CHAIN_IDS", _MAX_CHAIN_ID)
        if len(set(self.allowed_chain_ids)) != len(self.allowed_chain_ids):
            raise AuthConfigError("AUTH_ALLOWED_CHAIN_IDS: không được lặp chain ID.")
        for value, name in (
            (self.challenge_ttl_seconds, "AUTH_CHALLENGE_TTL_SECONDS"),
            (self.registration_ttl_seconds, "AUTH_REGISTRATION_TTL_SECONDS"),
            (self.session_ttl_seconds, "AUTH_SESSION_TTL_SECONDS"),
        ):
            _positive_int(value, name, _MAX_TTL)
        if type(self.cookie_secure) is not bool:
            raise AuthConfigError("AUTH_COOKIE_SECURE: phải là bool.")
        if type(self.cors_origins) is not tuple or not self.cors_origins:
            raise AuthConfigError("CORS_ORIGINS: cần tuple origin cụ thể, không rỗng.")
        origins = [_web_url(origin, "CORS_ORIGINS", origin_only=True) for origin in self.cors_origins]
        origin_keys = [_origin_key(origin) for origin in origins]
        if len(set(origin_keys)) != len(origin_keys):
            raise AuthConfigError("CORS_ORIGINS: không được lặp origin tương đương.")
        if _origin_key(uri) not in origin_keys:
            raise AuthConfigError("CORS_ORIGINS: phải chứa origin của AUTH_SIWE_URI.")
        if not self.cookie_secure and any(url.scheme == "https" for url in [uri, *origins]):
            raise AuthConfigError("AUTH_COOKIE_SECURE: phải là true khi dùng HTTPS.")
        # Browser serialize origin với hostname lowercase, bỏ default port.
        # Chuẩn hóa trong lúc khởi tạo, snapshot sau đó vẫn bất biến.
        object.__setattr__(self, "cors_origins", tuple(_origin_text(origin) for origin in origins))


def load_auth_config(environ: Mapping[str, str] | None = None) -> AuthConfig:
    """Đọc env theo yêu cầu, không cache hoặc sửa Mapping/os.environ.

    ``None`` đọc os.environ; ``{}`` là env test rỗng (sẽ lỗi thiếu secret).
    Các biến vắng dùng mặc định local; chuỗi rỗng không thay thế bằng mặc định.
    AUTH_COOKIE_SECURE chỉ nhận true/false (không phân biệt hoa thường).
    Chain IDs và CORS origins là danh sách phân cách bởi dấu phẩy.
    """
    source = os.environ if environ is None else environ

    def read(name: str, default: str | None = None) -> str:
        return _text(source.get(name, default), name)

    raw_secret = read("AUTH_CSRF_SECRET")
    if not re.fullmatch(r"[0-9a-fA-F]{64,}", raw_secret) or len(raw_secret) % 2:
        raise AuthConfigError("AUTH_CSRF_SECRET: cần chuỗi hex của ít nhất 32 byte ngẫu nhiên.")
    secret = bytes.fromhex(raw_secret)
    secure = read("AUTH_COOKIE_SECURE", "false").lower()
    if secure not in ("true", "false"):
        raise AuthConfigError("AUTH_COOKIE_SECURE: chỉ nhận true hoặc false.")
    chains = tuple(
        _env_int(item, "AUTH_ALLOWED_CHAIN_IDS", _MAX_CHAIN_ID)
        for item in read("AUTH_ALLOWED_CHAIN_IDS", "31337").split(",")
    )
    return AuthConfig(
        csrf_secret=secret,
        database_url=read("AUTH_DATABASE_URL", "sqlite:///./data/auth/gold_rush_auth.db"),
        siwe_domain=read("AUTH_SIWE_DOMAIN", "localhost:5000"),
        siwe_uri=read("AUTH_SIWE_URI", "http://localhost:5000"),
        allowed_chain_ids=chains,
        challenge_ttl_seconds=_env_int(
            read("AUTH_CHALLENGE_TTL_SECONDS", "300"), "AUTH_CHALLENGE_TTL_SECONDS", _MAX_TTL
        ),
        registration_ttl_seconds=_env_int(
            read("AUTH_REGISTRATION_TTL_SECONDS", "600"), "AUTH_REGISTRATION_TTL_SECONDS", _MAX_TTL
        ),
        session_ttl_seconds=_env_int(
            read("AUTH_SESSION_TTL_SECONDS", "28800"), "AUTH_SESSION_TTL_SECONDS", _MAX_TTL
        ),
        cookie_secure=secure == "true",
        cors_origins=tuple(item.strip() for item in read("CORS_ORIGINS", ",".join(_LOCAL_ORIGINS)).split(",")),
    )
