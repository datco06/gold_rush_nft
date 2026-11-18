"""Cấp phiếu EIP-712 cho ThanhTuuSBT.

Backend chỉ xác minh điều kiện và ký phiếu. Ví người chơi vẫn là bên gửi
giao dịch claimSBT và trả gas; private key không bao giờ rời khỏi Backend.
"""
from __future__ import annotations

import re
import secrets
import time

from core.eth_ky import bam_eip712, checksum, dia_chi_tu_khoa, ky, phuc_hoi

EIP712_DOMAIN_NAME = "GoldRushSBT"
EIP712_DOMAIN_VERSION = "1"
VOUCHER_FIELDS = [
    ("player", "address"),
    ("achievementId", "uint256"),
    ("nonce", "bytes32"),
    ("deadline", "uint256"),
]


class LoiCauHinhSBT(Exception):
    pass


class DichVuVoucherSBT:
    def __init__(
        self,
        *,
        private_key: str,
        contract_address: str,
        chain_id: int,
        authorized_signer: str = "",
        ttl_seconds: int = 900,
    ):
        self.private_key = private_key.strip()
        self.contract_address = contract_address.strip()
        self.chain_id = chain_id
        self.authorized_signer = authorized_signer.strip()
        self.ttl_seconds = ttl_seconds

    def _key(self) -> bytes:
        clean = self.private_key.removeprefix("0x").removeprefix("0X")
        if not re.fullmatch(r"[0-9a-fA-F]{64}", clean):
            raise LoiCauHinhSBT("SBT_SIGNER_PRIVATE_KEY không đúng định dạng 32 byte hex")
        return bytes.fromhex(clean)

    def _signer(self) -> str:
        if not re.fullmatch(r"0x[0-9a-fA-F]{40}", self.contract_address):
            raise LoiCauHinhSBT("HOP_DONG_SBT không đúng địa chỉ Ethereum")
        signer = dia_chi_tu_khoa(self._key())
        if self.authorized_signer and signer.lower() != self.authorized_signer.lower():
            raise LoiCauHinhSBT("Khóa ký SBT không khớp SBT_AUTHORIZED_SIGNER")
        return signer

    def da_cau_hinh(self) -> bool:
        return bool(self.private_key and self.contract_address and self.chain_id > 0)

    def tao_va_ky(self, *, player: str, achievement_id: int, now: float | None = None) -> dict:
        if not re.fullmatch(r"0x[0-9a-fA-F]{40}", player):
            raise ValueError("Ví người chơi không hợp lệ")
        if not 1 <= achievement_id <= 5:
            raise ValueError("achievement_id phải từ 1 đến 5")
        if self.ttl_seconds <= 0:
            raise LoiCauHinhSBT("SBT_VOUCHER_TTL_SECONDS phải lớn hơn 0")

        signer = self._signer()
        player_checksum = checksum(player)
        contract_checksum = checksum(self.contract_address)
        nonce = f"0x{secrets.token_bytes(32).hex()}"
        deadline = int(time.time() if now is None else now) + self.ttl_seconds
        domain = {
            "name": EIP712_DOMAIN_NAME,
            "version": EIP712_DOMAIN_VERSION,
            "chainId": self.chain_id,
            "verifyingContract": contract_checksum,
        }
        message = {
            "player": player_checksum,
            "achievementId": achievement_id,
            "nonce": nonce,
            "deadline": deadline,
        }
        digest = bam_eip712(domain, "PhieuSBT", VOUCHER_FIELDS, message)
        signature = f"0x{ky(digest, self._key()).hex()}"
        if phuc_hoi(digest, bytes.fromhex(signature[2:])).lower() != signer.lower():
            raise LoiCauHinhSBT("Không đối soát được chữ ký phiếu SBT")

        return {
            "phieu": {
                "player": player_checksum,
                "achievementId": achievement_id,
                "nonce": nonce,
                "deadline": str(deadline),
            },
            "chuKy": signature,
            "chainId": self.chain_id,
            "hopDong": contract_checksum,
            "domain": domain,
            "types": {
                "PhieuSBT": [
                    {"name": name, "type": kind} for name, kind in VOUCHER_FIELDS
                ]
            },
            "primaryType": "PhieuSBT",
            "signerAddress": signer,
        }
