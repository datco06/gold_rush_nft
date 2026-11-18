"""Sepolia native-ETH faucet, fail-closed and backed by the existing SQLite store.

The module deliberately uses the project's small Ethereum primitives and raw JSON-RPC;
it does not add a second wallet library or expose the faucet private key to the app.
"""
from __future__ import annotations

import time
import uuid
from datetime import datetime, timezone
from typing import Any, Callable

import config
from core.csdl import lay_csdl
from core.eth_ky import N, dia_chi_tu_khoa, keccak256, ky
from core.qua_tang import goi_rpc


class SepoliaFaucetError(Exception):
    def __init__(self, status_code: int, code: str, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


def _hex_int(value: Any) -> int:
    if isinstance(value, int):
        return value
    if not isinstance(value, str) or not value.startswith("0x"):
        raise ValueError("RPC integer không hợp lệ")
    return int(value, 16)


def _rlp(value: int | bytes | list[Any]) -> bytes:
    if isinstance(value, int):
        value = b"" if value == 0 else value.to_bytes((value.bit_length() + 7) // 8, "big")
    if isinstance(value, list):
        payload = b"".join(_rlp(v) for v in value)
        return _rlp_prefix(payload, 0xC0, 0xF7)
    return _rlp_prefix(value, 0x80, 0xB7)


def _rlp_prefix(payload: bytes, short_prefix: int, long_prefix: int) -> bytes:
    if len(payload) == 1 and short_prefix == 0x80 and payload[0] < 0x80:
        return payload
    if len(payload) <= (55 if short_prefix == 0x80 else 55):
        return bytes([short_prefix + len(payload)]) + payload
    length = len(payload).to_bytes((len(payload).bit_length() + 7) // 8, "big")
    return bytes([long_prefix + len(length)]) + length + payload


class SepoliaFaucetService:
    """One claim coordinator; SQLite BEGIN IMMEDIATE serializes workers/instances."""

    def __init__(
        self,
        *,
        rpc: Callable[[str, list[Any]], Any] = goi_rpc,
        now: Callable[[], float] = time.time,
        sleep: Callable[[float], None] = time.sleep,
        db_path=None,
    ):
        self.rpc = rpc
        self.now = now
        self.sleep = sleep
        self.db_path = db_path

    def _raise(self, status: int, code: str, message: str) -> None:
        raise SepoliaFaucetError(status, code, message)

    def _now_iso(self) -> str:
        return datetime.fromtimestamp(self.now(), timezone.utc).isoformat(timespec="seconds")

    def _day(self) -> str:
        return datetime.fromtimestamp(self.now(), timezone.utc).date().isoformat()

    def _private_key(self) -> bytes:
        raw = config.SEPOLIA_FAUCET_PRIVATE_KEY.strip().removeprefix("0x")
        if len(raw) != 64:
            self._raise(503, "FAUCET_KEY_INVALID", "Sepolia Faucet chưa được cấu hình hợp lệ.")
        try:
            key = bytes.fromhex(raw)
        except ValueError:
            self._raise(503, "FAUCET_KEY_INVALID", "Sepolia Faucet chưa được cấu hình hợp lệ.")
        if not 0 < int.from_bytes(key, "big") < N:
            self._raise(503, "FAUCET_KEY_INVALID", "Sepolia Faucet chưa được cấu hình hợp lệ.")
        try:
            derived = dia_chi_tu_khoa(key)
        except Exception:
            self._raise(503, "FAUCET_KEY_INVALID", "Sepolia Faucet chưa được cấu hình hợp lệ.")
        if derived.lower() != config.SEPOLIA_FAUCET_ADDRESS.lower():
            self._raise(503, "FAUCET_KEY_MISMATCH", "Địa chỉ Faucet không khớp private key.")
        return key

    def _validate_config(self) -> bytes:
        if config.CHAIN_ID != config.SEPOLIA_CHAIN_ID or not config.SEPOLIA_FAUCET_ENABLED:
            self._raise(404, "FAUCET_DISABLED", "Sepolia Faucet đang tắt.")
        if config.SEPOLIA_FAUCET_ADDRESS.lower() != config.SEPOLIA_FAUCET_EXPECTED_ADDRESS.lower():
            self._raise(503, "FAUCET_ADDRESS_INVALID", "Địa chỉ Sepolia Faucet không đúng cấu hình.")
        if not config.BLOCKCHAIN_RPC_URL:
            self._raise(503, "FAUCET_RPC_MISSING", "Sepolia Faucet chưa có RPC.")
        if config.SEPOLIA_FAUCET_TARGET_BALANCE_WEI <= 0:
            self._raise(503, "FAUCET_CONFIG_INVALID", "Mức cấp Sepolia Faucet không hợp lệ.")
        return self._private_key()

    def _chain_id(self) -> None:
        try:
            chain_id = _hex_int(self.rpc("eth_chainId", []))
        except Exception:
            self._raise(503, "FAUCET_RPC_UNAVAILABLE", "Không kiểm tra được Chain ID Sepolia.")
        if chain_id != config.SEPOLIA_CHAIN_ID:
            self._raise(503, "FAUCET_WRONG_CHAIN", "RPC Faucet không kết nối Ethereum Sepolia.")

    def _balance(self, wallet: str) -> int:
        try:
            return _hex_int(self.rpc("eth_getBalance", [wallet, "latest"]))
        except Exception:
            self._raise(503, "FAUCET_RPC_UNAVAILABLE", "Không đọc được số dư Sepolia.")

    def _claim_for(self, wallet: str, day: str | None = None):
        # Chỉ dùng bản ghi gần nhất để khôi phục giao dịch đang dở dang.
        # Bản ghi confirmed không khóa các lần cấp tiếp theo: nếu người chơi
        # đã tiêu hết ETH, request mới vẫn được phép bù lại lên target.
        where_day = " AND day_utc = ?" if day is not None else ""
        params = (wallet,) if day is None else (wallet, day)
        with lay_csdl(self.db_path) as conn:
            return conn.execute(
                """SELECT * FROM sepolia_faucet_claims
                   WHERE wallet_address = ? COLLATE NOCASE""" + where_day + """
                   ORDER BY created_at DESC LIMIT 1""",
                params,
            ).fetchone()

    def _reserve(self, wallet: str, amount: int, day: str):
        now = self._now_iso()
        with lay_csdl(self.db_path) as conn:
            existing = conn.execute(
                """SELECT * FROM sepolia_faucet_claims
                   WHERE wallet_address = ? COLLATE NOCASE
                     AND status IN ('reserved', 'broadcasting', 'pending')
                   ORDER BY created_at DESC LIMIT 1""",
                (wallet,),
            ).fetchone()
            if existing is not None:
                return existing, False
            try:
                rpc_nonce = _hex_int(
                    self.rpc("eth_getTransactionCount", [config.SEPOLIA_FAUCET_ADDRESS, "pending"])
                )
            except Exception:
                self._raise(503, "FAUCET_RPC_UNAVAILABLE", "Không đọc được nonce của Faucet.")
            # SQLite BEGIN IMMEDIATE serializes this allocation across workers.  The
            # local maximum also covers the short window before the first worker
            # broadcasts its transaction, when the RPC still reports the old nonce.
            last = conn.execute(
                """SELECT MAX(nonce) AS nonce FROM sepolia_faucet_claims
                   WHERE status IN ('reserved', 'broadcasting', 'pending', 'confirmed')"""
            ).fetchone()["nonce"]
            nonce = max(rpc_nonce, (int(last) + 1) if last is not None else rpc_nonce)
            claim_id = uuid.uuid4().hex
            conn.execute(
                """INSERT INTO sepolia_faucet_claims
                   (claim_id, wallet_address, day_utc, amount_wei, nonce, status, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, 'reserved', ?, ?)""",
                (claim_id, wallet, day, str(amount), nonce, now, now),
            )
            claim = conn.execute(
                "SELECT * FROM sepolia_faucet_claims WHERE claim_id = ?", (claim_id,)
            ).fetchone()
            return claim, True

    def _mark(
        self,
        claim_id: str,
        status: str,
        *,
        tx_hash: str | None = None,
        raw_transaction: str | None = None,
        error_code: str = "",
    ):
        now = self._now_iso()
        with lay_csdl(self.db_path) as conn:
            conn.execute(
                """UPDATE sepolia_faucet_claims
                   SET status = ?, transaction_hash = COALESCE(?, transaction_hash),
                       raw_transaction = COALESCE(?, raw_transaction),
                       error_code = ?, updated_at = ?,
                       confirmed_at = CASE WHEN ? = 'confirmed' THEN ? ELSE confirmed_at END
                   WHERE claim_id = ?""",
                (
                    status,
                    tx_hash,
                    raw_transaction,
                    error_code,
                    now,
                    status,
                    now if status == "confirmed" else None,
                    claim_id,
                ),
            )

    def _fees(self) -> tuple[int, int]:
        try:
            try:
                priority = _hex_int(self.rpc("eth_maxPriorityFeePerGas", []))
            except Exception:
                priority = 1_000_000_000
            try:
                block = self.rpc("eth_getBlockByNumber", ["latest", False]) or {}
                base = _hex_int(block.get("baseFeePerGas", "0x0"))
            except Exception:
                base = 0
            if base:
                max_fee = base * 2 + priority
            else:
                max_fee = _hex_int(self.rpc("eth_gasPrice", []))
            return priority, max_fee
        except Exception:
            self._raise(503, "FAUCET_RPC_UNAVAILABLE", "Không đọc được phí gas Sepolia.")

    def _gas_limit(self, faucet: str, player: str, amount: int) -> int:
        try:
            estimate = _hex_int(self.rpc("eth_estimateGas", [{"from": faucet, "to": player, "value": hex(amount)}]))
            return max(21_000, (estimate * 120 + 99) // 100)
        except Exception:
            self._raise(503, "FAUCET_GAS_ESTIMATE_FAILED", "Không ước lượng được gas cho Faucet.")

    def _make_raw(self, key: bytes, recipient: str, nonce: int, amount: int, priority: int, max_fee: int, gas_limit: int) -> str:
        to = bytes.fromhex(recipient.removeprefix("0x"))
        unsigned = [config.SEPOLIA_CHAIN_ID, nonce, priority, max_fee, gas_limit, to, amount, b"", []]
        digest = keccak256(b"\x02" + _rlp(unsigned))
        signature = ky(digest, key)
        r = int.from_bytes(signature[:32], "big")
        s = int.from_bytes(signature[32:64], "big")
        y_parity = signature[64] - 27
        signed = unsigned + [y_parity, r, s]
        return "0x02" + _rlp(signed).hex()

    def _send(self, key: bytes, recipient: str, amount: int, nonce: int, claim_id: str) -> str:
        priority, max_fee = self._fees()
        gas_limit = self._gas_limit(config.SEPOLIA_FAUCET_ADDRESS, recipient, amount)
        faucet_balance = self._balance(config.SEPOLIA_FAUCET_ADDRESS)
        if faucet_balance < amount + gas_limit * max_fee:
            self._raise(503, "FAUCET_INSUFFICIENT_FUNDS", "Ví Faucet không đủ Sepolia ETH để trả gas và cấp tiền.")
        raw = self._make_raw(key, recipient, nonce, amount, priority, max_fee, gas_limit)
        # Persist the exact signed bytes before broadcasting so a lost RPC
        # response can be retried with the same nonce and transaction hash.
        self._mark(claim_id, "broadcasting", raw_transaction=raw)
        try:
            tx_hash = self.rpc("eth_sendRawTransaction", [raw])
        except Exception:
            # The HTTP response can be lost after the node accepts the raw
            # transaction.  Recover its deterministic hash before deciding
            # whether the send really failed; never create a second nonce.
            tx_hash_du_kien = "0x" + keccak256(bytes.fromhex(raw[2:])).hex()
            try:
                if self.rpc("eth_getTransactionByHash", [tx_hash_du_kien]):
                    return tx_hash_du_kien
            except Exception:
                pass
            self._raise(
                503,
                "FAUCET_SEND_PENDING",
                "Chưa xác định được giao dịch Faucet; yêu cầu được giữ để tránh gửi trùng.",
            )
        if not isinstance(tx_hash, str) or not tx_hash.startswith("0x"):
            self._raise(503, "FAUCET_SEND_FAILED", "RPC Faucet trả mã giao dịch không hợp lệ.")
        return tx_hash

    def _resume_broadcasting(self, claim) -> str:
        raw = claim["raw_transaction"]
        if not raw:
            self._raise(503, "FAUCET_REQUEST_IN_PROGRESS", "Yêu cầu Faucet trước đang được xử lý.")
        tx_hash_du_kien = "0x" + keccak256(bytes.fromhex(raw[2:])).hex()
        try:
            known = self.rpc("eth_getTransactionByHash", [tx_hash_du_kien])
        except Exception:
            known = None
        if known:
            return tx_hash_du_kien
        try:
            tx_hash = self.rpc("eth_sendRawTransaction", [raw])
        except Exception:
            self._raise(503, "FAUCET_REQUEST_IN_PROGRESS", "Yêu cầu Faucet trước đang được xử lý.")
        if not isinstance(tx_hash, str) or not tx_hash.startswith("0x"):
            self._raise(503, "FAUCET_REQUEST_IN_PROGRESS", "Yêu cầu Faucet trước đang được xử lý.")
        return tx_hash

    def _wait_receipt(self, tx_hash: str) -> dict[str, Any]:
        deadline = self.now() + max(0.0, config.SEPOLIA_FAUCET_RECEIPT_TIMEOUT_SECONDS)
        while True:
            try:
                receipt = self.rpc("eth_getTransactionReceipt", [tx_hash])
            except Exception:
                receipt = None
            if receipt:
                if str(receipt.get("status", "0x0")) not in ("0x1", "1"):
                    self._raise(503, "FAUCET_TX_FAILED", "Giao dịch Faucet bị thất bại trên Sepolia.")
                return receipt
            if self.now() >= deadline:
                self._raise(503, "FAUCET_TX_PENDING", "Giao dịch Faucet đang chờ xác nhận trên Sepolia.")
            self.sleep(min(1.0, max(0.0, deadline - self.now())))

    def _result(self, claim, balance: int, *, status: str = "confirmed") -> dict[str, Any]:
        return {
            "chain_id": config.SEPOLIA_CHAIN_ID,
            "vi": claim["wallet_address"],
            "amount_wei": int(claim["amount_wei"]),
            "balance_wei": balance,
            "transaction_hash": claim["transaction_hash"],
            "status": status,
        }

    def cap_eth(self, wallet: str) -> dict[str, Any]:
        key = self._validate_config()
        if len(wallet) != 42 or not wallet.startswith("0x"):
            self._raise(422, "WALLET_INVALID", "Địa chỉ ví người chơi không hợp lệ.")
        try:
            bytes.fromhex(wallet[2:])
        except ValueError:
            self._raise(422, "WALLET_INVALID", "Địa chỉ ví người chơi không hợp lệ.")
        wallet = wallet.lower()
        if wallet == config.SEPOLIA_FAUCET_ADDRESS.lower():
            self._raise(422, "WALLET_INVALID", "Ví người chơi không được trùng ví Faucet.")
        self._chain_id()
        day = self._day()
        existing = self._claim_for(wallet)
        # Chỉ chặn/khôi phục request còn đang xử lý. Claim đã confirmed không
        # phải idempotency lock vĩnh viễn; ví có thể nhận lại sau khi đã tiêu ETH.
        if existing is not None and existing["status"] in ("reserved", "broadcasting", "pending"):
            if existing["status"] == "reserved":
                self._raise(503, "FAUCET_REQUEST_IN_PROGRESS", "Yêu cầu Faucet trước đang được xử lý.")
            if existing["status"] == "broadcasting":
                tx_hash = self._resume_broadcasting(existing)
                self._mark(existing["claim_id"], "pending", tx_hash=tx_hash)
            elif not existing["transaction_hash"]:
                self._raise(503, "FAUCET_REQUEST_IN_PROGRESS", "Yêu cầu Faucet trước đang được xử lý.")
            self._wait_receipt(tx_hash if existing["status"] == "broadcasting" else existing["transaction_hash"])
            self._mark(existing["claim_id"], "confirmed")
            fresh = self._claim_for(wallet, day)
            return self._result(fresh, self._balance(wallet))

        player_balance = self._balance(wallet)
        if player_balance >= config.SEPOLIA_FAUCET_TARGET_BALANCE_WEI:
            return {
                "chain_id": config.SEPOLIA_CHAIN_ID,
                "vi": wallet,
                "amount_wei": 0,
                "balance_wei": player_balance,
                "transaction_hash": None,
                "status": "not_needed",
            }

        amount = config.SEPOLIA_FAUCET_TARGET_BALANCE_WEI - player_balance

        faucet_balance = self._balance(config.SEPOLIA_FAUCET_ADDRESS)
        if faucet_balance < config.SEPOLIA_FAUCET_LOW_BALANCE_WEI:
            self._raise(503, "FAUCET_LOW_BALANCE", "Ví Faucet sắp hết Sepolia ETH.")
        claim, created = self._reserve(wallet, amount, day)
        if not created or claim["status"] != "reserved":
            self._raise(503, "FAUCET_REQUEST_IN_PROGRESS", "Yêu cầu Faucet trước đang được xử lý.")
        self._mark(claim["claim_id"], "broadcasting")
        try:
            tx_hash = self._send(key, wallet, amount, int(claim["nonce"]), claim["claim_id"])
        except SepoliaFaucetError as error:
            if error.code == "FAUCET_SEND_FAILED":
                self._mark(claim["claim_id"], "failed", error_code=error.code)
            raise
        self._mark(claim["claim_id"], "pending", tx_hash=tx_hash)
        # Fast path: the transaction is durably recorded and accepted by the
        # RPC. Flutter polls the player's balance before opening MetaMask;
        # later retries of this endpoint reconcile the receipt and confirm it.
        fresh = self._claim_for(wallet, day)
        return self._result(fresh, player_balance, status="pending")
