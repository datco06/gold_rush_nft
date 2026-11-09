"""Dịch vụ cấp và ký EIP-712 CharacterVoucher cho Backend AI (Giai đoạn 4).

Chuẩn EIP-712 tương thích hoàn toàn với CharacterRegistry.sol:
- Domain: { name: "CharacterRegistry", version: "1", chainId, verifyingContract }
- Struct: CharacterVoucher(string characterId, bytes32 characterHash, address owner, bytes32 nonce, uint256 deadline)
- TypeHash: keccak256("CharacterVoucher(string characterId,bytes32 characterHash,address owner,bytes32 nonce,uint256 deadline)")
- Chữ ký số ECDSA (secp256k1) sinh bởi Backend Authorization Signer (khóa máy chủ an toàn).
"""
from __future__ import annotations

from dataclasses import dataclass, field
import logging
import re
import secrets
import threading
import time
from typing import Any

from core.eth_ky import (
    bam_eip712,
    checksum,
    dia_chi_tu_khoa,
    ky,
    phuc_hoi,
)
from core.schemas_nhan_vat import (
    CharacterVoucherMessage,
    EIP712DomainInfo,
    PhanHoiKyVoucher,
)

log = logging.getLogger(__name__)

EIP712_DOMAIN_NAME = "CharacterRegistry"
EIP712_DOMAIN_VERSION = "1"
VOUCHER_TYPE_NAME = "CharacterVoucher"

# Các trường và kiểu dữ liệu EIP-712 tương thích với CharacterRegistry.sol
VOUCHER_FIELDS = [
    ("characterId", "string"),
    ("characterHash", "bytes32"),
    ("owner", "address"),
    ("nonce", "bytes32"),
    ("deadline", "uint256"),
]

TYPES_MAP = {
    "EIP712Domain": [
        {"name": "name", "type": "string"},
        {"name": "version", "type": "string"},
        {"name": "chainId", "type": "uint256"},
        {"name": "verifyingContract", "type": "address"},
    ],
    "CharacterVoucher": [
        {"name": "characterId", "type": "string"},
        {"name": "characterHash", "type": "bytes32"},
        {"name": "owner", "type": "address"},
        {"name": "nonce", "type": "bytes32"},
        {"name": "deadline", "type": "uint256"},
    ],
}


class LoiVoucher(Exception):
    """Lỗi cơ sở cho các thao tác liên quan tới Voucher."""
    pass


class LoiCauHinhVoucher(LoiVoucher):
    """Thiếu cấu hình hoặc cấu hình khóa/hợp đồng không hợp lệ."""
    pass


class LoiTrangThaiNhanVatVoucher(LoiVoucher):
    """Nhân vật ở trạng thái không thể cấp voucher (đã registered hoặc đang pending)."""
    pass


class LoiXacThucVoucher(LoiVoucher):
    """Người chơi không có quyền yêu cầu voucher cho nhân vật này."""
    pass


@dataclass(frozen=True)
class CauHinhVoucher:
    signer_private_key: str = ""
    authorized_signer: str = ""
    registry_contract: str = ""
    chain_id: int = 31337
    ttl_seconds: int = 1800  # 30 phút
    enabled: bool = True

    def da_cau_hinh(self) -> bool:
        return bool(self.enabled and self.signer_private_key and self.registry_contract)


@dataclass
class _BanGhiVoucherCache:
    voucher_response: PhanHoiKyVoucher
    expires_at: float
    issued_at: float


class DichVuVoucherNhanVat:
    """Service tạo, quản lý và ký EIP-712 CharacterVoucher."""

    def __init__(self, config: CauHinhVoucher):
        self.config = config
        self._cache_vouchers: dict[str, _BanGhiVoucherCache] = {}
        self._lock = threading.Lock()

    def da_cau_hinh(self) -> bool:
        return self.config.da_cau_hinh()

    def _lay_khoa_ky(self) -> bytes:
        """Trích xuất và chuẩn hóa khóa bí mật ký Backend (32 bytes)."""
        raw = self.config.signer_private_key.strip()
        if not raw:
            raise LoiCauHinhVoucher("Chưa cấu hình khóa bí mật của Backend Signer (AI_CHARACTER_SIGNER_PRIVATE_KEY)")
        clean = raw.removeprefix("0x").removeprefix("0X")
        if not re.fullmatch(r"^[0-9a-fA-F]{64}$", clean):
            raise LoiCauHinhVoucher("Khóa bí mật Backend Signer không đúng định dạng 64 ký tự hex")
        return bytes.fromhex(clean)

    def lay_dia_chi_signer(self) -> str:
        """Tính địa chỉ Ethereum công khai từ khóa bí mật và đối soát authorizedSigner."""
        key = self._lay_khoa_ky()
        derived = dia_chi_tu_khoa(key)
        if self.config.authorized_signer:
            expected = self.config.authorized_signer.strip().lower()
            if derived.lower() != expected:
                raise LoiCauHinhVoucher(
                    f"Địa chỉ ví suy ra từ khóa bí mật ({derived}) "
                    f"không khớp với authorizedSigner đã cấu hình ({self.config.authorized_signer})"
                )
        return derived

    def tao_va_ky_voucher(
        self,
        *,
        character_id: str,
        character_hash: str,
        owner_wallet: str,
        now: float | None = None,
    ) -> PhanHoiKyVoucher:
        """Tạo thông điệp EIP-712 và ký bằng Backend Signer.

        Quy tắc an toàn:
        - Kiểm tra tính đầy đủ của cấu hình (fail-closed).
        - Cache voucher còn hạn để hỗ trợ client retry an toàn mà không sinh nonce rác.
        - Sinh nonce 32 bytes ngẫu nhiên bằng `secrets.token_bytes(32)`.
        - Tính deadline từ đồng hồ máy chủ (mặc định 30 phút).
        - Ký digest bằng secp256k1 EIP-712.
        - Tuyệt đối không log hoặc trả về private key.
        """
        current_time = time.time() if now is None else now

        if not self.config.enabled:
            raise LoiCauHinhVoucher("Tính năng cấp voucher EIP-712 hiện đang bị tắt")
        if not self.config.registry_contract:
            raise LoiCauHinhVoucher("Chưa cấu hình địa chỉ hợp đồng CharacterRegistry (AI_CHARACTER_REGISTRY_ADDRESS)")

        signer_key = self._lay_khoa_ky()
        signer_address = self.lay_dia_chi_signer()

        # Chuẩn hóa tham số
        clean_char_id = character_id.strip()
        if not re.fullmatch(r"^char_[0-9a-f]{32}$", clean_char_id):
            raise ValueError("character_id không đúng định dạng chuẩn (char_ + 32 ký tự hex)")

        clean_hash = character_hash.strip().lower().removeprefix("0x")
        if len(clean_hash) != 64:
            raise ValueError("character_hash phải có đúng 64 ký tự hex SHA-256")
        char_hash_0x = f"0x{clean_hash}"

        if not re.fullmatch(r"^0x[0-9a-fA-F]{40}$", owner_wallet):
            raise ValueError("owner_wallet không đúng định dạng địa chỉ ví Ethereum")
        owner_checksum = checksum(owner_wallet)

        with self._lock:
            # Kiểm tra cache còn hạn (hỗ trợ retry an toàn nếu gọi lại trong khoảng thời gian hiệu lực)
            cached = self._cache_vouchers.get(clean_char_id)
            if cached is not None:
                # Nếu voucher cũ vẫn còn hiệu lực ít nhất 60s và khớp đúng owner/hash, tái sử dụng an toàn
                if (
                    cached.expires_at > current_time + 60
                    and cached.voucher_response.message.owner.lower() == owner_checksum.lower()
                    and cached.voucher_response.message.characterHash.lower() == char_hash_0x
                ):
                    return cached.voucher_response

            # Sinh nonce mới và deadline
            nonce_bytes = secrets.token_bytes(32)
            nonce_hex = f"0x{nonce_bytes.hex()}"
            deadline_ts = int(current_time) + self.config.ttl_seconds

            contract_checksum = checksum(self.config.registry_contract)
            domain = {
                "name": EIP712_DOMAIN_NAME,
                "version": EIP712_DOMAIN_VERSION,
                "chainId": self.config.chain_id,
                "verifyingContract": contract_checksum,
            }

            voucher_msg = {
                "characterId": clean_char_id,
                "characterHash": char_hash_0x,
                "owner": owner_checksum,
                "nonce": nonce_hex,
                "deadline": deadline_ts,
            }

            # Băm EIP-712 Typed Data Digest
            digest = bam_eip712(domain, VOUCHER_TYPE_NAME, VOUCHER_FIELDS, voucher_msg)

            # Ký digest bằng Backend Signer
            signature_bytes = ky(digest, signer_key)
            signature_hex = f"0x{signature_bytes.hex()}"

            # Kiểm tra đối soát tự động: chữ ký phải phục hồi đúng signer_address
            recovered = phuc_hoi(digest, signature_bytes)
            if recovered.lower() != signer_address.lower():
                raise LoiVoucher("Lỗi kiểm soát chữ ký: địa chỉ phục hồi không khớp Backend Signer")

            result = PhanHoiKyVoucher(
                domain=EIP712DomainInfo(
                    name=EIP712_DOMAIN_NAME,
                    version=EIP712_DOMAIN_VERSION,
                    chainId=self.config.chain_id,
                    verifyingContract=contract_checksum,
                ),
                types=TYPES_MAP,
                primaryType="CharacterVoucher",
                message=CharacterVoucherMessage(
                    characterId=clean_char_id,
                    characterHash=char_hash_0x,
                    owner=owner_checksum,
                    nonce=nonce_hex,
                    deadline=deadline_ts,
                ),
                signature=signature_hex,
                signerAddress=signer_address,
                contractAddress=contract_checksum,
                chainId=self.config.chain_id,
                deadline=deadline_ts,
            )

            # Lưu cache
            self._cache_vouchers[clean_char_id] = _BanGhiVoucherCache(
                voucher_response=result,
                expires_at=float(deadline_ts),
                issued_at=current_time,
            )

            return result


def tao_dich_vu_voucher_tu_moi_truong() -> DichVuVoucherNhanVat:
    """Khởi tạo DichVuVoucherNhanVat từ biến môi trường cấu hình."""
    import config
    import os

    cfg = CauHinhVoucher(
        signer_private_key=os.environ.get("AI_CHARACTER_SIGNER_PRIVATE_KEY", config.AI_CHARACTER_SIGNER_PRIVATE_KEY),
        authorized_signer=os.environ.get("AI_CHARACTER_AUTHORIZED_SIGNER", config.AI_CHARACTER_AUTHORIZED_SIGNER),
        registry_contract=os.environ.get("AI_CHARACTER_REGISTRY_ADDRESS", config.AI_CHARACTER_REGISTRY_ADDRESS),
        chain_id=int(os.environ.get("AI_BLOCKCHAIN_CHAIN_ID", str(config.AI_BLOCKCHAIN_CHAIN_ID))),
        ttl_seconds=int(os.environ.get("AI_CHARACTER_VOUCHER_TTL_SECONDS", str(config.AI_CHARACTER_VOUCHER_TTL_SECONDS))),
        enabled=os.environ.get("AI_CHARACTER_VOUCHER_ENABLED", str(config.AI_CHARACTER_VOUCHER_ENABLED)).lower() in ("true", "1"),
    )
    return DichVuVoucherNhanVat(cfg)
