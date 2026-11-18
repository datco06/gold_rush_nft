from concurrent.futures import ThreadPoolExecutor

import pytest

import config
from core.csdl import khoi_tao_csdl
import core.faucet_sepolia as faucet_sepolia
from core.faucet_sepolia import SepoliaFaucetError, SepoliaFaucetService


FAUCET = "0xa93BE13C54197457602437eC6EF9B8F7bA36B36A"
PLAYER = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"


class RpcMock:
    def __init__(self, *, chain_id=11155111, player_balance=0, faucet_balance=10**18):
        self.chain_id = chain_id
        self.balances = {PLAYER.lower(): player_balance, FAUCET.lower(): faucet_balance}
        self.sent = []
        self.receipts = {}
        self.nonce = 0

    def __call__(self, method, params):
        if method == "eth_chainId":
            return hex(self.chain_id)
        if method == "eth_getBalance":
            return hex(self.balances.get(params[0].lower(), 0))
        if method == "eth_getTransactionCount":
            return hex(self.nonce)
        if method == "eth_maxPriorityFeePerGas":
            return hex(1_000_000_000)
        if method == "eth_getBlockByNumber":
            return {"baseFeePerGas": hex(1_000_000_000)}
        if method == "eth_estimateGas":
            return hex(21_000)
        if method == "eth_sendRawTransaction":
            tx_hash = f"0x{len(self.sent) + 1:064x}"
            self.sent.append(params[0])
            self.receipts[tx_hash] = {"status": "0x1"}
            self.balances[PLAYER.lower()] = 3 * 10**15
            self.nonce += 1
            return tx_hash
        if method == "eth_getTransactionReceipt":
            return self.receipts.get(params[0])
        raise AssertionError(f"RPC không mong đợi: {method}")


@pytest.fixture
def faucet_config(tmp_path, monkeypatch):
    db = tmp_path / "gold_rush.db"
    khoi_tao_csdl(db)
    monkeypatch.setattr(config, "CHAIN_ID", 11155111)
    monkeypatch.setattr(config, "BLOCKCHAIN_RPC_URL", "https://sepolia.example")
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_ENABLED", True)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_EXPECTED_ADDRESS", FAUCET)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_ADDRESS", FAUCET)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_PRIVATE_KEY", "test-only")
    monkeypatch.setattr(SepoliaFaucetService, "_private_key", lambda self: b"test-only")
    monkeypatch.setattr(faucet_sepolia, "ky", lambda digest, key: b"\x01" * 64 + b"\x1b")
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_LOW_BALANCE_WEI", 10**15)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_TARGET_BALANCE_WEI", 3 * 10**15)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_MAX_PER_WALLET_DAY_WEI", 6 * 10**15)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_MAX_TOTAL_DAY_WEI", 50 * 10**15)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_COOLDOWN_SECONDS", 0)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_MAX_REQUESTS_PER_HOUR", 3)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_RECEIPT_TIMEOUT_SECONDS", 0)
    return db


def test_disabled_or_wrong_chain_never_sends(faucet_config, monkeypatch):
    rpc = RpcMock()
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_ENABLED", False)
    with pytest.raises(SepoliaFaucetError) as error:
        SepoliaFaucetService(rpc=rpc, db_path=faucet_config).cap_eth(PLAYER)
    assert error.value.status_code == 404
    assert rpc.sent == []

    monkeypatch.setattr(config, "SEPOLIA_FAUCET_ENABLED", True)
    rpc.chain_id = 31337
    with pytest.raises(SepoliaFaucetError) as error:
        SepoliaFaucetService(rpc=rpc, db_path=faucet_config).cap_eth(PLAYER)
    assert error.value.code == "FAUCET_WRONG_CHAIN"
    assert rpc.sent == []


def test_sufficient_balance_does_not_call_faucet(faucet_config):
    rpc = RpcMock(player_balance=3 * 10**15)
    result = SepoliaFaucetService(rpc=rpc, db_path=faucet_config).cap_eth(PLAYER)
    assert result["status"] == "not_needed"
    assert result["amount_wei"] == 0
    assert rpc.sent == []


def test_player_wallet_cannot_be_faucet_wallet(faucet_config):
    rpc = RpcMock(player_balance=0)
    with pytest.raises(SepoliaFaucetError) as error:
        SepoliaFaucetService(rpc=rpc, db_path=faucet_config).cap_eth(FAUCET)
    assert error.value.code == "WALLET_INVALID"
    assert rpc.sent == []


def test_missing_balance_gets_eip1559_transfer_and_retry_is_idempotent(faucet_config):
    rpc = RpcMock(player_balance=0)
    service = SepoliaFaucetService(rpc=rpc, db_path=faucet_config)
    first = service.cap_eth(PLAYER)
    second = service.cap_eth(PLAYER)
    assert first["status"] == "pending"
    assert first["amount_wei"] == 3 * 10**15
    assert first["transaction_hash"] == second["transaction_hash"]
    assert second["status"] == "confirmed"
    assert len(rpc.sent) == 1
    assert rpc.sent[0].startswith("0x02")


def test_key_mismatch_and_low_balance_do_not_send(faucet_config, monkeypatch):
    rpc = RpcMock(player_balance=0, faucet_balance=10**18)
    def mismatch(self):
        self._raise(503, "FAUCET_KEY_MISMATCH", "Địa chỉ Faucet không khớp private key.")

    monkeypatch.setattr(SepoliaFaucetService, "_private_key", mismatch)
    with pytest.raises(SepoliaFaucetError) as error:
        SepoliaFaucetService(rpc=rpc, db_path=faucet_config).cap_eth(PLAYER)
    assert error.value.code == "FAUCET_KEY_MISMATCH"
    assert rpc.sent == []

    monkeypatch.setattr(SepoliaFaucetService, "_private_key", lambda self: b"test-only")
    rpc.balances[FAUCET.lower()] = 0
    with pytest.raises(SepoliaFaucetError) as error:
        SepoliaFaucetService(rpc=rpc, db_path=faucet_config).cap_eth(PLAYER)
    assert error.value.code == "FAUCET_LOW_BALANCE"
    assert rpc.sent == []


def test_total_daily_limit_is_persistent(faucet_config, monkeypatch):
    rpc = RpcMock(player_balance=0)
    monkeypatch.setattr(config, "SEPOLIA_FAUCET_MAX_TOTAL_DAY_WEI", 3 * 10**15)
    service = SepoliaFaucetService(rpc=rpc, db_path=faucet_config)
    service.cap_eth(PLAYER)
    other = "0x" + "4" * 40
    with pytest.raises(SepoliaFaucetError) as error:
        service.cap_eth(other)
    assert error.value.code == "FAUCET_TOTAL_LIMIT"
    assert len(rpc.sent) == 1


def test_concurrent_same_wallet_claim_sends_once(faucet_config):
    rpc = RpcMock(player_balance=0)
    service = SepoliaFaucetService(rpc=rpc, db_path=faucet_config)

    def call():
        try:
            return service.cap_eth(PLAYER)
        except SepoliaFaucetError as error:
            return error

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: call(), range(2)))
    assert len(rpc.sent) == 1
    assert any(isinstance(result, dict) for result in results)
    assert all(
        not isinstance(result, SepoliaFaucetError)
        or result.code == "FAUCET_REQUEST_IN_PROGRESS"
        for result in results
    )


def test_send_timeout_keeps_claim_in_progress_instead_of_retrying(faucet_config):
    class TimeoutRpc(RpcMock):
        def __call__(self, method, params):
            if method == "eth_sendRawTransaction":
                raise RuntimeError("timeout after broadcast")
            return super().__call__(method, params)

    rpc = TimeoutRpc(player_balance=0)
    service = SepoliaFaucetService(rpc=rpc, db_path=faucet_config)
    with pytest.raises(SepoliaFaucetError) as first:
        service.cap_eth(PLAYER)
    assert first.value.code == "FAUCET_SEND_PENDING"
    with pytest.raises(SepoliaFaucetError) as second:
        service.cap_eth(PLAYER)
    assert second.value.code == "FAUCET_REQUEST_IN_PROGRESS"
    assert rpc.sent == []
