"""Kiểm thử tích hợp hệ thống SIWE Auth và On-chain Ticket Verification (Phase 1.5).

Các kịch bản kiểm định:
1. Auth router đã được mount vào FastAPI (/api/auth/challenge, /api/auth/verify, /api/auth/register, /api/me, /api/auth/logout).
2. SIWE session hợp lệ được AuthService nhận diện và trích xuất đúng danh tính người chơi.
3. Cookie giả mạo hoặc hết hạn bị từ chối 401 Unauthorized.
4. Yêu cầu thay đổi trạng thái (mutation) thiếu hoặc sai X-CSRF-Token bị từ chối 403 Forbidden.
5. Có session hợp lệ và CSRF đúng thì mutation (/api/man/bat-dau) được phép đi tới logic nghiệp vụ.
6. CORS credentialed origins đúng cấu hình (allow_credentials=True, cấm wildcard, từ chối origin lạ).
7. Màn 2 có vé giả (ve.so mismatch hoặc ve.so=0) bị từ chối 422 Unprocessable Entity.
8. Chain ID sai bị từ chối 503 Service Unavailable (Fail-Closed).
9. RPC timeout fail-closed 503 và tuyệt đối không ghi ticket vào SoVe.
10. Khi không có AuthService production (hoặc hệ thống auth chưa khởi động), toàn bộ API bảo vệ hoạt động theo chế độ fail-closed (401/403).
"""
from __future__ import annotations

import os
import secrets
import shutil
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import MagicMock

import httpx
from alembic import command
from alembic.config import Config as AlembicConfig
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi import FastAPI, HTTPException, Request
from fastapi.testclient import TestClient

import config
from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai, kiem_tra_csrf_va_origin
from api import main
from api.main import app
from core import trong_tai
from core.xac_minh_ve_onchain import (
    XacMinhVeOnchain,
    LoiCauHinhVe,
    LoiKetNoiRPC,
    LoiVeKhongHopLe,
)


class TestAuthIntegrationPhase15(unittest.TestCase):
    """Kiểm thử tích hợp chuyên sâu cho Auth và Ticket Verifier."""

    @classmethod
    def setUpClass(cls):
        cls.test_dir = tempfile.mkdtemp(prefix="gr_auth_test_")
        cls.db_path = Path(cls.test_dir) / "auth_test.db"
        cls.so_ve_path = Path(cls.test_dir) / "ve_test.jsonl"
        cls.csrf_secret = secrets.token_hex(32)

        cls.origin_allowed = "http://localhost:5173"
        cls.origin_forbidden = "http://malicious-site.com"

        # Thiết lập biến môi trường cho Auth
        os.environ["AUTH_DATABASE_URL"] = f"sqlite:///{cls.db_path}"
        os.environ["AUTH_CSRF_SECRET"] = cls.csrf_secret
        os.environ["CORS_ORIGINS"] = f"{cls.origin_allowed},http://localhost:8501,http://localhost:5000"
        os.environ["APP_ROOT"] = str(Path(__file__).resolve().parents[1])

        cls.old_so_ve = config.SO_VE
        cls.old_main_so_ve = main.SO_VE
        config.SO_VE = cls.so_ve_path
        main.SO_VE = cls.so_ve_path

        # Chạy Alembic migrations để tạo schema Auth chuẩn
        backend_dir = Path(__file__).resolve().parents[1]
        alembic_cfg = AlembicConfig(str(backend_dir / "alembic.ini"))
        alembic_cfg.set_main_option("sqlalchemy.url", f"sqlite:///{cls.db_path}")
        command.upgrade(alembic_cfg, "head")

    @classmethod
    def tearDownClass(cls):
        config.SO_VE = cls.old_so_ve
        main.SO_VE = cls.old_main_so_ve
        os.environ.pop("AUTH_DATABASE_URL", None)
        os.environ.pop("AUTH_CSRF_SECRET", None)
        shutil.rmtree(cls.test_dir, ignore_errors=True)

    def test_01_auth_router_mounted_in_fastapi(self):
        """1. Kiểm tra 5 endpoint Auth đã được mount vào FastAPI."""
        with TestClient(app) as client:
            res = client.get("/openapi.json")
            self.assertEqual(res.status_code, 200)
            paths = res.json().get("paths", {})
            required_endpoints = [
                "/api/auth/challenge",
                "/api/auth/verify",
                "/api/auth/register",
                "/api/me",
                "/api/auth/logout",
            ]
            for ep in required_endpoints:
                self.assertIn(ep, paths, f"Thiếu endpoint Auth bắt buộc: {ep}")
            self.assertIsNotNone(getattr(app.state, "auth_service", None))
            self.assertIsNotNone(getattr(app.state, "ai_auth_source", None))

    def test_02_siwe_session_recognition(self):
        """2. SIWE session hợp lệ được AuthService nhận diện đúng thông tin ví."""
        with TestClient(app) as client:
            acc = Account.create()
            headers = {"Origin": self.origin_allowed, "X-Gold-Rush-Auth": "1"}

            # Bước 1: Xin challenge
            chal_res = client.post(
                "/api/auth/challenge",
                json={"wallet_address": acc.address, "chain_id": 31337},
                headers=headers,
            )
            self.assertEqual(chal_res.status_code, 201)
            chal_data = chal_res.json()
            self.assertIn("challenge_id", chal_data)
            self.assertIn("message", chal_data)

            # Bước 2: Ký thông điệp SIWE và verify
            sig = f"0x{acc.sign_message(encode_defunct(text=chal_data['message'])).signature.hex()}"
            ver_res = client.post(
                "/api/auth/verify",
                json={
                    "challenge_id": chal_data["challenge_id"],
                    "message": chal_data["message"],
                    "signature": sig,
                },
                headers=headers,
            )
            self.assertEqual(ver_res.status_code, 200)
            self.assertEqual(ver_res.json().get("status"), "registration_required")
            csrf_reg = ver_res.json()["csrf_token"]

            # Bước 3: Đăng ký tên người chơi
            reg_res = client.post(
                "/api/auth/register",
                json={"username": f"Player_{secrets.token_hex(4)}"},
                headers={"X-CSRF-Token": csrf_reg, "Origin": self.origin_allowed},
            )
            self.assertEqual(reg_res.status_code, 201)
            auth_data = reg_res.json()
            self.assertEqual(auth_data.get("status"), "authenticated")
            self.assertEqual(auth_data["user"]["wallet_address"].lower(), acc.address.lower())

            # Bước 4: Kiểm tra GET /api/me trả về đúng ví đã xác thực
            me_res = client.get("/api/me", headers={"Origin": self.origin_allowed})
            self.assertEqual(me_res.status_code, 200)
            self.assertEqual(me_res.json()["user"]["wallet_address"].lower(), acc.address.lower())

    def test_03_fake_or_expired_cookie_rejected(self):
        """3. Cookie giả mạo hoặc không tồn tại bị từ chối 401."""
        with TestClient(app) as client:
            # Gửi cookie ngẫu nhiên 64 hex không có trong CSDL
            client.cookies.set("gr_session", "a" * 64)
            res = client.get("/api/me", headers={"Origin": self.origin_allowed})
            self.assertEqual(res.status_code, 401)

            # Gọi mutation với cookie giả cũng bị từ chối 401
            res_mut = client.post(
                "/api/man/bat-dau",
                json={"man": 1, "ve": 0},
                headers={"Origin": self.origin_allowed, "X-CSRF-Token": "test"},
            )
            self.assertEqual(res_mut.status_code, 401)

    def test_04_invalid_csrf_or_origin_rejected(self):
        """4. Thiếu CSRF, sai CSRF hoặc sai Origin khi dùng cookie đều bị từ chối 403."""
        with TestClient(app) as client:
            acc = Account.create()
            headers = {"Origin": self.origin_allowed, "X-Gold-Rush-Auth": "1"}
            chal_res = client.post("/api/auth/challenge", json={"wallet_address": acc.address, "chain_id": 31337}, headers=headers)
            sig = f"0x{acc.sign_message(encode_defunct(text=chal_res.json()['message'])).signature.hex()}"
            ver_res = client.post("/api/auth/verify", json={"challenge_id": chal_res.json()["challenge_id"], "message": chal_res.json()["message"], "signature": sig}, headers=headers)
            csrf_reg = ver_res.json()["csrf_token"]
            reg_res = client.post("/api/auth/register", json={"username": f"User_{secrets.token_hex(4)}"}, headers={"X-CSRF-Token": csrf_reg, "Origin": self.origin_allowed})
            real_csrf = reg_res.json()["csrf_token"]

            # 4a. Thiếu X-CSRF-Token -> 403
            res_no_csrf = client.post("/api/man/bat-dau", json={"man": 1, "ve": 0}, headers={"Origin": self.origin_allowed})
            self.assertEqual(res_no_csrf.status_code, 403)
            self.assertEqual(res_no_csrf.json()["detail"]["code"], "CSRF_MISSING")

            # 4b. CSRF token sai -> 403
            res_bad_csrf = client.post(
                "/api/man/bat-dau",
                json={"man": 1, "ve": 0},
                headers={"Origin": self.origin_allowed, "X-CSRF-Token": "bad_token_1234"},
            )
            self.assertEqual(res_bad_csrf.status_code, 403)
            self.assertEqual(res_bad_csrf.json()["detail"]["code"], "CSRF_INVALID")

            # 4c. Origin không được phép -> 403
            res_bad_origin = client.post(
                "/api/man/bat-dau",
                json={"man": 1, "ve": 0},
                headers={"Origin": self.origin_forbidden, "X-CSRF-Token": real_csrf},
            )
            self.assertEqual(res_bad_origin.status_code, 403)
            self.assertEqual(res_bad_origin.json()["detail"]["code"], "ORIGIN_FORBIDDEN")

    def test_05_valid_session_and_csrf_allows_mutation(self):
        """5. Có session hợp lệ và CSRF đúng thì mutation thành công (Stage 1, ve=0)."""
        with TestClient(app) as client:
            acc = Account.create()
            headers = {"Origin": self.origin_allowed, "X-Gold-Rush-Auth": "1"}
            chal_res = client.post("/api/auth/challenge", json={"wallet_address": acc.address, "chain_id": 31337}, headers=headers)
            sig = f"0x{acc.sign_message(encode_defunct(text=chal_res.json()['message'])).signature.hex()}"
            ver_res = client.post("/api/auth/verify", json={"challenge_id": chal_res.json()["challenge_id"], "message": chal_res.json()["message"], "signature": sig}, headers=headers)
            reg_res = client.post("/api/auth/register", json={"username": f"User_{secrets.token_hex(4)}"}, headers={"X-CSRF-Token": ver_res.json()["csrf_token"], "Origin": self.origin_allowed})
            real_csrf = reg_res.json()["csrf_token"]

            res = client.post(
                "/api/man/bat-dau",
                json={"man": 1, "ve": 0},
                headers={"Origin": self.origin_allowed, "X-CSRF-Token": real_csrf},
            )
            self.assertEqual(res.status_code, 201)
            self.assertTrue(res.json()["da_bat_dau"])
            self.assertEqual(res.json()["vi"].lower(), acc.address.lower())

    def test_06_cors_credentialed_origins(self):
        """6. CORS credentialed origins đúng cấu hình, cho phép cookie với origin được whitelist."""
        with TestClient(app) as client:
            # OPTIONS preflight từ origin hợp lệ
            res = client.options(
                "/api/man/bat-dau",
                headers={
                    "Origin": self.origin_allowed,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "X-CSRF-Token,Content-Type",
                },
            )
            self.assertEqual(res.headers.get("access-control-allow-origin"), self.origin_allowed)
            self.assertEqual(res.headers.get("access-control-allow-credentials"), "true")

            # Preflight từ origin cấm không được gán allow-credentials
            res_bad = client.options(
                "/api/man/bat-dau",
                headers={
                    "Origin": self.origin_forbidden,
                    "Access-Control-Request-Method": "POST",
                },
            )
            self.assertNotEqual(res_bad.headers.get("access-control-allow-origin"), self.origin_forbidden)

    def test_07_stage_2_fake_ticket_rejected_422(self):
        """7. Màn 2 có vé giả bị từ chối 422 Unprocessable Entity."""
        with TestClient(app) as client:
            acc = Account.create()
            headers = {"Origin": self.origin_allowed, "X-Gold-Rush-Auth": "1"}
            chal_res = client.post("/api/auth/challenge", json={"wallet_address": acc.address, "chain_id": 31337}, headers=headers)
            sig = f"0x{acc.sign_message(encode_defunct(text=chal_res.json()['message'])).signature.hex()}"
            ver_res = client.post("/api/auth/verify", json={"challenge_id": chal_res.json()["challenge_id"], "message": chal_res.json()["message"], "signature": sig}, headers=headers)
            reg_res = client.post("/api/auth/register", json={"username": f"User_{secrets.token_hex(4)}"}, headers={"X-CSRF-Token": ver_res.json()["csrf_token"], "Origin": self.origin_allowed})
            real_csrf = reg_res.json()["csrf_token"]

            # Mock verifier trả về lỗi vé không hợp lệ
            mock_verifier = MagicMock(spec=XacMinhVeOnchain)
            mock_verifier.xac_minh_ve_hop_le_de_vao_man.side_effect = LoiVeKhongHopLe("Số vé không khớp on-chain")
            app.state.onchain_ticket_verifier = mock_verifier

            try:
                res = client.post(
                    "/api/man/bat-dau",
                    json={"man": 2, "ve": 999},
                    headers={"Origin": self.origin_allowed, "X-CSRF-Token": real_csrf},
                )
                self.assertEqual(res.status_code, 422)
                self.assertIn("Vé cọc on-chain không hợp lệ", res.json()["detail"])
            finally:
                if hasattr(app.state, "onchain_ticket_verifier"):
                    delattr(app.state, "onchain_ticket_verifier")

    def test_08_wrong_chain_id_rejected_503(self):
        """8. Chain ID sai bị từ chối 503 Service Unavailable (Fail-Closed)."""
        with TestClient(app) as client:
            acc = Account.create()
            headers = {"Origin": self.origin_allowed, "X-Gold-Rush-Auth": "1"}
            chal_res = client.post("/api/auth/challenge", json={"wallet_address": acc.address, "chain_id": 31337}, headers=headers)
            sig = f"0x{acc.sign_message(encode_defunct(text=chal_res.json()['message'])).signature.hex()}"
            ver_res = client.post("/api/auth/verify", json={"challenge_id": chal_res.json()["challenge_id"], "message": chal_res.json()["message"], "signature": sig}, headers=headers)
            reg_res = client.post("/api/auth/register", json={"username": f"User_{secrets.token_hex(4)}"}, headers={"X-CSRF-Token": ver_res.json()["csrf_token"], "Origin": self.origin_allowed})
            real_csrf = reg_res.json()["csrf_token"]

            mock_verifier = MagicMock(spec=XacMinhVeOnchain)
            mock_verifier.xac_minh_ve_hop_le_de_vao_man.side_effect = LoiCauHinhVe("Mạng RPC sai chainId: trả về 1, yêu cầu 31337.")
            app.state.onchain_ticket_verifier = mock_verifier

            try:
                res = client.post(
                    "/api/man/bat-dau",
                    json={"man": 2, "ve": 1},
                    headers={"Origin": self.origin_allowed, "X-CSRF-Token": real_csrf},
                )
                self.assertEqual(res.status_code, 503)
                self.assertIn("Hệ thống xác minh blockchain chưa sẵn sàng", res.json()["detail"])
            finally:
                if hasattr(app.state, "onchain_ticket_verifier"):
                    delattr(app.state, "onchain_ticket_verifier")

    def test_09_rpc_timeout_does_not_write_ticket(self):
        """9. RPC timeout trả về 503 và tuyệt đối không ghi ticket vào SoVe."""
        with TestClient(app) as client:
            acc = Account.create()
            headers = {"Origin": self.origin_allowed, "X-Gold-Rush-Auth": "1"}
            chal_res = client.post("/api/auth/challenge", json={"wallet_address": acc.address, "chain_id": 31337}, headers=headers)
            sig = f"0x{acc.sign_message(encode_defunct(text=chal_res.json()['message'])).signature.hex()}"
            ver_res = client.post("/api/auth/verify", json={"challenge_id": chal_res.json()["challenge_id"], "message": chal_res.json()["message"], "signature": sig}, headers=headers)
            reg_res = client.post("/api/auth/register", json={"username": f"User_{secrets.token_hex(4)}"}, headers={"X-CSRF-Token": ver_res.json()["csrf_token"], "Origin": self.origin_allowed})
            real_csrf = reg_res.json()["csrf_token"]

            mock_verifier = MagicMock(spec=XacMinhVeOnchain)
            mock_verifier.xac_minh_ve_hop_le_de_vao_man.side_effect = LoiKetNoiRPC("RPC timeout sau 5.0s")
            app.state.onchain_ticket_verifier = mock_verifier

            ma_van = f"van-timeout-{secrets.token_hex(6)}"
            try:
                res = client.post(
                    "/api/man/bat-dau",
                    json={"man": 2, "ve": 5, "ma_van": ma_van},
                    headers={"Origin": self.origin_allowed, "X-CSRF-Token": real_csrf},
                )
                self.assertEqual(res.status_code, 503)
                self.assertIn("Không thể kết nối RPC xác minh vé on-chain", res.json()["detail"])

                # Kiểm tra SoVe: đảm bảo mã ván và vé 5 KHÔNG hề được ghi vào sổ
                so_ve = trong_tai.SoVe(config.SO_VE)
                self.assertIsNone(so_ve.lay_theo_van(ma_van))
                self.assertFalse(so_ve.da_dung(acc.address, 5))
            finally:
                if hasattr(app.state, "onchain_ticket_verifier"):
                    delattr(app.state, "onchain_ticket_verifier")

    def test_10_missing_auth_service_fails_closed(self):
        """10. Khi không có AuthService gắn trên app, hệ thống từ chối truy cập (Fail-Closed)."""
        app_dummy = FastAPI()

        @app_dummy.post("/test-protected")
        async def protected_endpoint(request: Request, player: NguoiChoiXacThuc = unittest.mock.AsyncMock()):
            # Giả lập hàm guard thực tế
            return {"ok": True}

        # Gọi trực tiếp lay_nguoi_choi_hien_tai trên app_dummy không có auth_service
        req_dummy = Request({"type": "http", "method": "POST", "headers": [], "app": app_dummy})
        with self.assertRaises(HTTPException) as ctx:
            import asyncio
            asyncio.run(lay_nguoi_choi_hien_tai(req_dummy))
        self.assertEqual(ctx.exception.status_code, 401)
        self.assertEqual(ctx.exception.detail.get("code"), "SESSION_REQUIRED")


if __name__ == "__main__":
    unittest.main()
