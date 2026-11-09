#!/usr/bin/env python3
"""Smoke Auth over real, finite-time HTTP to an explicitly loopback backend.

From gold_rush_ai, with its dependencies installed:
    python scripts/smoke_auth_http.py
    python scripts/smoke_auth_http.py --full-flow

The default only sends GET/OPTIONS requests. --full-flow explicitly authorizes
creating ONE persistent TEST account on the server. Its random wallet/key only
exists in memory: the account remains after logout and cannot be recovered by
this script later. No DB access, migrations, server startup, RPC or TestClient.
Do not point a local reverse proxy/tunnel at a production database/backend.

HTTP observations cannot count DB rows, prove browser CORS/SameSite enforcement,
or exercise a MetaMask extension. Re-login checks the same public user ID and
wallet; database uniqueness is covered by the separate backend test suite.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import math
import re
import secrets
import socket
from dataclasses import dataclass
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from hashlib import sha256
from http.cookies import CookieError, SimpleCookie
from urllib.parse import urlsplit
from uuid import UUID

import httpx


_ROUTES = {
    "/api/auth/challenge": "post", "/api/auth/verify": "post",
    "/api/auth/register": "post", "/api/me": "get", "/api/auth/logout": "post",
}
_PUBLIC_USER = {"id", "wallet_address", "username", "avatar", "created_at"}
_PRIVATE_FIELDS = {
    "token", "session_token", "cookie_token", "token_hash", "private_key",
    "seed_phrase", "browser_binding", "browser_binding_hash", "nonce", "signature",
}


class SmokeFailure(Exception):
    """Fixed diagnostic only: never retain response bodies or raw exceptions."""


def _local_url(value: str, *, origin: bool = False) -> str:
    try:
        url = urlsplit(value)
        valid = (
            value == value.strip() and value.isascii()
            and not any(ord(c) <= 32 or ord(c) == 127 for c in value)
            and url.scheme in {"http", "https"}
            and url.hostname in {"localhost", "127.0.0.1"}
            and url.username is None and url.password is None
            and url.port != 0 and url.path in {"", "/"}
            and not url.query and not url.fragment and "?" not in value and "#" not in value
            and not url.netloc.endswith(":") and "\\" not in value and "%" not in value
        )
        if not valid:
            raise ValueError
        port = url.port or (443 if url.scheme == "https" else 80)
        suffix = "" if port == (443 if url.scheme == "https" else 80) else f":{port}"
        return f"{url.scheme}://{url.hostname}{suffix}"
    except (TypeError, ValueError):
        label = "Origin" if origin else "Base URL"
        raise argparse.ArgumentTypeError(
            f"{label}: chỉ cho phép HTTP(S) localhost/127.0.0.1, không credentials/path/query/fragment."
        ) from None


def _timeout(value: str) -> float:
    try:
        seconds = float(value)
        if not math.isfinite(seconds) or not 0 < seconds <= 60:
            raise ValueError
        return seconds
    except ValueError:
        raise argparse.ArgumentTypeError("Timeout phải hữu hạn, lớn hơn 0 và tối đa 60 giây.") from None


def _chain(value: str) -> int:
    if not re.fullmatch(r"[0-9]{1,78}", value) or not 0 < int(value) <= 2**256 - 1:
        raise argparse.ArgumentTypeError("Chain ID phải là số nguyên từ 1 đến 2^256-1.")
    return int(value)


def _resolve_loopback(base_url: str) -> None:
    url = urlsplit(base_url)
    try:
        addresses = socket.getaddrinfo(
            url.hostname, url.port or (443 if url.scheme == "https" else 80), type=socket.SOCK_STREAM,
        )
        if not addresses or any(not ipaddress.ip_address(item[4][0]).is_loopback for item in addresses):
            raise ValueError
    except (OSError, ValueError):
        raise SmokeFailure("Không xác nhận được địa chỉ loopback; không gửi request.") from None


@dataclass
class Report:
    passed: int = 0
    failed: int = 0

    def check(self, condition: bool, label: str, status: int | None = None) -> None:
        suffix = f" [HTTP {status}]" if status is not None else ""
        if condition:
            self.passed += 1
            print(f"PASS {label}{suffix}")
        else:
            self.failed += 1
            print(f"FAIL {label}{suffix}")
            raise SmokeFailure("Dừng luồng phụ thuộc sau kiểm tra thất bại.")

    def summary(self) -> int:
        print(f"Tổng: {self.passed} PASS, {self.failed} FAIL.")
        return 0 if self.failed == 0 else 1


class Smoke:
    """A single cookie client; every diagnostic is a fixed, non-secret label."""

    def __init__(self, client: httpx.Client, report: Report, *, origin: str, chain_id: int):
        self.client = client
        self.report = report
        self.origin = origin
        self.chain_id = chain_id
        self._sensitive: set[str] = set()
        self._csrf: str | None = None
        self._may_have_session = False

    def __repr__(self) -> str:
        return "<Auth HTTP smoke>"

    def _remember(self, value: str) -> str:
        self._sensitive.add(value)
        self._sensitive.add(sha256(value.encode("utf-8")).hexdigest())
        return value

    def request(self, method: str, path: str, expected: int, label: str, *,
                code: str | None = None, auth: bool = True, **kwargs) -> httpx.Response:
        try:
            response = self.client.request(method, path, **kwargs)
        except httpx.RequestError:
            self.report.check(False, "Không kết nối được Backend loopback trong timeout; kiểm tra uvicorn/cổng/TLS")
            raise SmokeFailure("HTTP không hoàn tất.") from None
        # Remember even unexpected cookies so they cannot leak through JSON.
        for cookie in self.client.cookies.jar:
            if cookie.name in {"gr_session", "gr_auth_flow"} and cookie.value:
                self._remember(cookie.value)
        self.report.check(response.status_code == expected, label, response.status_code)
        if auth:
            self.report.check(response.headers.get("Cache-Control") == "no-store", "Auth không được cache")
        if code is not None:
            body = self.body(response)
            self.report.check(isinstance(body.get("detail"), dict) and body["detail"].get("code") == code,
                              "Mã lỗi Auth đúng hợp đồng", response.status_code)
            self.report.check("set-cookie" not in response.headers, "Lỗi Auth không cấp cookie mới")
        return response

    def body(self, response: httpx.Response, fields: set[str] | None = None) -> dict:
        try:
            body = response.json() if len(response.content) <= 256 * 1024 else None
        except (ValueError, UnicodeError):
            body = None
        self.report.check(isinstance(body, dict), "Response là JSON object")

        def clean(value):
            if isinstance(value, dict):
                return not (_PRIVATE_FIELDS & value.keys()) and all(clean(item) for item in value.values())
            if isinstance(value, list):
                return all(clean(item) for item in value)
            return True

        encoded = json.dumps(body, ensure_ascii=False)
        self.report.check(clean(body) and not any(value in encoded for value in self._sensitive),
                          "JSON không chứa token/hash/binding/private key/chữ ký")
        if fields is not None:
            self.report.check(set(body) == fields, "Các field response đúng hợp đồng")
        return body

    def cors(self, response: httpx.Response) -> None:
        self.report.check(response.headers.get("Access-Control-Allow-Origin") == self.origin
                          and response.headers.get("Access-Control-Allow-Credentials") == "true",
                          "CORS origin cụ thể + credentials, không wildcard")

    def cookie(self, response: httpx.Response, name: str) -> str:
        found = []
        try:
            for header in response.headers.get_list("set-cookie"):
                jar = SimpleCookie()
                jar.load(header)
                if name in jar:
                    found.append(jar[name])
        except CookieError:
            pass
        self.report.check(len(found) == 1, "Có đúng một cookie " + name)
        cookie = found[0]
        secure = self.client.base_url.scheme == "https"
        self.report.check(bool(cookie["httponly"]) and cookie["samesite"].lower() == "lax"
                          and bool(cookie["secure"]) is secure and cookie["path"] == "/api"
                          and not cookie["domain"], "Cookie HttpOnly/SameSite/Secure/Path/host-only phù hợp")
        self.report.check(re.fullmatch(r"[0-9a-f]{64}", cookie.value) is not None,
                          "Cookie opaque đúng định dạng")
        try:
            age = int(cookie["max-age"])
            expires = parsedate_to_datetime(cookie["expires"])
            lifetime = (expires - datetime.now(UTC)).total_seconds()
            valid = age > 0 and expires.tzinfo is not None and lifetime > 0 and age <= lifetime + 5
        except (TypeError, ValueError, OverflowError):
            valid = False
        self.report.check(valid, "Cookie có thời hạn hữu hạn nhất quán")
        return self._remember(cookie.value)

    def readonly(self) -> None:
        health = self.request("GET", "/api/health", 200, "Backend đang phục vụ health", auth=False)
        self.report.check(self.body(health).get("status") == "ok", "Health status ok")
        schema = self.request("GET", "/openapi.json", 200, "Đọc OpenAPI", auth=False)
        try:
            paths = schema.json()["paths"]
            valid = all(set(paths[path]) == {method} for path, method in _ROUTES.items())
            ids = [paths[path][method]["operationId"] for path, method in _ROUTES.items()]
            valid = valid and len(ids) == len(set(ids)) and "/api/auth/me" not in paths
        except (ValueError, KeyError, TypeError):
            valid = False
        self.report.check(valid, "Đủ 5 Auth endpoint, method/prefix/operation ID đúng")
        self.report.check(not list(self.client.cookies.jar), "Client khởi đầu không có session")
        me = self.request("GET", "/api/me", 401, "/me không cookie bị từ chối", code="SESSION_REQUIRED")
        self.cors(me)
        preflight = self.request("OPTIONS", "/api/auth/register", 200, "Preflight Flutter Web", auth=False,
                                 headers={"Access-Control-Request-Method": "POST",
                                          "Access-Control-Request-Headers": "Content-Type,X-CSRF-Token,X-Gold-Rush-Auth"})
        self.cors(preflight)
        allowed = {item.strip().lower() for item in preflight.headers.get("Access-Control-Allow-Headers", "").split(",")}
        self.report.check({"content-type", "x-csrf-token", "x-gold-rush-auth"} <= allowed
                          and "*" not in allowed, "Preflight cho phép rõ các Auth headers")
        self.report.check(not list(self.client.cookies.jar), "Chế độ mặc định không nhận/cấp phiên")

    def challenge(self, wallet) -> tuple[dict, dict, str]:
        from eth_account.messages import encode_defunct

        response = self.request("POST", "/api/auth/challenge", 201, "Tạo challenge", json={
            "wallet_address": wallet.address, "chain_id": self.chain_id,
        }, headers={"X-Gold-Rush-Auth": "1"})
        binding = self.cookie(response, "gr_auth_flow")
        body = self.body(response, {"challenge_id", "message", "expires_at"})
        try:
            UUID(body["challenge_id"])
            message = body["message"]
            lines = message.split("\n")
            origin = urlsplit(self.origin)
            uri = urlsplit(lines[5].removeprefix("URI: "))
            issued = datetime.fromisoformat(lines[9].removeprefix("Issued At: "))
            expiry = datetime.fromisoformat(lines[10].removeprefix("Expiration Time: "))
            valid = (
                len(lines) == 11 and len(message.encode("utf-8")) <= 4096
                and lines[0] == f"{origin.scheme}://{origin.netloc} wants you to sign in with your Ethereum account:"
                and lines[1] == wallet.address and lines[2] == lines[4] == ""
                and lines[3] == "Sign in to Gold Rush. This request does not transfer assets."
                and lines[5].startswith("URI: ") and uri.scheme == origin.scheme and uri.netloc == origin.netloc
                and not uri.username and not uri.password and not uri.fragment
                and lines[6] == "Version: 1" and lines[7] == f"Chain ID: {self.chain_id}"
                and re.fullmatch(r"Nonce: [0-9a-f]{32}", lines[8]) is not None
                and issued.tzinfo is not None and expiry.tzinfo is not None
                and expiry == datetime.fromisoformat(body["expires_at"])
                and issued <= datetime.now(UTC) < expiry
            )
        except (TypeError, ValueError, IndexError, AttributeError):
            valid = False
        self.report.check(valid, "Challenge đúng ví TEST, Origin/SIWE/chain/nonce/thời gian trước khi ký")
        signature = "0x" + wallet.sign_message(encode_defunct(text=body["message"])).signature.hex()
        self._remember(signature)
        payload = {"challenge_id": body["challenge_id"], "message": body["message"], "signature": signature}
        return body, payload, binding

    def verify(self, payload: dict, expected: str) -> tuple[dict, str]:
        # A failed/timeout response may still have committed server-side.
        self._may_have_session = True
        response = self.request("POST", "/api/auth/verify", 200, "Xác minh chữ ký EIP-191 thật",
                                json=payload, headers={"X-Gold-Rush-Auth": "1"})
        token = self.cookie(response, "gr_session")
        fields = {"status", "expires_at", "csrf_token", "wallet_address" if expected == "registration_required" else "user"}
        body = self.body(response, fields)
        self.report.check(body.get("status") == expected, "Verify trả " + expected)
        self._csrf = body.get("csrf_token")
        self.report.check(isinstance(self._csrf, str) and bool(self._csrf), "Nhận CSRF qua JSON, không in giá trị")
        self.cors(response)
        return body, token

    def me(self, expected_user: dict) -> dict:
        response = self.request("GET", "/api/me", 200, "Đọc hồ sơ authenticated")
        body = self.body(response, {"user", "chain_id", "expires_at", "csrf_token"})
        self.report.check(body.get("user") == expected_user and body.get("chain_id") == self.chain_id,
                          "/me khớp users.id, username, wallet và chain")
        self.report.check(isinstance(body.get("csrf_token"), str) and bool(body["csrf_token"]), "Khôi phục CSRF từ /me")
        self._csrf = body["csrf_token"]
        self.cors(response)
        return body

    def logout(self, token: str) -> None:
        response = self.request("POST", "/api/auth/logout", 204, "Đăng xuất và thu hồi phiên",
                                json={}, headers={"X-CSRF-Token": self._csrf})
        self.report.check(response.content == b"", "Logout không có response body")
        self.report.check(not any(cookie.name in {"gr_session", "gr_auth_flow"} for cookie in self.client.cookies.jar),
                          "Cookie session và binding đã được xóa")
        self._may_have_session = False
        self._csrf = None
        self.request("GET", "/api/me", 401, "/me sau logout bị từ chối", code="SESSION_REQUIRED")
        self.request("GET", "/api/me", 401, "Cookie cũ sau logout không thể dùng lại", code="SESSION_REVOKED",
                     headers={"Cookie": "gr_session=" + token})

    def full_flow(self) -> None:
        from eth_account import Account

        wallet = Account.create()
        self._remember(wallet.key.hex())
        self._remember("0x" + wallet.key.hex())
        username = "TestAuth" + secrets.token_hex(5)  # 18 allowed ASCII code points.
        print(f"Ví TEST: {wallet.address}; username TEST: {username}")
        challenge, payload, _ = self.challenge(wallet)
        self.request("POST", "/api/auth/verify", 403, "Thiếu browser binding bị từ chối",
                     code="BROWSER_BINDING_INVALID", json=payload,
                     headers={"X-Gold-Rush-Auth": "1", "Cookie": "unrelated=1"})
        self.request("POST", "/api/auth/verify", 401, "Browser binding sai bị từ chối",
                     code="BROWSER_BINDING_INVALID", json=payload,
                     headers={"X-Gold-Rush-Auth": "1", "Cookie": "gr_auth_flow=" + secrets.token_hex(32)})
        grant, grant_token = self.verify(payload, "registration_required")
        self.report.check(grant["wallet_address"] == wallet.address.lower(), "Grant thuộc ví TEST đã ký")
        self.request("GET", "/api/me", 401, "Registration grant không có quyền /me", code="SESSION_INVALID")
        self.request("POST", "/api/auth/verify", 409, "Nonce đã dùng không được verify lại",
                     code="CHALLENGE_USED", json=payload, headers={"X-Gold-Rush-Auth": "1"})
        self.request("POST", "/api/auth/register", 403, "CSRF sai không được tạo user", code="CSRF_INVALID",
                     json={"username": username}, headers={"X-CSRF-Token": "invalid-smoke-csrf"})
        self.request("POST", "/api/auth/register", 403, "Origin sai không được tạo user", code="ORIGIN_FORBIDDEN",
                     json={"username": username}, headers={"Origin": "https://invalid.example", "X-CSRF-Token": self._csrf})
        response = self.request("POST", "/api/auth/register", 201, "Đăng ký tài khoản TEST",
                                json={"username": username}, headers={"X-CSRF-Token": self._csrf})
        token = self.cookie(response, "gr_session")
        registered = self.body(response, {"status", "user", "expires_at", "csrf_token"})
        user = registered.get("user")
        try:
            valid = (registered["status"] == "authenticated" and set(user) == _PUBLIC_USER
                     and user["username"] == username and user["wallet_address"] == wallet.address.lower()
                     and user["avatar"] == "george" and bool(UUID(user["id"])))
        except (TypeError, ValueError, KeyError):
            valid = False
        self.report.check(valid, "Tài khoản authenticated đúng ví/tên/user ID")
        self.report.check(token != grant_token and registered.get("csrf_token") != self._csrf,
                          "Đăng ký xoay session và CSRF, không tái dùng grant")
        self._csrf = registered.get("csrf_token")
        self.me(user)
        print("PASS Tóm tắt đăng ký mới: challenge → ký → verify → register → /me.")
        self.request("POST", "/api/auth/logout", 403, "CSRF sai không được logout", code="CSRF_INVALID",
                     json={}, headers={"X-CSRF-Token": "invalid-smoke-csrf"})
        self.logout(token)
        fresh, login_payload, _ = self.challenge(wallet)
        self.report.check(fresh["challenge_id"] != challenge["challenge_id"] and fresh["message"] != challenge["message"],
                          "Đăng nhập lại dùng challenge/message mới và binding được cấp lại")
        login, token = self.verify(login_payload, "authenticated")
        self.report.check(login.get("user") == user, "Đăng nhập lại giữ cùng user ID; không đăng ký thêm user")
        self.me(user)
        self.logout(token)
        print("PASS Tóm tắt đăng nhập lại: challenge mới → ký → authenticated cùng user → logout cuối.")
        print("Giới hạn: HTTP không đếm được số hàng users; chưa kiểm chứng MetaMask/browser/PostgreSQL/API game cũ.")

    def cleanup(self) -> None:
        """Best effort on a failed full flow; never claim revocation on failure."""
        if not self._may_have_session:
            return
        try:
            if not self._csrf:
                response = self.client.get("/api/me")
                if response.status_code == 200:
                    body = response.json()
                    value = body.get("csrf_token")
                    if isinstance(value, str) and value:
                        self._csrf = value
            if not self._csrf:
                self.report.failed += 1
                print("FAIL Cleanup: không có CSRF; phiên/grant có thể còn hiệu lực tới khi hết hạn.")
                return
            response = self.client.post("/api/auth/logout", json={}, headers={"X-CSRF-Token": self._csrf})
            if response.status_code != 204:
                self.report.failed += 1
            print("Cleanup: logout trả HTTP " + str(response.status_code) +
                  ("; đã thu hồi quyền." if response.status_code == 204 else "; chưa xác nhận thu hồi quyền."))
        except Exception:
            self.report.failed += 1
            print("FAIL Cleanup: không xác nhận được logout; phiên/grant có thể còn hiệu lực tới khi hết hạn.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", type=_local_url, default="http://localhost:8000")
    parser.add_argument("--origin", type=lambda value: _local_url(value, origin=True), default="http://localhost:5000")
    parser.add_argument("--timeout", type=_timeout, default=10.0, metavar="SECONDS")
    parser.add_argument("--chain-id", type=_chain, default=31337)
    parser.add_argument("--full-flow", action="store_true", help="Tạo một tài khoản TEST trong Database local; không xóa user khi logout.")
    args = parser.parse_args(argv)
    report = Report()
    smoke = None
    try:
        _resolve_loopback(args.base_url)
        print("Chế độ FULL: sẽ tạo một tài khoản TEST còn lưu trong Database local." if args.full_flow
              else "Chế độ đọc: chỉ GET/OPTIONS, không tạo challenge/user/session.")
        with httpx.Client(
            base_url=args.base_url, headers={"Origin": args.origin}, timeout=args.timeout,
            trust_env=False, follow_redirects=False,
        ) as client:
            smoke = Smoke(client, report, origin=args.origin, chain_id=args.chain_id)
            completed = False
            try:
                smoke.readonly()
                if args.full_flow:
                    smoke.full_flow()
                else:
                    print("Chưa kiểm tra luồng ghi Auth; tự chạy --full-flow nếu muốn tạo tài khoản TEST.")
                completed = True
            finally:
                if args.full_flow and not completed:
                    smoke.cleanup()
    except KeyboardInterrupt:
        report.failed += 1
        print("FAIL Đã dừng; không in dữ liệu xác thực.")
    except SmokeFailure:
        if report.failed == 0:
            report.failed += 1
            print("FAIL Không xác nhận được địa chỉ loopback; không gửi request.")
    except Exception:
        # Do not print traceback/exception: httpx/JSON errors can carry URLs or tokens.
        report.failed += 1
        print("FAIL Không hoàn tất smoke test; kiểm tra dependencies, HTTP và hợp đồng API.")
    return report.summary()


if __name__ == "__main__":
    raise SystemExit(main())
