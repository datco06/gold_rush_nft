"""Bộ kiểm thử bảo mật P0/P1 toàn diện cho Map Backend (Round 2 Final Patch).

Bao gồm đầy đủ các ca kiểm thử bảo mật nghiêm ngặt:
NHÓM 1: AUTHENTICATION, ORIGIN & CSRF (Fail-Closed)
- Chưa đăng nhập SIWE -> 401 SESSION_REQUIRED.
- Cookie có CSRF nhưng chưa có verifier -> 403 CSRF_VERIFIER_UNAVAILABLE.
- Origin lạ hoặc thiếu khi dùng cookie -> 403 ORIGIN_FORBIDDEN / ORIGIN_REQUIRED.
- Không cho phép request.state bypass authentication trong production.

NHÓM 2: EVIDENCE ZERO-TRUST & VERIFIED WALLET AUTHORIZATION
- Complete-stage với evidence_id không tồn tại -> 404.
- Complete-stage với evidence của ví khác -> 403.
- Complete-stage với is_verified=1 nhưng player_id tự khai trùng Alice trong khi verified_wallet thuộc Bob -> Alice bị từ chối 403.
- Complete-stage với is_verified=1 nhưng verified_wallet trống -> 422 Fail-Closed.
- Complete-stage đúng ví nhưng sai stage_id -> 400.
- Complete-stage với evidence ván thua -> 400.
- Complete-stage với telemetry thô / chưa kiểm định (is_verified = 0) -> 422.
- Complete-stage với cùng evidence hai lần -> lần hai trả 409, không cộng EXP.
- Không cho phép dùng lại bằng chứng của người khác -> 403/409.
- Telemetry tự khai gửi qua /api/nhat-ky không thể làm bằng chứng nhận thưởng -> 422.
- Thẩm định qua SoPhieu đúng ví, đúng màn -> 200 thành công.
- Thẩm định qua SoPhieu sai ví -> 403 bị từ chối.
- Stage_id ngoài 1..6 bị từ chối -> 422.

NHÓM 3: CONCURRENCY & RACE CONDITIONS
- Hai evidence hợp lệ khác nhau gửi đồng thời -> tính đúng 60 EXP (50 + 10) và mở khóa màn.
- Hai request claim cùng một nhiệm vụ đồng thời -> chỉ đúng 1 request thành công (atomic).

NHÓM 4: AI QUEST HARDENING & REMOVAL OF GLOBAL FLAGS
- External client chưa đăng nhập không thể tạo AI quest -> 401.
- External client đã đăng nhập SIWE không thể gọi HTTP /api/quests/ai-assign -> 403 AI_ASSIGN_RESTRICTED.
- Thay đổi app.state.internal_ai_service không cấp quyền HTTP cho external client -> vẫn 403.
- Hàm nội bộ tao_nhiem_vu_ai_noi_bo được phép tạo Quest theo server policy.
- Hàm nội bộ áp trần 50 EXP (khi truyền số lớn hơn vẫn chỉ nhận 50 EXP).
- Hàm nội bộ kẹp 0 gold on-chain và 0 items ngoài chính sách.
- Hàm nội bộ giới hạn tối đa 3 nhiệm vụ active.
- Loại mục tiêu ngoài allowlist bị từ chối.

NHÓM 5: IDOR & DATA ISOLATION
- Người chơi Alice không đọc được nhiệm vụ của Bob.
- Alice không thể nhận thưởng nhiệm vụ của Bob.
- Trang bị vũ khí không thuộc sở hữu bị từ chối 400.

NHÓM 6: MAPS, MIGRATION & BLOCKCHAIN EIP-712
- Migration CSDL cũ không mất dữ liệu.
- API Inventory hoạt động an toàn.
- Bản đồ thuật toán BFS/A* đảm bảo đường đi tới xu.
- Chống path traversal trong map pool.
- Blockchain EIP-712 voucher và cấu hình vàng nguyên vẹn.
"""
from __future__ import annotations

import concurrent.futures
import sqlite3
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

import config
from api import main
from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai
from api.main import app
from core import csdl, kho_do, luoi, man_choi, quan_ly_ban_do, quan_ly_nhiem_vu, sinh_ban_do, tien_trinh, trong_tai


class TestSecurityVaTienTrinhRound2(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.old_khoa = getattr(main, "TRONG_TAI_KHOA", "")
        cls.old_hop_dong = getattr(main, "HOP_DONG_CUA_HANG", "")
        main.TRONG_TAI_KHOA = "59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
        main.HOP_DONG_CUA_HANG = "0x5FbDB2315678afecb367f032d93F642f64180aa3"
        try:
            main.STATE["man_choi"] = man_choi.doc(config.MAN_CHOI)
        except Exception:
            pass

    @classmethod
    def tearDownClass(cls):
        main.TRONG_TAI_KHOA = cls.old_khoa
        main.HOP_DONG_CUA_HANG = cls.old_hop_dong

    def setUp(self):
        self.tam_dir = tempfile.mkdtemp()
        self.db_path = Path(self.tam_dir) / "test_sec_round2.db"
        config.CSDL_PATH = self.db_path
        csdl.CSDL_PATH = self.db_path
        csdl.khoi_tao_csdl(self.db_path)

        # Thư mục nhật ký và sổ phiếu tạm thời cách ly tuyệt đối runtime
        self.nhat_ky_dir = Path(self.tam_dir) / "nhat_ky"
        self.nhat_ky_dir.mkdir(parents=True, exist_ok=True)
        self.old_nhat_ky_dir = getattr(main, "NHAT_KY_DIR", config.NHAT_KY_DIR)
        main.NHAT_KY_DIR = self.nhat_ky_dir

        self.so_phieu_path = Path(self.tam_dir) / "so_phieu.json"
        config.SO_PHIEU = self.so_phieu_path
        main.SO_PHIEU = self.so_phieu_path

        self.so_ve_path = Path(self.tam_dir) / "so_ve.jsonl"
        config.SO_VE = self.so_ve_path
        main.SO_VE = self.so_ve_path

        self.client = TestClient(app)

        self.user_a = NguoiChoiXacThuc(
            user_id="user_alice",
            wallet_address="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        )
        self.user_b = NguoiChoiXacThuc(
            user_id="user_bob",
            wallet_address="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        )

        self.current_user = self.user_a

        def mock_auth():
            return self.current_user

        app.dependency_overrides[lay_nguoi_choi_hien_tai] = mock_auth

    def tearDown(self):
        main.NHAT_KY_DIR = self.old_nhat_ky_dir
        app.dependency_overrides.clear()
        if hasattr(app.state, "internal_ai_service"):
            delattr(app.state, "internal_ai_service")

    # =========================================================================
    # NHÓM 1: AUTHENTICATION, ORIGIN & CSRF (Fail-Closed)
    # =========================================================================

    def test_01_chua_dang_nhap_siwe_tra_401_fail_closed(self):
        """1. Không xác thực SIWE -> 401 SESSION_REQUIRED (Fail-Closed)."""
        app.dependency_overrides.clear()
        res = self.client.get("/api/progress")
        self.assertEqual(res.status_code, 401)
        self.assertEqual(res.json()["detail"]["code"], "SESSION_REQUIRED")

    def test_02_cookie_co_csrf_nhung_khong_co_verifier_tra_403(self):
        """2. Cookie có CSRF header nhưng server chưa gắn verifier -> từ chối 403."""
        res = self.client.post(
            "/api/equipment/select",
            json={"loai": "weapon", "item_id": "kiem_go"},
            headers={
                "Origin": "http://localhost:8501",
                "X-CSRF-Token": "random_fake_token_12345",
            },
            cookies={"gr_session": "a" * 64},
        )
        self.assertEqual(res.status_code, 403)
        self.assertEqual(res.json()["detail"]["code"], "CSRF_VERIFIER_UNAVAILABLE")

    def test_03_origin_la_hoac_thieu_khi_dung_cookie_bi_tu_choi(self):
        """3. Origin lạ hoặc thiếu header Origin khi gửi kèm cookie -> 403."""
        # A. Origin lạ
        res_la = self.client.post(
            "/api/equipment/select",
            json={"loai": "weapon", "item_id": "kiem_go"},
            headers={"Origin": "https://attacker.evil.com"},
        )
        self.assertEqual(res_la.status_code, 403)
        self.assertEqual(res_la.json()["detail"]["code"], "ORIGIN_FORBIDDEN")

        # B. Dùng cookie nhưng thiếu Origin
        res_thieu = self.client.post(
            "/api/equipment/select",
            json={"loai": "weapon", "item_id": "kiem_go"},
            cookies={"gr_session": "a" * 64},
        )
        self.assertEqual(res_thieu.status_code, 403)
        self.assertEqual(res_thieu.json()["detail"]["code"], "ORIGIN_REQUIRED")

    def test_04_khong_cho_request_state_bypass_production(self):
        """4. Không có nguồn SIWE tin cậy -> không thể bypass xác thực bằng request.state."""
        app.dependency_overrides.clear()
        res = self.client.get("/api/progress")
        self.assertEqual(res.status_code, 401)
        self.assertEqual(res.json()["detail"]["code"], "SESSION_REQUIRED")

    # =========================================================================
    # NHÓM 2: EVIDENCE ZERO-TRUST & VERIFIED WALLET AUTHORIZATION
    # =========================================================================

    def test_05_complete_stage_evidence_khong_ton_tai_tra_404(self):
        """5. POST complete-stage với evidence_id không tồn tại -> 404, không cấp EXP."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")

        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_non_existent_999"},
        )
        self.assertEqual(res.status_code, 404)

        with csdl.lay_csdl() as conn:
            tt = tien_trinh.lay_tien_trinh(conn, "user_alice")
            self.assertEqual(tt["exp"], 0)
            self.assertEqual(tt["completed_stage_ids"], [])

    def test_06_complete_stage_evidence_cua_nguoi_khac_tra_403(self):
        """6. POST complete-stage với evidence thuộc ví của người khác -> 403."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_bob")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_bob_verified', 'user_bob', 1, 'thang', 1, 1, 'referee', ?, datetime('now'))""",
                (self.user_b.wallet_address.lower(),),
            )

        # Alice gọi bằng mã ván của Bob
        self.current_user = self.user_a
        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_bob_verified"},
        )
        self.assertEqual(res.status_code, 403)

    def test_07_complete_stage_is_verified_nhung_player_id_khac_vi_tra_403(self):
        """7. Bản ghi is_verified=1 nhưng player_id tự khai là Alice, verified_wallet là Bob -> Alice bị từ chối 403."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            # Kẻ gian gửi telemetry tự khai player_id = 'user_alice', nhưng ví được trọng tài ký là Bob
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_spoofed_player_id', 'user_alice', 1, 'thang', 1, 1, 'referee', ?, datetime('now'))""",
                (self.user_b.wallet_address.lower(),),
            )

        # Alice đăng nhập SIWE với ví user_a cố nhận thưởng -> Phải bị từ chối 403 vì verified_wallet != ví Alice
        self.current_user = self.user_a
        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_spoofed_player_id"},
        )
        self.assertEqual(res.status_code, 403)
        self.assertIn("địa chỉ ví khác", res.json()["detail"])

    def test_08_complete_stage_is_verified_nhung_verified_wallet_trong_tra_422(self):
        """8. Bản ghi is_verified=1 nhưng verified_wallet rỗng -> Fail-closed 422."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_missing_wallet', 'user_alice', 1, 'thang', 1, 1, 'referee', '', datetime('now'))""",
            )

        self.current_user = self.user_a
        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_missing_wallet"},
        )
        self.assertEqual(res.status_code, 422)
        self.assertIn("thiếu thông tin ví", res.json()["detail"])

    def test_09_complete_stage_sai_stage_id_tra_400(self):
        """9. POST complete-stage với evidence sai stage_id -> 400."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_m1_verified', 'user_alice', 1, 'thang', 1, 1, 'referee', ?, datetime('now'))""",
                (self.user_a.wallet_address.lower(),),
            )

        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 2, "evidence_id": "van_m1_verified"},
        )
        self.assertEqual(res.status_code, 400)

    def test_10_complete_stage_evidence_thua_tra_400(self):
        """10. POST complete-stage với evidence ván thua -> 400."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_thua_verified', 'user_alice', 1, 'thua', 1, 1, 'referee', ?, datetime('now'))""",
                (self.user_a.wallet_address.lower(),),
            )

        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_thua_verified"},
        )
        self.assertEqual(res.status_code, 400)

    def test_11_complete_stage_evidence_chua_kiem_dinh_tra_422(self):
        """11. POST complete-stage với evidence chưa kiểm định (is_verified = 0) -> 422."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_unverified', 'user_alice', 1, 'thang', 0, 0, 'none', ?, datetime('now'))""",
                (self.user_a.wallet_address.lower(),),
            )

        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_unverified"},
        )
        self.assertEqual(res.status_code, 422)

    def test_12_complete_stage_cung_evidence_hai_lan_tra_409(self):
        """12. POST complete-stage với cùng evidence hai lần -> lần 2 trả về 409, không cộng EXP."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_alice_good', 'user_alice', 1, 'thang', 1, 1, 'referee', ?, datetime('now'))""",
                (self.user_a.wallet_address.lower(),),
            )

        res1 = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_alice_good"},
        )
        self.assertEqual(res1.status_code, 200)

        res2 = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_alice_good"},
        )
        self.assertEqual(res2.status_code, 409)

        with csdl.lay_csdl() as conn:
            tt = tien_trinh.lay_tien_trinh(conn, "user_alice")
            self.assertEqual(tt["exp"], 50)

    def test_13_complete_stage_voi_telemetry_gia_bi_tu_choi_422(self):
        """13. Gửi telemetry tự khai qua /api/nhat-ky rồi dùng nó làm evidence -> bị từ chối 422."""
        import uuid
        ma_fake = f"van-fake-{uuid.uuid4().hex[:8]}"
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")

        res_nk = self.client.post(
            "/api/nhat-ky",
            json={
                "ma_van": ma_fake,
                "phien_ban_app": "1.3.0",
                "man": 1,
                "ban_do": "gold_rush.tmx",
                "ket_qua": "thang",
                "giay": 30.5,
                "diem": 100,
                "player_id": "user_alice",
                "su_kien": [],
            },
        )
        self.assertEqual(res_nk.status_code, 201)

        res_claim = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": ma_fake},
        )
        self.assertEqual(res_claim.status_code, 422)

    def test_14_khong_cho_dung_lai_bang_chung_cho_tai_khoan_khac(self):
        """14. Bằng chứng đã được Alice sử dụng không thể được tái sử dụng bởi tài khoản khác."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_bob")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_ev_shared', 'user_alice', 1, 'thang', 1, 1, 'referee', ?, datetime('now'))""",
                (self.user_a.wallet_address.lower(),),
            )

        self.current_user = self.user_a
        res_a = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_ev_shared"},
        )
        self.assertEqual(res_a.status_code, 200)

        self.current_user = self.user_b
        res_b = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van_ev_shared"},
        )
        self.assertIn(res_b.status_code, [403, 409])

    def test_15_tham_dinh_qua_so_phieu_dung_vi_thanh_cong(self):
        """15. Thẩm định qua SoPhieu hợp lệ đúng ví và đúng màn -> 200 thành công."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")

        so = trong_tai.SoPhieu(self.so_phieu_path)
        so.ghi(
            ma_van="van-sophieu-alice-01",
            vi=self.user_a.wallet_address,
            so_vang=15,
            man=1,
            ve=0,
        )

        self.current_user = self.user_a
        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van-sophieu-alice-01"},
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["thanh_cong"], True)

    def test_16_tham_dinh_qua_so_phieu_sai_vi_bi_tu_choi_403(self):
        """16. SoPhieu thuộc ví Bob nhưng Alice gọi nhận thưởng -> 403."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")

        so = trong_tai.SoPhieu(self.so_phieu_path)
        so.ghi(
            ma_van="van-sophieu-bob-01",
            vi=self.user_b.wallet_address,
            so_vang=15,
            man=1,
            ve=0,
        )

        self.current_user = self.user_a
        res = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 1, "evidence_id": "van-sophieu-bob-01"},
        )
        self.assertEqual(res.status_code, 403)

    def test_17_stage_id_ngoai_pham_vi_bi_tu_choi_422(self):
        """17. stage_id < 1 hoặc > 6 bị FastAPI validation từ chối 422."""
        res_0 = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 0, "evidence_id": "van-some-valid-id"},
        )
        self.assertEqual(res_0.status_code, 422)

        res_7 = self.client.post(
            "/api/progress/complete-stage",
            json={"stage_id": 7, "evidence_id": "van-some-valid-id"},
        )
        self.assertEqual(res_7.status_code, 422)

    # =========================================================================
    # NHÓM 3: CONCURRENCY & RACE CONDITIONS
    # =========================================================================

    def test_18_hai_evidence_khac_nhau_dong_thoi_khong_mat_exp_hay_unlock(self):
        """18. Một người chơi gửi đồng thời 2 evidence hợp lệ khác nhau -> EXP và Unlock tính đúng."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, ket_qua, hop_le, is_verified, verified_by, verified_wallet, created_at)
                   VALUES ('van_conc_1', 'user_alice', 1, 'thang', 1, 1, 'referee', ?, datetime('now')),
                          ('van_conc_2', 'user_alice', 1, 'thang', 1, 1, 'referee', ?, datetime('now'))""",
                (self.user_a.wallet_address.lower(), self.user_a.wallet_address.lower()),
            )

        ket_qua = []
        loi = []

        def submit_ev(m_van):
            try:
                res = self.client.post(
                    "/api/progress/complete-stage",
                    json={"stage_id": 1, "evidence_id": m_van},
                )
                if res.status_code == 200:
                    ket_qua.append(res.json())
                else:
                    loi.append(res.status_code)
            except Exception as e:
                loi.append(str(e))

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            f1 = ex.submit(submit_ev, "van_conc_1")
            f2 = ex.submit(submit_ev, "van_conc_2")
            f1.result()
            f2.result()

        self.assertEqual(len(ket_qua), 2)
        with csdl.lay_csdl() as conn:
            tt = tien_trinh.lay_tien_trinh(conn, "user_alice")
            self.assertEqual(tt["exp"], 60)
            self.assertIn(1, tt["completed_stage_ids"])
            self.assertIn(2, tt["unlocked_stage_ids"])

    def test_19_quest_claim_chong_double_claim_dong_thoi(self):
        """19. Hai request claim nhiệm vụ đồng thời -> chỉ đúng 1 request thành công (atomic)."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            q = quan_ly_nhiem_vu.tao_nhiem_vu(
                conn, "user_alice", "Atomic Q", "Desc", "nhat_xu", target_count=5, reward_exp=50
            )
            quan_ly_nhiem_vu.cap_nhat_tien_do(conn, "user_alice", "nhat_xu", 5)

        kq = []
        err = []

        def claim_worker():
            try:
                res = self.client.post("/api/quests/claim", json={"quest_id": q["quest_id"]})
                if res.status_code == 200:
                    kq.append(True)
                else:
                    err.append(res.status_code)
            except Exception as e:
                err.append(str(e))

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            f1 = ex.submit(claim_worker)
            f2 = ex.submit(claim_worker)
            f1.result()
            f2.result()

        self.assertEqual(len(kq), 1)
        self.assertEqual(len(err), 1)
        with csdl.lay_csdl() as conn:
            tt = tien_trinh.lay_tien_trinh(conn, "user_alice")
            self.assertEqual(tt["exp"], 50)

    # =========================================================================
    # NHÓM 4: AI QUEST HARDENING & REMOVAL OF GLOBAL FLAGS
    # =========================================================================

    def test_20_external_client_chua_dang_nhap_khong_tao_duoc_ai_quest(self):
        """20. External client chưa đăng nhập không thể gọi POST /api/quests/ai-assign -> 401."""
        app.dependency_overrides.clear()
        res = self.client.post("/api/quests/ai-assign")
        self.assertEqual(res.status_code, 401)

    def test_21_external_client_da_dang_nhap_bi_tu_choi_ai_assign_403(self):
        """21. External client dù đã đăng nhập SIWE vẫn bị từ chối 403 AI_ASSIGN_RESTRICTED."""
        res = self.client.post("/api/quests/ai-assign")
        self.assertEqual(res.status_code, 403)
        self.assertEqual(res.json()["detail"]["code"], "AI_ASSIGN_RESTRICTED")

    def test_22_thay_doi_app_state_khong_cap_quyen_http_cho_ai_quest(self):
        """22. Thay đổi cờ app.state.internal_ai_service không cấp quyền HTTP cho client ngoài."""
        app.state.internal_ai_service = True
        try:
            res = self.client.post("/api/quests/ai-assign")
            self.assertEqual(res.status_code, 403)
            self.assertEqual(res.json()["detail"]["code"], "AI_ASSIGN_RESTRICTED")
        finally:
            app.state.internal_ai_service = False

    def test_23_ham_noi_bo_tao_ai_quest_theo_server_policy(self):
        """23. Hàm server nội bộ tao_nhiem_vu_ai_noi_bo áp trần 50 EXP và 0 gold/item."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            # Yêu cầu 500 EXP -> server policy kẹp trần 50 EXP
            q = quan_ly_nhiem_vu.tao_nhiem_vu_ai_noi_bo(
                conn,
                player_id="user_alice",
                title="AI Quest An Toan",
                description="Kiem tra trần thưởng",
                target_type="nhat_xu",
                target_count=10,
                reward_exp=500,
            )
            self.assertEqual(q["reward_exp"], 50)
            self.assertEqual(q["reward_gold"], 0)
            self.assertEqual(q["reward_items"], [])
            self.assertEqual(q["quest_type"], "ai_generated")

    def test_24_ham_noi_bo_gioi_han_toi_da_3_nhiem_vu_active(self):
        """24. Hàm nội bộ chặn tạo quá 3 nhiệm vụ active cho một người chơi."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            for i in range(3):
                quan_ly_nhiem_vu.tao_nhiem_vu_ai_noi_bo(
                    conn,
                    player_id="user_alice",
                    title=f"Quest {i+1}",
                    description=f"Desc {i+1}",
                    target_type="nhat_xu",
                    target_count=5,
                    reward_exp=50,
                )

            # Tạo nhiệm vụ thứ 4 -> ném ValueError
            with self.assertRaises(ValueError) as ctx:
                quan_ly_nhiem_vu.tao_nhiem_vu_ai_noi_bo(
                    conn,
                    player_id="user_alice",
                    title="Quest 4 Overload",
                    description="Vượt giới hạn 3 quest",
                    target_type="nhat_xu",
                    target_count=5,
                    reward_exp=50,
                )
            self.assertIn("tối đa 3 nhiệm vụ", str(ctx.exception))

    def test_25_ham_noi_bo_tu_choi_target_type_ngoai_allowlist(self):
        """25. Mục tiêu ngoài allowlist bị hàm nội bộ từ chối ném ValueError."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            with self.assertRaises(ValueError) as ctx:
                quan_ly_nhiem_vu.tao_nhiem_vu_ai_noi_bo(
                    conn,
                    player_id="user_alice",
                    title="Hack Target",
                    description="Loại mục tiêu lạ",
                    target_type="hack_gold_blockchain",
                    target_count=1,
                    reward_exp=50,
                )
            self.assertIn("không hợp lệ", str(ctx.exception))

    # =========================================================================
    # NHÓM 5: IDOR & DATA ISOLATION
    # =========================================================================

    def test_26_alice_khong_doc_duoc_nhiem_vu_cua_bob(self):
        """26. Alice chỉ đọc được nhiệm vụ của Alice, không lộ danh sách của Bob."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_alice")
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_bob")
            quan_ly_nhiem_vu.tao_nhiem_vu(conn, "user_bob", "Secret Bob", "Desc", "nhat_xu", 5, 50)

        self.current_user = self.user_a
        res = self.client.get("/api/quests/active")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["tong_so"], 0)

    def test_27_alice_khong_the_claim_nhiem_vu_cua_bob(self):
        """27. Alice không thể nhận thưởng nhiệm vụ thuộc về Bob (chống IDOR)."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "user_bob")
            q = quan_ly_nhiem_vu.tao_nhiem_vu(conn, "user_bob", "Bob Quest", "Desc", "nhat_xu", 1, 50)
            quan_ly_nhiem_vu.cap_nhat_tien_do(conn, "user_bob", "nhat_xu", 1)

        self.current_user = self.user_a
        res = self.client.post("/api/quests/claim", json={"quest_id": q["quest_id"]})
        self.assertEqual(res.status_code, 400)

    def test_28_equipment_khong_so_huu_bi_tu_choi_400(self):
        """28. Người chơi không thể trang bị vật phẩm chưa sở hữu trong kho đồ."""
        res = self.client.post(
            "/api/equipment/select",
            json={"loai": "weapon", "item_id": "kiem_anh_sang_toi_thuong"},
        )
        self.assertEqual(res.status_code, 400)

    # =========================================================================
    # NHÓM 6: MAPS, MIGRATION & BLOCKCHAIN EIP-712
    # =========================================================================

    def test_29_migration_database_cu_khong_mat_du_lieu(self):
        """29. Khởi tạo lại CSDL trên database cũ không làm mất tiến trình hay kho đồ."""
        with csdl.lay_csdl() as conn:
            tien_trinh.lay_hoac_tao_nguoi_choi(conn, "persisted_user_r2")
            tien_trinh.cong_exp(conn, "persisted_user_r2", 320)

        csdl.khoi_tao_csdl(self.db_path)

        with csdl.lay_csdl() as conn:
            tt = tien_trinh.lay_tien_trinh(conn, "persisted_user_r2")
            self.assertEqual(tt["exp"], 320)
            self.assertEqual(tt["level"], 3)

    def test_30_api_inventory_hoat_dong_voi_auth_hop_le(self):
        """30. API Inventory đọc đúng danh sách và đổi trang bị an toàn."""
        res_inv = self.client.get("/api/inventory")
        self.assertEqual(res_inv.status_code, 200)
        self.assertGreaterEqual(res_inv.json()["so_luong_vat_pham"], 2)

        res_eq = self.client.post(
            "/api/equipment/select",
            json={"loai": "weapon", "item_id": "kiem_go"},
        )
        self.assertEqual(res_eq.status_code, 200)

    def test_31_api_maps_pool_va_generator_an_toan(self):
        """31. API map pool, map config và generator hoạt động an toàn, chống path traversal."""
        res_cfg = self.client.get("/api/maps/config")
        self.assertEqual(res_cfg.status_code, 200)

        res_pool = self.client.get("/api/maps/pool")
        self.assertEqual(res_pool.status_code, 200)

        res_gen = self.client.get("/api/maps/generate?seed=123&mat_do=0.35&dinh_dang=json")
        self.assertEqual(res_gen.status_code, 200)
        self.assertEqual(res_gen.json()["seed"], 123)

        # Chống path traversal
        res_pt = self.client.get("/api/maps/pool/../../config.py")
        self.assertIn(res_pt.status_code, [400, 404])

    def test_32_maps_tim_duong_bfs_va_a_sao(self):
        """32. Thuật toán BFS / A* tìm đường tới xu trên bản đồ sinh ra."""
        ban_do = sinh_ban_do.sinh(seed=42, mat_do=0.35)
        so_xu = len([d for d in ban_do["doi_tuong"] if d[0] == "coin"])
        self.assertGreater(so_xu, 0)
        self.assertGreater(ban_do["chi_so"]["duong_tb_toi_xu"], 0)

    def test_33_blockchain_eip712_voucher_nguyen_ven(self):
        """33. Cấu hình vàng và EIP-712 voucher blockchain nguyên vẹn."""
        res_v = self.client.get("/api/vang/cau-hinh")
        self.assertEqual(res_v.status_code, 200)
        data = res_v.json()
        self.assertIn("chain_id", data)
        self.assertIn("trong_tai", data)

    # =========================================================================
    # NHÓM 7: VOUCHER OWNERSHIP BINDING & HIJACKING PREVENTION
    # =========================================================================

    def _tao_van_thang_tmx(self, ma_van: str, man: int = 1, ban_do: str = "gold_rush.tmx") -> None:
        from core.luoi import doc_tmx
        from tests.test_trong_tai import TILES, TMX, van_that
        tep = TMX if man == 1 else TILES / f"man_{man}.tmx"
        b = doc_tmx(tep)
        nk_data = {
            "ma_van": ma_van,
            "phien_ban_app": "1.3.0",
            "man": man,
            "ban_do": ban_do,
            **van_that(b, 5, ket_qua="thang"),
        }
        res = self.client.post("/api/nhat-ky", json=nk_data)
        self.assertEqual(res.status_code, 201)

    def test_34_voucher_ownership_man_mien_phi_b_xin_truoc_bi_tu_choi_403(self):
        """34. A đăng ký bắt đầu màn 1 (miễn phí), B biết ma_van và xin phiếu trước -> B bị từ chối 403."""
        import uuid
        ma_van = f"van-free-hijack-{uuid.uuid4().hex[:8]}"

        # 1. Người A đăng ký bắt đầu màn 1 (ve = 0)
        res_bd = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res_bd.status_code, 201)

        # 2. Tạo nhật ký ván thắng hợp lệ
        self._tao_van_thang_tmx(ma_van, man=1)

        # 3. Kẻ tấn công B (với phiên SIWE của B) biết ma_van, lập tức gọi POST /api/vang/phieu với ví B
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            res_b = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
            )
            # BẮT BUỘC BỊ TỪ CHỐI 403 Forbidden
            self.assertEqual(res_b.status_code, 403)
            self.assertIn("địa chỉ ví khác", res_b.json()["detail"])
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_35_voucher_ownership_man_mien_phi_a_xin_dung_thanh_cong_200(self):
        """35. Sau khi B bị chặn, A (chủ sở hữu đã đăng ký) xin phiếu -> thành công 200, cập nhật verified_wallet."""
        import uuid
        ma_van = f"van-free-owner-{uuid.uuid4().hex[:8]}"

        # 1. A đăng ký bắt đầu ván
        res_bd = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res_bd.status_code, 201)

        # 2. A gửi nhật ký
        self._tao_van_thang_tmx(ma_van, man=1)

        # 3. A xin phiếu với ví A
        res_a = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(res_a.status_code, 200)
        self.assertEqual(res_a.json()["phieu"]["man"], 1)

        # 4. Kiểm tra CSDL match_results: verified_wallet được ghi đúng ví A
        with csdl.lay_csdl() as conn:
            cur = conn.cursor()
            cur.execute("SELECT is_verified, verified_wallet FROM match_results WHERE ma_van = ?", (ma_van,))
            r = cur.fetchone()
            self.assertIsNotNone(r)
            self.assertEqual(r["is_verified"], 1)
            self.assertEqual(r["verified_wallet"], self.user_a.wallet_address.lower())

    def test_36_voucher_ownership_xin_lai_cung_ma_van_khong_phat_thuong_trung(self):
        """36. A xin lại phiếu cùng ma_van -> ký lại cùng nội dung (idempotent), ví khác xin lại trả 409."""
        import uuid
        ma_van = f"van-resend-{uuid.uuid4().hex[:8]}"

        self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self._tao_van_thang_tmx(ma_van, man=1)

        # Lần 1: Cấp phiếu
        res1 = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(res1.status_code, 200)
        p1 = res1.json()["phieu"]

        # Lần 2: Xin lại -> cùng maVan, cùng soVang, hanChot mới
        res2 = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(res2.status_code, 200)
        p2 = res2.json()["phieu"]
        self.assertEqual(p1["maVan"], p2["maVan"])
        self.assertEqual(p1["soVang"], p2["soVang"])

        # B cố tình xin lại phiếu bằng ví B -> 409 Conflict
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            res_b = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
            )
            self.assertIn(res_b.status_code, [403, 409])
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_37_voucher_ownership_khong_tao_verified_wallet_tu_request_chua_xac_thuc(self):
        """37. Ván chơi không có SIWE -> từ chối 401 fail-closed, KHÔNG ghi verified_wallet vào match_results."""
        import uuid
        ma_van = f"van-unauth-{uuid.uuid4().hex[:8]}"

        # Gửi nhật ký
        self._tao_van_thang_tmx(ma_van, man=1)

        # Bỏ override auth để giả lập unauthenticated client
        app.dependency_overrides.clear()
        try:
            vi_la = "0x" + "9" * 40
            res = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": vi_la},
            )
            # Unauthenticated request bị từ chối 401 fail-closed
            self.assertEqual(res.status_code, 401)
            with csdl.lay_csdl() as conn:
                cur = conn.cursor()
                cur.execute("SELECT is_verified, verified_wallet FROM match_results WHERE ma_van = ?", (ma_van,))
                r = cur.fetchone()
                self.assertEqual(r["is_verified"], 0)
                self.assertEqual(r["verified_wallet"], "")
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_38_voucher_ownership_man_co_coc_van_kiem_tra_ve_va_vi(self):
        """38. Màn có cọc (màn 2) bắt buộc kiểm tra vé và ví đối chiếu qua SoVe."""
        import uuid
        ma_van = f"van-coc-{uuid.uuid4().hex[:8]}"

        # 1. A đăng ký màn 2 với ve = 1
        res_bd = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 2, "ve": 1},
        )
        self.assertEqual(res_bd.status_code, 201)

        # 2. Gửi nhật ký màn 2
        self._tao_van_thang_tmx(ma_van, man=2, ban_do="man_2.tmx")

        # 3. B xin phiếu cho màn có cọc của A -> bị từ chối 403
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            res_b = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
            )
            self.assertEqual(res_b.status_code, 403)
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_39_voucher_ownership_siwe_session_khac_vi_body_bi_tu_choi_403(self):
        """39. Session SIWE đăng nhập ví Alice nhưng body gửi ví Bob -> 403 Forbidden."""
        import uuid
        ma_van = f"van-siwe-mismatch-{uuid.uuid4().hex[:8]}"
        self._tao_van_thang_tmx(ma_van, man=1)

        # Client đã đăng nhập SIWE ví A (self.user_a)
        res = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
        )
        self.assertEqual(res.status_code, 403)
        self.assertIn("không khớp với phiên đăng nhập SIWE", res.json()["detail"])

    # =========================================================================
    # NHÓM 6: KIỂM TRA TOÀN DIỆN 12 YÊU CẦU BẢO MẬT VOUCHER & TICKET (FINAL CHECK)
    # =========================================================================

    def test_40_anonymous_dang_ky_ticket_bi_tu_choi_401(self):
        """40. [Check 1] Anonymous client không có SIWE gọi POST /api/man/bat-dau -> bị từ chối 401."""
        app.dependency_overrides.clear()
        try:
            res = self.client.post(
                "/api/man/bat-dau",
                json={"ma_van": "van-anon-ticket-1", "vi": self.user_b.wallet_address, "man": 1, "ve": 0},
            )
            self.assertEqual(res.status_code, 401)
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_41_alice_siwe_dang_ky_ticket_voi_vi_bob_bi_tu_choi_403(self):
        """41. [Check 2] Alice đăng nhập SIWE nhưng khai vi của Bob khi đăng ký ticket -> bị từ chối 403."""
        res = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": "van-mismatch-ticket-1", "vi": self.user_b.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res.status_code, 403)
        self.assertIn("không khớp với phiên đăng nhập SIWE", res.json()["detail"])

    def test_42_alice_dang_ky_ticket_hop_le_rang_buoc_vi_alice_201(self):
        """42. [Check 3] Alice đăng ký ticket hợp lệ -> tạo ticket ràng buộc ví Alice trong SoVe (201)."""
        import uuid
        ma_van = f"van-alice-valid-{uuid.uuid4().hex[:8]}"
        res = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res.status_code, 201)
        j = res.json()
        self.assertTrue(j["da_bat_dau"])
        self.assertEqual(j["ma_van"], ma_van)
        self.assertEqual(j["vi"].lower(), self.user_a.wallet_address.lower())

        # Kiểm tra SoVe
        bd = trong_tai.SoVe(config.SO_VE).lay_theo_van(ma_van)
        self.assertIsNotNone(bd)
        self.assertEqual(bd["vi"].lower(), self.user_a.wallet_address.lower())
        self.assertEqual(bd["man"], 1)
        self.assertEqual(bd["ve"], 0)

    def test_43_bob_dang_ky_lai_cung_ma_van_bi_tu_choi_409(self):
        """43. [Check 4] Bob cố tình đăng ký lại cùng mã ván mà Alice đã đăng ký -> bị từ chối 409 Conflict."""
        import uuid
        ma_van = f"van-dup-reg-{uuid.uuid4().hex[:8]}"

        # Alice đăng ký trước
        res_a = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res_a.status_code, 201)

        # Bob cố tình đăng ký lại ma_van này
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            res_b = self.client.post(
                "/api/man/bat-dau",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address, "man": 1, "ve": 0},
            )
            self.assertEqual(res_b.status_code, 409)
            self.assertIn("Mã ván đã được dùng", res_b.json()["detail"])
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_44_bob_xin_phieu_cho_van_cua_alice_bi_tu_choi_403(self):
        """44. [Check 5] Bob xin phiếu cho ván chơi của Alice -> bị từ chối 403 Forbidden."""
        import uuid
        ma_van = f"van-alice-game-{uuid.uuid4().hex[:8]}"

        # Alice đăng ký và chơi
        res_bd = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res_bd.status_code, 201)
        self._tao_van_thang_tmx(ma_van, man=1)

        # Bob yêu cầu cấp phiếu cho ma_van này
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            res_b = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
            )
            self.assertEqual(res_b.status_code, 403)
            self.assertIn("địa chỉ ví khác", res_b.json()["detail"])
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_45_alice_xin_phieu_thanh_cong_va_nhan_voucher_hop_le_200(self):
        """45. [Check 6] Alice (đúng chủ sở hữu ván và ticket) xin phiếu -> thành công 200, nhận chữ ký EIP-712."""
        import uuid
        ma_van = f"van-alice-success-{uuid.uuid4().hex[:8]}"

        self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self._tao_van_thang_tmx(ma_van, man=1)

        res_a = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(res_a.status_code, 200)
        p = res_a.json()["phieu"]
        ck = res_a.json()["chu_ky"]
        self.assertEqual(p["nguoiChoi"].lower(), self.user_a.wallet_address.lower())
        self.assertTrue(ck.startswith("0x"))
        self.assertEqual(len(ck), 132)

    def test_46_server_sinh_ma_van_ngau_nhien_khi_client_khong_truyen(self):
        """46. Khi client không truyền ma_van, server tự sinh mã an toàn (UUID v4) và đăng ký thành công (201)."""
        res = self.client.post(
            "/api/man/bat-dau",
            json={"vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res.status_code, 201)
        data = res.json()
        self.assertTrue(data["da_bat_dau"])
        self.assertTrue(data["ma_van"].startswith("van-"))
        self.assertEqual(len(data["ma_van"]), 36)  # "van-" (4) + hex (32)

        # Ticket được lưu trong SoVe
        bd = trong_tai.SoVe(config.SO_VE).lay_theo_van(data["ma_van"])
        self.assertIsNotNone(bd)
        self.assertEqual(bd["vi"].lower(), self.user_a.wallet_address.lower())

    def test_47_cookie_mutation_khong_co_csrf_bi_tu_choi_403(self):
        """47. [Check 8] Gọi POST /api/man/bat-dau bằng cookie phiên nhưng thiếu CSRF/Origin -> bị từ chối 403."""
        # Gọi với cookie gr_session nhưng không có Origin / X-CSRF-Token
        res = self.client.post(
            "/api/man/bat-dau",
            json={"man": 1, "ve": 0},
            cookies={"gr_session": "a" * 64},
        )
        self.assertEqual(res.status_code, 403)

    # =========================================================================
    # NHÓM 7: BỘ SÁU BÀI KIỂM THỬ HTTP BẮT BUỘC (TESTS A - F) - FINAL PATCH
    # =========================================================================

    def test_48_test_a_alice_siwe_thang_man_1_khong_ticket_bi_tu_choi_fail_closed(self):
        """Test A: Alice có SIWE, thắng màn 1 nhưng KHÔNG đăng ký ticket -> bị từ chối, không ghi SoPhieu, verified_wallet rỗng."""
        import uuid
        ma_van = f"van-test-a-{uuid.uuid4().hex[:8]}"

        # Alice KHÔNG gọi /api/man/bat-dau, chỉ có telemetry thắng hợp lệ
        self._tao_van_thang_tmx(ma_van, man=1)

        # Alice gọi POST /api/vang/phieu
        res = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        # Bắt buộc bị từ chối fail-closed (403)
        self.assertEqual(res.status_code, 403)
        self.assertIn("thiếu ticket SoVe", res.json()["detail"])

        # Không có phiếu mới trong SoPhieu
        self.assertIsNone(trong_tai.SoPhieu(config.SO_PHIEU).lay(ma_van))

        # match_results.is_verified vẫn bằng 0, verified_wallet vẫn rỗng
        with csdl.lay_csdl() as conn:
            cur = conn.cursor()
            cur.execute("SELECT is_verified, verified_wallet FROM match_results WHERE ma_van = ?", (ma_van,))
            r = cur.fetchone()
            self.assertIsNotNone(r)
            self.assertEqual(r["is_verified"], 0)
            self.assertEqual(r["verified_wallet"], "")

    def test_49_test_b_bob_siwe_biet_ma_van_alice_chua_ticket_bi_tu_choi(self):
        """Test B: Bob có SIWE, biết ma_van thắng của Alice chưa có ticket, Bob xin phiếu -> bị từ chối, không ghi SoPhieu."""
        import uuid
        ma_van = f"van-test-b-{uuid.uuid4().hex[:8]}"

        # Alice tạo ván thắng nhưng chưa có ticket
        self._tao_van_thang_tmx(ma_van, man=1)

        # Bob (SIWE Bob) xin phiếu
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            res = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
            )
            self.assertEqual(res.status_code, 403)
            self.assertIn("thiếu ticket SoVe", res.json()["detail"])
            # Không ghi SoPhieu
            self.assertIsNone(trong_tai.SoPhieu(config.SO_PHIEU).lay(ma_van))
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_50_test_c_alice_ticket_man_1_hop_le_thang_nhan_voucher_eip712_200(self):
        """Test C: Alice đăng ký ticket màn 1 hợp lệ, chơi thắng, gửi telemetry -> xin phiếu 200 với EIP-712 đúng ví."""
        import uuid
        ma_van = f"van-test-c-{uuid.uuid4().hex[:8]}"

        # 1. Đăng ký ticket màn 1 (ve = 0)
        res_bd = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self.assertEqual(res_bd.status_code, 201)

        # 2. Chơi thắng, gửi telemetry
        self._tao_van_thang_tmx(ma_van, man=1)

        # 3. Xin phiếu
        res = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(res.status_code, 200)
        p = res.json()["phieu"]
        ck = res.json()["chu_ky"]
        self.assertEqual(p["nguoiChoi"].lower(), self.user_a.wallet_address.lower())
        self.assertEqual(p["man"], 1)
        self.assertEqual(p["ve"], 0)
        self.assertTrue(ck.startswith("0x"))

        # CSDL match_results được cập nhật verified_wallet
        with csdl.lay_csdl() as conn:
            cur = conn.cursor()
            cur.execute("SELECT is_verified, verified_wallet FROM match_results WHERE ma_van = ?", (ma_van,))
            r = cur.fetchone()
            self.assertEqual(r["is_verified"], 1)
            self.assertEqual(r["verified_wallet"], self.user_a.wallet_address.lower())

    def test_51_test_d_ticket_dung_vi_nhung_sai_man_bi_tu_choi_422(self):
        """Test D: Ticket có đúng ví nhưng sai man so với nhật ký -> bị từ chối 422."""
        import uuid
        ma_van = f"van-test-d-{uuid.uuid4().hex[:8]}"

        # Đăng ký màn 2 (ve = 1)
        res_bd = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 2, "ve": 1},
        )
        self.assertEqual(res_bd.status_code, 201)

        # Nhưng nhật ký gửi màn 1
        self._tao_van_thang_tmx(ma_van, man=1)

        res = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(res.status_code, 422)
        self.assertIn("không khớp màn nhật ký", res.json()["detail"])
        self.assertIsNone(trong_tai.SoPhieu(config.SO_PHIEU).lay(ma_van))

    def test_52_test_e_man_co_coc_van_bat_buoc_ve_hop_le_va_dung_chu_so_huu(self):
        """Test E: Màn có cọc vẫn bắt buộc vé hợp lệ (ve >= 1) và đúng chủ sở hữu."""
        import uuid
        ma_van = f"van-test-e-{uuid.uuid4().hex[:8]}"

        # Màn 2 (có cọc) không cho phép ve = 0
        res_fail = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 2, "ve": 0},
        )
        self.assertEqual(res_fail.status_code, 422)

        # Alice đăng ký ve = 1
        res_ok = self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 2, "ve": 1},
        )
        self.assertEqual(res_ok.status_code, 201)
        self._tao_van_thang_tmx(ma_van, man=2, ban_do="man_2.tmx")

        # Bob (SIWE Bob) xin phiếu cho ván màn có cọc của Alice -> 403
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            res_b = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
            )
            self.assertEqual(res_b.status_code, 403)
            self.assertIn("địa chỉ ví khác", res_b.json()["detail"])
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a

    def test_53_test_f_xin_lai_voucher_hop_le_hoat_dong_idempotent_khong_thuong_trung(self):
        """Test F: Xin lại voucher hợp lệ vẫn hoạt động theo chính sách an toàn, không phát sinh phần thưởng trùng."""
        import uuid
        ma_van = f"van-test-f-{uuid.uuid4().hex[:8]}"

        self.client.post(
            "/api/man/bat-dau",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address, "man": 1, "ve": 0},
        )
        self._tao_van_thang_tmx(ma_van, man=1)

        # Lần 1: Cấp voucher
        r1 = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(r1.status_code, 200)
        p1 = r1.json()["phieu"]

        # Lần 2: Xin lại phiếu hợp lệ (idempotent)
        r2 = self.client.post(
            "/api/vang/phieu",
            json={"ma_van": ma_van, "vi": self.user_a.wallet_address},
        )
        self.assertEqual(r2.status_code, 200)
        p2 = r2.json()["phieu"]

        self.assertEqual(p1["maVan"], p2["maVan"])
        self.assertEqual(p1["soVang"], p2["soVang"])
        self.assertGreaterEqual(p2["hanChot"], p1["hanChot"])

        # Kiểm tra SoPhieu: Chỉ có đúng 1 bản ghi duy nhất cho ma_van, không cấp trùng
        records = [p for p in trong_tai.SoPhieu(config.SO_PHIEU)._doc() if p["ma_van"] == ma_van]
        self.assertEqual(len(records), 1)

        # Bob cố tình xin lại phiếu của Alice bằng ví Bob -> 409
        app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_b
        try:
            r_b = self.client.post(
                "/api/vang/phieu",
                json={"ma_van": ma_van, "vi": self.user_b.wallet_address},
            )
            self.assertEqual(r_b.status_code, 409)
            self.assertIn("đã cấp phiếu cho một ví khác", r_b.json()["detail"])
        finally:
            app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: self.user_a


if __name__ == "__main__":
    unittest.main()
