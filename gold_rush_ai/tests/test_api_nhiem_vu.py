"""API nhiệm vụ: context server/demo, service và SQLite thật trong thư mục tạm."""
from contextlib import contextmanager
from dataclasses import replace
from pathlib import Path
import json
import sqlite3

from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

TILES = Path(__file__).resolve().parents[2] / "gold_rush" / "assets" / "tiles"
URL = "/api/ai/nhiem-vu/tao"
HEADERS = {"Idempotency-Key": "request_1", "X-Demo-Player": "demo_player"}


@contextmanager
def client(tmp_path, monkeypatch, *, enabled=True, demo=True, backend_context=None, **env):
    import config
    from api.nhiem_vu import khoi_dong_nhiem_vu, router

    monkeypatch.setattr(config, "ENABLED", {"nhiem_vu"} if enabled else set())
    monkeypatch.setattr(config, "MAN_CHOI", TILES / "man_choi.json")
    monkeypatch.setattr(config, "BAN_DO_DIR", TILES)
    monkeypatch.setenv("AI_QUEST_DB", str(tmp_path / "quests.sqlite3"))
    monkeypatch.setenv("AI_QUEST_DEMO", "true" if demo else "false")
    monkeypatch.setenv("LLM_ENABLED", "false")
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    app = FastAPI()
    if backend_context is not None:
        @app.middleware("http")
        async def gan_context(request, call_next):
            request.state.ai_quest_player = backend_context
            return await call_next(request)
    app.include_router(router)
    khoi_dong_nhiem_vu(app)
    with TestClient(app) as c:
        yield c, app


def tao(c, stage=1, headers=None, **body):
    return c.post(URL, json={"stage_id": stage, **body}, headers=HEADERS if headers is None else headers)


def test_demo_tra_quest_hop_le_voi_nhan_ngu_canh_ro_rang(tmp_path, monkeypatch):
    from api.nhiem_vu import PhanHoiNhiemVu

    with client(tmp_path, monkeypatch) as (c, _):
        r = tao(c)
    assert r.status_code == 200
    nv = PhanHoiNhiemVu.model_validate(r.json())
    assert nv.context_source == "demo"
    assert nv.stage_id == 1
    assert nv.generation_source == "rule_based"
    assert nv.reward.gold == 0


def test_retry_cung_key_giu_ket_qua_va_khong_luu_trung(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, _):
        mot, hai = tao(c), tao(c)
    assert mot.status_code == hai.status_code == 200
    assert mot.json() == hai.json()
    with sqlite3.connect(tmp_path / "quests.sqlite3") as conn:
        assert conn.execute("SELECT COUNT(*) FROM nhiem_vu").fetchone()[0] == 1


def test_key_moi_doc_lich_su_de_tranh_lap(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, _):
        a = tao(c).json()
        b = tao(c, headers={**HEADERS, "Idempotency-Key": "request_2"}).json()
    assert a["id"] != b["id"]
    assert (a["objective"], a["target"], a["time_limit_seconds"]) != (b["objective"], b["target"], b["time_limit_seconds"])


@pytest.mark.parametrize("body", [{}, {"stage_id": True}, {"stage_id": "1"},
    {"stage_id": 0}, {"stage_id": 1, "reward": {"gold": 50}},
    {"stage_id": 1, "do_kho": "hard"}, {"stage_id": 1, "allowed_stage_ids": [1, 2]}])
def test_body_sai_tra_422(tmp_path, monkeypatch, body):
    with client(tmp_path, monkeypatch) as (c, _):
        assert c.post(URL, json=body, headers=HEADERS).status_code == 422


@pytest.mark.parametrize("headers", [
    {"X-Demo-Player": "demo_player"}, {**HEADERS, "Idempotency-Key": "../bad"},
    {**HEADERS, "Idempotency-Key": "x" * 65}, {"Idempotency-Key": "request_1"},
])
def test_header_thieu_hoac_sai_tra_422(tmp_path, monkeypatch, headers):
    with client(tmp_path, monkeypatch) as (c, _):
        assert tao(c, headers=headers).status_code == 422


def test_demo_khong_tu_mo_man_2_va_khong_nhan_player_id_gia(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, _):
        assert tao(c, stage=2).status_code == 403
        assert tao(c, player_id="someone_else").status_code == 403


def test_tat_tinh_nang_tra_404_khong_tao_db(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, enabled=False) as (c, _):
        assert tao(c).status_code == 404
    assert not (tmp_path / "quests.sqlite3").exists()


def test_khong_co_context_that_va_demo_tat_tra_503(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, demo=False) as (c, _):
        assert tao(c).status_code == 503


def test_context_backend_xac_minh_quyet_dinh_man_va_do_kho(tmp_path, monkeypatch):
    from api.nhiem_vu import NguCanhNguoiChoi, lay_ngu_canh_nguoi_choi

    with client(tmp_path, monkeypatch, demo=False) as (c, app):
        app.dependency_overrides[lay_ngu_canh_nguoi_choi] = lambda: NguCanhNguoiChoi(
            player_id="verified_player", allowed_stage_ids=frozenset({2}), difficulty="medium")
        r = tao(c, stage=2, headers={"Idempotency-Key": "request_1"})
        assert r.status_code == 200
        assert r.json()["context_source"] == "verified"
        assert r.json()["difficulty"] == "medium"
        assert tao(c, stage=3).status_code == 403
        assert tao(c, stage=2, player_id="fake").status_code == 403


def test_cung_request_doi_man_duoc_phep_tra_409(tmp_path, monkeypatch):
    from api.nhiem_vu import NguCanhNguoiChoi, lay_ngu_canh_nguoi_choi

    with client(tmp_path, monkeypatch) as (c, app):
        app.dependency_overrides[lay_ngu_canh_nguoi_choi] = lambda: NguCanhNguoiChoi(
            player_id="verified_player", allowed_stage_ids=frozenset({1, 2}))
        assert tao(c).status_code == 200
        assert tao(c, stage=2).status_code == 409


def test_man_duoc_context_cho_phep_nhung_khong_ton_tai_tra_404(tmp_path, monkeypatch):
    from api.nhiem_vu import NguCanhNguoiChoi, lay_ngu_canh_nguoi_choi

    with client(tmp_path, monkeypatch) as (c, app):
        app.dependency_overrides[lay_ngu_canh_nguoi_choi] = lambda: NguCanhNguoiChoi(
            player_id="verified_player", allowed_stage_ids=frozenset({999}))
        assert tao(c, stage=999).status_code == 404


def test_demo_khong_goi_llm_ke_ca_khi_da_cau_hinh_provider(tmp_path, monkeypatch):
    class KhongDuocGoi:
        def sinh(self, **kw):
            raise AssertionError("Demo không được gọi provider")

    with client(tmp_path, monkeypatch) as (c, app):
        app.state.nhiem_vu.service.provider = KhongDuocGoi()
        assert tao(c).json()["generation_source"] == "rule_based"


def test_loi_kho_tra_503_khong_lo_duong_dan(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, _):
        (tmp_path / "quests.sqlite3").write_bytes(b"broken database")
        r = tao(c)
    assert r.status_code == 503
    assert str(tmp_path) not in r.text


def test_manifest_hong_khong_lam_sap_app(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, app):
        import config
        from api.nhiem_vu import khoi_dong_nhiem_vu
        monkeypatch.setattr(config, "MAN_CHOI", tmp_path / "missing.json")
        khoi_dong_nhiem_vu(app)
        assert tao(c).status_code == 503


@pytest.mark.parametrize("sai", [{"id": 1.0}, {"id": True}, {"id": 1001},
                                 {"so_xu": 24.0}, {"gioi_han_giay": "0"}, {"gioi_han_giay": -1}])
def test_manifest_sai_kieu_hoac_mien_gia_tri_phai_tat_component(tmp_path, monkeypatch, sai):
    import config
    from api.nhiem_vu import khoi_dong_nhiem_vu, nhiem_vu_da_nap

    data = json.loads((TILES / "man_choi.json").read_text(encoding="utf-8"))
    data["man"][0].update(sai)
    tep = tmp_path / "man_bad.json"
    tep.write_text(json.dumps(data), encoding="utf-8")
    with client(tmp_path, monkeypatch) as (c, app):
        monkeypatch.setattr(config, "MAN_CHOI", tep)
        khoi_dong_nhiem_vu(app)
        assert nhiem_vu_da_nap(app) is False
        assert tao(c).status_code == 503


def test_llm_config_sai_van_co_the_chay_offline(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, LLM_ENABLED="true", LLM_CHAT_URL="", LLM_MODEL="") as (c, _):
        assert tao(c).status_code == 200


def test_context_tu_middleware_noi_duoc_llm_va_luu_ket_qua(tmp_path, monkeypatch):
    from api.nhiem_vu import NguCanhNguoiChoi

    class ProviderNoiDung:
        def sinh(self, *, system_prompt, user_prompt):
            quest = json.loads(user_prompt)["quest"]
            quest["title"] = "Nhiệm vụ từ LLM"
            return json.dumps(quest, ensure_ascii=False)
    ctx = NguCanhNguoiChoi(player_id="server_player", allowed_stage_ids=frozenset({2}))
    with client(tmp_path, monkeypatch, demo=False, backend_context=ctx) as (c, app):
        app.state.nhiem_vu.service.provider = ProviderNoiDung()
        r = tao(c, stage=2, headers={"Idempotency-Key": "request_1"})
        assert r.status_code == 200
        assert r.json()["context_source"] == "verified"
        assert r.json()["generation_source"] == "llm"
        assert r.json()["title"] == "Nhiệm vụ từ LLM"
        assert tao(c, stage=2, headers={"Idempotency-Key": "request_1"}).json() == r.json()


def test_demo_va_verified_khong_chung_namespace_lich_su(tmp_path, monkeypatch):
    from api.nhiem_vu import NguCanhNguoiChoi, lay_ngu_canh_nguoi_choi

    with client(tmp_path, monkeypatch) as (c, app):
        demo = tao(c).json()
        app.dependency_overrides[lay_ngu_canh_nguoi_choi] = lambda: NguCanhNguoiChoi(
            player_id="demo_player", allowed_stage_ids=frozenset({1}))
        verified = tao(c).json()
        assert demo["id"] != verified["id"]
        assert demo["context_source"] == "demo"
        assert verified["context_source"] == "verified"
    with sqlite3.connect(tmp_path / "quests.sqlite3") as conn:
        assert conn.execute("SELECT COUNT(DISTINCT player_id) FROM nhiem_vu").fetchone()[0] == 2


def test_khong_co_nhiem_vu_kha_thi_tra_422(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, app):
        state = app.state.nhiem_vu
        state.cac_man[1] = replace(state.cac_man[1], gioi_han_giay=1)
        assert tao(c).status_code == 422


def test_router_da_dang_ky_trong_app_chung(tmp_path, monkeypatch):
    import api.main
    import config
    monkeypatch.setattr(config, "ENABLED", {"nhiem_vu"})
    monkeypatch.setenv("AI_QUEST_DB", str(tmp_path / "quests.sqlite3"))
    monkeypatch.setenv("AI_QUEST_DEMO", "true")
    monkeypatch.setenv("LLM_ENABLED", "false")
    with TestClient(api.main.app) as c:
        assert tao(c).status_code == 200
        assert c.get("/api/health").json()["da_nap"]["nhiem_vu"] is True
