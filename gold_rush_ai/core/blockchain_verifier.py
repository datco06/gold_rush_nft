"""Module xác minh giao dịch đăng ký nhân vật qua Ethereum JSON-RPC (AI-001).

Quy trình xác minh:
1. Kiểm tra mạng: eth_chainId khớp với chain_id đã cấu hình.
2. Kiểm tra giao dịch: eth_getTransactionByHash, eth_getTransactionReceipt, eth_blockNumber.
   - Transaction tồn tại và đã được mined.
   - Transaction gửi tới đúng hợp đồng CharacterRegistry.
   - Receipt có status == 1 (thành công).
   - Đạt số block xác nhận tối thiểu (min_confirmations).
   - Dữ liệu receipt và transaction nhất quán (chống reorg).
3. Kiểm tra sự kiện Smart Contract (Event Verification):
   event CharacterRegistered(
       string indexed characterId,
       bytes32 indexed characterHash,
       address indexed owner
   );
   - topic[0] == keccak256("CharacterRegistered(string,bytes32,address)")
   - topic[1] == keccak256(character_id.encode("utf-8")) (Solidity indexed string encoding)
   - topic[2] == "0x" + character_hash.lower() (bytes32 characterHash)
   - topic[3] == "0x" + 24 zeros + owner_wallet.lower().removeprefix("0x") (address indexed)
   - address log == registry_contract.lower()
   - log.removed is False
4. Bảo vệ dữ liệu & Fail-closed:
   - Thiếu cấu hình: không xác nhận registered (giữ pending).
   - Lỗi RPC / timeout: trả về trạng thái rpc_error, không đánh dấu thất bại vĩnh viễn.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import logging
import re
from typing import Any

import httpx

from core.eth_ky import keccak256

log = logging.getLogger(__name__)

EVENT_SIGNATURE_STR = "CharacterRegistered(string,bytes32,address)"
TOPIC_EVENT_CHARACTER_REGISTERED = "0x" + keccak256(EVENT_SIGNATURE_STR.encode("ascii")).hex().lower()


class TrangThaiXacMinhBlockchain(str, Enum):
    REGISTERED = "registered"
    PENDING = "pending"
    FAILED = "failed"
    RPC_ERROR = "rpc_error"
    NOT_CONFIGURED = "not_configured"


class LoiBlockchainRPC(Exception):
    """Lỗi giao tiếp với Ethereum JSON-RPC node (timeout, kết nối, mã lỗi RPC)."""
    pass


class LoiCauHinhBlockchain(Exception):
    """Thiếu hoặc sai cấu hình kết nối Blockchain."""
    pass


class LoiDuLieuBlockchain(Exception):
    """Dữ liệu phản hồi từ RPC node không hợp lệ hoặc thiếu trường bắt buộc."""
    pass


@dataclass(frozen=True)
class CauHinhBlockchain:
    rpc_url: str = ""
    chain_id: int = 31337
    registry_address: str = ""
    min_confirmations: int = 1
    timeout_seconds: float = 5.0

    def da_cau_hinh(self) -> bool:
        """Kiểm tra cấu hình có đủ để thực hiện xác minh RPC hay không."""
        return bool(self.rpc_url and self.registry_address)


@dataclass(frozen=True)
class KetQuaXacMinhOnchain:
    trang_thai: TrangThaiXacMinhBlockchain
    chi_tiet: str
    transaction_hash: str
    block_number: int | None = None
    confirmations: int = 0
    event_data: dict[str, Any] | None = None


def ma_hoa_topic_indexed_string(gia_tri: str) -> str:
    """Solidity mã hóa indexed string thành keccak256 của chuỗi bytes UTF-8."""
    return "0x" + keccak256(gia_tri.encode("utf-8")).hex().lower()


def ma_hoa_topic_bytes32(hex_32bytes: str) -> str:
    """Solidity mã hóa indexed bytes32 (ví dụ character_hash dạng SHA-256 64 ký tự hex)."""
    clean = hex_32bytes.lower().removeprefix("0x")
    if len(clean) != 64:
        raise ValueError(f"Dữ liệu bytes32 phải đúng 64 ký tự hex, nhận được: {len(clean)}")
    return "0x" + clean


def ma_hoa_topic_address(address_hex: str) -> str:
    """Solidity mã hóa indexed address bằng cách đệm 12 bytes 0 vào đầu (32 bytes = 64 ký tự hex)."""
    clean = address_hex.lower().removeprefix("0x")
    if len(clean) != 40:
        raise ValueError(f"Địa chỉ Ethereum phải đúng 40 ký tự hex, nhận được: {len(clean)}")
    return "0x" + "0" * 24 + clean


def _parse_hex_int(v: Any) -> int:
    if isinstance(v, int):
        return v
    if isinstance(v, str):
        v = v.strip()
        if v.startswith("0x") or v.startswith("0X"):
            return int(v, 16)
        return int(v, 10)
    raise ValueError(f"Không thể chuyển đổi {v!r} thành int")


class BlockchainVerifier:
    """Service xác minh giao dịch đăng ký nhân vật qua Ethereum JSON-RPC."""

    def __init__(
        self,
        config: CauHinhBlockchain,
        *,
        http_client: httpx.Client | None = None,
    ):
        self.config = config
        self._custom_client = http_client

    def da_cau_hinh(self) -> bool:
        return self.config.da_cau_hinh()

    def _tao_client(self) -> httpx.Client:
        if self._custom_client is not None:
            return self._custom_client
        return httpx.Client(timeout=self.config.timeout_seconds)

    def _gui_rpc(self, method: str, params: list[Any]) -> Any:
        """Gửi request JSON-RPC 2.0 tới Ethereum node."""
        if not self.config.rpc_url:
            raise LoiCauHinhBlockchain("Chưa cấu hình AI_BLOCKCHAIN_RPC_URL")

        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        }

        try:
            # Nếu dùng custom_client, không dùng context manager đóng nó
            if self._custom_client is not None:
                resp = self._custom_client.post(self.config.rpc_url, json=payload)
            else:
                with httpx.Client(timeout=self.config.timeout_seconds) as client:
                    resp = client.post(self.config.rpc_url, json=payload)

            if resp.status_code != 200:
                raise LoiBlockchainRPC(
                    f"HTTP error {resp.status_code} khi gọi JSON-RPC method {method}: {resp.text}"
                )

            data = resp.json()
            if "error" in data and data["error"] is not None:
                err = data["error"]
                code = err.get("code")
                msg = err.get("message")
                raise LoiBlockchainRPC(f"Lỗi JSON-RPC method {method} (code {code}): {msg}")

            return data.get("result")
        except httpx.TimeoutException as e:
            raise LoiBlockchainRPC(f"Hết thời gian chờ phản hồi RPC node ({self.config.timeout_seconds}s)") from e
        except httpx.RequestError as e:
            raise LoiBlockchainRPC(f"Lỗi kết nối RPC node: {e}") from e

    def kiem_tra_mang(self) -> int:
        """Bước A: Kiểm tra mạng RPC qua eth_chainId."""
        res = self._gui_rpc("eth_chainId", [])
        if res is None:
            raise LoiDuLieuBlockchain("RPC node trả về kết quả eth_chainId rỗng")
        chain_id = _parse_hex_int(res)
        if chain_id != self.config.chain_id:
            raise LoiDuLieuBlockchain(
                f"Sai mạng blockchain: node trả về chain_id={chain_id}, "
                f"nhưng cấu hình yêu cầu {self.config.chain_id}"
            )
        return chain_id

    def xac_minh_giao_dich(
        self,
        *,
        character_id: str,
        character_hash: str,
        owner_wallet: str,
        transaction_hash: str,
    ) -> KetQuaXacMinhOnchain:
        """Quy trình toàn diện xác minh giao dịch đăng ký nhân vật.

        Các bước:
        A. Kiểm tra mạng eth_chainId.
        B. Kiểm tra giao dịch eth_getTransactionByHash, receipt và blockNumber.
        C. Đối soát sự kiện CharacterRegistered (indexed string, bytes32, address).
        D. Trả về kết quả xác minh chi tiết.
        """
        tx_clean = transaction_hash.lower()

        # Kiểm tra cấu hình (fail-closed)
        if not self.da_cau_hinh():
            return KetQuaXacMinhOnchain(
                trang_thai=TrangThaiXacMinhBlockchain.NOT_CONFIGURED,
                chi_tiet="Chưa cấu hình đầy đủ RPC URL hoặc địa chỉ hợp đồng CharacterRegistry",
                transaction_hash=tx_clean,
            )

        try:
            # 1. Bước A: Kiểm tra mạng
            try:
                self.kiem_tra_mang()
            except LoiDuLieuBlockchain as e:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet=str(e),
                    transaction_hash=tx_clean,
                )

            # 2. Bước B: Kiểm tra giao dịch
            tx = self._gui_rpc("eth_getTransactionByHash", [tx_clean])
            if tx is None:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.PENDING,
                    chi_tiet="Giao dịch chưa tồn tại trên blockchain hoặc chưa vào mempool",
                    transaction_hash=tx_clean,
                )

            # Kiểm tra địa chỉ nhận
            tx_to = tx.get("to")
            if not tx_to or tx_to.lower() != self.config.registry_address.lower():
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet=(
                        f"Giao dịch gửi tới địa chỉ {tx_to}, không khớp với hợp đồng "
                        f"CharacterRegistry ({self.config.registry_address})"
                    ),
                    transaction_hash=tx_clean,
                )

            # Kiểm tra xem giao dịch đã được mined chưa
            tx_block_raw = tx.get("blockNumber")
            tx_block_hash = tx.get("blockHash")
            if tx_block_raw is None or tx_block_hash is None:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.PENDING,
                    chi_tiet="Giao dịch đang ở mempool (chưa được đóng block)",
                    transaction_hash=tx_clean,
                )

            tx_block_number = _parse_hex_int(tx_block_raw)

            # Lấy Transaction Receipt
            receipt = self._gui_rpc("eth_getTransactionReceipt", [tx_clean])
            if receipt is None:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.PENDING,
                    chi_tiet="Giao dịch chưa có receipt từ node",
                    transaction_hash=tx_clean,
                    block_number=tx_block_number,
                )

            # Kiểm tra tính nhất quán giữa Transaction và Receipt (chống reorg và giả mạo)
            receipt_tx_hash = receipt.get("transactionHash", "")
            if receipt_tx_hash.lower() != tx_clean:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet="Mã hash trong receipt không khớp với mã hash được yêu cầu",
                    transaction_hash=tx_clean,
                )

            receipt_block_hash = receipt.get("blockHash")
            if receipt_block_hash and tx_block_hash and receipt_block_hash.lower() != tx_block_hash.lower():
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet="BlockHash trong receipt không khớp với transaction (dấu hiệu chain reorg)",
                    transaction_hash=tx_clean,
                )

            receipt_block_number = _parse_hex_int(receipt.get("blockNumber"))
            if receipt_block_number != tx_block_number:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet="BlockNumber trong receipt không khớp với transaction",
                    transaction_hash=tx_clean,
                )

            # Kiểm tra trạng thái giao dịch (status == 1)
            raw_status = receipt.get("status")
            if raw_status is None:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet="Receipt thiếu trường status của giao dịch",
                    transaction_hash=tx_clean,
                    block_number=tx_block_number,
                )

            status_int = _parse_hex_int(raw_status)
            if status_int != 1:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet="Giao dịch đã bị REVERT trên blockchain (status = 0)",
                    transaction_hash=tx_clean,
                    block_number=tx_block_number,
                )

            # Kiểm tra confirmations
            latest_block_raw = self._gui_rpc("eth_blockNumber", [])
            latest_block = _parse_hex_int(latest_block_raw)
            confirmations = latest_block - tx_block_number + 1

            if confirmations < self.config.min_confirmations:
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.PENDING,
                    chi_tiet=(
                        f"Chưa đủ số block xác nhận tối thiểu: "
                        f"hiện có {confirmations}, yêu cầu {self.config.min_confirmations}"
                    ),
                    transaction_hash=tx_clean,
                    block_number=tx_block_number,
                    confirmations=max(0, confirmations),
                )

            # 3. Bước C: Xác minh sự kiện Smart Contract
            # event CharacterRegistered(string indexed characterId, bytes32 indexed characterHash, address indexed owner);
            expected_topic_0 = TOPIC_EVENT_CHARACTER_REGISTERED
            expected_topic_1 = ma_hoa_topic_indexed_string(character_id)
            expected_topic_2 = ma_hoa_topic_bytes32(character_hash)
            expected_topic_3 = ma_hoa_topic_address(owner_wallet)

            logs = receipt.get("logs", [])
            if not isinstance(logs, list):
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet="Receipt không chứa danh sách logs hợp lệ",
                    transaction_hash=tx_clean,
                    block_number=tx_block_number,
                    confirmations=confirmations,
                )

            matching_event_found = False
            mismatch_reason = ""

            for idx, log_entry in enumerate(logs):
                # Kiểm tra reorg flag
                if log_entry.get("removed", False) is True:
                    continue

                log_address = log_entry.get("address", "")
                if log_address.lower() != self.config.registry_address.lower():
                    continue

                topics = log_entry.get("topics", [])
                if not topics or len(topics) < 4:
                    continue

                # Kiểm tra event signature
                if topics[0].lower() != expected_topic_0:
                    continue

                # Tìm thấy event CharacterRegistered từ đúng contract, đối chiếu từng topic:
                actual_topic_1 = topics[1].lower()
                actual_topic_2 = topics[2].lower()
                actual_topic_3 = topics[3].lower()

                if actual_topic_1 != expected_topic_1:
                    mismatch_reason = (
                        f"characterId trong sự kiện on-chain ({actual_topic_1}) "
                        f"không khớp với nhân vật ({expected_topic_1})"
                    )
                    continue

                if actual_topic_2 != expected_topic_2:
                    mismatch_reason = (
                        f"characterHash trong sự kiện on-chain ({actual_topic_2}) "
                        f"không khớp với SHA-256 đã lưu ({expected_topic_2})"
                    )
                    continue

                if actual_topic_3 != expected_topic_3:
                    mismatch_reason = (
                        f"Chủ sở hữu (owner) trong sự kiện on-chain ({actual_topic_3}) "
                        f"không khớp với ví đã xác thực ({expected_topic_3})"
                    )
                    continue

                # Tất cả 4 topics đều khớp hoàn hảo!
                matching_event_found = True
                event_data = {
                    "event": EVENT_SIGNATURE_STR,
                    "character_id": character_id,
                    "character_hash": character_hash,
                    "owner_wallet": owner_wallet.lower(),
                    "contract": self.config.registry_address.lower(),
                    "log_index": log_entry.get("logIndex"),
                }
                break

            if not matching_event_found:
                chi_tiet = mismatch_reason or "Không tìm thấy sự kiện CharacterRegistered hợp lệ trong receipt giao dịch"
                return KetQuaXacMinhOnchain(
                    trang_thai=TrangThaiXacMinhBlockchain.FAILED,
                    chi_tiet=chi_tiet,
                    transaction_hash=tx_clean,
                    block_number=tx_block_number,
                    confirmations=confirmations,
                )

            # Thành công toàn diện!
            return KetQuaXacMinhOnchain(
                trang_thai=TrangThaiXacMinhBlockchain.REGISTERED,
                chi_tiet="Giao dịch đăng ký nhân vật đã được xác minh thành công trên blockchain",
                transaction_hash=tx_clean,
                block_number=tx_block_number,
                confirmations=confirmations,
                event_data=event_data,
            )

        except LoiBlockchainRPC as e:
            # Lỗi RPC tạm thời: không biến thành FAILED vĩnh viễn, giữ trạng thái pending
            log.warning("Lỗi tạm thời khi kết nối RPC blockchain: %s", e)
            return KetQuaXacMinhOnchain(
                trang_thai=TrangThaiXacMinhBlockchain.RPC_ERROR,
                chi_tiet=f"Lỗi tạm thời khi gọi RPC node: {e}",
                transaction_hash=tx_clean,
            )
        except Exception as e:
            log.error("Lỗi không mong muốn trong quá trình xác minh blockchain: %s", e)
            return KetQuaXacMinhOnchain(
                trang_thai=TrangThaiXacMinhBlockchain.RPC_ERROR,
                chi_tiet=f"Lỗi hệ thống khi xác minh giao dịch: {e}",
                transaction_hash=tx_clean,
            )


def tao_blockchain_verifier_tu_moi_truong(
    *,
    http_client: httpx.Client | None = None,
) -> BlockchainVerifier:
    """Khởi tạo BlockchainVerifier từ biến môi trường cấu hình."""
    import config

    cfg = CauHinhBlockchain(
        rpc_url=config.AI_BLOCKCHAIN_RPC_URL,
        chain_id=config.AI_BLOCKCHAIN_CHAIN_ID,
        registry_address=config.AI_CHARACTER_REGISTRY_ADDRESS,
        min_confirmations=config.AI_BLOCKCHAIN_MIN_CONFIRMATIONS,
        timeout_seconds=config.AI_BLOCKCHAIN_TIMEOUT_SECONDS,
    )
    return BlockchainVerifier(cfg, http_client=http_client)
