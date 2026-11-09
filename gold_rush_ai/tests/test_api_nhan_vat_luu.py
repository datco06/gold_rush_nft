from contextlib import contextmanager
from io import BytesIO
from pathlib import Path
import sqlite3
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image

from api.nhan_vat_ai import (
    NguCanhAnhNhanVat,
    khoi_dong_nhan_vat_ai,
    lay_nguoi_choi_xac_thuc,
    router,
)
from core.nhan_vat_storage import tinh_character_hash
from core.schemas_nhan_vat import NguoiChoiXacThuc

ASSETS = Path(__file__).resolve().parents[2] / "gold_rush/assets/images"


def nguoi_choi_verified(
    player_id="player_a",
    user_id="user_11111111-1111-1111-1111-111111111111",
    wallet="0x1111111111111111111111111111111111111111",
):
    return NguCanhAnhNhanVat(
        player_id=player_id,
        allowed_stage_ids=frozenset(range(1, 7)),
        completed_stage_ids=frozenset(range(1, 7)),
        user_id=user_id,
        wallet_address=wallet,
    )


@contextmanager
def client_env(tmp_path, monkeypatch, *, auth_user=None, image_player=None, **env):
    import config
    monkeypatch.setattr(config, "ENABLED", {"nhan_vat_ai"})
    monkeypatch.setattr(config, "APP_FLUTTER", ASSETS.parents[1])
    monkeypatch.setenv("AI_IMAGE_DB", str(tmp_path / "images.sqlite3"))
    monkeypatch.setenv("AI_CHARACTER_DB", str(tmp_path / "characters.sqlite3"))
    monkeypatch.setenv("AI_IMAGE_ENABLED", "false")
    monkeypatch.setenv("AI_IMAGE_DEMO", "true")
    monkeypatch.setenv("AI_IMAGE_TTL_SECONDS", "86400")
    monkeypatch.setenv("AI_IMAGE_MAX_IMAGES", "200")
    for name, value in env.items():
        monkeypatch.setenv(name, value)

    app = FastAPI()

    @app.middleware("http")
    async def inject_contexts(request, call_next):
        if auth_user is not None:
            request.state.ai_auth_user = auth_user
        if image_player is not None:
            request.state.ai_image_player = image_player
        return await call_next(request)

    app.include_router(router)
    khoi_dong_nhan_vat_ai(app)
    with TestClient(app) as c:
        yield c, app


def test_chua_dang_nhap_bi_tu_choi_401(tmp_path, monkeypatch):
    """Bảo đảm fail-closed: Chưa đăng nhập SIWE thì bị từ chối 401, không cấp quyền ảo."""
    with client_env(tmp_path, monkeypatch) as (c, _):
        # Thử lưu
        r1 = c.post("/api/ai/nhan-vat/luu", json={"image_id": "img_00000000000000000000000000000001"})
        assert r1.status_code == 401

        # Thử xem danh sách
        r2 = c.get("/api/ai/nhan-vat/danh-sach")
        assert r2.status_code == 401

        # Thử xem chi tiết
        r3 = c.get("/api/ai/nhan-vat/char_00000000000000000000000000000001")
        assert r3.status_code == 401


def test_phien_demo_khong_duoc_luu_nhan_vat_that(tmp_path, monkeypatch):
    """Phiên demo (X-Demo-Player) chỉ được preview, không được phép lưu nhân vật chính thức."""
    headers_demo = {"X-Demo-Player": "demo_guest", "Idempotency-Key": "req_demo_1"}
    with client_env(tmp_path, monkeypatch) as (c, _):
        # Demo tạo preview ảnh thành công
        r_tao = c.post("/api/ai/nhan-vat/tao", json={"description": "Thợ mỏ"}, headers=headers_demo)
        assert r_tao.status_code == 200
        image_id = r_tao.json()["image_id"]

        # Nhưng khi demo cố gọi /luu -> Bị chặn 401
        r_luu = c.post(
            "/api/ai/nhan-vat/luu",
            json={"image_id": image_id},
            headers={"X-Demo-Player": "demo_guest"},
        )
        assert r_luu.status_code == 401


def test_chong_gia_mao_owner_trong_request_body(tmp_path, monkeypatch):
    """Client không thể tự khai báo owner_user_id hoặc wallet_address trong request body."""
    user = NguoiChoiXacThuc(
        user_id="user_real_111111111111111111111111",
        wallet_address="0x1111111111111111111111111111111111111111",
    )
    with client_env(tmp_path, monkeypatch, auth_user=user) as (c, _):
        # Gửi thêm owner_user_id giả mạo -> Pydantic forbid extra fields -> trả 422
        r = c.post(
            "/api/ai/nhan-vat/luu",
            json={
                "image_id": "img_00000000000000000000000000000001",
                "owner_user_id": "fake_user_id",
            },
        )
        assert r.status_code == 422

        # Gửi thêm wallet_address giả mạo -> trả 422
        r2 = c.post(
            "/api/ai/nhan-vat/luu",
            json={
                "image_id": "img_00000000000000000000000000000001",
                "wallet_address": "0x9999999999999999999999999999999999999999",
            },
        )
        assert r2.status_code == 422


def test_luong_tao_luu_doc_va_kiem_tra_hash_toan_ven(tmp_path, monkeypatch):
    """Luồng đầy đủ: Người chơi xác thực tạo preview -> lưu chính thức -> đọc danh sách -> kiểm tra hash -> tải ảnh."""
    user_a = NguoiChoiXacThuc(
        user_id="user_aaaa_1111_2222_3333_444444444444",
        wallet_address="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
    ctx_a = nguoi_choi_verified(
        player_id=user_a.user_id,
        user_id=user_a.user_id,
        wallet=user_a.wallet_address,
    )

    with client_env(tmp_path, monkeypatch, auth_user=user_a, image_player=ctx_a) as (c, app):
        # 1. Tạo preview
        tao_resp = c.post(
            "/api/ai/nhan-vat/tao",
            json={"description": "Thợ mỏ mũ vàng"},
            headers={"Idempotency-Key": "req_user_a_1"},
        )
        assert tao_resp.status_code == 200
        img_meta = tao_resp.json()
        image_id = img_meta["image_id"]

        # 2. Lưu chính thức
        luu_resp = c.post(
            "/api/ai/nhan-vat/luu",
            json={"image_id": image_id, "name": "Bác Thợ Mỏ"},
        )
        assert luu_resp.status_code == 201
        char_data = luu_resp.json()
        char_id = char_data["character_id"]

        assert char_data["owner_user_id"] == user_a.user_id
        assert char_data["verified_wallet_address"] == user_a.wallet_address.lower()
        assert char_data["name"] == "Bác Thợ Mỏ"
        assert len(char_data["character_hash"]) == 64
        assert char_data["onchain_status"] == "not_registered"
        assert char_data["preview_ready"] is True
        assert char_data["playable_ready"] is False

        # Lưu lại lần 2 cùng image_id (idempotent) -> trả về cùng char_id
        luu_lai = c.post("/api/ai/nhan-vat/luu", json={"image_id": image_id})
        assert luu_lai.status_code == 201
        assert luu_lai.json()["character_id"] == char_id

        # 3. Xem danh sách nhân vật
        ds_resp = c.get("/api/ai/nhan-vat/danh-sach")
        assert ds_resp.status_code == 200
        ds = ds_resp.json()
        assert len(ds) == 1
        assert ds[0]["character_id"] == char_id

        # 4. Xem metadata chi tiết
        ct_resp = c.get(f"/api/ai/nhan-vat/{char_id}")
        assert ct_resp.status_code == 200
        assert ct_resp.json()["character_id"] == char_id

        # 5. Kiểm tra hash SHA-256
        hash_resp = c.get(f"/api/ai/nhan-vat/{char_id}/kiem-tra-hash")
        assert hash_resp.status_code == 200
        hash_kq = hash_resp.json()
        assert hash_kq["is_valid"] is True
        assert hash_kq["computed_hash"] == char_data["character_hash"]
        assert hash_kq["algorithm"] == "SHA-256"

        # 6. Tải ảnh chính thức
        anh_resp = c.get(f"/api/ai/nhan-vat/{char_id}/anh")
        assert anh_resp.status_code == 200
        assert anh_resp.headers["content-type"] == "image/png"
        assert anh_resp.headers["cache-control"] == "no-store"
        assert tinh_character_hash(anh_resp.content) == char_data["character_hash"]

        # 7. Dữ liệu chuẩn bị onchain
        onchain_resp = c.get(f"/api/ai/nhan-vat/{char_id}/chuan-bi-onchain")
        assert onchain_resp.status_code == 200
        oc = onchain_resp.json()
        assert oc["character_hash_bytes32"] == f"0x{char_data['character_hash']}"
        assert oc["owner_wallet"] == user_a.wallet_address.lower()
        assert oc["onchain_status"] == "not_registered"

        # 8. Xác nhận giao dịch onchain bằng tx hash hợp lệ
        tx_hash = "0x" + "f" * 64
        xac_nhan_resp = c.post(
            f"/api/ai/nhan-vat/{char_id}/xac-minh-onchain",
            json={"transaction_hash": tx_hash},
        )
        assert xac_nhan_resp.status_code == 200
        assert xac_nhan_resp.json()["onchain_status"] == "pending"
        assert xac_nhan_resp.json()["transaction_hash"] == tx_hash.lower()


def test_nguoi_dung_b_khong_the_luu_preview_cua_nguoi_dung_a(tmp_path, monkeypatch):
    """Người dùng B không thể lấy image_id của Người dùng A để lưu làm nhân vật của mình."""
    user_a = NguoiChoiXacThuc(user_id="user_a", wallet_address="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    ctx_a = nguoi_choi_verified(player_id="user_a", user_id="user_a", wallet=user_a.wallet_address)

    user_b = NguoiChoiXacThuc(user_id="user_b", wallet_address="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    ctx_b = nguoi_choi_verified(player_id="user_b", user_id="user_b", wallet=user_b.wallet_address)

    # User A tạo preview
    with client_env(tmp_path, monkeypatch, auth_user=user_a, image_player=ctx_a) as (c, _):
        tao_a = c.post("/api/ai/nhan-vat/tao", json={"description": "Thợ mỏ A"}, headers={"Idempotency-Key": "req_1"})
        assert tao_a.status_code == 200
        image_id_a = tao_a.json()["image_id"]

    # User B cố tình dùng image_id của User A để lưu vào kho của B
    with client_env(tmp_path, monkeypatch, auth_user=user_b, image_player=ctx_b) as (c, _):
        steal_resp = c.post("/api/ai/nhan-vat/luu", json={"image_id": image_id_a})
        # Bị từ chối vì không phải chủ sở hữu preview image
        assert steal_resp.status_code == 403


def test_vi_a_khong_doc_duoc_nhan_vat_rieng_cua_vi_b(tmp_path, monkeypatch):
    """Ví A không thể xem metadata, không thể tải ảnh, và không thấy trong danh sách của Ví B."""
    user_a = NguoiChoiXacThuc(user_id="user_a", wallet_address="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    ctx_a = nguoi_choi_verified(player_id="user_a", user_id="user_a", wallet=user_a.wallet_address)

    user_b = NguoiChoiXacThuc(user_id="user_b", wallet_address="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    ctx_b = nguoi_choi_verified(player_id="user_b", user_id="user_b", wallet=user_b.wallet_address)

    # User B tạo và lưu nhân vật
    with client_env(tmp_path, monkeypatch, auth_user=user_b, image_player=ctx_b) as (c, _):
        img = c.post("/api/ai/nhan-vat/tao", json={"description": "Kỵ sĩ B"}, headers={"Idempotency-Key": "req_b"}).json()
        char_b = c.post("/api/ai/nhan-vat/luu", json={"image_id": img["image_id"]}).json()
        char_b_id = char_b["character_id"]

    # User A đăng nhập và thử truy cập nhân vật của User B
    with client_env(tmp_path, monkeypatch, auth_user=user_a, image_player=ctx_a) as (c, _):
        # Không có trong danh sách của A
        ds = c.get("/api/ai/nhan-vat/danh-sach").json()
        assert len(ds) == 0

        # Thử xem chi tiết -> 403
        r_meta = c.get(f"/api/ai/nhan-vat/{char_b_id}")
        assert r_meta.status_code == 403

        # Thử tải ảnh -> 403
        r_anh = c.get(f"/api/ai/nhan-vat/{char_b_id}/anh")
        assert r_anh.status_code == 403

        # Thử kiểm tra hash -> 403
        r_hash = c.get(f"/api/ai/nhan-vat/{char_b_id}/kiem-tra-hash")
        assert r_hash.status_code == 403


def test_preview_het_han_khong_xoa_nhan_vat_chinh_thuc(tmp_path, monkeypatch):
    """Khi preview cache hết hạn và bị xóa bởi TTL trong KhoAnh, nhân vật đã lưu chính thức KHÔNG bị xóa."""
    user = NguoiChoiXacThuc(user_id="user_persist", wallet_address="0x3333333333333333333333333333333333333333")
    ctx = nguoi_choi_verified(player_id="user_persist", user_id="user_persist", wallet=user.wallet_address)

    with client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx, AI_IMAGE_TTL_SECONDS="10") as (c, app):
        clock = [1000.0]
        app.state.nhan_vat_ai.kho.lay_thoi_gian = lambda: clock[0]

        # Tạo và lưu
        tao = c.post("/api/ai/nhan-vat/tao", json={"description": "Thợ mỏ bền vững"}, headers={"Idempotency-Key": "req_p"}).json()
        image_id = tao["image_id"]
        char = c.post("/api/ai/nhan-vat/luu", json={"image_id": image_id}).json()
        char_id = char["character_id"]

        # Cho thời gian nhảy qua 20 giây -> TTL 10 giây hết hạn
        clock[0] = 1025.0
        app.state.nhan_vat_ai.kho.don_het_han()

        # Preview cache trong KhoAnh đã hết hạn -> trả 404
        # (Lưu ý: Header verified cần snapshot)
        preview_get = c.get(f"/api/ai/nhan-vat/anh/{image_id}")
        assert preview_get.status_code == 404

        # NHƯNG nhân vật chính thức trong KhoNhanVat VẪN CÒN NGUYÊN!
        doc_char = c.get(f"/api/ai/nhan-vat/{char_id}")
        assert doc_char.status_code == 200
        assert doc_char.json()["character_id"] == char_id

        doc_anh = c.get(f"/api/ai/nhan-vat/{char_id}/anh")
        assert doc_anh.status_code == 200
        assert doc_anh.headers["content-type"] == "image/png"
        assert len(doc_anh.content) > 0


def test_api_chong_replay_transaction_hash_ai_002(tmp_path, monkeypatch):
    """AI-002: Khi transaction_hash đã gắn cho nhân vật 1, cố tình gắn cho nhân vật 2 phải trả về HTTP 409 Conflict."""
    user = NguoiChoiXacThuc(user_id="user_replay_test", wallet_address="0x4444444444444444444444444444444444444444")
    ctx = nguoi_choi_verified(player_id="user_replay_test", user_id="user_replay_test", wallet=user.wallet_address)

    with client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx) as (c, _):
        # Tạo và lưu nhân vật 1
        img1 = c.post("/api/ai/nhan-vat/tao", json={"description": "Nhân vật 1"}, headers={"Idempotency-Key": "req_char1"}).json()
        char1 = c.post("/api/ai/nhan-vat/luu", json={"image_id": img1["image_id"]}).json()
        char1_id = char1["character_id"]

        # Tạo và lưu nhân vật 2
        img2 = c.post("/api/ai/nhan-vat/tao", json={"description": "Nhân vật 2"}, headers={"Idempotency-Key": "req_char2"}).json()
        char2 = c.post("/api/ai/nhan-vat/luu", json={"image_id": img2["image_id"]}).json()
        char2_id = char2["character_id"]

        tx_shared = "0x" + "e" * 64

        # Gắn tx cho nhân vật 1 -> Thành công (200)
        r1 = c.post(f"/api/ai/nhan-vat/{char1_id}/xac-minh-onchain", json={"transaction_hash": tx_shared})
        assert r1.status_code == 200
        assert r1.json()["transaction_hash"] == tx_shared.lower()
        assert r1.json()["onchain_status"] == "pending"

        # Replay tx_shared sang nhân vật 2 -> Bị từ chối HTTP 409 Conflict!
        r2 = c.post(f"/api/ai/nhan-vat/{char2_id}/xac-minh-onchain", json={"transaction_hash": tx_shared})
        assert r2.status_code == 409
        assert "đã được sử dụng" in r2.json()["detail"]


def test_api_luu_nhieu_lan_cung_image_id_an_toan_idempotent(tmp_path, monkeypatch):
    """AI-004 / AI-005: Lưu nhiều lần cùng image_id luôn trả về cùng character_id, bảo toàn tính idempotent."""
    user = NguoiChoiXacThuc(user_id="user_idempotent", wallet_address="0x5555555555555555555555555555555555555555")
    ctx = nguoi_choi_verified(player_id="user_idempotent", user_id="user_idempotent", wallet=user.wallet_address)

    with client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx) as (c, _):
        img = c.post("/api/ai/nhan-vat/tao", json={"description": "Nhân vật Idempotent"}, headers={"Idempotency-Key": "req_idem"}).json()
        image_id = img["image_id"]

        # Gọi lưu lần 1
        r1 = c.post("/api/ai/nhan-vat/luu", json={"image_id": image_id, "name": "Bản ghi đầu"})
        assert r1.status_code == 201
        char_id_1 = r1.json()["character_id"]

        # Gọi lưu lần 2 với cùng image_id
        r2 = c.post("/api/ai/nhan-vat/luu", json={"image_id": image_id, "name": "Bản ghi thử lại"})
        assert r2.status_code == 201
        char_id_2 = r2.json()["character_id"]

        assert char_id_1 == char_id_2
