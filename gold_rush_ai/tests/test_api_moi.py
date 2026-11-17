"""Kiểm thử tích hợp các endpoint API mới (Tiến trình, Kho đồ, Nhiệm vụ, Bản đồ).

Sử dụng FastAPI TestClient và dependency_overrides để kiểm định bảo mật phiên SIWE.
"""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai
from api.main import app
from core import csdl, quan_ly_nhiem_vu, tien_trinh


class TestApiMoi(unittest.TestCase):
    def setUp(self):
        self.tam_dir = tempfile.mkdtemp()
        self.db_path = Path(self.tam_dir) / "test_api.db"
        import config
        config.CSDL_PATH = self.db_path
        csdl.CSDL_PATH = self.db_path
        csdl.khoi_tao_csdl(self.db_path)

        self.client = TestClient(app)
        self.current_user = NguoiChoiXacThuc(
            user_id="player_test_01",
            wallet_address="0x1111111111111111111111111111111111111111",
        )

        def mock_auth():
            return self.current_user

        app.dependency_overrides[lay_nguoi_choi_hien_tai] = mock_auth

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_api_progress_chua_dang_nhap_bi_tu_choi(self):
        # Bỏ override -> phải fail-closed 401
        app.dependency_overrides.clear()
        res = self.client.get("/api/progress")
        self.assertEqual(res.status_code, 401)

    def test_api_progress_da_xac_thuc(self):
        res = self.client.get("/api/progress")
        self.assertEqual(res.status_code, 200)
        tt = res.json()
        self.assertEqual(tt["player_id"], "player_test_01")
        self.assertEqual(tt["level"], 1)
        self.assertEqual(tt["unlocked_stage_ids"], [1])
        self.assertEqual(tt["equipped_weapon_id"], "kiem_go")
        self.assertEqual(tt["equipped_character_id"], "george")

    def test_api_inventory_va_equipment(self):
        # Lấy kho đồ
        res = self.client.get("/api/inventory")
        self.assertEqual(res.status_code, 200)
        kd = res.json()
        self.assertGreaterEqual(kd["so_luong_vat_pham"], 2)

        # Đổi sang trang bị có sẵn
        res_doi = self.client.post(
            "/api/equipment/select",
            json={"loai": "weapon", "item_id": "kiem_go"},
        )
        self.assertEqual(res_doi.status_code, 200)
        self.assertTrue(res_doi.json()["thanh_cong"])

        # Đổi sang trang bị chưa sở hữu -> 400
        res_sai = self.client.post(
            "/api/equipment/select",
            json={"loai": "weapon", "item_id": "kiem_huyen_thoai"},
        )
        self.assertEqual(res_sai.status_code, 400)

    def test_api_quests_va_ai_context(self):
        # 1. External client (kể cả có SIWE) bị từ chối 403 khi gọi HTTP ai-assign
        res_ext = self.client.post("/api/quests/ai-assign")
        self.assertEqual(res_ext.status_code, 403)

        # 2. Dịch vụ AI nội bộ tạo nhiệm vụ qua hàm nghiệp vụ server tao_nhiem_vu_ai_noi_bo
        with csdl.lay_csdl() as conn:
            q = quan_ly_nhiem_vu.tao_nhiem_vu_ai_noi_bo(
                conn,
                player_id="player_test_01",
                title="Săn vàng hang động",
                description="Nhặt 15 xu trong màn 2",
                target_type="nhat_xu",
                target_count=15,
                reward_exp=50,
            )
            qid = q["quest_id"]

        # 3. Lấy danh sách nhiệm vụ active
        res_act = self.client.get("/api/quests/active")
        self.assertEqual(res_act.status_code, 200)
        self.assertEqual(res_act.json()["tong_so"], 1)

        # 4. Lấy ngữ cảnh cho AI
        res_ctx = self.client.get("/api/quests/ai-context")
        self.assertEqual(res_ctx.status_code, 200)
        ctx = res_ctx.json()
        self.assertEqual(ctx["player_id"], "player_test_01")
        self.assertIn("nhat_xu", ctx["muc_tieu_hop_le"])

        # 5. Giả lập người chơi hoàn thành nhiệm vụ và nhận thưởng
        with csdl.lay_csdl() as conn:
            quan_ly_nhiem_vu.cap_nhat_tien_do(conn, "player_test_01", "nhat_xu", 15)

        res_claim = self.client.post(
            "/api/quests/claim",
            json={"quest_id": qid},
        )
        self.assertEqual(res_claim.status_code, 200)
        self.assertEqual(res_claim.json()["ket_qua"]["reward_exp"], 50)

        # Kiểm tra EXP sau nhận thưởng
        res_tt = self.client.get("/api/progress")
        self.assertEqual(res_tt.json()["exp"], 50)
        self.assertEqual(res_tt.json()["level"], 1)

    def test_api_maps(self):
        # 1. Cấu hình bản đồ
        res_cfg = self.client.get("/api/maps/config")
        self.assertEqual(res_cfg.status_code, 200)
        self.assertEqual(res_cfg.json()["phien_ban_thuat_toan"], "v1.3")

        # 2. Sinh bản đồ metadata theo seed
        res_gen = self.client.get("/api/maps/generate?seed=7&mat_do=0.36&dinh_dang=json")
        self.assertEqual(res_gen.status_code, 200)
        self.assertEqual(res_gen.json()["seed"], 7)

        # 3. Quét pool bản đồ
        res_pool = self.client.get("/api/maps/pool")
        self.assertEqual(res_pool.status_code, 200)
        self.assertGreater(res_pool.json()["tong_so_ban_do"], 0)


if __name__ == "__main__":
    unittest.main()
