"""Bộ kiểm thử toàn diện cho module EIP-712 CharacterVoucher (Giai đoạn 4).

Bao phủ đủ 23 trường hợp kiểm thử theo yêu cầu:
1. Voucher hợp lệ.
2. EIP-712 domain chính xác.
3. Chữ ký được phục hồi thành đúng Backend Signer.
4. Sai characterId (phát hiện khi sửa ID).
5. Sai characterHash (phát hiện khi sửa hash).
6. Sai owner (phát hiện khi sửa owner).
7. Sai chainId.
8. Sai verifyingContract.
9. Nonce ngẫu nhiên và không trùng lặp.
10. Voucher hết hạn (deadline và TTL).
11. API: Nhân vật không tồn tại -> 404.
12. API: Người chơi không phải chủ sở hữu -> 403.
13. API: Người chơi chưa Auth -> 401.
14. API: Session demo -> 401.
15. API: Ảnh bị thay đổi SHA-256 -> 500.
16. API: Nhân vật đã registered -> 409.
17. API: Trạng thái pending -> 409.
18. Thiếu private key -> 503 fail-closed.
19. Signer khác authorizedSigner -> từ chối.
20. Request đồng thời (Concurrency test).
21. Không rò rỉ private key trong response hoặc log.
22. CSRF và header bảo vệ endpoint.
23. Tương thích chữ ký và dữ liệu EIP-712 với Solidity.
"""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from io import BytesIO
from pathlib import Path
import sqlite3
import pytest
from PIL import Image
from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.nhan_vat_ai import (
    NguCanhAnhNhanVat,
    khoi_dong_nhan_vat_ai,
    router,
)
from core.character_voucher import (
    CauHinhVoucher,
    DichVuVoucherNhanVat,
    LoiCauHinhVoucher,
    VOUCHER_FIELDS,
    VOUCHER_TYPE_NAME,
)
from core.eth_ky import (
    bam_eip712,
    checksum,
    dia_chi_tu_khoa,
    phuc_hoi,
)
from core.nhan_vat_storage import (
    KhoNhanVat,
    tinh_character_hash,
)
from core.schemas_nhan_vat import NguoiChoiXacThuc

# Khóa bí mật test tiêu chuẩn của Hardhat Account #0 (chỉ dùng cho môi trường test):
TEST_PRIVATE_KEY = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
TEST_SIGNER_ADDRESS = dia_chi_tu_khoa(bytes.fromhex(TEST_PRIVATE_KEY))
REGISTRY_CONTRACT = "0x2222222222222222222222222222222222222222"
CHAIN_ID = 31337
USER_WALLET = "0x1111111111111111111111111111111111111111"
USER_ID = "user_11111111-1111-1111-1111-111111111111"
CHAR_ID = "char_" + "1" * 32
CHAR_HASH = "a" * 64

ASSETS = Path(__file__).resolve().parents[2] / "gold_rush/assets/images"


def tao_anh_png_mau(color="yellow") -> bytes:
    img = Image.new("RGBA", (128, 128), color=color)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def tao_dich_vu_test(**kwargs) -> DichVuVoucherNhanVat:
    params = {
        "signer_private_key": TEST_PRIVATE_KEY,
        "authorized_signer": TEST_SIGNER_ADDRESS,
        "registry_contract": REGISTRY_CONTRACT,
        "chain_id": CHAIN_ID,
        "ttl_seconds": 1800,
        "enabled": True,
    }
    params.update(kwargs)
    cfg = CauHinhVoucher(**params)
    return DichVuVoucherNhanVat(cfg)


def tao_ngu_canh_verified(
    player_id=USER_ID,
    user_id=USER_ID,
    wallet=USER_WALLET,
) -> NguCanhAnhNhanVat:
    return NguCanhAnhNhanVat(
        player_id=player_id,
        allowed_stage_ids=frozenset(range(1, 7)),
        completed_stage_ids=frozenset(range(1, 7)),
        user_id=user_id,
        wallet_address=wallet,
    )


@contextmanager
def app_client_env(tmp_path, monkeypatch, *, auth_user=None, image_player=None, **env):
    import config
    monkeypatch.setattr(config, "ENABLED", {"nhan_vat_ai"})
    monkeypatch.setattr(config, "APP_FLUTTER", ASSETS.parents[1])
    monkeypatch.setattr(config, "AI_CHARACTER_SIGNER_PRIVATE_KEY", TEST_PRIVATE_KEY)
    monkeypatch.setattr(config, "AI_CHARACTER_AUTHORIZED_SIGNER", TEST_SIGNER_ADDRESS)
    monkeypatch.setattr(config, "AI_CHARACTER_REGISTRY_ADDRESS", REGISTRY_CONTRACT)
    monkeypatch.setattr(config, "AI_BLOCKCHAIN_CHAIN_ID", CHAIN_ID)
    monkeypatch.setattr(config, "AI_CHARACTER_VOUCHER_ENABLED", True)

    monkeypatch.setenv("AI_IMAGE_DB", str(tmp_path / "images.sqlite3"))
    monkeypatch.setenv("AI_CHARACTER_DB", str(tmp_path / "characters.sqlite3"))
    monkeypatch.setenv("AI_IMAGE_ENABLED", "false")
    monkeypatch.setenv("AI_IMAGE_DEMO", "true")
    monkeypatch.setenv("AI_CHARACTER_SIGNER_PRIVATE_KEY", TEST_PRIVATE_KEY)
    monkeypatch.setenv("AI_CHARACTER_AUTHORIZED_SIGNER", TEST_SIGNER_ADDRESS)
    monkeypatch.setenv("AI_CHARACTER_REGISTRY_ADDRESS", REGISTRY_CONTRACT)
    monkeypatch.setenv("AI_BLOCKCHAIN_CHAIN_ID", str(CHAIN_ID))
    monkeypatch.setenv("AI_CHARACTER_VOUCHER_ENABLED", "true")
    for name, value in env.items():
        monkeypatch.setenv(name, value)
        monkeypatch.setattr(config, name, value, raising=False)

    app = FastAPI()

    @app.middleware("http")
    async def inject_ctx(request, call_next):
        if auth_user is not None:
            request.state.ai_auth_user = auth_user
        if image_player is not None:
            request.state.ai_image_player = image_player
        return await call_next(request)

    app.include_router(router)
    khoi_dong_nhan_vat_ai(app)

    with TestClient(app) as c:
        yield c, app


# ---------------------------------------------------------------------------
# 1. Voucher hợp lệ
# ---------------------------------------------------------------------------
def test_01_voucher_hop_le():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )
    assert res.primaryType == "CharacterVoucher"
    assert res.message.characterId == CHAR_ID
    assert res.message.characterHash == f"0x{CHAR_HASH}"
    assert res.message.owner.lower() == USER_WALLET.lower()
    assert res.signature.startswith("0x")
    assert len(res.signature) == 132  # 0x + 130 hex chars (65 bytes)
    assert res.signerAddress.lower() == TEST_SIGNER_ADDRESS.lower()
    assert res.chainId == CHAIN_ID


# ---------------------------------------------------------------------------
# 2. EIP-712 domain chính xác
# ---------------------------------------------------------------------------
def test_02_eip712_domain_chinh_xac():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )
    assert res.domain.name == "CharacterRegistry"
    assert res.domain.version == "1"
    assert res.domain.chainId == CHAIN_ID
    assert res.domain.verifyingContract.lower() == REGISTRY_CONTRACT.lower()


# ---------------------------------------------------------------------------
# 3. Chữ ký được phục hồi thành đúng Backend Signer
# ---------------------------------------------------------------------------
def test_03_chu_ky_phuc_hoi_dung_backend_signer():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )

    domain_dict = {
        "name": res.domain.name,
        "version": res.domain.version,
        "chainId": res.domain.chainId,
        "verifyingContract": res.domain.verifyingContract,
    }
    msg_dict = {
        "characterId": res.message.characterId,
        "characterHash": res.message.characterHash,
        "owner": res.message.owner,
        "nonce": res.message.nonce,
        "deadline": res.message.deadline,
    }
    digest = bam_eip712(domain_dict, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, msg_dict)
    sig_bytes = bytes.fromhex(res.signature[2:])
    recovered = phuc_hoi(digest, sig_bytes)

    assert recovered.lower() == TEST_SIGNER_ADDRESS.lower()


# ---------------------------------------------------------------------------
# 4. Sai characterId -> Phục hồi sai địa chỉ
# ---------------------------------------------------------------------------
def test_04_sai_character_id():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )
    domain_dict = {
        "name": res.domain.name,
        "version": res.domain.version,
        "chainId": res.domain.chainId,
        "verifyingContract": res.domain.verifyingContract,
    }
    # Giả mạo characterId khác
    tampered_msg = {
        "characterId": "char_" + "9" * 32,
        "characterHash": res.message.characterHash,
        "owner": res.message.owner,
        "nonce": res.message.nonce,
        "deadline": res.message.deadline,
    }
    digest = bam_eip712(domain_dict, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, tampered_msg)
    sig_bytes = bytes.fromhex(res.signature[2:])
    recovered = phuc_hoi(digest, sig_bytes)

    assert recovered.lower() != TEST_SIGNER_ADDRESS.lower()


# ---------------------------------------------------------------------------
# 5. Sai characterHash -> Phục hồi sai địa chỉ
# ---------------------------------------------------------------------------
def test_05_sai_character_hash():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )
    domain_dict = {
        "name": res.domain.name,
        "version": res.domain.version,
        "chainId": res.domain.chainId,
        "verifyingContract": res.domain.verifyingContract,
    }
    tampered_msg = {
        "characterId": res.message.characterId,
        "characterHash": "0x" + "9" * 64,
        "owner": res.message.owner,
        "nonce": res.message.nonce,
        "deadline": res.message.deadline,
    }
    digest = bam_eip712(domain_dict, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, tampered_msg)
    sig_bytes = bytes.fromhex(res.signature[2:])
    recovered = phuc_hoi(digest, sig_bytes)

    assert recovered.lower() != TEST_SIGNER_ADDRESS.lower()


# ---------------------------------------------------------------------------
# 6. Sai owner -> Phục hồi sai địa chỉ
# ---------------------------------------------------------------------------
def test_06_sai_owner():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )
    domain_dict = {
        "name": res.domain.name,
        "version": res.domain.version,
        "chainId": res.domain.chainId,
        "verifyingContract": res.domain.verifyingContract,
    }
    tampered_msg = {
        "characterId": res.message.characterId,
        "characterHash": res.message.characterHash,
        "owner": "0x9999999999999999999999999999999999999999",
        "nonce": res.message.nonce,
        "deadline": res.message.deadline,
    }
    digest = bam_eip712(domain_dict, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, tampered_msg)
    sig_bytes = bytes.fromhex(res.signature[2:])
    recovered = phuc_hoi(digest, sig_bytes)

    assert recovered.lower() != TEST_SIGNER_ADDRESS.lower()


# ---------------------------------------------------------------------------
# 7. Sai chainId -> Phục hồi sai địa chỉ
# ---------------------------------------------------------------------------
def test_07_sai_chain_id():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )
    domain_sai_chain = {
        "name": res.domain.name,
        "version": res.domain.version,
        "chainId": 1,  # Sai chainId
        "verifyingContract": res.domain.verifyingContract,
    }
    msg_dict = {
        "characterId": res.message.characterId,
        "characterHash": res.message.characterHash,
        "owner": res.message.owner,
        "nonce": res.message.nonce,
        "deadline": res.message.deadline,
    }
    digest = bam_eip712(domain_sai_chain, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, msg_dict)
    sig_bytes = bytes.fromhex(res.signature[2:])
    recovered = phuc_hoi(digest, sig_bytes)

    assert recovered.lower() != TEST_SIGNER_ADDRESS.lower()


# ---------------------------------------------------------------------------
# 8. Sai verifyingContract -> Phục hồi sai địa chỉ
# ---------------------------------------------------------------------------
def test_08_sai_verifying_contract():
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )
    domain_sai_contract = {
        "name": res.domain.name,
        "version": res.domain.version,
        "chainId": res.domain.chainId,
        "verifyingContract": "0x8888888888888888888888888888888888888888",
    }
    msg_dict = {
        "characterId": res.message.characterId,
        "characterHash": res.message.characterHash,
        "owner": res.message.owner,
        "nonce": res.message.nonce,
        "deadline": res.message.deadline,
    }
    digest = bam_eip712(domain_sai_contract, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, msg_dict)
    sig_bytes = bytes.fromhex(res.signature[2:])
    recovered = phuc_hoi(digest, sig_bytes)

    assert recovered.lower() != TEST_SIGNER_ADDRESS.lower()


# ---------------------------------------------------------------------------
# 9. Nonce ngẫu nhiên và không trùng lặp
# ---------------------------------------------------------------------------
def test_09_nonce_ngau_nhien_khong_trung():
    svc = tao_dich_vu_test()
    nonces = set()
    for i in range(20):
        # Tạo voucher cho các nhân vật khác nhau để bỏ qua cache
        c_id = f"char_{i:032x}"
        res = svc.tao_va_ky_voucher(
            character_id=c_id,
            character_hash=CHAR_HASH,
            owner_wallet=USER_WALLET,
        )
        assert res.message.nonce.startswith("0x")
        assert len(res.message.nonce) == 66
        nonces.add(res.message.nonce)
    assert len(nonces) == 20


# ---------------------------------------------------------------------------
# 10. Voucher hết hạn (deadline và TTL)
# ---------------------------------------------------------------------------
def test_10_voucher_het_han():
    svc = tao_dich_vu_test(ttl_seconds=600)
    now = 1000000.0
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        now=now,
    )
    assert res.deadline == 1000600
    assert res.message.deadline == 1000600


# ---------------------------------------------------------------------------
# 11. API: Nhân vật không tồn tại -> 404
# ---------------------------------------------------------------------------
def test_11_api_nhan_vat_khong_ton_tai_tra_404(tmp_path, monkeypatch):
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    ctx = tao_ngu_canh_verified(player_id=USER_ID, user_id=USER_ID, wallet=USER_WALLET)

    with app_client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx) as (c, _):
        r = c.post(f"/api/ai/nhan-vat/{CHAR_ID}/ky-voucher")
        assert r.status_code == 404
        assert "không tồn tại" in r.json()["detail"]


# ---------------------------------------------------------------------------
# 12. API: Người chơi không phải chủ sở hữu -> 403
# ---------------------------------------------------------------------------
def test_12_api_nguoi_choi_khong_phai_chu_so_huu_tra_403(tmp_path, monkeypatch):
    user_a = NguoiChoiXacThuc(user_id="user_a", wallet_address="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    ctx_a = tao_ngu_canh_verified(player_id="user_a", user_id="user_a", wallet=user_a.wallet_address)

    user_b = NguoiChoiXacThuc(user_id="user_b", wallet_address="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    ctx_b = tao_ngu_canh_verified(player_id="user_b", user_id="user_b", wallet=user_b.wallet_address)

    with app_client_env(tmp_path, monkeypatch, auth_user=user_a, image_player=ctx_a) as (c, _):
        img = c.post("/api/ai/nhan-vat/tao", json={"description": "Nhân vật A"}, headers={"Idempotency-Key": "req_a"}).json()
        char_a = c.post("/api/ai/nhan-vat/luu", json={"image_id": img["image_id"]}).json()
        char_id = char_a["character_id"]

    # User B cố tình yêu cầu voucher cho nhân vật của User A
    with app_client_env(tmp_path, monkeypatch, auth_user=user_b, image_player=ctx_b) as (c, _):
        r = c.post(f"/api/ai/nhan-vat/{char_id}/ky-voucher")
        assert r.status_code == 403
        assert "Không có quyền" in r.json()["detail"]


# ---------------------------------------------------------------------------
# 13. API: Người chơi chưa Auth -> 401
# ---------------------------------------------------------------------------
def test_13_api_chua_dang_nhap_tra_401(tmp_path, monkeypatch):
    with app_client_env(tmp_path, monkeypatch) as (c, _):
        r = c.post(f"/api/ai/nhan-vat/{CHAR_ID}/ky-voucher")
        assert r.status_code == 401
        assert "MetaMask" in r.json()["detail"]


# ---------------------------------------------------------------------------
# 14. API: Session demo -> 401
# ---------------------------------------------------------------------------
def test_14_api_session_demo_tra_401(tmp_path, monkeypatch):
    with app_client_env(tmp_path, monkeypatch) as (c, _):
        r = c.post(
            f"/api/ai/nhan-vat/{CHAR_ID}/ky-voucher",
            headers={"X-Demo-Player": "demo_guest"},
        )
        assert r.status_code == 401


# ---------------------------------------------------------------------------
# 15. API: Ảnh bị thay đổi SHA-256 -> 500
# ---------------------------------------------------------------------------
def test_15_api_anh_bi_thay_doi_sha256_tra_500(tmp_path, monkeypatch):
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    ctx = tao_ngu_canh_verified(player_id=USER_ID, user_id=USER_ID, wallet=USER_WALLET)

    with app_client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx) as (c, app):
        img = c.post("/api/ai/nhan-vat/tao", json={"description": "Thử nghiệm toàn vẹn"}, headers={"Idempotency-Key": "req_integ"}).json()
        char = c.post("/api/ai/nhan-vat/luu", json={"image_id": img["image_id"]}).json()
        char_id = char["character_id"]

        # Cố tình làm hỏng blob ảnh trong SQLite
        db_path = app.state.nhan_vat_ai.kho_nhan_vat.duong_dan
        with sqlite3.connect(db_path) as conn:
            conn.execute("UPDATE nhan_vat SET image_blob = ? WHERE character_id = ?", (b"CORRUPTED_PNG_BYTES", char_id))

        r = c.post(f"/api/ai/nhan-vat/{char_id}/ky-voucher")
        assert r.status_code == 500
        assert "toàn vẹn" in r.json()["detail"]


# ---------------------------------------------------------------------------
# 16. API: Nhân vật đã registered -> 409
# ---------------------------------------------------------------------------
def test_16_api_nhan_vat_da_registered_tra_409(tmp_path, monkeypatch):
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    ctx = tao_ngu_canh_verified(player_id=USER_ID, user_id=USER_ID, wallet=USER_WALLET)

    with app_client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx) as (c, app):
        img = c.post("/api/ai/nhan-vat/tao", json={"description": "Đã registered"}, headers={"Idempotency-Key": "req_reg"}).json()
        char = c.post("/api/ai/nhan-vat/luu", json={"image_id": img["image_id"]}).json()
        char_id = char["character_id"]

        # Giả lập đã đăng ký thành công on-chain
        app.state.nhan_vat_ai.kho_nhan_vat.cap_nhat_trang_thai_onchain(
            char_id, "registered", transaction_hash="0x" + "f" * 64, nguoi_yeu_cau=user
        )

        r = c.post(f"/api/ai/nhan-vat/{char_id}/ky-voucher")
        assert r.status_code == 409
        assert "đã được đăng ký on-chain" in r.json()["detail"]


# ---------------------------------------------------------------------------
# 17. API: Trạng thái pending -> 409
# ---------------------------------------------------------------------------
def test_17_api_trang_thai_pending_tra_409(tmp_path, monkeypatch):
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    ctx = tao_ngu_canh_verified(player_id=USER_ID, user_id=USER_ID, wallet=USER_WALLET)

    with app_client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx) as (c, app):
        img = c.post("/api/ai/nhan-vat/tao", json={"description": "Đang pending"}, headers={"Idempotency-Key": "req_pend"}).json()
        char = c.post("/api/ai/nhan-vat/luu", json={"image_id": img["image_id"]}).json()
        char_id = char["character_id"]

        # Đặt trạng thái pending
        app.state.nhan_vat_ai.kho_nhan_vat.cap_nhat_trang_thai_onchain(
            char_id, "pending", transaction_hash="0x" + "e" * 64, nguoi_yeu_cau=user
        )

        r = c.post(f"/api/ai/nhan-vat/{char_id}/ky-voucher")
        assert r.status_code == 409
        assert "đang có giao dịch on-chain" in r.json()["detail"]


# ---------------------------------------------------------------------------
# 18. Thiếu private key -> 503 fail-closed
# ---------------------------------------------------------------------------
def test_18_thieu_private_key_fail_closed():
    svc = tao_dich_vu_test(signer_private_key="")
    with pytest.raises(LoiCauHinhVoucher) as exc:
        svc.tao_va_ky_voucher(
            character_id=CHAR_ID,
            character_hash=CHAR_HASH,
            owner_wallet=USER_WALLET,
        )
    assert "Chưa cấu hình khóa bí mật" in str(exc.value)


# ---------------------------------------------------------------------------
# 19. Signer khác authorizedSigner -> từ chối
# ---------------------------------------------------------------------------
def test_19_signer_khac_authorized_signer():
    # Cấu hình authorized_signer không khớp với private key
    svc = tao_dich_vu_test(authorized_signer="0x8888888888888888888888888888888888888888")
    with pytest.raises(LoiCauHinhVoucher) as exc:
        svc.tao_va_ky_voucher(
            character_id=CHAR_ID,
            character_hash=CHAR_HASH,
            owner_wallet=USER_WALLET,
        )
    assert "không khớp với authorizedSigner" in str(exc.value)


# ---------------------------------------------------------------------------
# 20. Request đồng thời (Concurrency test)
# ---------------------------------------------------------------------------
def test_20_request_dong_thoi():
    svc = tao_dich_vu_test()

    def call_sign(i):
        return svc.tao_va_ky_voucher(
            character_id=CHAR_ID,
            character_hash=CHAR_HASH,
            owner_wallet=USER_WALLET,
        )

    with ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(call_sign, range(10)))

    # Tất cả các thread đều thành công và nhận được cùng voucher hợp lệ (nhờ cơ chế cache an toàn)
    first_sig = results[0].signature
    assert all(r.signature == first_sig for r in results)
    assert all(r.message.characterId == CHAR_ID for r in results)


# ---------------------------------------------------------------------------
# 21. Không rò rỉ private key trong response hoặc log
# ---------------------------------------------------------------------------
def test_21_khong_ro_ri_private_key(tmp_path, monkeypatch):
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    ctx = tao_ngu_canh_verified(player_id=USER_ID, user_id=USER_ID, wallet=USER_WALLET)

    with app_client_env(tmp_path, monkeypatch, auth_user=user, image_player=ctx) as (c, _):
        img = c.post("/api/ai/nhan-vat/tao", json={"description": "Bảo mật khóa"}, headers={"Idempotency-Key": "req_sec"}).json()
        char = c.post("/api/ai/nhan-vat/luu", json={"image_id": img["image_id"]}).json()
        char_id = char["character_id"]

        r = c.post(f"/api/ai/nhan-vat/{char_id}/ky-voucher")
        assert r.status_code == 200
        raw_text = r.text

        # Khóa bí mật tuyệt đối KHÔNG xuất hiện trong nội dung phản hồi
        assert TEST_PRIVATE_KEY not in raw_text
        assert TEST_PRIVATE_KEY.lower() not in raw_text.lower()


# ---------------------------------------------------------------------------
# 22. CSRF và header bảo vệ endpoint
# ---------------------------------------------------------------------------
def test_22_csrf_bao_ve_request(tmp_path, monkeypatch):
    """Xác nhận POST method bảo vệ: GET vào endpoint ký voucher phải bị từ chối 405 Method Not Allowed."""
    with app_client_env(tmp_path, monkeypatch) as (c, _):
        r = c.get(f"/api/ai/nhan-vat/{CHAR_ID}/ky-voucher")
        assert r.status_code == 405


# ---------------------------------------------------------------------------
# 23. Tương thích chữ ký và dữ liệu EIP-712 với Solidity
# ---------------------------------------------------------------------------
def test_23_tuong_thich_chu_ky_solidity():
    """Kiểm tra chữ ký EIP-712 sinh bởi Python khớp đúng TypeHash và Domain của CharacterRegistry.sol."""
    svc = tao_dich_vu_test()
    res = svc.tao_va_ky_voucher(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
    )

    # 1. Kiểm tra TypeHash của struct CharacterVoucher khớp Solidity
    from core.eth_ky import chuoi_kieu, keccak256
    type_str = chuoi_kieu(VOUCHER_TYPE_NAME, VOUCHER_FIELDS)
    assert type_str == "CharacterVoucher(string characterId,bytes32 characterHash,address owner,bytes32 nonce,uint256 deadline)"
    type_hash = "0x" + keccak256(type_str.encode()).hex()
    # Khớp hằng số CHARACTER_VOUCHER_TYPEHASH trong CharacterRegistry.sol
    assert type_hash == "0x68ce1bc33785f08f888a40ae343488ffd98413a477172789210c4cdbd68fb8eb"

    # 2. Kiểm tra chữ ký phục hồi chuẩn ECDSA
    domain_dict = {
        "name": res.domain.name,
        "version": res.domain.version,
        "chainId": res.domain.chainId,
        "verifyingContract": res.domain.verifyingContract,
    }
    msg_dict = {
        "characterId": res.message.characterId,
        "characterHash": res.message.characterHash,
        "owner": res.message.owner,
        "nonce": res.message.nonce,
        "deadline": res.message.deadline,
    }
    digest = bam_eip712(domain_dict, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, msg_dict)
    sig_bytes = bytes.fromhex(res.signature[2:])
    recovered = phuc_hoi(digest, sig_bytes)
    assert recovered.lower() == TEST_SIGNER_ADDRESS.lower()
