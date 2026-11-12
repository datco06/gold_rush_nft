"""Bộ kiểm thử toàn diện cho module AI-001: Ethereum JSON-RPC Blockchain Verifier.

Bao gồm đủ 18 trường hợp kiểm thử theo yêu cầu:
1. Transaction hợp lệ và đủ confirmations -> REGISTERED.
2. Transaction không tồn tại -> PENDING.
3. Transaction đang pending trong mempool (blockNumber null) -> PENDING.
4. Transaction revert (status == 0) -> FAILED.
5. Sai chain ID -> FAILED.
6. Sai contract address -> FAILED.
7. Sai character_hash -> FAILED.
8. Sai owner wallet -> FAILED.
9. Sai characterId -> FAILED.
10. Sai event signature -> FAILED.
11. RPC timeout -> RPC_ERROR (CSDL giữ pending).
12. RPC trả lỗi JSON-RPC error -> RPC_ERROR.
13. Receipt thiếu dữ liệu -> FAILED.
14. Giao dịch chưa đủ confirmations -> PENDING.
15. Transaction hash bị sử dụng lại (Replay across characters) -> 409 Conflict.
16. Blockchain reorganization hoặc receipt không nhất quán -> FAILED.
17. Dữ liệu SQLite không bị thay đổi khi xác minh thất bại.
18. Hai request xác minh đồng thời (Concurrency test).
"""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from io import BytesIO
from pathlib import Path
import re
import sqlite3
import httpx
from PIL import Image
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.nhan_vat_ai import (
    NguCanhAnhNhanVat,
    khoi_dong_nhan_vat_ai,
    router,
)
from core.blockchain_verifier import (
    CauHinhBlockchain,
    BlockchainVerifier,
    TrangThaiXacMinhBlockchain,
    TOPIC_EVENT_CHARACTER_REGISTERED,
    ma_hoa_topic_indexed_string,
    ma_hoa_topic_bytes32,
    ma_hoa_topic_address,
)
from core.nhan_vat_storage import (
    GiaoDichDaDuocSuDung,
    KhoNhanVat,
    tinh_character_hash,
)
from core.schemas_nhan_vat import NguoiChoiXacThuc

REGISTRY_ADDR = "0x2222222222222222222222222222222222222222"
USER_WALLET = "0x1111111111111111111111111111111111111111"
USER_ID = "user_11111111-1111-1111-1111-111111111111"
CHAR_ID = "char_" + "1" * 32
CHAR_HASH = "a" * 64
TX_HASH = "0x" + "f" * 64
BLOCK_HASH = "0x" + "b" * 64
TX_BLOCK = 16  # 0x10


def tao_anh_png_mau(color="gold") -> bytes:
    img = Image.new("RGBA", (128, 128), color=color)
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def tao_mock_log(
    *,
    registry: str = REGISTRY_ADDR,
    character_id: str = CHAR_ID,
    character_hash: str = CHAR_HASH,
    owner_wallet: str = USER_WALLET,
    event_sig: str = TOPIC_EVENT_CHARACTER_REGISTERED,
    removed: bool = False,
) -> dict:
    return {
        "address": registry.lower(),
        "topics": [
            event_sig.lower(),
            ma_hoa_topic_indexed_string(character_id),
            ma_hoa_topic_bytes32(character_hash),
            ma_hoa_topic_address(owner_wallet),
        ],
        "data": "0x",
        "blockNumber": hex(TX_BLOCK),
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "logIndex": "0x0",
        "removed": removed,
    }


def tao_mock_rpc_client(
    *,
    chain_id: int = 31337,
    tx: dict | None = "DEFAULT",
    receipt: dict | None = "DEFAULT",
    latest_block: int = 20,
    rpc_error: dict | None = None,
    timeout: bool = False,
) -> tuple[httpx.Client, CauHinhBlockchain]:
    cfg = CauHinhBlockchain(
        rpc_url="http://mock-eth-rpc.local:8545",
        chain_id=31337,
        registry_address=REGISTRY_ADDR,
        min_confirmations=2,
        timeout_seconds=2.0,
    )

    default_tx = {
        "hash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "from": USER_WALLET.lower(),
        "to": REGISTRY_ADDR.lower(),
        "value": "0x0",
    }

    default_receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x1",
        "logs": [tao_mock_log()],
    }

    resolved_tx = default_tx if tx == "DEFAULT" else tx
    resolved_receipt = default_receipt if receipt == "DEFAULT" else receipt

    def handler(request: httpx.Request) -> httpx.Response:
        if timeout:
            raise httpx.TimeoutException("Mock RPC Timeout", request=request)

        body = request.read().decode("utf-8")
        import json
        req = json.loads(body)
        method = req.get("method")
        req_id = req.get("id", 1)

        if rpc_error is not None:
            return httpx.Response(200, json={"jsonrpc": "2.0", "id": req_id, "error": rpc_error})

        if method == "eth_chainId":
            return httpx.Response(200, json={"jsonrpc": "2.0", "id": req_id, "result": hex(chain_id)})
        elif method == "eth_getTransactionByHash":
            return httpx.Response(200, json={"jsonrpc": "2.0", "id": req_id, "result": resolved_tx})
        elif method == "eth_getTransactionReceipt":
            return httpx.Response(200, json={"jsonrpc": "2.0", "id": req_id, "result": resolved_receipt})
        elif method == "eth_blockNumber":
            return httpx.Response(200, json={"jsonrpc": "2.0", "id": req_id, "result": hex(latest_block)})
        else:
            return httpx.Response(200, json={"jsonrpc": "2.0", "id": req_id, "result": None})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    return client, cfg


# ---------------------------------------------------------------------------
# 1. Transaction hợp lệ và đủ confirmations -> REGISTERED
# ---------------------------------------------------------------------------
def test_01_transaction_hop_le_va_du_confirmations():
    client, cfg = tao_mock_rpc_client(latest_block=TX_BLOCK + 4)  # 5 confirmations >= 2
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.REGISTERED
    assert res.confirmations == 5
    assert res.block_number == TX_BLOCK
    assert "thành công" in res.chi_tiet


# ---------------------------------------------------------------------------
# 2. Transaction không tồn tại -> PENDING
# ---------------------------------------------------------------------------
def test_02_transaction_khong_ton_tai():
    client, cfg = tao_mock_rpc_client(tx=None)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.PENDING
    assert "chưa tồn tại" in res.chi_tiet


# ---------------------------------------------------------------------------
# 3. Transaction đang pending trong mempool (blockNumber null) -> PENDING
# ---------------------------------------------------------------------------
def test_03_transaction_dang_pending_trong_mempool():
    pending_tx = {
        "hash": TX_HASH.lower(),
        "blockHash": None,
        "blockNumber": None,
        "from": USER_WALLET.lower(),
        "to": REGISTRY_ADDR.lower(),
    }
    client, cfg = tao_mock_rpc_client(tx=pending_tx, receipt=None)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.PENDING
    assert "mempool" in res.chi_tiet


# ---------------------------------------------------------------------------
# 4. Transaction revert (status == 0) -> FAILED
# ---------------------------------------------------------------------------
def test_04_transaction_revert():
    revert_receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x0",  # Revert
        "logs": [],
    }
    client, cfg = tao_mock_rpc_client(receipt=revert_receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "REVERT" in res.chi_tiet


# ---------------------------------------------------------------------------
# 5. Sai chain ID -> FAILED
# ---------------------------------------------------------------------------
def test_05_sai_chain_id():
    client, cfg = tao_mock_rpc_client(chain_id=1)  # Node trả 1 (Ethereum Mainnet), cấu hình 31337
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "Sai mạng" in res.chi_tiet


# ---------------------------------------------------------------------------
# 6. Sai contract address -> FAILED
# ---------------------------------------------------------------------------
def test_06_sai_contract_address():
    wrong_contract_tx = {
        "hash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "from": USER_WALLET.lower(),
        "to": "0x9999999999999999999999999999999999999999",  # Sai địa chỉ contract
    }
    client, cfg = tao_mock_rpc_client(tx=wrong_contract_tx)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "không khớp với hợp đồng" in res.chi_tiet


# ---------------------------------------------------------------------------
# 7. Sai character_hash -> FAILED
# ---------------------------------------------------------------------------
def test_07_sai_character_hash():
    wrong_log = tao_mock_log(character_hash="b" * 64)  # Sai character_hash
    receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x1",
        "logs": [wrong_log],
    }
    client, cfg = tao_mock_rpc_client(receipt=receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "characterHash trong sự kiện" in res.chi_tiet


# ---------------------------------------------------------------------------
# 8. Sai owner wallet -> FAILED
# ---------------------------------------------------------------------------
def test_08_sai_owner_wallet():
    wrong_log = tao_mock_log(owner_wallet="0x8888888888888888888888888888888888888888")
    receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x1",
        "logs": [wrong_log],
    }
    client, cfg = tao_mock_rpc_client(receipt=receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "Chủ sở hữu" in res.chi_tiet


# ---------------------------------------------------------------------------
# 9. Sai characterId -> FAILED
# ---------------------------------------------------------------------------
def test_09_sai_character_id():
    wrong_log = tao_mock_log(character_id="char_" + "9" * 32)
    receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x1",
        "logs": [wrong_log],
    }
    client, cfg = tao_mock_rpc_client(receipt=receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "characterId trong sự kiện" in res.chi_tiet


# ---------------------------------------------------------------------------
# 10. Sai event signature -> FAILED
# ---------------------------------------------------------------------------
def test_10_sai_event_signature():
    wrong_log = tao_mock_log(event_sig="0x" + "0" * 64)
    receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x1",
        "logs": [wrong_log],
    }
    client, cfg = tao_mock_rpc_client(receipt=receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "Không tìm thấy sự kiện CharacterRegistered" in res.chi_tiet


# ---------------------------------------------------------------------------
# 11. RPC timeout -> RPC_ERROR (không biến thành failed vĩnh viễn)
# ---------------------------------------------------------------------------
def test_11_rpc_timeout():
    client, cfg = tao_mock_rpc_client(timeout=True)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.RPC_ERROR
    assert "Hết thời gian chờ" in res.chi_tiet


# ---------------------------------------------------------------------------
# 12. RPC trả lỗi JSON-RPC error -> RPC_ERROR
# ---------------------------------------------------------------------------
def test_12_rpc_tra_loi_json_rpc():
    client, cfg = tao_mock_rpc_client(rpc_error={"code": -32603, "message": "Internal node error"})
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.RPC_ERROR
    assert "code -32603" in res.chi_tiet


# ---------------------------------------------------------------------------
# 13. Receipt thiếu dữ liệu (thiếu status hoặc logs) -> FAILED
# ---------------------------------------------------------------------------
def test_13_receipt_thieu_du_lieu():
    # Trường hợp 13a: thiếu trường status
    bad_receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        # thiếu status
        "logs": [tao_mock_log()],
    }
    client, cfg = tao_mock_rpc_client(receipt=bad_receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "thiếu trường status" in res.chi_tiet


# ---------------------------------------------------------------------------
# 14. Giao dịch chưa đủ confirmations -> PENDING
# ---------------------------------------------------------------------------
def test_14_giao_dich_chua_du_confirmations():
    # tx block = 16, latest block = 16 -> 1 confirmation < min_confirmations (2)
    client, cfg = tao_mock_rpc_client(latest_block=TX_BLOCK)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.PENDING
    assert res.confirmations == 1
    assert "Chưa đủ số block xác nhận" in res.chi_tiet


# ---------------------------------------------------------------------------
# 15. Transaction hash bị sử dụng lại (Replay across characters) -> 409
# ---------------------------------------------------------------------------
def test_15_transaction_hash_bi_su_dung_lai(tmp_path):
    kho = KhoNhanVat(tmp_path / "chars.sqlite3")
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    png = tao_anh_png_mau("blue")

    c1 = kho.luu_nhan_vat(player=user, image_id="img_" + "1" * 32, image_bytes=png, generation_source="demo")
    c2 = kho.luu_nhan_vat(player=user, image_id="img_" + "2" * 32, image_bytes=png, generation_source="demo")

    # Gán tx cho c1 thành công
    kho.xac_nhan_giao_dich_onchain(c1.character_id, TX_HASH, nguoi_yeu_cau=user)

    # Cố tình gán cùng TX_HASH cho c2 -> Bị từ chối GiaoDichDaDuocSuDung
    with pytest.raises(GiaoDichDaDuocSuDung) as exc:
        kho.xac_nhan_giao_dich_onchain(c2.character_id, TX_HASH, nguoi_yeu_cau=user)
    assert "đã được sử dụng" in str(exc.value)


# ---------------------------------------------------------------------------
# 16. Blockchain reorganization hoặc receipt không nhất quán -> FAILED
# ---------------------------------------------------------------------------
def test_16_blockchain_reorganization_hoac_receipt_khong_nhat_quan():
    # 16a: blockHash trong receipt khác blockHash trong tx
    reorg_receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": "0x" + "c" * 64,  # khác BLOCK_HASH
        "blockNumber": hex(TX_BLOCK),
        "status": "0x1",
        "logs": [tao_mock_log()],
    }
    client, cfg = tao_mock_rpc_client(receipt=reorg_receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    res = verifier.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "reorg" in res.chi_tiet

    # 16b: log có cờ removed = True do reorg
    removed_log_receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x1",
        "logs": [tao_mock_log(removed=True)],
    }
    client2, cfg2 = tao_mock_rpc_client(receipt=removed_log_receipt)
    verifier2 = BlockchainVerifier(cfg2, http_client=client2)

    res2 = verifier2.xac_minh_giao_dich(
        character_id=CHAR_ID,
        character_hash=CHAR_HASH,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert res2.trang_thai == TrangThaiXacMinhBlockchain.FAILED
    assert "Không tìm thấy sự kiện CharacterRegistered" in res2.chi_tiet


# ---------------------------------------------------------------------------
# 17. Dữ liệu SQLite không bị thay đổi khi xác minh thất bại
# ---------------------------------------------------------------------------
def test_17_du_lieu_sqlite_khong_bi_thay_doi_khi_xac_minh_that_bai(tmp_path):
    kho = KhoNhanVat(tmp_path / "integrity.sqlite3")
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    png = tao_anh_png_mau("purple")
    initial_char = kho.luu_nhan_vat(
        player=user,
        image_id="img_" + "3" * 32,
        image_bytes=png,
        generation_source="demo",
        name="Hiệp sĩ tím",
    )
    char_id = initial_char.character_id
    initial_hash = initial_char.character_hash

    # Giả lập verifier báo revert (FAILED)
    revert_receipt = {
        "transactionHash": TX_HASH.lower(),
        "blockHash": BLOCK_HASH.lower(),
        "blockNumber": hex(TX_BLOCK),
        "status": "0x0",
        "logs": [],
    }
    client, cfg = tao_mock_rpc_client(receipt=revert_receipt)
    verifier = BlockchainVerifier(cfg, http_client=client)

    # Ghi nhận pending
    kho.xac_nhan_giao_dich_onchain(char_id, TX_HASH, nguoi_yeu_cau=user, trang_thai="pending")

    # Xác minh
    kq = verifier.xac_minh_giao_dich(
        character_id=char_id,
        character_hash=initial_hash,
        owner_wallet=USER_WALLET,
        transaction_hash=TX_HASH,
    )
    assert kq.trang_thai == TrangThaiXacMinhBlockchain.FAILED

    # Cập nhật failed
    kho.cap_nhat_trang_thai_onchain(char_id, "failed", nguoi_yeu_cau=user)

    # Kiểm tra dữ liệu nhân vật vẫn nguyên vẹn: ảnh, hash, owner, name
    after = kho.doc_nhan_vat(char_id, nguoi_yeu_cau=user)
    assert after.character_hash == initial_hash
    assert after.name == "Hiệp sĩ tím"
    assert after.owner_user_id == USER_ID
    assert after.verified_wallet_address == USER_WALLET.lower()
    assert after.onchain_status == "failed"

    # Kiểm tra blob ảnh và đối soát SHA-256
    _, blob = kho.doc_anh_nhan_vat(char_id, nguoi_yeu_cau=user)
    assert tinh_character_hash(blob) == initial_hash


# ---------------------------------------------------------------------------
# 18. Hai request xác minh đồng thời (Concurrency test)
# ---------------------------------------------------------------------------
def test_18_hai_request_xac_minh_dong_thoi(tmp_path):
    kho = KhoNhanVat(tmp_path / "concurrent_verify.sqlite3")
    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    png = tao_anh_png_mau("silver")
    char = kho.luu_nhan_vat(player=user, image_id="img_" + "4" * 32, image_bytes=png, generation_source="demo")
    char_id = char.character_id

    # 10 luồng cùng gọi xác nhận giao dịch với cùng transaction_hash
    def verify_action(i):
        return kho.xac_nhan_giao_dich_onchain(char_id, TX_HASH, nguoi_yeu_cau=user, trang_thai="pending")

    with ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(verify_action, range(10)))

    # Tất cả đều thành công, không deadlock và đều có onchain_status == pending
    assert all(r.character_id == char_id for r in results)
    assert all(r.transaction_hash == TX_HASH.lower() for r in results)

    # CSDL chỉ có đúng 1 bản ghi
    with kho._ket_noi_doc() as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhan_vat WHERE transaction_hash = ?", (TX_HASH.lower(),)).fetchone()[0] == 1


# ---------------------------------------------------------------------------
# Integration test: Endpoint /api/ai/nhan-vat/{char_id}/xac-minh-onchain qua HTTP
# ---------------------------------------------------------------------------
def test_api_xac_minh_onchain_voi_blockchain_verifier(tmp_path, monkeypatch):
    """Kiểm thử API Endpoint tích hợp verifier:
    1. Khi RPC verifier xác nhận thành công -> onchain_status chuyển sang 'registered'.
    2. Khi RPC verifier báo revert -> onchain_status chuyển sang 'failed'.
    3. Khi RPC timeout -> onchain_status giữ nguyên 'pending'.
    """
    ASSETS = Path(__file__).resolve().parents[2] / "gold_rush/assets/images"
    import config
    monkeypatch.setattr(config, "ENABLED", {"nhan_vat_ai"})
    monkeypatch.setattr(config, "APP_FLUTTER", ASSETS.parents[1])
    monkeypatch.setenv("AI_IMAGE_DB", str(tmp_path / "images.sqlite3"))
    monkeypatch.setenv("AI_CHARACTER_DB", str(tmp_path / "characters.sqlite3"))
    monkeypatch.setenv("AI_IMAGE_ENABLED", "false")
    monkeypatch.setenv("AI_IMAGE_DEMO", "true")
    monkeypatch.setenv("AI_BLOCKCHAIN_RPC_URL", "http://mock-eth-rpc.local:8545")
    monkeypatch.setenv("AI_CHARACTER_REGISTRY_ADDRESS", REGISTRY_ADDR)

    user = NguoiChoiXacThuc(user_id=USER_ID, wallet_address=USER_WALLET)
    ctx = NguCanhAnhNhanVat(
        player_id=USER_ID,
        allowed_stage_ids=frozenset(range(1, 7)),
        completed_stage_ids=frozenset(range(1, 7)),
        user_id=USER_ID,
        wallet_address=USER_WALLET,
    )

    app = FastAPI()

    @app.middleware("http")
    async def inject_ctx(request, call_next):
        request.state.ai_auth_user = user
        request.state.ai_image_player = ctx
        return await call_next(request)

    app.include_router(router)
    khoi_dong_nhan_vat_ai(app)

    # 1. Tạo và lưu nhân vật
    with TestClient(app) as c:
        img_resp = c.post("/api/ai/nhan-vat/tao", json={"description": "Chiến binh on-chain"}, headers={"Idempotency-Key": "req_oc_1"})
        assert img_resp.status_code == 200
        image_id = img_resp.json()["image_id"]

        char_resp = c.post("/api/ai/nhan-vat/luu", json={"image_id": image_id, "name": "Chiến binh"})
        assert char_resp.status_code == 201
        char_data = char_resp.json()
        char_id = char_data["character_id"]
        char_hash = char_data["character_hash"]

        # Gắn mock verifier thành công
        success_log = tao_mock_log(character_id=char_id, character_hash=char_hash, owner_wallet=USER_WALLET)
        success_receipt = {
            "transactionHash": TX_HASH.lower(),
            "blockHash": BLOCK_HASH.lower(),
            "blockNumber": hex(TX_BLOCK),
            "status": "0x1",
            "logs": [success_log],
        }
        client_ok, cfg = tao_mock_rpc_client(receipt=success_receipt, latest_block=TX_BLOCK + 5)
        app.state.nhan_vat_ai.blockchain_verifier = BlockchainVerifier(cfg, http_client=client_ok)

        # Gọi xac-minh-onchain
        r_ver = c.post(f"/api/ai/nhan-vat/{char_id}/xac-minh-onchain", json={"transaction_hash": TX_HASH})
        assert r_ver.status_code == 200
        assert r_ver.json()["onchain_status"] == "registered"
        assert r_ver.json()["transaction_hash"] == TX_HASH.lower()

        # Gọi lại lần 2 (idempotent)
        r_again = c.post(f"/api/ai/nhan-vat/{char_id}/xac-minh-onchain", json={"transaction_hash": TX_HASH})
        assert r_again.status_code == 200
        assert r_again.json()["onchain_status"] == "registered"

        # 2. Tạo nhân vật thứ 2 để test trường hợp revert -> 'failed'
        img_resp2 = c.post("/api/ai/nhan-vat/tao", json={"description": "Chiến binh 2"}, headers={"Idempotency-Key": "req_oc_2"})
        char_resp2 = c.post("/api/ai/nhan-vat/luu", json={"image_id": img_resp2.json()["image_id"]})
        char2_id = char_resp2.json()["character_id"]
        tx_revert = "0x" + "d" * 64

        revert_receipt = {
            "transactionHash": tx_revert.lower(),
            "blockHash": BLOCK_HASH.lower(),
            "blockNumber": hex(TX_BLOCK),
            "status": "0x0",  # Revert
            "logs": [],
        }
        revert_tx = {
            "hash": tx_revert.lower(),
            "blockHash": BLOCK_HASH.lower(),
            "blockNumber": hex(TX_BLOCK),
            "from": USER_WALLET.lower(),
            "to": REGISTRY_ADDR.lower(),
        }
        client_fail, cfg_fail = tao_mock_rpc_client(tx=revert_tx, receipt=revert_receipt)
        app.state.nhan_vat_ai.blockchain_verifier = BlockchainVerifier(cfg_fail, http_client=client_fail)

        r_fail = c.post(f"/api/ai/nhan-vat/{char2_id}/xac-minh-onchain", json={"transaction_hash": tx_revert})
        assert r_fail.status_code == 200
        assert r_fail.json()["onchain_status"] == "failed"

        # 3. Tạo nhân vật thứ 3 để test RPC timeout -> giữ nguyên 'pending'
        img_resp3 = c.post("/api/ai/nhan-vat/tao", json={"description": "Chiến binh 3"}, headers={"Idempotency-Key": "req_oc_3"})
        char_resp3 = c.post("/api/ai/nhan-vat/luu", json={"image_id": img_resp3.json()["image_id"]})
        char3_id = char_resp3.json()["character_id"]
        tx_timeout = "0x" + "c" * 64

        client_timeout, cfg_timeout = tao_mock_rpc_client(timeout=True)
        app.state.nhan_vat_ai.blockchain_verifier = BlockchainVerifier(cfg_timeout, http_client=client_timeout)

        r_timeout = c.post(f"/api/ai/nhan-vat/{char3_id}/xac-minh-onchain", json={"transaction_hash": tx_timeout})
        assert r_timeout.status_code == 200
        assert r_timeout.json()["onchain_status"] == "pending"
