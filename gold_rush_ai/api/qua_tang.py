"""Đổi mã quà tặng bằng phiên SIWE và voucher EIP-712 hiện có."""
from __future__ import annotations

import hashlib
import json
import time
import uuid
from datetime import datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

import config
from api.auth_guard import NguoiChoiXacThuc, kiem_tra_csrf_va_origin, lay_nguoi_choi_hien_tai
from core.csdl import lay_csdl
from core.qua_tang import (
    co_bytecode,
    doc_balance,
    doc_receipt,
    goi_rpc,
    ky_phieu_vat_pham,
    phieu_nonce,
    receipt_thanh_cong,
)
from core import trong_tai

router = APIRouter(prefix="/api/qua-tang", tags=["qua-tang"])

_GOLD_VOUCHER_LIMIT = 24


class YeuCauDoiMa(BaseModel):
    ma: str = Field(min_length=1, max_length=128)


class YeuCauXacNhan(BaseModel):
    claim_id: str = Field(min_length=20, max_length=64)
    transaction_hash: str = Field(min_length=66, max_length=66, pattern=r"^0x[0-9a-fA-F]{64}$")


def _hash_ma(ma: str) -> str:
    return hashlib.sha256(ma.strip().upper().encode("utf-8")).hexdigest()


def _now() -> float:
    return time.time()


def _expiry(value: Any) -> float | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        raise ValueError("expires_at không hợp lệ") from None


def _load_codes_from_json() -> None:
    """Nạp mã được cấu hình ngoài DB; không ghi plaintext của mã vào DB."""
    path = config.QUA_TANG_CODES_JSON
    if not path.exists():
        return
    try:
        rows = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise RuntimeError("Tệp mã quà tặng không hợp lệ") from exc
    if not isinstance(rows, list):
        raise RuntimeError("Tệp mã quà tặng phải là một mảng JSON")
    with lay_csdl() as conn:
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("code"), str):
                continue
            reward_type = str(row.get("rewardType", row.get("reward_type", ""))).lower()
            token_id = int(row.get("tokenId", row.get("token_id", 0)))
            amount = int(row.get("amount", 0))
            if reward_type not in ("gold", "item") or amount <= 0 or (reward_type == "item" and token_id <= 0):
                continue
            conn.execute(
                """INSERT OR IGNORE INTO gift_codes
                (code_hash, reward_type, token_id, amount, name, image_url, rarity,
                 expires_at, max_uses, per_wallet_limit, active)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)""",
                (
                    _hash_ma(row["code"]),
                    reward_type,
                    token_id,
                    amount,
                    str(row.get("name", "Quà tặng Gold Rush")),
                    str(row.get("imageUrl", row.get("image_url", ""))),
                    str(row.get("rarity", "")),
                    _expiry(row.get("expiresAt", row.get("expires_at"))),
                    max(1, int(row.get("maxUses", row.get("max_uses", 1)))),
                    max(1, int(row.get("perWalletLimit", row.get("per_wallet_limit", 1)))),
                ),
            )


def _kiem_cau_hinh(reward_type: str) -> None:
    hop_dong = config.HOP_DONG_CUA_HANG if reward_type == "gold" else config.HOP_DONG_VAT_PHAM
    if not config.BLOCKCHAIN_RPC_URL or not hop_dong or not config.TRONG_TAI_KHOA:
        raise HTTPException(503, "Backend chưa cấu hình đầy đủ RPC, khoá ký hoặc hợp đồng phần thưởng.")
    try:
        chain_id = int(goi_rpc("eth_chainId", []), 16)
        if chain_id != config.CHAIN_ID:
            raise HTTPException(503, f"Blockchain đang ở chain {chain_id}, cần {config.CHAIN_ID}.")
        if not co_bytecode(hop_dong):
            raise HTTPException(503, "Không tìm thấy bytecode hợp đồng phần thưởng trên mạng hiện tại.")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "Không thể kiểm tra hợp đồng phần thưởng trên Blockchain.") from None


def _kiem_item_da_dang_ky(token_id: int) -> None:
    try:
        data = "0xe6cf1346" + hex(token_id)[2:].rjust(64, "0")
        raw = goi_rpc("eth_call", [{"to": config.HOP_DONG_VAT_PHAM, "data": data}, "latest"])
        if int(raw, 16) == 0:
            raise HTTPException(422, "Vật phẩm trong mã quà chưa được đăng ký trên hợp đồng NFT.")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "Không thể kiểm tra token NFT trên Blockchain.") from None


def _claim_payload(claim: Any, *, status: str, tx_hash: str | None = None, gold_balance: int | None = None) -> dict[str, Any]:
    result = {
        "success": status == "confirmed",
        "claimId": claim["claim_id"],
        "rewardType": claim["reward_type"],
        "tokenId": int(claim["token_id"]),
        "amount": int(claim["amount"]),
        "name": claim["name"],
        "imageUrl": claim["image_url"],
        "rarity": claim["rarity"],
        "status": status,
    }
    if tx_hash:
        result["transactionHash"] = tx_hash
    if claim["reward_type"] == "gold" and gold_balance is not None:
        result["goldBalance"] = gold_balance
    return result


def _voucher_payload(claim: Any) -> dict[str, Any]:
    khoa = bytes.fromhex(config.TRONG_TAI_KHOA.removeprefix("0x"))
    if claim["reward_type"] == "gold":
        vouchers = []
        remain = int(claim["amount"])
        index = 0
        while remain > 0:
            so_vang = min(remain, _GOLD_VOUCHER_LIMIT)
            vouchers.append(trong_tai.ky_phieu(
                claim["wallet_address"], 1, 0, so_vang, f"gift-{claim['claim_id']}-{index}", khoa,
                config.CHAIN_ID, config.HOP_DONG_CUA_HANG,
            ))
            remain -= so_vang
            index += 1
        return {"vouchers": vouchers}
    voucher = ky_phieu_vat_pham(
        claim["wallet_address"],
        int(claim["token_id"]),
        int(claim["amount"]),
        phieu_nonce(claim["claim_id"]),
        khoa,
    )
    return {
        "voucher": voucher["phieu_vat_pham"],
        "signature": voucher["chu_ky"],
        "chainId": voucher["chain_id"],
        "contractAddress": voucher["hop_dong"],
    }


def _fail_claim(claim_id: str, message: str) -> None:
    with lay_csdl() as conn:
        claim = conn.execute("SELECT code_hash, status FROM gift_claims WHERE claim_id = ?", (claim_id,)).fetchone()
        if claim is None or claim["status"] != "pending":
            return
        conn.execute(
            "UPDATE gift_claims SET status = 'failed', error_message = ?, updated_at = datetime('now') WHERE claim_id = ?",
            (message, claim_id),
        )
        conn.execute("UPDATE gift_codes SET used_count = CASE WHEN used_count > 0 THEN used_count - 1 ELSE 0 END WHERE code_hash = ?", (claim["code_hash"],))


def _xac_nhan_claim(claim_id: str, wallet: str, tx_hash: str) -> dict[str, Any]:
    with lay_csdl() as conn:
        claim = conn.execute(
            "SELECT * FROM gift_claims WHERE claim_id = ? AND wallet_address = ? COLLATE NOCASE",
            (claim_id, wallet),
        ).fetchone()
    if claim is None:
        raise HTTPException(404, "Không tìm thấy lượt đổi mã.")
    if claim["status"] == "confirmed":
        balance = None
        if claim["reward_type"] == "gold":
            balance = doc_balance(config.HOP_DONG_CUA_HANG, wallet, 0)
        return _claim_payload(claim, status="confirmed", tx_hash=claim["transaction_hash"], gold_balance=balance)
    if claim["status"] == "failed":
        raise HTTPException(409, claim["error_message"] or "Lượt cấp thưởng đã thất bại.")

    try:
        receipt = doc_receipt(tx_hash)
        if receipt is None:
            with lay_csdl() as conn:
                conn.execute("UPDATE gift_claims SET transaction_hash = ?, updated_at = datetime('now') WHERE claim_id = ?", (tx_hash, claim_id))
            return _claim_payload(claim, status="pending", tx_hash=tx_hash)
        if not receipt_thanh_cong(receipt):
            _fail_claim(claim_id, "Giao dịch cấp thưởng bị hoàn tác trên Blockchain.")
            raise HTTPException(422, "Giao dịch cấp thưởng thất bại trên Blockchain.")

        hop_dong = config.HOP_DONG_CUA_HANG if claim["reward_type"] == "gold" else config.HOP_DONG_VAT_PHAM
        if str(receipt.get("to", "")).lower() != hop_dong.lower():
            _fail_claim(claim_id, "Giao dịch không gửi tới đúng hợp đồng phần thưởng.")
            raise HTTPException(422, "Giao dịch không đúng hợp đồng phần thưởng.")

        balance = doc_balance(hop_dong, wallet, int(claim["token_id"]))
        before = int(claim["balance_before"])
        if balance < before + int(claim["amount"]):
            _fail_claim(claim_id, "Receipt thành công nhưng số dư NFT/vàng chưa khớp.")
            raise HTTPException(422, "Chưa xác minh được phần thưởng trên Blockchain.")
        with lay_csdl() as conn:
            conn.execute(
                "UPDATE gift_claims SET status = 'confirmed', transaction_hash = ?, updated_at = datetime('now') WHERE claim_id = ? AND status = 'pending'",
                (tx_hash, claim_id),
            )
            saved = conn.execute("SELECT * FROM gift_claims WHERE claim_id = ?", (claim_id,)).fetchone()
        return _claim_payload(saved, status="confirmed", tx_hash=tx_hash, gold_balance=balance if claim["reward_type"] == "gold" else None)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "Chưa xác minh được receipt; giữ trạng thái pending để thử lại.") from None


@router.post("/claim")
async def doi_ma_qua_tang(
    body: YeuCauDoiMa,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    kiem_tra_csrf_va_origin(request, player)
    _load_codes_from_json()
    wallet = player.wallet_address
    code_hash = _hash_ma(body.ma)

    with lay_csdl() as conn:
        existing = conn.execute(
            "SELECT * FROM gift_claims WHERE code_hash = ? AND wallet_address = ? COLLATE NOCASE AND status IN ('pending', 'confirmed') ORDER BY created_at DESC LIMIT 1",
            (code_hash, wallet),
        ).fetchone()
        if existing is not None:
            balance = None
            if existing["status"] == "confirmed" and existing["reward_type"] == "gold":
                balance = doc_balance(config.HOP_DONG_CUA_HANG, wallet, 0)
            response = _claim_payload(existing, status=existing["status"], tx_hash=existing["transaction_hash"], gold_balance=balance)
            if existing["status"] == "pending":
                _kiem_cau_hinh(existing["reward_type"])
                response.update(_voucher_payload(existing))
            return response
        code = conn.execute("SELECT * FROM gift_codes WHERE code_hash = ?", (code_hash,)).fetchone()
        if code is None or not int(code["active"]):
            raise HTTPException(404, "Mã quà tặng không hợp lệ.")
        if code["expires_at"] is not None and float(code["expires_at"]) < _now():
            raise HTTPException(410, "Mã quà tặng đã hết hạn.")
        if int(code["used_count"]) >= int(code["max_uses"]):
            raise HTTPException(409, "Mã quà tặng đã hết lượt sử dụng.")
        used_by_wallet = conn.execute(
            "SELECT COUNT(*) FROM gift_claims WHERE code_hash = ? AND wallet_address = ? COLLATE NOCASE AND status IN ('pending', 'confirmed')",
            (code_hash, wallet),
        ).fetchone()[0]
        if int(used_by_wallet) >= int(code["per_wallet_limit"]):
            raise HTTPException(409, "Ví này đã đạt giới hạn nhận mã quà tặng.")

    _kiem_cau_hinh(code["reward_type"])
    if code["reward_type"] == "item":
        _kiem_item_da_dang_ky(int(code["token_id"]))
    try:
        before = doc_balance(
            config.HOP_DONG_CUA_HANG if code["reward_type"] == "gold" else config.HOP_DONG_VAT_PHAM,
            wallet,
            int(code["token_id"]),
        )
    except Exception:
        raise HTTPException(503, "Không đọc được số dư Blockchain trước khi cấp thưởng.") from None

    claim_id = uuid.uuid4().hex
    try:
        with lay_csdl() as conn:
            # BEGIN IMMEDIATE trong lay_csdl bảo vệ used_count trước yêu cầu đồng thời.
            code_locked = conn.execute("SELECT * FROM gift_codes WHERE code_hash = ?", (code_hash,)).fetchone()
            if code_locked is None or int(code_locked["used_count"]) >= int(code_locked["max_uses"]):
                raise HTTPException(409, "Mã quà tặng đã hết lượt sử dụng.")
            conn.execute("UPDATE gift_codes SET used_count = used_count + 1 WHERE code_hash = ?", (code_hash,))
            conn.execute(
                """INSERT INTO gift_claims
                (claim_id, code_hash, wallet_address, reward_type, token_id, amount, name, image_url, rarity,
                 balance_before, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'))""",
                (
                    claim_id,
                    code_hash,
                    wallet.lower(),
                    code_locked["reward_type"],
                    int(code_locked["token_id"]),
                    int(code_locked["amount"]),
                    code_locked["name"],
                    code_locked["image_url"],
                    code_locked["rarity"],
                    str(before),
                ),
            )
            claim = conn.execute("SELECT * FROM gift_claims WHERE claim_id = ?", (claim_id,)).fetchone()

        return {**_claim_payload(claim, status="pending"), **_voucher_payload(claim)}
    except HTTPException:
        _fail_claim(claim_id, "Không thể tạo voucher phần thưởng.")
        raise
    except Exception:
        _fail_claim(claim_id, "Không thể tạo voucher phần thưởng.")
        raise HTTPException(503, "Backend chưa tạo được voucher phần thưởng.") from None


@router.post("/confirm")
async def xac_nhan_qua_tang(
    body: YeuCauXacNhan,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    kiem_tra_csrf_va_origin(request, player)
    return _xac_nhan_claim(body.claim_id, player.wallet_address, body.transaction_hash)


@router.get("/status/{claim_id}")
async def trang_thai_qua_tang(
    claim_id: str,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    with lay_csdl() as conn:
        claim = conn.execute(
            "SELECT * FROM gift_claims WHERE claim_id = ? AND wallet_address = ? COLLATE NOCASE",
            (claim_id, player.wallet_address),
        ).fetchone()
    if claim is None:
        raise HTTPException(404, "Không tìm thấy lượt đổi mã.")
    if claim["status"] == "pending" and claim["transaction_hash"]:
        return _xac_nhan_claim(claim_id, player.wallet_address, claim["transaction_hash"])
    balance = None
    if claim["status"] == "confirmed" and claim["reward_type"] == "gold":
        balance = doc_balance(config.HOP_DONG_CUA_HANG, player.wallet_address, 0)
    return _claim_payload(claim, status=claim["status"], tx_hash=claim["transaction_hash"], gold_balance=balance)
