"""Bộ kiểm thử tích hợp toàn diện Auth SIWE thật với Backend AI và EIP-712 Voucher (Giai đoạn 5).

Bao phủ đầy đủ 22 kịch bản kiểm thử theo yêu cầu:
1. SIWE đăng nhập hợp lệ.
2. Chữ ký SIWE giả.
3. Nonce đã sử dụng.
4. Nonce hết hạn.
5. Sai domain.
6. Sai chain ID.
7. Session hết hạn.
8. Session bị thu hồi.
9. Cookie không hợp lệ.
10. Cookie bị sửa.
11. Header giả mạo user_id.
12. Header giả mạo wallet_address.
13. Người dùng A truy cập nhân vật B.
14. Người dùng A xin voucher của nhân vật B.
15. CSRF token hợp lệ.
16. CSRF token thiếu.
17. CSRF token sai.
18. Origin không hợp lệ.
19. Database Auth không sẵn sàng.
20. Session demo bị từ chối.
21. Session thật kết hợp RPC Verifier.
22. Session thật kết hợp EIP-712 Voucher.
"""
from __future__ import annotations

import io
import secrets
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from io import BytesIO
from pathlib import Path
from unittest.mock import patch
import uuid

import pytest
from alembic import command
from alembic.config import Config as AlembicConfig
from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import select, update

from api.auth_adapter import tich_hop_auth_vao_app
from api.nhan_vat_ai import (
    NguCanhAnhNhanVat,
    khoi_dong_nhan_vat_ai,
    router as router_nhan_vat_ai,
)
from auth.config import AuthConfig
from auth.database import create_auth_engine, create_session_factory
from auth.models import AuthChallenge, AuthSession, User
from auth.router import create_auth_router
from auth.service import AuthService
from core.character_voucher import CauHinhVoucher, DichVuVoucherNhanVat
from core.eth_ky import dia_chi_tu_khoa, phuc_hoi, bam_eip712
from core.character_voucher import VOUCHER_TYPE_NAME, VOUCHER_FIELDS

_BACKEND_DIR = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_DIR / "alembic.ini"
_ORIGIN = "http://localhost:5000"
_BOOTSTRAP_HEADERS = {"Origin": _ORIGIN, "X-Gold-Rush-Auth": "1"}

TEST_SIGNER_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
TEST_SIGNER_ADDR = dia_chi_tu_khoa(bytes.fromhex(TEST_SIGNER_KEY))
TEST_CONTRACT = "0x2222222222222222222222222222222222222222"
CHAIN_ID = 31337


def _tao_anh_png() -> bytes:
    img = Image.new("RGBA", (128, 128), color="gold")
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@contextmanager
def app_auth_moi_truong(tmp_path: Path, monkeypatch) -> Iterator[tuple[TestClient, FastAPI, AuthService, AuthConfig]]:
    """Tạo môi trường kiểm thử hoàn chỉnh với SQLite Auth đã migrate và Backend AI."""
    auth_db_path = tmp_path / "auth.sqlite3"
    char_db_path = tmp_path / "characters.sqlite3"
    img_db_path = tmp_path / "images.sqlite3"
    csrf_hex = secrets.token_hex(32)
    csrf_secret = bytes.fromhex(csrf_hex)

    monkeypatch.setenv("AUTH_CSRF_SECRET", csrf_hex)
    monkeypatch.setenv("AUTH_DATABASE_URL", f"sqlite:///{auth_db_path}")
    monkeypatch.setenv("AI_IMAGE_DB", str(img_db_path))
    monkeypatch.setenv("AI_CHARACTER_DB", str(char_db_path))
    monkeypatch.setenv("AI_IMAGE_ENABLED", "false")
    monkeypatch.setenv("AI_IMAGE_DEMO", "true")
    monkeypatch.setenv("AI_CHARACTER_SIGNER_PRIVATE_KEY", TEST_SIGNER_KEY)
    monkeypatch.setenv("AI_CHARACTER_AUTHORIZED_SIGNER", TEST_SIGNER_ADDR)
    monkeypatch.setenv("AI_BLOCKCHAIN_RPC_URL", "http://mock-rpc.local:8545")
    monkeypatch.setenv("AI_CHARACTER_REGISTRY_ADDRESS", TEST_CONTRACT)
    monkeypatch.setenv("AI_BLOCKCHAIN_CHAIN_ID", str(CHAIN_ID))
    monkeypatch.setenv("AI_CHARACTER_VOUCHER_ENABLED", "true")

    import config
    monkeypatch.setattr(config, "ENABLED", {"nhan_vat_ai"})
    monkeypatch.setattr(config, "AI_BLOCKCHAIN_RPC_URL", "http://mock-rpc.local:8545")
    monkeypatch.setattr(config, "AI_CHARACTER_SIGNER_PRIVATE_KEY", TEST_SIGNER_KEY)
    monkeypatch.setattr(config, "AI_CHARACTER_AUTHORIZED_SIGNER", TEST_SIGNER_ADDR)
    monkeypatch.setattr(config, "AI_CHARACTER_REGISTRY_ADDRESS", TEST_CONTRACT)
    monkeypatch.setattr(config, "AI_BLOCKCHAIN_CHAIN_ID", CHAIN_ID)
    monkeypatch.setattr(config, "AI_CHARACTER_VOUCHER_ENABLED", True)

    auth_config = AuthConfig(
        database_url=f"sqlite:///{auth_db_path}",
        csrf_secret=csrf_secret,
        cors_origins=(_ORIGIN,),
        siwe_domain="localhost:5000",
        siwe_uri=_ORIGIN,
        allowed_chain_ids=(31337,),
        challenge_ttl_seconds=300,
        session_ttl_seconds=86400,
        registration_ttl_seconds=900,
        cookie_secure=False,
    )

    # Chạy Alembic migration cho SQLite DB test
    alembic_cfg = AlembicConfig(str(_ALEMBIC_INI), stdout=io.StringIO())
    alembic_cfg.set_main_option("sqlalchemy.url", str(auth_config.database_url))
    with patch("logging.config.fileConfig"):
        command.upgrade(alembic_cfg, "head")

    engine = create_auth_engine(auth_config)
    session_factory = create_session_factory(engine)
    auth_service = AuthService(auth_config, session_factory)

    app = FastAPI(title="Test Gold Rush Auth + AI")
    # Gắn Auth router dùng chung clock với auth_service
    auth_router = create_auth_router(auth_config, session_factory, clock=lambda: auth_service._now())
    app.include_router(auth_router)
    app.include_router(router_nhan_vat_ai)

    # Khởi động dịch vụ AI và gắn adapter Auth SIWE
    khoi_dong_nhan_vat_ai(app)
    tich_hop_auth_vao_app(app, auth_service, auth_config)

    with TestClient(app, base_url=_ORIGIN) as client:
        yield client, app, auth_service, auth_config

    engine.dispose()


def thuc_hien_dang_nhap_siwe(
    client: TestClient, account, *, username: str = "ThoMo"
) -> dict:
    """Thực hiện trọn vẹn luồng đăng nhập SIWE: challenge -> verify -> (register)."""
    # 1. Challenge
    r_chal = client.post(
        "/api/auth/challenge",
        headers=_BOOTSTRAP_HEADERS,
        json={"wallet_address": account.address, "chain_id": 31337},
    )
    assert r_chal.status_code == 201, r_chal.text
    chal_data = r_chal.json()
    chal_id = chal_data["challenge_id"]
    msg = chal_data["message"]

    # 2. Ký thông điệp SIWE bằng ví EOA
    sig = "0x" + account.sign_message(encode_defunct(text=msg)).signature.hex()

    # 3. Verify
    r_ver = client.post(
        "/api/auth/verify",
        headers=_BOOTSTRAP_HEADERS,
        json={"challenge_id": chal_id, "message": msg, "signature": sig},
    )
    assert r_ver.status_code == 200, r_ver.text
    ver_data = r_ver.json()

    # 4. Nếu là người chơi mới, hoàn tất đăng ký username
    if ver_data.get("status") == "registration_required":
        r_reg = client.post(
            "/api/auth/register",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": ver_data["csrf_token"]},
            json={"username": username},
        )
        assert r_reg.status_code == 201, r_reg.text
        res_data = r_reg.json()
        return {
            "user_id": str(res_data["user"]["id"]),
            "wallet_address": res_data["user"]["wallet_address"],
            "csrf_token": res_data["csrf_token"],
            "username": res_data["user"]["username"],
            "challenge_data": chal_data,
        }

    return {
        "user_id": str(ver_data["user"]["id"]),
        "wallet_address": ver_data["user"]["wallet_address"],
        "csrf_token": ver_data["csrf_token"],
        "username": ver_data["user"]["username"],
        "challenge_data": chal_data,
    }


def tao_va_luu_nhan_vat_cho_user(client: TestClient, user_info: dict, desc: str = "Thợ mỏ vàng") -> dict:
    """Tạo preview và lưu nhân vật chính thức qua session SIWE."""
    ctx = NguCanhAnhNhanVat(
        player_id=user_info["user_id"],
        allowed_stage_ids=frozenset(range(1, 7)),
        completed_stage_ids=frozenset(range(1, 7)),
        user_id=user_info["user_id"],
        wallet_address=user_info["wallet_address"],
    )
    client.app.state.ai_image_player = ctx

    r_tao = client.post(
        "/api/ai/nhan-vat/tao",
        headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
        json={"description": desc},
    )
    assert r_tao.status_code == 200, r_tao.text
    img_id = r_tao.json()["image_id"]

    r_luu = client.post(
        "/api/ai/nhan-vat/luu",
        headers={"Origin": _ORIGIN, "X-CSRF-Token": user_info["csrf_token"]},
        json={"image_id": img_id},
    )
    assert r_luu.status_code == 201, r_luu.text
    return r_luu.json()


# ===========================================================================
# 22 BÀI KIỂM THỬ THEO ĐẶC TẢ GIAI ĐOẠN 5
# ===========================================================================

def test_01_siwe_dang_nhap_hop_le(tmp_path, monkeypatch):
    """1. SIWE đăng nhập hợp lệ: chữ ký EIP-4361 phục hồi đúng ví, session thiết lập."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="HiepSi")
        assert info["wallet_address"].lower() == acc.address.lower()

        # Kiểm tra endpoint /me bằng session cookie đã thiết lập
        r = c.get("/api/me", headers={"Origin": _ORIGIN})
        assert r.status_code == 200
        assert r.json()["user"]["wallet_address"].lower() == acc.address.lower()


def test_02_chu_ky_siwe_gia(tmp_path, monkeypatch):
    """2. Chữ ký SIWE giả: thông điệp của ví A nhưng ký bằng khóa ví B -> 401 SIGNER_MISMATCH."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc_a = Account.create()
        acc_b = Account.create()

        r_chal = c.post(
            "/api/auth/challenge",
            headers=_BOOTSTRAP_HEADERS,
            json={"wallet_address": acc_a.address, "chain_id": 31337},
        )
        chal = r_chal.json()

        # Ví B ký thông điệp của ví A
        fake_sig = "0x" + acc_b.sign_message(encode_defunct(text=chal["message"])).signature.hex()

        r_ver = c.post(
            "/api/auth/verify",
            headers=_BOOTSTRAP_HEADERS,
            json={"challenge_id": chal["challenge_id"], "message": chal["message"], "signature": fake_sig},
        )
        assert r_ver.status_code == 401
        assert r_ver.json()["detail"]["code"] == "SIGNER_MISMATCH"


def test_03_nonce_da_su_dung(tmp_path, monkeypatch):
    """3. Nonce đã sử dụng: nỗ lực gọi verify lần thứ hai với cùng challenge -> 409 CHALLENGE_USED."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        r_chal = c.post(
            "/api/auth/challenge",
            headers=_BOOTSTRAP_HEADERS,
            json={"wallet_address": acc.address, "chain_id": 31337},
        )
        chal = r_chal.json()
        sig = "0x" + acc.sign_message(encode_defunct(text=chal["message"])).signature.hex()

        # Lần 1: Thành công
        r1 = c.post(
            "/api/auth/verify",
            headers=_BOOTSTRAP_HEADERS,
            json={"challenge_id": chal["challenge_id"], "message": chal["message"], "signature": sig},
        )
        assert r1.status_code == 200

        # Lần 2: Bị từ chối vì nonce đã bị consume
        r2 = c.post(
            "/api/auth/verify",
            headers=_BOOTSTRAP_HEADERS,
            json={"challenge_id": chal["challenge_id"], "message": chal["message"], "signature": sig},
        )
        assert r2.status_code == 409
        assert r2.json()["detail"]["code"] == "CHALLENGE_USED"


def test_04_nonce_het_han(tmp_path, monkeypatch):
    """4. Nonce hết hạn: challenge quá hạn TTL -> 410 CHALLENGE_EXPIRED."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, auth_service, _):
        acc = Account.create()
        r_chal = c.post(
            "/api/auth/challenge",
            headers=_BOOTSTRAP_HEADERS,
            json={"wallet_address": acc.address, "chain_id": 31337},
        )
        chal = r_chal.json()
        sig = "0x" + acc.sign_message(encode_defunct(text=chal["message"])).signature.hex()

        # Giả lập thời gian server trôi qua quá thời hạn challenge
        original_now = auth_service._now
        auth_service._now = lambda: datetime.now(UTC) + timedelta(seconds=600)
        try:
            r_ver = c.post(
                "/api/auth/verify",
                headers=_BOOTSTRAP_HEADERS,
                json={"challenge_id": chal["challenge_id"], "message": chal["message"], "signature": sig},
            )
            assert r_ver.status_code == 410
            assert r_ver.json()["detail"]["code"] == "CHALLENGE_EXPIRED"
        finally:
            auth_service._now = original_now


def test_05_sai_domain(tmp_path, monkeypatch):
    """5. Sai domain: thông điệp bị thay đổi domain khác cấu hình -> 401 MESSAGE_INVALID."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        r_chal = c.post(
            "/api/auth/challenge",
            headers=_BOOTSTRAP_HEADERS,
            json={"wallet_address": acc.address, "chain_id": 31337},
        )
        chal = r_chal.json()

        # Giả mạo domain
        tampered_msg = chal["message"].replace("localhost:5000", "attacker-domain.com")
        sig = "0x" + acc.sign_message(encode_defunct(text=tampered_msg)).signature.hex()

        r_ver = c.post(
            "/api/auth/verify",
            headers=_BOOTSTRAP_HEADERS,
            json={"challenge_id": chal["challenge_id"], "message": tampered_msg, "signature": sig},
        )
        assert r_ver.status_code == 401
        assert r_ver.json()["detail"]["code"] in ("MESSAGE_INVALID", "MESSAGE_MISMATCH")


def test_06_sai_chain_id(tmp_path, monkeypatch):
    """6. Sai chain ID: yêu cầu challenge với chainId không được phép -> 422 CHAIN_NOT_ALLOWED."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        r = c.post(
            "/api/auth/challenge",
            headers=_BOOTSTRAP_HEADERS,
            json={"wallet_address": acc.address, "chain_id": 999999},
        )
        assert r.status_code == 422
        assert r.json()["detail"]["code"] == "CHAIN_NOT_ALLOWED"


def test_07_session_het_han(tmp_path, monkeypatch):
    """7. Session hết hạn: truy cập API nhân vật bằng session đã hết hạn -> 401 SESSION_EXPIRED."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, auth_service, _):
        acc = Account.create()
        thuc_hien_dang_nhap_siwe(c, acc, username="UserExp")

        # Giả lập thời gian server trôi qua quá thời hạn session
        original_now = auth_service._now
        auth_service._now = lambda: datetime.now(UTC) + timedelta(days=10)
        try:
            r = c.get("/api/ai/nhan-vat/danh-sach", headers={"Origin": _ORIGIN})
            assert r.status_code == 401
            assert r.json()["detail"]["code"] == "SESSION_EXPIRED"
        finally:
            auth_service._now = original_now


def test_08_session_bi_thu_hoi(tmp_path, monkeypatch):
    """8. Session bị thu hồi: người chơi đăng xuất -> session revoked -> truy cập nhân vật bị từ chối 401."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="UserRevoke")

        # Đăng xuất
        r_logout = c.post(
            "/api/auth/logout",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
            json={},
        )
        assert r_logout.status_code == 204

        # Sau khi đăng xuất, cố tình gửi cookie cũ
        r = c.get("/api/ai/nhan-vat/danh-sach", headers={"Origin": _ORIGIN})
        assert r.status_code == 401


def test_09_cookie_khong_hop_le(tmp_path, monkeypatch):
    """9. Cookie không hợp lệ: cookie sai định dạng format -> 401 SESSION_INVALID."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        c.cookies.set("gr_session", "not_a_valid_hex_token")
        r = c.get("/api/ai/nhan-vat/danh-sach", headers={"Origin": _ORIGIN})
        assert r.status_code == 401
        assert r.json()["detail"]["code"] == "SESSION_INVALID"


def test_10_cookie_bi_sua(tmp_path, monkeypatch):
    """10. Cookie bị sửa: sửa 1 ký tự trong cookie 64-hex -> token không tồn tại trong DB -> 401."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        thuc_hien_dang_nhap_siwe(c, acc, username="UserTamper")

        token = c.cookies.get("gr_session")
        # Thay đổi ký tự đầu
        tampered_token = ("0" if token[0] != "0" else "1") + token[1:]
        c.cookies.set("gr_session", tampered_token)

        r = c.get("/api/ai/nhan-vat/danh-sach", headers={"Origin": _ORIGIN})
        assert r.status_code == 401
        assert r.json()["detail"]["code"] == "SESSION_INVALID"


def test_11_header_gia_mao_user_id(tmp_path, monkeypatch):
    """11. Header giả mạo user_id: kẻ tấn công gửi X-User-Id mà không có session -> 401."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        fake_id = str(uuid.uuid4())
        r = c.get(
            "/api/ai/nhan-vat/danh-sach",
            headers={"Origin": _ORIGIN, "X-User-Id": fake_id, "User-Id": fake_id},
        )
        assert r.status_code == 401


def test_12_header_gia_mao_wallet_address(tmp_path, monkeypatch):
    """12. Header giả mạo wallet_address: kẻ tấn công gửi X-Wallet-Address -> API bỏ qua, dùng đúng ví session."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="RealUser")
        tao_va_luu_nhan_vat_cho_user(c, info, "Nhân vật thật")

        fake_wallet = "0x9999999999999999999999999999999999999999"
        r = c.get(
            "/api/ai/nhan-vat/danh-sach",
            headers={"Origin": _ORIGIN, "X-Wallet-Address": fake_wallet},
        )
        assert r.status_code == 200
        # Danh sách trả về chỉ chứa nhân vật thuộc về ví thật
        chars = r.json()
        assert len(chars) == 1
        assert chars[0]["verified_wallet_address"].lower() == acc.address.lower()


def test_13_nguoi_dung_a_truy_cap_nhan_vat_b(tmp_path, monkeypatch):
    """13. Người dùng A truy cập nhân vật B: Người dùng B cố GET nhân vật của A -> 403."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc_a = Account.create()
        info_a = thuc_hien_dang_nhap_siwe(c, acc_a, username="UserA")
        char_a = tao_va_luu_nhan_vat_cho_user(c, info_a, "Nhân vật A")
        char_id = char_a["character_id"]

        # Người dùng B đăng nhập trên client mới
        acc_b = Account.create()
        c.cookies.clear()
        thuc_hien_dang_nhap_siwe(c, acc_b, username="UserB")

        # B cố truy cập nhân vật của A
        r = c.get(f"/api/ai/nhan-vat/{char_id}", headers={"Origin": _ORIGIN})
        assert r.status_code == 403
        assert "Không có quyền" in r.json()["detail"]


def test_14_nguoi_dung_a_xin_voucher_nhan_vat_b(tmp_path, monkeypatch):
    """14. Người dùng A xin voucher của nhân vật B: B cố xin voucher cho nhân vật A -> 403."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc_a = Account.create()
        info_a = thuc_hien_dang_nhap_siwe(c, acc_a, username="UserA")
        char_a = tao_va_luu_nhan_vat_cho_user(c, info_a, "Nhân vật A")
        char_id = char_a["character_id"]

        acc_b = Account.create()
        c.cookies.clear()
        info_b = thuc_hien_dang_nhap_siwe(c, acc_b, username="UserB")

        # B cố xin voucher cho nhân vật của A
        r = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info_b["csrf_token"]},
        )
        assert r.status_code == 403
        assert "Không có quyền" in r.json()["detail"]


def test_15_csrf_token_hop_le(tmp_path, monkeypatch):
    """15. CSRF token hợp lệ: POST /ky-voucher có CSRF token và Origin đúng -> 200 OK."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="CSRFValid")
        char = tao_va_luu_nhan_vat_cho_user(c, info, "Voucher CSRF")
        char_id = char["character_id"]

        r = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
        )
        assert r.status_code == 200
        assert r.json()["signature"].startswith("0x")


def test_16_csrf_token_thieu(tmp_path, monkeypatch):
    """16. CSRF token thiếu: POST /ky-voucher thiếu header X-CSRF-Token -> 403 CSRF_INVALID."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="CSRFMissing")
        char = tao_va_luu_nhan_vat_cho_user(c, info, "Voucher Test")
        char_id = char["character_id"]

        # Thiếu header X-CSRF-Token
        r = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": _ORIGIN},
        )
        assert r.status_code == 403
        assert r.json()["detail"]["code"] == "CSRF_INVALID"


def test_17_csrf_token_sai(tmp_path, monkeypatch):
    """17. CSRF token sai: gửi CSRF token sai giá trị HMAC -> 403 CSRF_INVALID."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="CSRFWrong")
        char = tao_va_luu_nhan_vat_cho_user(c, info, "Voucher Test")
        char_id = char["character_id"]

        fake_csrf = "0" * 64
        r = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": fake_csrf},
        )
        assert r.status_code == 403
        assert r.json()["detail"]["code"] == "CSRF_INVALID"


def test_18_origin_khong_hop_le(tmp_path, monkeypatch):
    """18. Origin không hợp lệ: gửi Origin từ domain lạ hoặc thiếu Origin -> 403 ORIGIN_FORBIDDEN."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="OriginBad")
        char = tao_va_luu_nhan_vat_cho_user(c, info, "Voucher Test")
        char_id = char["character_id"]

        # 1. Origin lạ
        r1 = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": "https://attacker-phishing.com", "X-CSRF-Token": info["csrf_token"]},
        )
        assert r1.status_code == 403
        assert r1.json()["detail"]["code"] == "ORIGIN_FORBIDDEN"

        # 2. Thiếu Origin
        r2 = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"X-CSRF-Token": info["csrf_token"]},
        )
        assert r2.status_code == 403
        assert r2.json()["detail"]["code"] == "ORIGIN_FORBIDDEN"


def test_19_database_auth_khong_san_sang(tmp_path, monkeypatch):
    """19. Database Auth không sẵn sàng: database bị lỗi -> trả 503 AUTH_UNAVAILABLE (fail-closed)."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, auth_service, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="DBFail")

        # Mock database exception trong get_authenticated_session
        with patch.object(auth_service, "get_authenticated_session", side_effect=Exception("DB connection broken")):
            r = c.get("/api/ai/nhan-vat/danh-sach", headers={"Origin": _ORIGIN})
            assert r.status_code == 503
            assert r.json()["detail"]["code"] == "AUTH_UNAVAILABLE"


def test_20_session_demo_bi_tu_choi(tmp_path, monkeypatch):
    """20. Session demo bị từ chối: gửi header X-Demo-Player vào endpoint nhân vật -> 401."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        r = c.get(
            "/api/ai/nhan-vat/danh-sach",
            headers={"Origin": _ORIGIN, "X-Demo-Player": "guest_player"},
        )
        assert r.status_code == 401
        assert "Tài khoản demo" in r.json()["detail"]


def test_21_session_that_ket_hop_rpc_verifier(tmp_path, monkeypatch):
    """21. Session thật kết hợp RPC Verifier: user đăng nhập SIWE thật, xác minh giao dịch on-chain."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, app, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="VerifierUser")
        char = tao_va_luu_nhan_vat_cho_user(c, info, "Nhân vật Verifier")
        char_id = char["character_id"]
        tx_hash = "0x" + "a" * 64

        # Mock blockchain verifier trả về thành công
        from core.blockchain_verifier import KetQuaXacMinhOnchain, TrangThaiXacMinhBlockchain
        ket_qua_mock = KetQuaXacMinhOnchain(
            trang_thai=TrangThaiXacMinhBlockchain.REGISTERED,
            chi_tiet="Xác minh thành công",
            transaction_hash=tx_hash,
            block_number=100,
            confirmations=5,
            event_data={
                "character_id": char_id,
                "character_hash": "0x" + char["character_hash"],
                "owner": info["wallet_address"],
            },
        )

        with patch.object(app.state.nhan_vat_ai.blockchain_verifier, "xac_minh_giao_dich", return_value=ket_qua_mock):
            r = c.post(
                f"/api/ai/nhan-vat/{char_id}/xac-minh-onchain",
                headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
                json={"transaction_hash": tx_hash},
            )
            assert r.status_code == 200
            assert r.json()["onchain_status"] == "registered"
            assert r.json()["transaction_hash"] == tx_hash


def test_22_session_that_ket_hop_eip712_voucher(tmp_path, monkeypatch):
    """22. Session thật kết hợp EIP-712 Voucher: cấp voucher cho ví SIWE đã đăng nhập, kiểm tra tính toàn vẹn."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="VoucherSIWE")
        char = tao_va_luu_nhan_vat_cho_user(c, info, "Nhân vật EIP712")
        char_id = char["character_id"]

        r = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
        )
        assert r.status_code == 200
        voucher_data = r.json()

        # Xác thực owner trong voucher đúng là ví SIWE đã đăng nhập
        assert voucher_data["message"]["owner"].lower() == info["wallet_address"].lower()
        assert voucher_data["message"]["characterId"] == char_id
        assert voucher_data["message"]["characterHash"] == f"0x{char['character_hash']}"

        # Xác thực chữ ký EIP-712 phục hồi đúng Backend Signer
        domain = {
            "name": voucher_data["domain"]["name"],
            "version": voucher_data["domain"]["version"],
            "chainId": voucher_data["domain"]["chainId"],
            "verifyingContract": voucher_data["domain"]["verifyingContract"],
        }
        msg = {
            "characterId": voucher_data["message"]["characterId"],
            "characterHash": voucher_data["message"]["characterHash"],
            "owner": voucher_data["message"]["owner"],
            "nonce": voucher_data["message"]["nonce"],
            "deadline": voucher_data["message"]["deadline"],
        }
        digest = bam_eip712(domain, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, msg)
        sig_bytes = bytes.fromhex(voucher_data["signature"][2:])
        recovered = phuc_hoi(digest, sig_bytes)
        assert recovered.lower() == TEST_SIGNER_ADDR.lower()


def test_23_siwe_xac_thuc_nhung_thieu_snapshot_khong_tu_mo_khoa_503(tmp_path, monkeypatch):
    """23. SIWE đã xác thực nhưng thiếu snapshot tiến trình: không tự mở khóa, trả về HTTP 503 fail-closed."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        thuc_hien_dang_nhap_siwe(c, acc, username="NoSnapshotPlayer")

        # Gọi API tạo ảnh nhân vật mà không có snapshot tiến trình trên server
        r = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Thợ mỏ vàng cổ điển"},
        )
        assert r.status_code == 503
        assert "tiến trình" in r.text


def test_24_siwe_chua_hoan_thanh_du_6_man_bi_tu_choi_403(tmp_path, monkeypatch):
    """24. SIWE có snapshot nhưng chỉ hoàn thành một phần (chưa đủ 6 màn): từ chối với HTTP 403."""
    from api.ngu_canh_ai import gan_nguon_du_lieu_ai
    from core.ngu_canh_ai import BanChupNguoiChoiAI

    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, app, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="PartialPlayer")

        # Cung cấp snapshot tiến trình xác thực nhưng chỉ hoàn thành màn 1, 2, 3
        snap = BanChupNguoiChoiAI(
            player_id=info["user_id"],
            level=1,
            allowed_stage_ids=frozenset(range(1, 7)),
            completed_stage_ids=frozenset({1, 2, 3}),
            user_id=info["user_id"],
            wallet_address=info["wallet_address"],
        )
        async def source(request):
            return snap
        gan_nguon_du_lieu_ai(app, source)

        r = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Thợ mỏ mới chơi"},
        )
        assert r.status_code == 403
        assert "Cần hoàn thành đủ màn 1–6" in r.text
        assert "3/6" in r.text


def test_25_siwe_hoan_thanh_du_6_man_tu_nguon_tin_cay_thanh_cong_200(tmp_path, monkeypatch):
    """25. SIWE có snapshot hoàn thành đủ màn 1–6 từ nguồn tin cậy: tạo ảnh thành công HTTP 200."""
    from api.ngu_canh_ai import gan_nguon_du_lieu_ai
    from core.ngu_canh_ai import BanChupNguoiChoiAI

    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, app, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="MasterPlayer")

        snap = BanChupNguoiChoiAI(
            player_id=info["user_id"],
            level=1,
            allowed_stage_ids=frozenset(range(1, 7)),
            completed_stage_ids=frozenset(range(1, 7)),
            user_id=info["user_id"],
            wallet_address=info["wallet_address"],
        )
        async def source(request):
            return snap
        gan_nguon_du_lieu_ai(app, source)

        r = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Thợ mỏ cao cấp"},
        )
        assert r.status_code == 200
        data = r.json()
        assert data["context_source"] == "verified"
        assert data["image_id"].startswith("img_")


def test_26_client_khong_the_gia_mao_tien_trinh_qua_header_hoac_body(tmp_path, monkeypatch):
    """26. Client cố tình gửi header hoặc body giả mạo tiến trình: bị chặn hoàn toàn."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        acc = Account.create()
        thuc_hien_dang_nhap_siwe(c, acc, username="SpoofAttacker")

        # Thử 1: Giả mạo header tiến trình
        r_header = c.post(
            "/api/ai/nhan-vat/tao",
            headers={
                "Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}",
                "X-Completed-Stages": "1,2,3,4,5,6",
                "X-Stage-Progress": "6",
            },
            json={"description": "Thợ mỏ giả mạo"},
        )
        assert r_header.status_code == 503

        # Thử 2: Giả mạo body payload
        r_body = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={
                "description": "Thợ mỏ giả mạo",
                "completed_stage_ids": [1, 2, 3, 4, 5, 6],
            },
        )
        assert r_body.status_code == 422  # Extra fields forbidden


def test_27_ai_demo_preview_khong_vuot_quyen_so_huu_luu_nhan_vat_chinh_thuc(tmp_path, monkeypatch):
    """27. Ảnh tạo từ phiên Demo preview không thể lưu hoặc cấp voucher chính thức."""
    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, _, _, _):
        # 1. Tạo preview trong phiên demo
        r_demo = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"X-Demo-Player": "demo_guest", "Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Nhân vật demo"},
        )
        assert r_demo.status_code == 200
        demo_img_id = r_demo.json()["image_id"]
        assert r_demo.json()["context_source"] == "demo"

        # 2. Khách demo gọi API lưu (kèm Origin hợp lệ) -> bị từ chối 401
        r_demo_luu = c.post(
            "/api/ai/nhan-vat/luu",
            headers={"Origin": _ORIGIN, "X-Demo-Player": "demo_guest"},
            json={"image_id": demo_img_id},
        )
        assert r_demo_luu.status_code == 401

        # 3. Người chơi đăng nhập SIWE thật nhưng cố tình lưu ảnh tạo từ demo -> 403
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="RealUser")
        r_siwe_luu_demo = c.post(
            "/api/ai/nhan-vat/luu",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
            json={"image_id": demo_img_id},
        )
        assert r_siwe_luu_demo.status_code == 403
        assert "demo" in r_siwe_luu_demo.text.lower()


def test_28_luu_nhan_vat_va_ky_voucher_khong_bi_anh_huong_khi_tien_trinh_hop_le(tmp_path, monkeypatch):
    """28. Quy trình trọn vẹn: SIWE + tiến trình hợp lệ -> tạo ảnh -> lưu nhân vật -> ký EIP-712 voucher."""
    from api.ngu_canh_ai import gan_nguon_du_lieu_ai
    from core.ngu_canh_ai import BanChupNguoiChoiAI

    with app_auth_moi_truong(tmp_path, monkeypatch) as (c, app, _, _):
        acc = Account.create()
        info = thuc_hien_dang_nhap_siwe(c, acc, username="FullFlowHero")

        snap = BanChupNguoiChoiAI(
            player_id=info["user_id"],
            level=1,
            allowed_stage_ids=frozenset(range(1, 7)),
            completed_stage_ids=frozenset(range(1, 7)),
            user_id=info["user_id"],
            wallet_address=info["wallet_address"],
        )
        async def source(request):
            return snap
        gan_nguon_du_lieu_ai(app, source)

        # 1. Tạo ảnh (200)
        r_tao = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Thợ mỏ huyền thoại"},
        )
        assert r_tao.status_code == 200
        img_id = r_tao.json()["image_id"]

        # 2. Lưu nhân vật (201)
        r_luu = c.post(
            "/api/ai/nhan-vat/luu",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
            json={"image_id": img_id, "name": "Huyền Thoại"},
        )
        assert r_luu.status_code == 201
        char_data = r_luu.json()
        char_id = char_data["character_id"]

        # 3. Ký EIP-712 Voucher (200)
        r_vouch = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
        )
        assert r_vouch.status_code == 200
        vouch_data = r_vouch.json()
        assert vouch_data["message"]["owner"].lower() == info["wallet_address"].lower()
        assert vouch_data["signature"].startswith("0x")
