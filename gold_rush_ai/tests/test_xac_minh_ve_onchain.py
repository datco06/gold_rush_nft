"""Bộ kiểm thử bảo mật toàn diện cho On-chain Ticket Verifier và SIWE Auth (Phase 1).

Bao gồm đầy đủ 15 ca kiểm thử bắt buộc:
1. Màn 1 với SIWE và ve=0: thành công (201 Created).
2. Màn 1 với ve>0: bị từ chối (422).
3. Màn 2 với vé on-chain hợp lệ: thành công (201 Created, vé được ghi vào SoVe).
4. Màn 2 với ve giả (mismatch số vé): bị từ chối (422), không ghi SoVe.
5. Vé đúng số nhưng sai màn: bị từ chối (422).
6. Vé thuộc ví khác (on-chain ve.so=0 cho ví này): bị từ chối (422).
7. Chain ID sai (RPC trả về chainId khác CHAIN_ID): bị từ chối (503), fail-closed.
8. Contract address / cấu hình sai hoặc thiếu: không ghi ticket (503).
9. RPC timeout: fail-closed (503).
10. Đăng ký trùng ma_van: bị từ chối (409 Conflict).
11. Không có phiên SIWE: bị từ chối (401 Unauthorized).
12. Cookie thiếu CSRF hợp lệ: bị từ chối (403 Forbidden).
13. Telemetry hoặc client không thể tự nâng is_verified.
14. Không nhận EXP / Voucher từ vé giả.
15. Voucher EIP-712 cũ vẫn tương thích 100%.
"""
from __future__ import annotations

import tempfile
import unittest
import uuid
from pathlib import Path

import httpx
from fastapi.testclient import TestClient

import config
from api import main
from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai
from api.main import app
from core import csdl, man_choi, trong_tai
from core.xac_minh_ve_onchain import (
    XacMinhVeOnchain,
    LoiCauHinhVe,
    LoiKetNoiRPC,
    LoiVeKhongHopLe,
)

CHAIN_ID = 31337
HOP_DONG = "0x5FbDB2315678afecb367f032d93F642f64180aa3"
VI_ALICE = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
VI_BOB = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"


def encode_eth_call_ve(man: int, so: int, coc: int) -> str:
    """Mã hóa kết quả ABI của ve(address) -> (uint256, uint256, uint256)."""
    return f"0x{man:064x}{so:064x}{coc:064x}"


class MockRPCTransport(httpx.BaseTransport):
    """Giả lập Ethereum JSON-RPC node phục vụ kiểm thử đơn vị độc lập."""

    def __init__(
        self,
        chain_id: int = CHAIN_ID,
        ve_map: dict[str, tuple[int, int, int]] | None = None,
        timeout: bool = False,
        rpc_error: str | None = None,
    ):
        self.chain_id = chain_id
        # mapping vi.lower() -> (man, so, coc)
        self.ve_map = ve_map or {}
        self.timeout = timeout
        self.rpc_error = rpc_error

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        if self.timeout:
            raise httpx.TimeoutException("RPC connection timed out")

        import json
        body = json.loads(request.content.decode("utf-8"))
        method = body.get("method")
        req_id = body.get("id", 1)

        if self.rpc_error:
            return httpx.Response(
                200,
                json={"jsonrpc": "2.0", "id": req_id, "error": {"code": -32000, "message": self.rpc_error}},
            )

        if method == "eth_chainId":
            return httpx.Response(
                200,
                json={"jsonrpc": "2.0", "id": req_id, "result": hex(self.chain_id)},
            )

        if method == "eth_call":
            params = body.get("params", [])
            call_obj = params[0] if params else {}
            data = call_obj.get("data", "")
            # Trích xuất 40 hex char cuối cùng đại diện cho address
            if len(data) >= 74 and data.startswith("0xe5c297ba"):
                raw_addr = "0x" + data[-40:].lower()
                ticket = self.ve_map.get(raw_addr, (0, 0, 0))
                return httpx.Response(
                    200,
                    json={"jsonrpc": "2.0", "id": req_id, "result": encode_eth_call_ve(*ticket)},
                )
            return httpx.Response(
                200,
                json={"jsonrpc": "2.0", "id": req_id, "result": encode_eth_call_ve(0, 0, 0)},
            )

        return httpx.Response(
            200,
            json={"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Method not found: {method}"}},
        )


class TestOnchainTicketSecurity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            main.STATE["man_choi"] = man_choi.doc(config.MAN_CHOI)
        except Exception:
            pass

    def setUp(self):
        self.tam_dir = tempfile.mkdtemp()
        self.db_path = Path(self.tam_dir) / "test_ticket_sec.db"
        config.CSDL_PATH = self.db_path
        csdl.CSDL_PATH = self.db_path
        csdl.khoi_tao_csdl(self.db_path)

        self.nhat_ky_dir = Path(self.tam_dir) / "nhat_ky"
        self.nhat_ky_dir.mkdir(parents=True, exist_ok=True)
        main.NHAT_KY_DIR = self.nhat_ky_dir

        self.so_phieu_path = Path(self.tam_dir) / "so_phieu.jsonl"
        config.SO_PHIEU = self.so_phieu_path
        main.SO_PHIEU = self.so_phieu_path

        self.so_ve_path = Path(self.tam_dir) / "so_ve.jsonl"
        config.SO_VE = self.so_ve_path
        main.SO_VE = self.so_ve_path

        config.CHAIN_ID = CHAIN_ID
        main.CHAIN_ID = CHAIN_ID
        config.HOP_DONG_CUA_HANG = HOP_DONG
        main.HOP_DONG_CUA_HANG = HOP_DONG
        config.BLOCKCHAIN_RPC_URL = "http://127.0.0.1:8545"
        main.BLOCKCHAIN_RPC_URL = "http://127.0.0.1:8545"
        main.TRONG_TAI_KHOA = "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

        self.user_alice = NguoiChoiXacThuc(user_id="alice", wallet_address=VI_ALICE)
        self.user_bob = NguoiChoiXacThuc(user_id="bob", wallet_address=VI_BOB)

        def mock_auth():
            return self.user_alice

        app.dependency_overrides[lay_nguoi_choi_hien_tai] = mock_auth
        self.client = TestClient(app)

    def tearDown(self):
        app.dependency_overrides.clear()
        if hasattr(app.state, "onchain_ticket_verifier"):
            delattr(app.state, "onchain_ticket_verifier")

    def _setup_rpc_verifier(
        self,
        chain_id: int = CHAIN_ID,
        rpc_chain_id: int = CHAIN_ID,
        ve_map: dict[str, tuple[int, int, int]] | None = None,
        timeout: bool = False,
    ):
        transport = MockRPCTransport(chain_id=rpc_chain_id, ve_map=ve_map, timeout=timeout)
        mock_http = httpx.Client(transport=transport)
        verifier = XacMinhVeOnchain(
            rpc_url="http://mock-eth-rpc.local:8545",
            contract_address=HOP_DONG,
            chain_id=chain_id,
            http_client=mock_http,
        )
        app.state.onchain_ticket_verifier = verifier
        return verifier

    # -------------------------------------------------------------------------
    # TEST 1 & 2: MÀN 1 (MIỄN PHÍ)
    # -------------------------------------------------------------------------
    def test_01_man_1_siwe_va_ve_0_thanh_cong(self):
        """1. Màn 1 với SIWE và ve=0: thành công 201 Created và ghi match ticket."""
        ma_van = f"van-1-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 1, "ve": 0})
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertTrue(data["da_bat_dau"])
        self.assertEqual(data["ma_van"], ma_van)
        self.assertEqual(data["vi"].lower(), VI_ALICE.lower())

        # Kiểm tra SoVe đã ghi nhận
        bd = trong_tai.SoVe(self.so_ve_path).lay_theo_van(ma_van)
        self.assertIsNotNone(bd)
        self.assertEqual(bd["ve"], 0)
        self.assertEqual(bd["vi"].lower(), VI_ALICE.lower())

    def test_02_man_1_voi_ve_lon_hon_0_bi_tu_choi_422(self):
        """2. Màn 1 với ve>0: bị từ chối 422 (màn miễn phí không cần vé)."""
        ma_van = f"van-1-fail-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 1, "ve": 1})
        self.assertEqual(res.status_code, 422)
        self.assertIn("luyện tập", res.json()["detail"])

    # -------------------------------------------------------------------------
    # TEST 3, 4, 5, 6: MÀN CÓ CỌC (MÀN 2) VỚI TRẠNG THÁI VÉ ON-CHAIN
    # -------------------------------------------------------------------------
    def test_03_man_2_ve_onchain_hop_le_thanh_cong(self):
        """3. Màn 2 với vé on-chain hợp lệ: thành công 201 Created."""
        # On-chain có vé mở: man=2, so=5, coc=100
        self._setup_rpc_verifier(ve_map={VI_ALICE.lower(): (2, 5, 100)})

        ma_van = f"van-2-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 2, "ve": 5})
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertEqual(data["ma_van"], ma_van)

        bd = trong_tai.SoVe(self.so_ve_path).lay_theo_van(ma_van)
        self.assertIsNotNone(bd)
        self.assertEqual(bd["ve"], 5)
        self.assertEqual(bd["man"], 2)

    def test_04_man_2_ve_gia_bi_tu_choi_khong_ghi_so_ve(self):
        """4. Màn 2 với vé giả (on-chain chưa có vé hoặc số vé khác): bị từ chối 422, không ghi SoVe."""
        # On-chain chỉ có vé số 5, client gửi vé số 999
        self._setup_rpc_verifier(ve_map={VI_ALICE.lower(): (2, 5, 100)})

        ma_van = f"van-fake-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 2, "ve": 999})
        self.assertEqual(res.status_code, 422)
        self.assertIn("Số vé không khớp on-chain", res.json()["detail"])

        # Đảm bảo SoVe không bị ghi vé giả
        bd = trong_tai.SoVe(self.so_ve_path).lay_theo_van(ma_van)
        self.assertIsNone(bd)

    def test_05_ve_dung_so_nhung_sai_man_bi_tu_choi_422(self):
        """5. Vé đúng số nhưng sai màn: bị từ chối 422."""
        # On-chain vé được đặt cho màn 3, nhưng client xin vào màn 2
        self._setup_rpc_verifier(ve_map={VI_ALICE.lower(): (3, 5, 100)})

        ma_van = f"van-sai-man-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 2, "ve": 5})
        self.assertEqual(res.status_code, 422)
        self.assertIn("Màn chơi không khớp on-chain", res.json()["detail"])

    def test_06_ve_thuoc_vi_khac_bi_tu_choi(self):
        """6. Vé thuộc ví khác (Alice yêu cầu nhưng vé trên chain thuộc Bob): bị từ chối 422."""
        # Bob có vé on-chain, Alice không có vé (ve.so = 0)
        self._setup_rpc_verifier(ve_map={VI_BOB.lower(): (2, 1, 100)})

        ma_van = f"van-vi-khac-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 2, "ve": 1})
        self.assertEqual(res.status_code, 422)
        self.assertIn("không có vé đang mở trên Smart Contract", res.json()["detail"])

    # -------------------------------------------------------------------------
    # TEST 7, 8, 9: CẤU HÌNH, NETWORK VÀ RPC RESILIENCE (FAIL-CLOSED)
    # -------------------------------------------------------------------------
    def test_07_chain_id_sai_bi_tu_choi_fail_closed(self):
        """7. Chain ID sai: RPC trả về chainId khác với CHAIN_ID cấu hình -> bị từ chối 503."""
        # RPC trả về chainId 1 (Ethereum Mainnet) trong khi server cấu hình 31337
        self._setup_rpc_verifier(chain_id=CHAIN_ID, rpc_chain_id=1, ve_map={VI_ALICE.lower(): (2, 1, 100)})

        ma_van = f"van-wrong-chain-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 2, "ve": 1})
        self.assertEqual(res.status_code, 503)
        self.assertIn("Mạng RPC sai chainId", res.json()["detail"])

    def test_08_contract_address_hoac_cau_hinh_sai_khong_ghi_ticket(self):
        """8. Contract address / cấu hình sai hoặc rỗng -> 503 fail-closed, không ghi ticket."""
        verifier = XacMinhVeOnchain(
            rpc_url="http://mock-eth-rpc.local:8545",
            contract_address="0xInvalidContract",
            chain_id=CHAIN_ID,
        )
        app.state.onchain_ticket_verifier = verifier

        ma_van = f"van-bad-cfg-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 2, "ve": 1})
        self.assertEqual(res.status_code, 503)
        self.assertIsNone(trong_tai.SoVe(self.so_ve_path).lay_theo_van(ma_van))

    def test_09_rpc_timeout_fail_closed(self):
        """9. RPC timeout: fail-closed 503."""
        self._setup_rpc_verifier(timeout=True)

        ma_van = f"van-timeout-{uuid.uuid4().hex[:8]}"
        res = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 2, "ve": 1})
        self.assertEqual(res.status_code, 503)
        self.assertIn("timeout", res.json()["detail"])
        self.assertIsNone(trong_tai.SoVe(self.so_ve_path).lay_theo_van(ma_van))

    # -------------------------------------------------------------------------
    # TEST 10, 11, 12: ĐĂNG KÝ TRÙNG, SIWE AUTH VÀ CSRF
    # -------------------------------------------------------------------------
    def test_10_dang_ky_trung_ma_van_bi_tu_choi_409(self):
        """10. Đăng ký trùng ma_van: bị từ chối 409 Conflict."""
        ma_van = f"van-duplicate-{uuid.uuid4().hex[:8]}"
        res1 = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 1, "ve": 0})
        self.assertEqual(res1.status_code, 201)

        res2 = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 1, "ve": 0})
        self.assertEqual(res2.status_code, 409)

    def test_11_khong_co_phien_siwe_bi_tu_choi_401(self):
        """11. Không có phiên SIWE: bị từ chối 401 SESSION_REQUIRED."""
        app.dependency_overrides.clear()
        res = self.client.post("/api/man/bat-dau", json={"man": 1, "ve": 0})
        self.assertEqual(res.status_code, 401)
        self.assertEqual(res.json()["detail"]["code"], "SESSION_REQUIRED")

    def test_12_cookie_thieu_csrf_hop_le_bi_tu_choi_403(self):
        """12. Cookie phiên thiếu hoặc sai CSRF: bị từ chối 403 Forbidden."""
        # Giả lập request gửi cookie phiên gr_session nhưng thiếu X-CSRF-Token
        res = self.client.post(
            "/api/man/bat-dau",
            json={"man": 1, "ve": 0},
            cookies={"gr_session": "a" * 64},
            headers={"origin": "http://localhost:5000"},
        )
        self.assertEqual(res.status_code, 403)
        self.assertIn("CSRF", res.json()["detail"]["code"])

    # -------------------------------------------------------------------------
    # TEST 13, 14, 15: BẢO VỆ BẰNG CHỨNG, EXP/VOUCHER VÀ EIP-712
    # -------------------------------------------------------------------------
    def test_13_telemetry_khong_the_tu_nang_is_verified(self):
        """13. Telemetry client không thể tự nâng is_verified trong match_results."""
        ma_van = f"van-telemetry-{uuid.uuid4().hex[:8]}"
        # Đăng ký vé màn 1
        res_bd = self.client.post("/api/man/bat-dau", json={"ma_van": ma_van, "man": 1, "ve": 0})
        self.assertEqual(res_bd.status_code, 201)

        # Gửi telemetry với is_verified = 1 cố tình chèn vào body
        res_nk = self.client.post(
            "/api/nhat-ky",
            json={
                "ma_van": ma_van,
                "phien_ban_app": "1.3.0",
                "ban_do": "gold_rush.tmx",
                "man": 1,
                "ket_qua": "thang",
                "giay": 15.0,
                "diem": 100,
                "is_verified": 1,
                "verified_by": "hacked_client",
            },
        )
        self.assertEqual(res_nk.status_code, 201)

        # Kiểm tra trong SQLite: is_verified phải bằng 0 (chưa qua trọng tài)
        with csdl.lay_csdl() as conn:
            cur = conn.cursor()
            cur.execute("SELECT is_verified, verified_by FROM match_results WHERE ma_van = ?", (ma_van,))
            row = cur.fetchone()
            self.assertIsNotNone(row)
            self.assertEqual(row["is_verified"], 0)
            self.assertEqual(row["verified_by"], "telemetry_unverified")

    def test_14_khong_nhan_voucher_tu_ve_gia_hoac_khong_ticket(self):
        """14. Không nhận EXP / Voucher nếu không có vé hợp lệ trong SoVe."""
        ma_van = f"van-unregistered-{uuid.uuid4().hex[:8]}"
        # Gửi telemetry mà không đăng ký vé
        res_nk = self.client.post(
            "/api/nhat-ky",
            json={
                "ma_van": ma_van,
                "phien_ban_app": "1.3.0",
                "ban_do": "gold_rush.tmx",
                "man": 1,
                "ket_qua": "thang",
                "giay": 25.0,
                "diem": 80,
            },
        )
        self.assertEqual(res_nk.status_code, 201)

        # Xin cấp phiếu -> Bị từ chối vì chưa có ticket
        res = self.client.post("/api/vang/phieu", json={"ma_van": ma_van})
        self.assertEqual(res.status_code, 403)
        self.assertIn("Ván chơi chưa được đăng ký bắt đầu (thiếu ticket SoVe)", res.json()["detail"])

        # Hoàn thành tiến trình màn bằng evidence_id này -> Bị từ chối vì chưa xác minh
        res_prog = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": ma_van},
        )
        self.assertEqual(res_prog.status_code, 422)

    def test_15_voucher_eip712_tuong_thich_dung_domain_va_struct(self):
        """15. Voucher EIP-712 tương thích 100% domain separator và struct PhieuVang."""
        from core.eth_ky import phuc_hoi

        khoa = bytes.fromhex(main.TRONG_TAI_KHOA)
        ma_van = "van-test-eip712"
        man = 2
        ve = 3
        so_vang = 80

        res_ky = trong_tai.ky_phieu(
            VI_ALICE, man, ve, so_vang, ma_van, khoa, CHAIN_ID, HOP_DONG
        )

        phieu = res_ky["phieu"]
        chu_ky = res_ky["chu_ky"]

        self.assertEqual(phieu["nguoiChoi"].lower(), VI_ALICE.lower())
        self.assertEqual(phieu["man"], man)
        self.assertEqual(phieu["ve"], ve)
        self.assertEqual(phieu["soVang"], so_vang)
        self.assertTrue(chu_ky.startswith("0x"))
        self.assertEqual(len(chu_ky), 132)  # 65 bytes = 130 hex chars + 0x

        # Thẩm định lại chữ ký bằng hàm phuc_hoi và hash EIP-712
        mien = {"name": "GoldRush", "version": "2", "chainId": CHAIN_ID, "verifyingContract": HOP_DONG}
        bam = trong_tai.bam_eip712(mien, "PhieuVang", trong_tai.PHIEU, phieu)
        self.assertEqual("0x" + bam.hex(), res_ky["bam"])
        dia_chi_hoi_phuc = phuc_hoi(bam, bytes.fromhex(chu_ky[2:]))
        self.assertEqual(dia_chi_hoi_phuc, res_ky["trong_tai"])


if __name__ == "__main__":
    unittest.main()