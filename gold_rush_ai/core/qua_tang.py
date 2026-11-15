"""Ký voucher quà tặng và đọc trạng thái giao dịch trên Hardhat.

Backend chỉ xác thực mã và ký voucher. MetaMask của người chơi vẫn là bên gửi
giao dịch claim, nên private key của Backend không bao giờ rời khỏi máy chủ.
"""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from typing import Any

from config import BLOCKCHAIN_RPC_URL, CHAIN_ID, HOP_DONG_CUA_HANG, HOP_DONG_VAT_PHAM, RPC_TIMEOUT_SECONDS
from .eth_ky import bam_eip712, checksum, dia_chi_tu_khoa, keccak256, ky

TEN_MIEN, PHIEN_BAN_MIEN = "GoldRush", "2"
PHIEU_VAT_PHAM = [
    ("player", "address"),
    ("tokenId", "uint256"),
    ("amount", "uint256"),
    ("nonce", "bytes32"),
    ("deadline", "uint256"),
]


def _tu_hex_word(value: int) -> str:
    return hex(value)[2:].rjust(64, "0")


def _dia_chi_word(value: str) -> str:
    raw = value.removeprefix("0x")
    if len(raw) != 40 or any(c not in "0123456789abcdefABCDEF" for c in raw):
        raise ValueError("Địa chỉ ví không hợp lệ")
    return raw.lower().rjust(64, "0")


def goi_rpc(method: str, params: list[Any]) -> Any:
    if not BLOCKCHAIN_RPC_URL:
        raise RuntimeError("Chưa cấu hình BLOCKCHAIN_RPC_URL")
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(
        BLOCKCHAIN_RPC_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=RPC_TIMEOUT_SECONDS) as response:
            result = json.loads(response.read().decode())
    except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise RuntimeError("Không kết nối được Blockchain RPC") from exc
    if "error" in result:
        raise RuntimeError(str(result["error"].get("message", "RPC error")))
    return result.get("result")


def doc_balance(hop_dong: str, wallet: str, token_id: int) -> int:
    data = "0x00fdd58e" + _dia_chi_word(wallet) + _tu_hex_word(token_id)
    return int(goi_rpc("eth_call", [{"to": hop_dong, "data": data}, "latest"]), 16)


def co_bytecode(hop_dong: str) -> bool:
    code = goi_rpc("eth_getCode", [hop_dong, "latest"])
    return isinstance(code, str) and code not in ("0x", "0x0") and int(code, 16) != 0


def doc_receipt(tx_hash: str) -> dict[str, Any] | None:
    return goi_rpc("eth_getTransactionReceipt", [tx_hash])


def receipt_thanh_cong(receipt: dict[str, Any]) -> bool:
    return str(receipt.get("status", "0x0")) in ("0x1", "1")


def ky_phieu_vat_pham(
    nguoi_choi: str,
    token_id: int,
    amount: int,
    nonce: str,
    khoa_trong_tai: bytes,
    chain_id: int = CHAIN_ID,
    hop_dong: str = HOP_DONG_VAT_PHAM,
    han_giay: int = 900,
    bay_gio: int | None = None,
) -> dict[str, Any]:
    if token_id <= 0 or amount <= 0:
        raise ValueError("Phiếu vật phẩm không hợp lệ")
    if not hop_dong:
        raise ValueError("Chưa cấu hình hợp đồng vật phẩm")
    raw_nonce = bytes.fromhex(nonce.removeprefix("0x"))
    if len(raw_nonce) != 32:
        raise ValueError("nonce phải đúng 32 byte")
    bay_gio = int(time.time()) if bay_gio is None else bay_gio
    phieu = {
        "player": checksum(nguoi_choi),
        "tokenId": token_id,
        "amount": amount,
        "nonce": "0x" + raw_nonce.hex(),
        "deadline": bay_gio + han_giay,
    }
    mien = {
        "name": "GoldRushEquipment",
        "version": "1",
        "chainId": chain_id,
        "verifyingContract": hop_dong,
    }
    digest = bam_eip712(mien, "PhieuVatPham", PHIEU_VAT_PHAM, phieu)
    return {
        "phieu_vat_pham": phieu,
        "chu_ky": "0x" + ky(digest, khoa_trong_tai).hex(),
        "chain_id": chain_id,
        "hop_dong": hop_dong,
        "trong_tai": dia_chi_tu_khoa(khoa_trong_tai),
    }


def phieu_nonce(claim_id: str, index: int = 0) -> str:
    return "0x" + keccak256(f"gift:{claim_id}:{index}".encode()).hex()
