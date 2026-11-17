"""Module xác minh trạng thái vé cọc màn chơi on-chain qua Ethereum JSON-RPC (Fail-Closed).

Quy trình xác minh:
1. Kiểm tra cấu hình:
   - RPC URL hợp lệ và sẵn sàng kết nối.
   - Contract address hợp lệ theo định dạng Ethereum (0x...).
   - Chain ID hợp lệ.
2. Kiểm tra mạng (Network Verification):
   - Gọi eth_chainId và so khớp với config.CHAIN_ID.
   - Từ chối nếu node RPC đang trỏ sai mạng.
3. Kiểm tra trạng thái vé trên Smart Contract (Ticket Verification):
   - Gọi hàm view `ve(address)` của CuaHangGoldRush qua eth_call:
     Selector: 0xe5c297ba (keccak256("ve(address)")[:4])
     Param: địa chỉ ví người chơi (padded 32 bytes).
   - Giải mã kết quả (uint256 man, uint256 so, uint256 coc):
     + ve.so == so_ve_yeu_cau: số vé phải khớp chính xác vé đang mở on-chain.
     + ve.man == man_yeu_cau: màn chơi phải khớp chính xác màn đã đặt cọc.
     + ve.so > 0 và ve.coc > 0: vé phải đang ở trạng thái mở hợp lệ.
4. Chế độ Fail-Closed:
   - Thiếu cấu hình -> ném LoiCauHinhVe (503).
   - Lỗi mạng / timeout / RPC error -> ném LoiKetNoiRPC (503).
   - Vé không khớp hoặc không hợp lệ -> ném LoiVeKhongHopLe (422).
"""
from __future__ import annotations

import logging
import re
from typing import Any

import httpx

import config

log = logging.getLogger("core.xac_minh_ve_onchain")

# Function selector của `ve(address)` trong CuaHangGoldRush: keccak256(b"ve(address)")[:4]
SELECTOR_VE_ADDRESS = "0xe5c297ba"
SELECTOR_ERC1155_BALANCE_OF = "0x00fdd58e"
DIA_CHI_REGEX = re.compile(r"^0x[0-9a-fA-F]{40}$")


class LoiXacMinhVe(Exception):
    """Lớp cha cho các lỗi xác minh vé on-chain."""
    def __init__(self, message: str, code: str = "VERIFICATION_ERROR"):
        super().__init__(message)
        self.message = message
        self.code = code


class LoiCauHinhVe(LoiXacMinhVe):
    """Thiếu hoặc sai cấu hình RPC / Contract / Chain ID."""
    def __init__(self, message: str):
        super().__init__(message, code="CONFIG_ERROR")


class LoiKetNoiRPC(LoiXacMinhVe):
    """Lỗi mạng, timeout hoặc RPC node không phản hồi."""
    def __init__(self, message: str):
        super().__init__(message, code="RPC_ERROR")


class LoiVeKhongHopLe(LoiXacMinhVe):
    """Vé không tồn tại, sai màn, sai số vé hoặc chưa đặt cọc."""
    def __init__(self, message: str):
        super().__init__(message, code="INVALID_TICKET")


class XacMinhVeOnchain:
    """Trình xác minh vé cọc on-chain đáng tin cậy kết nối qua JSON-RPC."""

    def __init__(
        self,
        rpc_url: str | None = None,
        contract_address: str | None = None,
        chain_id: int | None = None,
        timeout_seconds: float | None = None,
        http_client: httpx.Client | None = None,
    ):
        self.rpc_url = (rpc_url or getattr(config, "BLOCKCHAIN_RPC_URL", "") or getattr(config, "AI_BLOCKCHAIN_RPC_URL", "")).strip()
        self.contract_address = (contract_address or getattr(config, "HOP_DONG_CUA_HANG", "")).strip()
        self.chain_id = chain_id if chain_id is not None else getattr(config, "CHAIN_ID", 31337)
        self.timeout_seconds = timeout_seconds if timeout_seconds is not None else getattr(config, "RPC_TIMEOUT_SECONDS", 5.0)
        self._custom_client = http_client

    def _kiem_tra_cau_hinh(self) -> None:
        """Kiểm tra tính đầy đủ và hợp lệ của cấu hình blockchain (Fail-Closed)."""
        if not self.rpc_url:
            raise LoiCauHinhVe("Chưa cấu hình BLOCKCHAIN_RPC_URL.")
        if not self.contract_address or not DIA_CHI_REGEX.fullmatch(self.contract_address):
            raise LoiCauHinhVe(f"Địa chỉ HOP_DONG_CUA_HANG không hợp lệ: '{self.contract_address}'.")
        if not isinstance(self.chain_id, int) or self.chain_id <= 0:
            raise LoiCauHinhVe(f"CHAIN_ID không hợp lệ: {self.chain_id}.")

    def _gui_yeu_cau_rpc(self, method: str, params: list[Any]) -> Any:
        """Gửi request JSON-RPC 2.0 đồng bộ với timeout nghiêm ngặt."""
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1,
        }
        try:
            if self._custom_client is not None:
                resp = self._custom_client.post(self.rpc_url, json=payload, timeout=self.timeout_seconds)
            else:
                with httpx.Client(timeout=self.timeout_seconds) as client:
                    resp = client.post(self.rpc_url, json=payload)
            if resp.status_code != 200:
                raise LoiKetNoiRPC(f"RPC HTTP {resp.status_code}: {resp.text[:200]}")
            data = resp.json()
        except httpx.TimeoutException:
            raise LoiKetNoiRPC(f"RPC timeout sau {self.timeout_seconds}s khi gọi {method}.") from None
        except httpx.RequestError as e:
            raise LoiKetNoiRPC(f"Lỗi kết nối RPC ({type(e).__name__}): {e}") from None
        except Exception as e:
            if isinstance(e, LoiXacMinhVe):
                raise
            raise LoiKetNoiRPC(f"Không thể đọc phản hồi JSON-RPC: {e}") from None

        if "error" in data:
            err_msg = data["error"].get("message", str(data["error"]))
            raise LoiKetNoiRPC(f"RPC trả lỗi ({method}): {err_msg}")
        if "result" not in data:
            raise LoiKetNoiRPC(f"RPC phản hồi thiếu trường 'result' ({method}).")
        return data["result"]

    def xac_minh_chain_id(self) -> int:
        """Kiểm tra mạng Ethereum hiện tại có khớp với CHAIN_ID cấu hình."""
        result = self._gui_yeu_cau_rpc("eth_chainId", [])
        if not isinstance(result, str) or not result.startswith("0x"):
            raise LoiKetNoiRPC(f"Kết quả eth_chainId không đúng định dạng hex: {result}")
        try:
            rpc_chain_id = int(result, 16)
        except ValueError:
            raise LoiKetNoiRPC(f"Không thể chuyển đổi hex chainId '{result}' sang integer.")
        if rpc_chain_id != self.chain_id:
            raise LoiCauHinhVe(f"Mạng RPC sai chainId: RPC trả về {rpc_chain_id}, hệ thống yêu cầu {self.chain_id}.")
        return rpc_chain_id

    def lay_ve_onchain(self, vi: str) -> dict[str, int]:
        """Truy vấn hàm ve(address) từ hợp đồng CuaHangGoldRush qua eth_call.

        Returns:
            dict chứa {'man': int, 'so': int, 'coc': int}
        """
        self._kiem_tra_cau_hinh()
        if not DIA_CHI_REGEX.fullmatch(vi):
            raise LoiVeKhongHopLe(f"Địa chỉ ví không hợp lệ: {vi}")

        # Chuẩn bị calldata cho `ve(address)`: selector (4 bytes) + address padded to 32 bytes
        dia_chi_hex = vi.lower().removeprefix("0x").rjust(64, "0")
        calldata = SELECTOR_VE_ADDRESS + dia_chi_hex

        call_params = [
            {
                "to": self.contract_address.lower(),
                "data": calldata,
            },
            "latest",
        ]
        raw_result = self._gui_yeu_cau_rpc("eth_call", call_params)
        if not isinstance(raw_result, str) or not raw_result.startswith("0x"):
            raise LoiKetNoiRPC(f"eth_call trả về dữ liệu không hợp lệ: {raw_result}")

        data_hex = raw_result[2:]
        # Kết quả mong đợi tối thiểu 3 word 32 byte = 96 byte = 192 ký tự hex
        if len(data_hex) < 192:
            raise LoiKetNoiRPC(f"eth_call trả về dữ liệu không đủ 3 word (độ dài hex: {len(data_hex)})")

        try:
            man = int(data_hex[0:64], 16)
            so = int(data_hex[64:128], 16)
            coc = int(data_hex[128:192], 16)
        except ValueError as e:
            raise LoiKetNoiRPC(f"Lỗi giải mã số liệu từ eth_call: {e}")

        return {"man": man, "so": so, "coc": coc}

    def lay_balance_erc1155(self, vi: str, token_id: int) -> int:
        """Đọc balanceOf(address,uint256) trên hợp đồng đã cấu hình."""
        self._kiem_tra_cau_hinh()
        if not DIA_CHI_REGEX.fullmatch(vi):
            raise LoiCauHinhVe(f"Địa chỉ ví không hợp lệ: {vi}")
        if not isinstance(token_id, int) or token_id <= 0:
            raise LoiCauHinhVe(f"token_id không hợp lệ: {token_id}")
        calldata = (
            SELECTOR_ERC1155_BALANCE_OF
            + vi.removeprefix("0x").rjust(64, "0")
            + format(token_id, "064x")
        )
        raw_result = self._gui_yeu_cau_rpc(
            "eth_call",
            [{"to": self.contract_address.lower(), "data": calldata}, "latest"],
        )
        if not isinstance(raw_result, str) or not raw_result.startswith("0x") or len(raw_result) < 66:
            raise LoiKetNoiRPC("balanceOf trả về dữ liệu không hợp lệ.")
        try:
            return int(raw_result[2:66], 16)
        except ValueError:
            raise LoiKetNoiRPC("Không giải mã được balanceOf từ RPC.") from None

    def xac_minh_ve_hop_le_de_vao_man(self, vi: str, man_yeu_cau: int, so_ve_yeu_cau: int) -> dict[str, int]:
        """Xác minh toàn diện trạng thái vé cọc on-chain trước khi cho phép bắt đầu màn có cọc.

        Quy tắc:
        - Mạng RPC phải khớp chainId.
        - ve.so on-chain phải bằng so_ve_yeu_cau (ve >= 1).
        - ve.man on-chain phải bằng man_yeu_cau.
        - ve.coc on-chain phải > 0 (đã đốt cọc thành công).
        """
        self._kiem_tra_cau_hinh()
        # 1. Xác minh mạng
        self.xac_minh_chain_id()

        # 2. Đọc vé on-chain
        ve_onchain = self.lay_ve_onchain(vi)

        # 3. Kiểm tra các điều kiện an toàn
        if ve_onchain["so"] <= 0:
            raise LoiVeKhongHopLe(f"Ví {vi} không có vé đang mở trên Smart Contract (ve.so = 0).")
        if ve_onchain["so"] != so_ve_yeu_cau:
            raise LoiVeKhongHopLe(
                f"Số vé không khớp on-chain: client yêu cầu vé {so_ve_yeu_cau}, "
                f"nhưng vé đang mở trên Smart Contract là {ve_onchain['so']}."
            )
        if ve_onchain["man"] != man_yeu_cau:
            raise LoiVeKhongHopLe(
                f"Màn chơi không khớp on-chain: client yêu cầu màn {man_yeu_cau}, "
                f"nhưng vé trên Smart Contract đặt cho màn {ve_onchain['man']}."
            )
        if ve_onchain["coc"] <= 0:
            raise LoiVeKhongHopLe(f"Vé on-chain không có số vàng cọc hợp lệ (coc = {ve_onchain['coc']}).")

        log.info(
            "Xác minh vé on-chain thành công: vi=%s, man=%d, ve=%d, coc=%d",
            vi, ve_onchain["man"], ve_onchain["so"], ve_onchain["coc"]
        )
        return ve_onchain
