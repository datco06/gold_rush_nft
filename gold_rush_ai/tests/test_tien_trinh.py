"""Bộ kiểm thử toàn diện hệ thống quản lý và xác minh tiến trình màn chơi (Giai đoạn 8).

Bao gồm:
1. Kiểm thử lưu trữ SQLite bền vững và phân lập tài khoản (`KhoTienTrinh`).
2. Kiểm thử dịch vụ thẩm định bằng chứng (`DichVuXacMinhTienTrinh`): trọng tài và blockchain.
3. Kiểm thử chống Replay Attack trên mã ván và transaction hash.
4. Kiểm thử các API `/api/ai/tien-trinh` (xác thực SIWE, CSRF, Origin, phân quyền ví).
5. Kiểm thử tích hợp `ai_player_source` mở khóa tạo nhân vật AI (403 khi chưa đủ 6 màn, 200 khi đủ 6 màn).
"""
from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock
import uuid

from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

from alembic import command
from alembic.config import Config as AlembicConfig

from api.auth_adapter import tich_hop_auth_vao_app
from api.nhan_vat_ai import khoi_dong_nhan_vat_ai, router as router_nhan_vat_ai
from api.tien_trinh import khoi_dong_tien_trinh, router as router_tien_trinh
from auth.config import AuthConfig
from auth.database import create_auth_engine, create_session_factory
from auth.router import create_auth_router
from auth.service import AuthService
from core.blockchain_verifier import BlockchainVerifier, CauHinhBlockchain
from core.eth_ky import dia_chi_tu_khoa, keccak256
from core.schemas_nhan_vat import NguoiChoiXacThuc
from core.tien_trinh_storage import (
    KhoTienTrinh,
    LoiQuyenTienTrinh,
    LoiReplayTienTrinh,
)
from core.tien_trinh_verifier import DichVuXacMinhTienTrinh, LoiXacMinhTienTrinh
from core import trong_tai

_BACKEND_DIR = Path(__file__).resolve().parents[1]
_ALEMBIC_INI = _BACKEND_DIR / "alembic.ini"
_ORIGIN = "http://localhost:5000"
_BOOTSTRAP_HEADERS = {"Origin": _ORIGIN, "X-Gold-Rush-Auth": "1"}

TEST_SIGNER_KEY = "11" * 32
TEST_SIGNER_ADDR = dia_chi_tu_khoa(bytes.fromhex(TEST_SIGNER_KEY))
TEST_CONTRACT = "0x2222222222222222222222222222222222222222"


# ===========================================================================
# FIXTURES & HELPERS
# ===========================================================================

def tao_app_test(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Khởi tạo môi trường FastAPI tích hợp đầy đủ SIWE Auth, AI Character và Tiến trình."""
    auth_db_path = tmp_path / "auth.db"
    progress_db_path = tmp_path / "progress.sqlite3"
    char_db_path = tmp_path / "characters.sqlite3"
    image_db_path = tmp_path / "images.sqlite3"
    nhat_ky_dir = tmp_path / "nhat_ky"
    so_phieu_path = tmp_path / "phieu" / "da_cap.jsonl"
    so_ve_path = tmp_path / "phieu" / "ve.jsonl"

    nhat_ky_dir.mkdir(parents=True, exist_ok=True)
    so_phieu_path.parent.mkdir(parents=True, exist_ok=True)

    import secrets
    csrf_hex = secrets.token_hex(32)
    csrf_secret = bytes.fromhex(csrf_hex)

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

    alembic_cfg = AlembicConfig(str(_ALEMBIC_INI))
    alembic_cfg.set_main_option("sqlalchemy.url", auth_config.database_url)
    alembic_cfg.set_main_option("script_location", str(_BACKEND_DIR / "migrations"))
    with monkeypatch.context() as m:
        m.setenv("AUTH_DATABASE_URL", auth_config.database_url)
        m.setenv("AUTH_CSRF_SECRET", csrf_hex)
        command.upgrade(alembic_cfg, "head")

    engine = create_auth_engine(auth_config)
    session_factory = create_session_factory(engine)
    auth_service = AuthService(auth_config, session_factory)

    import config
    monkeypatch.setattr(config, "ENABLED", config.ENABLED | {"nhan_vat_ai", "auth", "tien_trinh"})
    monkeypatch.setattr(config, "SO_PHIEU", so_phieu_path)
    monkeypatch.setattr(config, "SO_VE", so_ve_path)
    monkeypatch.setattr(config, "NHAT_KY_DIR", nhat_ky_dir)
    monkeypatch.setattr(config, "AI_BLOCKCHAIN_RPC_URL", "http://mock-rpc.local:8545")
    monkeypatch.setattr(config, "AI_CHARACTER_SIGNER_PRIVATE_KEY", TEST_SIGNER_KEY)
    monkeypatch.setattr(config, "AI_CHARACTER_AUTHORIZED_SIGNER", TEST_SIGNER_ADDR)
    monkeypatch.setattr(config, "AI_CHARACTER_REGISTRY_ADDRESS", TEST_CONTRACT)
    monkeypatch.setattr(config, "AI_BLOCKCHAIN_CHAIN_ID", 31337)
    monkeypatch.setattr(config, "AI_CHARACTER_VOUCHER_ENABLED", True)

    monkeypatch.setenv("AI_IMAGE_DB", str(image_db_path))
    monkeypatch.setenv("AI_CHARACTER_DB", str(char_db_path))
    monkeypatch.setenv("AI_PROGRESS_DB", str(progress_db_path))
    monkeypatch.setenv("AI_IMAGE_DEMO", "true")
    monkeypatch.setenv("NHAT_KY_DIR", str(nhat_ky_dir))
    monkeypatch.setenv("SO_PHIEU", str(so_phieu_path))
    monkeypatch.setenv("SO_VE", str(so_ve_path))
    monkeypatch.setenv("AI_CHARACTER_SIGNER_PRIVATE_KEY", TEST_SIGNER_KEY)
    monkeypatch.setenv("AI_CHARACTER_AUTHORIZED_SIGNER", TEST_SIGNER_ADDR)
    monkeypatch.setenv("AI_BLOCKCHAIN_RPC_URL", "http://mock-rpc.local:8545")
    monkeypatch.setenv("AI_CHARACTER_REGISTRY_ADDRESS", TEST_CONTRACT)
    monkeypatch.setenv("AI_BLOCKCHAIN_CHAIN_ID", "31337")
    monkeypatch.setenv("AI_CHARACTER_VOUCHER_ENABLED", "true")

    app = FastAPI(title="Test Progress API")
    auth_router = create_auth_router(auth_config, session_factory, clock=lambda: auth_service._now())
    app.include_router(auth_router)
    app.include_router(router_nhan_vat_ai)
    app.include_router(router_tien_trinh)

    tich_hop_auth_vao_app(app, auth_service, auth_config)
    khoi_dong_nhan_vat_ai(app)
    khoi_dong_tien_trinh(app)

    return app, auth_service, progress_db_path, so_phieu_path, nhat_ky_dir


def dang_nhap_siwe(client: TestClient, account: Account, username: str = "Player") -> dict:
    r_chal = client.post(
        "/api/auth/challenge",
        headers=_BOOTSTRAP_HEADERS,
        json={"wallet_address": account.address, "chain_id": 31337},
    )
    assert r_chal.status_code == 201
    chal = r_chal.json()

    sig = "0x" + account.sign_message(encode_defunct(text=chal["message"])).signature.hex()
    r_ver = client.post(
        "/api/auth/verify",
        headers=_BOOTSTRAP_HEADERS,
        json={"challenge_id": chal["challenge_id"], "message": chal["message"], "signature": sig},
    )
    assert r_ver.status_code == 200
    ver = r_ver.json()

    if ver.get("status") == "registration_required":
        r_reg = client.post(
            "/api/auth/register",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": ver["csrf_token"]},
            json={"username": username},
        )
        assert r_reg.status_code == 201
        ver = r_reg.json()

    return {
        "user_id": str(ver["user"]["id"]),
        "wallet_address": ver["user"]["wallet_address"],
        "csrf_token": ver["csrf_token"],
    }


# ===========================================================================
# 1. KIỂM THỬ KHO LƯU TRỮ (KhoTienTrinh)
# ===========================================================================

def test_kho_tien_trinh_crud_va_ben_vung(tmp_path):
    """Lưu trữ tiến trình bền vững qua khởi động lại và phân lập người chơi."""
    db_file = tmp_path / "progress.sqlite3"
    kho = KhoTienTrinh(db_file)

    # 1. Ghi nhận hoàn thành màn 1 cho User A
    bg1 = kho.ghi_nhan_hoan_thanh(
        owner_user_id="user_a",
        verified_wallet_address="0x1111111111111111111111111111111111111111",
        stage_id=1,
        verification_source="referee_validation",
        completion_evidence={"ma_van": "van-001"},
        replay_key="referee:van-001",
    )
    assert bg1.stage_id == 1
    assert bg1.owner_user_id == "user_a"

    # 2. Khởi tạo instance mới (mô phỏng restart server) -> dữ liệu còn nguyên
    kho2 = KhoTienTrinh(db_file)
    assert kho2.lay_cac_man_hoan_thanh("user_a") == frozenset({1})
    assert kho2.lay_cac_man_hoan_thanh("user_b") == frozenset()

    # 3. Phân lập tài khoản: User B ghi nhận màn 1 với bằng chứng khác
    kho2.ghi_nhan_hoan_thanh(
        owner_user_id="user_b",
        verified_wallet_address="0x2222222222222222222222222222222222222222",
        stage_id=1,
        verification_source="referee_validation",
        completion_evidence={"ma_van": "van-002"},
        replay_key="referee:van-002",
    )
    assert kho2.lay_cac_man_hoan_thanh("user_a") == frozenset({1})
    assert kho2.lay_cac_man_hoan_thanh("user_b") == frozenset({1})

    # 4. Kiểm tra ràng buộc stage_id hợp lệ (1-6)
    with pytest.raises(ValueError):
        kho2.ghi_nhan_hoan_thanh(
            owner_user_id="user_a",
            verified_wallet_address="0x1111111111111111111111111111111111111111",
            stage_id=7,  # Vượt quá màn 6
            verification_source="referee_validation",
            completion_evidence={},
            replay_key="referee:van-007",
        )


def test_kho_tien_trinh_chong_replay(tmp_path):
    """Bằng chứng hoàn thành không thể tái sử dụng cho tài khoản khác (chống replay)."""
    db_file = tmp_path / "progress.sqlite3"
    kho = KhoTienTrinh(db_file)

    kho.ghi_nhan_hoan_thanh(
        owner_user_id="user_a",
        verified_wallet_address="0x1111111111111111111111111111111111111111",
        stage_id=2,
        verification_source="referee_validation",
        completion_evidence={"ma_van": "van-replay"},
        replay_key="referee:van-replay",
    )

    # Cố tình dùng cùng replay_key cho User B -> Bị từ chối
    with pytest.raises(LoiReplayTienTrinh):
        kho.ghi_nhan_hoan_thanh(
            owner_user_id="user_b",
            verified_wallet_address="0x2222222222222222222222222222222222222222",
            stage_id=2,
            verification_source="referee_validation",
            completion_evidence={"ma_van": "van-replay"},
            replay_key="referee:van-replay",
        )

    # Idempotent: gọi lại cho chính user_a và stage 2 -> thành công
    same = kho.ghi_nhan_hoan_thanh(
        owner_user_id="user_a",
        verified_wallet_address="0x1111111111111111111111111111111111111111",
        stage_id=2,
        verification_source="referee_validation",
        completion_evidence={"ma_van": "van-replay"},
        replay_key="referee:van-replay",
    )
    assert same.stage_id == 2


# ===========================================================================
# 2. KIỂM THỬ DỊCH VỤ THẨM ĐỊNH (DichVuXacMinhTienTrinh)
# ===========================================================================

def test_xac_minh_qua_referee_voucher(tmp_path):
    """Xác minh màn chơi thông qua sổ phiếu trọng tài đã cấp."""
    kho = KhoTienTrinh(tmp_path / "prog.sqlite3")
    so_phieu_file = tmp_path / "da_cap.jsonl"
    so = trong_tai.SoPhieu(so_phieu_file)

    wallet_a = "0x1111111111111111111111111111111111111111"
    wallet_b = "0x2222222222222222222222222222222222222222"
    so.ghi(ma_van="game-man-1", vi=wallet_a, so_vang=24, man=1, ve=0)

    dich_vu = DichVuXacMinhTienTrinh(kho, so_phieu_path=so_phieu_file)

    player_a = NguoiChoiXacThuc(user_id="user_a", wallet_address=wallet_a)
    player_b = NguoiChoiXacThuc(user_id="user_b", wallet_address=wallet_b)

    # 1. Ví A xác minh mã ván của chính mình -> Thành công
    bg = dich_vu.xac_minh_referee_log(player_a, stage_id=1, ma_van="game-man-1")
    assert bg.stage_id == 1
    assert bg.verification_source == "referee_validation"

    # 2. Ví B cố tình dùng mã ván của Ví A -> Bị từ chối quyền
    with pytest.raises(LoiQuyenTienTrinh):
        dich_vu.xac_minh_referee_log(player_b, stage_id=1, ma_van="game-man-1")

    # 3. Mã ván sai màn chơi -> Bị từ chối
    with pytest.raises(LoiXacMinhTienTrinh):
        dich_vu.xac_minh_referee_log(player_a, stage_id=2, ma_van="game-man-1")


def test_xac_minh_qua_blockchain_event(tmp_path):
    """Xác minh màn chơi thông qua sự kiện DaNhanVang trên Smart Contract."""
    kho = KhoTienTrinh(tmp_path / "prog.sqlite3")
    wallet = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    player = NguoiChoiXacThuc(user_id="user_onchain", wallet_address=wallet)

    topic_da_nhan_vang = "0x" + keccak256(b"DaNhanVang(address,bytes32,uint256,uint256,uint256)").hex().lower()
    topic_wallet = "0x" + "0" * 24 + wallet.removeprefix("0x")
    tx_hash = "0x" + "1" * 64

    # Giả lập receipt từ RPC node: màn 3 (uint256 = 3), số vàng 10, hoàn cọc 8
    stage_id_hex = "0" * 63 + "3"
    so_vang_hex = "0" * 63 + "a"
    hoan_coc_hex = "0" * 63 + "8"
    fake_receipt = {
        "status": "0x1",
        "blockNumber": "0x10",
        "logs": [
            {
                "topics": [topic_da_nhan_vang, topic_wallet, "0x" + "9" * 64],
                "data": "0x" + stage_id_hex + so_vang_hex + hoan_coc_hex,
            }
        ],
    }

    mock_bc = MagicMock(spec=BlockchainVerifier)
    mock_bc.da_cau_hinh.return_value = True
    mock_bc._gui_rpc.return_value = fake_receipt

    dich_vu = DichVuXacMinhTienTrinh(kho, blockchain_verifier=mock_bc)

    # 1. Xác minh đúng màn 3 -> Thành công
    bg = dich_vu.xac_minh_blockchain_tx(player, stage_id=3, tx_hash=tx_hash)
    assert bg.stage_id == 3
    assert bg.verification_source == "blockchain_event"
    assert bg.replay_key == f"tx:{tx_hash.lower()}"

    # 2. Replay cùng tx_hash cho user khác hoặc màn khác -> Bị từ chối
    player_b = NguoiChoiXacThuc(user_id="user_b", wallet_address="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    with pytest.raises(LoiReplayTienTrinh):
        dich_vu.xac_minh_blockchain_tx(player_b, stage_id=3, tx_hash=tx_hash)

    with pytest.raises(LoiReplayTienTrinh):
        dich_vu.xac_minh_blockchain_tx(player, stage_id=4, tx_hash=tx_hash)


# ===========================================================================
# 3. KIỂM THỬ API TIẾN TRÌNH (/api/ai/tien-trinh)
# ===========================================================================

def test_api_tien_trinh_xac_thuc_va_bao_mat(tmp_path, monkeypatch):
    """Kiểm tra xác thực SIWE, CSRF, Origin và phân quyền trên các endpoint tiến trình."""
    app, _, _, _, _ = tao_app_test(tmp_path, monkeypatch)
    with TestClient(app, base_url=_ORIGIN) as c:
        # 1. Chưa đăng nhập: GET /api/ai/tien-trinh -> 401
        r_get_unauth = c.get("/api/ai/tien-trinh")
        assert r_get_unauth.status_code == 401

        # 2. Phiên demo có header X-Demo-Player -> 401
        r_demo = c.get("/api/ai/tien-trinh", headers={"X-Demo-Player": "demo_guest"})
        assert r_demo.status_code == 401

        # 3. Đăng nhập SIWE
        acc_a = Account.create()
        info_a = dang_nhap_siwe(c, acc_a, username="AliceProgress")

        # 4. GET tiến trình hợp lệ: ban đầu 0 màn hoàn thành
        r_prog = c.get("/api/ai/tien-trinh")
        assert r_prog.status_code == 200
        data = r_prog.json()
        assert data["owner_user_id"] == info_a["user_id"]
        assert data["completed_stage_ids"] == []
        assert data["is_character_unlocked"] is False
        assert len(data["stages"]) == 6

        # 5. POST xác minh thiếu Origin hoặc CSRF -> 403
        r_no_csrf = c.post(
            "/api/ai/tien-trinh/xac-minh",
            headers={"Origin": _ORIGIN},
            json={"stage_id": 1, "evidence_type": "referee_log", "evidence": "game-fake"},
        )
        assert r_no_csrf.status_code == 403

        # 6. POST với body khai báo tự ý "completed=True" -> 422 (extra fields forbidden)
        r_spoof = c.post(
            "/api/ai/tien-trinh/xac-minh",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info_a["csrf_token"]},
            json={"stage_id": 1, "evidence_type": "referee_log", "evidence": "game-fake", "completed": True},
        )
        assert r_spoof.status_code == 422


def test_api_tien_trinh_xac_minh_va_phan_lap(tmp_path, monkeypatch):
    """Ví A xác minh màn 1, ví B không thấy tiến trình của ví A."""
    app, _, _, so_phieu_path, _ = tao_app_test(tmp_path, monkeypatch)
    with TestClient(app, base_url=_ORIGIN) as c:
        acc_a = Account.create()
        info_a = dang_nhap_siwe(c, acc_a, username="UserA")

        # Chuẩn bị một phiếu hợp lệ cho ví A trong SoPhieu
        so = trong_tai.SoPhieu(so_phieu_path)
        so.ghi(ma_van="game-a-stage-1", vi=info_a["wallet_address"], so_vang=24, man=1, ve=0)

        # Ví A gửi yêu cầu xác minh màn 1
        r_ver = c.post(
            "/api/ai/tien-trinh/xac-minh",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info_a["csrf_token"]},
            json={"stage_id": 1, "evidence_type": "referee_log", "evidence": "game-a-stage-1"},
        )
        assert r_ver.status_code == 200
        assert r_ver.json()["stage_id"] == 1
        assert r_ver.json()["verification_source"] == "referee_validation"

        # Kiểm tra GET tiến trình ví A -> có màn 1
        r_a = c.get("/api/ai/tien-trinh")
        assert r_a.json()["completed_stage_ids"] == [1]

        # GET chi tiết màn 1 -> 200
        r_m1 = c.get("/api/ai/tien-trinh/1")
        assert r_m1.status_code == 200
        assert r_m1.json()["stage_id"] == 1

        # GET chi tiết màn 2 (chưa hoàn thành) -> 404
        r_m2 = c.get("/api/ai/tien-trinh/2")
        assert r_m2.status_code == 404

        # Ví B đăng nhập
        acc_b = Account.create()
        info_b = dang_nhap_siwe(c, acc_b, username="UserB")

        # Ví B kiểm tra tiến trình -> rỗng (không thấy màn 1 của ví A)
        r_b = c.get("/api/ai/tien-trinh")
        assert r_b.json()["completed_stage_ids"] == []

        # Ví B cố tình dùng lại mã ván của ví A -> Bị từ chối quyền (403)
        r_steal = c.post(
            "/api/ai/tien-trinh/xac-minh",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info_b["csrf_token"]},
            json={"stage_id": 1, "evidence_type": "referee_log", "evidence": "game-a-stage-1"},
        )
        assert r_steal.status_code == 403


# ===========================================================================
# 4. KIỂM THỬ TÍCH HỢP AI PLAYER SOURCE & MỞ KHÓA TẠO NHÂN VẬT
# ===========================================================================

def test_tich_hop_ai_player_source_mo_khoa_nhan_vat(tmp_path, monkeypatch):
    """Quy trình đầy đủ: Chưa đủ 6 màn trả 403, hoàn thành đủ 6 màn mở khóa 200 và cấp voucher."""
    app, _, prog_db, so_phieu_path, _ = tao_app_test(tmp_path, monkeypatch)
    with TestClient(app, base_url=_ORIGIN) as c:
        acc = Account.create()
        info = dang_nhap_siwe(c, acc, username="MasterMiner")
        user_id = info["user_id"]
        wallet = info["wallet_address"]

        # 1. Ban đầu 0 màn hoàn thành -> Gọi tạo nhân vật bị từ chối 403 (0/6 màn)
        r_tao_0 = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Thợ mỏ sơ cấp"},
        )
        assert r_tao_0.status_code == 403
        assert "0/6" in r_tao_0.text

        # 2. Hoàn thành 5 màn (1 đến 5)
        kho = KhoTienTrinh(prog_db)
        for s in range(1, 6):
            kho.ghi_nhan_hoan_thanh(
                owner_user_id=user_id,
                verified_wallet_address=wallet,
                stage_id=s,
                verification_source="referee_validation",
                completion_evidence={"mock": True},
                replay_key=f"mock_stage_{s}",
            )

        # Gọi lại -> Vẫn bị từ chối 403 (5/6 màn)
        r_tao_5 = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Thợ mỏ 5 sao"},
        )
        assert r_tao_5.status_code == 403
        assert "5/6" in r_tao_5.text

        # 3. Hoàn thành nốt màn 6
        kho.ghi_nhan_hoan_thanh(
            owner_user_id=user_id,
            verified_wallet_address=wallet,
            stage_id=6,
            verification_source="referee_validation",
            completion_evidence={"mock": True},
            replay_key="mock_stage_6",
        )

        # 4. Gọi lại tạo nhân vật -> Mở khóa thành công HTTP 200
        r_tao_6 = c.post(
            "/api/ai/nhan-vat/tao",
            headers={"Idempotency-Key": f"req_{uuid.uuid4().hex[:8]}"},
            json={"description": "Thợ mỏ huyền thoại 6 sao"},
        )
        assert r_tao_6.status_code == 200
        char_preview = r_tao_6.json()
        assert char_preview["context_source"] == "verified"
        image_id = char_preview["image_id"]

        # 5. Lưu nhân vật chính thức
        r_luu = c.post(
            "/api/ai/nhan-vat/luu",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
            json={"image_id": image_id, "name": "Vua Mỏ Vàng"},
        )
        assert r_luu.status_code == 201
        char_saved = r_luu.json()
        char_id = char_saved["character_id"]

        # 6. Ký EIP-712 Voucher thành công
        r_vouch = c.post(
            f"/api/ai/nhan-vat/{char_id}/ky-voucher",
            headers={"Origin": _ORIGIN, "X-CSRF-Token": info["csrf_token"]},
        )
        assert r_vouch.status_code == 200
        v_data = r_vouch.json()
        assert v_data["message"]["owner"].lower() == wallet.lower()
        assert v_data["signature"].startswith("0x")
