"""API đề xuất độ khó với lịch sử do backend cung cấp và demo có nhãn."""
from contextlib import contextmanager
import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

from core.nhat_ky import NhatKyVan

TILES = Path(__file__).resolve().parents[2] / "gold_rush" / "assets" / "tiles"
URL = "/api/ai/do-kho/de-xuat"
HEADERS = {"X-Demo-Player": "demo_player"}


def ngu_canh(*, stage=1, allowed=None, history=(), previous=1.0, source="verified"):
    from api.de_xuat_do_kho import NguCanhDeXuatDoKho
    from api.nhiem_vu import NguCanhNguoiChoi
    return NguCanhDeXuatDoKho(
        nguoi_choi=NguCanhNguoiChoi(player_id="player_1",
            allowed_stage_ids=frozenset({stage} if allowed is None else allowed), context_source=source),
        stage_id=stage, lich_su=tuple(history), he_so_truoc=previous)


def van(i, ket_qua="thang", xu=24, **kw):
    return NhatKyVan(ma_van=f"game-{i:04d}", phien_ban_app="1.3.0", ket_qua=ket_qua,
                     diem=xu * 20, giay=120, **kw)


@contextmanager
def client(monkeypatch, *, enabled=True, demo=True, context=None, manifest=None, **env):
    import config
    from api.de_xuat_do_kho import khoi_dong_de_xuat_do_kho, router
    monkeypatch.setattr(config, "ENABLED", {"de_xuat_do_kho"} if enabled else set())
    monkeypatch.setattr(config, "MAN_CHOI", manifest or TILES / "man_choi.json")
    monkeypatch.setenv("AI_DIFFICULTY_DEMO", "true" if demo else "false")
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    app = FastAPI()
    if context is not None:
        @app.middleware("http")
        async def gan_context(request, call_next):
            request.state.ai_difficulty_context = context
            return await call_next(request)
    app.include_router(router)
    khoi_dong_de_xuat_do_kho(app)
    with TestClient(app) as c:
        yield c, app


def goi(c, stage=1, headers=None, **body):
    return c.post(URL, json={"stage_id": stage, **body}, headers=HEADERS if headers is None else headers)


def test_demo_chi_tra_fallback_trung_tinh_va_co_nhan(monkeypatch):
    with client(monkeypatch) as (c, _):
        r = goi(c)
    assert r.status_code == 200
    data = r.json()
    assert data["context_source"] == "demo"
    assert data["stage_id"] == 1
    assert data["source"] == "fallback"
    assert data["difficulty"] == "medium"
    assert data["performance_score"] is None
    assert data["sample_count"] == 0
    assert data["adjustments"] == {"enemy_speed_multiplier": 1.0}


@pytest.mark.parametrize("cac_van,do_kho,score,he_so", [
    ([van(i, "thua", 6) for i in range(4)], "easy", 0.075, 0.95),
    ([van(0), van(1), van(2, "thua", 12), van(3, "thua", 12)], "medium", 0.575, 1.03),
    ([van(i) for i in range(4)], "hard", 1.0, 1.05),
], ids=["yeu", "trung-binh", "gioi"])
def test_ngu_canh_backend_tao_de_xuat_theo_lich_su(monkeypatch, cac_van, do_kho, score, he_so):
    ctx = ngu_canh(history=cac_van)
    with client(monkeypatch, demo=False, context=ctx) as (c, _):
        r = goi(c, headers={})
    assert r.status_code == 200
    data = r.json()
    assert data["context_source"] == "verified"
    assert data["source"] == "rule_based"
    assert data["difficulty"] == do_kho
    assert data["performance_score"] == pytest.approx(score)
    assert data["adjustments"]["enemy_speed_multiplier"] == pytest.approx(he_so)
    assert data["sample_count"] == 4


def test_fallback_cua_nguoi_moi_van_la_ngu_canh_verified(monkeypatch):
    with client(monkeypatch, demo=False, context=ngu_canh(previous=1.15)) as (c, _):
        data = goi(c, headers={}).json()
    assert data["context_source"] == "verified"
    assert data["source"] == "fallback"
    assert data["adjustments"]["enemy_speed_multiplier"] == 1.1


def test_gui_lai_khong_tu_tang_he_so_va_khong_sua_ngu_canh(monkeypatch):
    ctx = ngu_canh(history=[van(i) for i in range(3)])
    with client(monkeypatch, context=ctx) as (c, _):
        a, b = goi(c), goi(c)
    assert a.status_code == b.status_code == 200
    assert a.json() == b.json()
    assert ctx.he_so_truoc == 1.0
    assert ctx.lich_su[0].diem == 480


@pytest.mark.parametrize("body", [{}, {"stage_id": True}, {"stage_id": "1"},
    {"stage_id": 0}, {"stage_id": 1001}, {"stage_id": 1, "player_id": "other"},
    {"stage_id": 1, "history": []}, {"stage_id": 1, "he_so_truoc": 1.15},
    {"stage_id": 1, "allowed_stage_ids": [1, 2]}])
def test_client_khong_duoc_gui_lich_su_quyen_hoac_he_so(monkeypatch, body):
    with client(monkeypatch) as (c, _):
        assert c.post(URL, json=body, headers=HEADERS).status_code == 422


@pytest.mark.parametrize("headers", [{}, {"X-Demo-Player": "../bad"}, {"X-Demo-Player": "x" * 65}])
def test_demo_can_header_hop_le(monkeypatch, headers):
    with client(monkeypatch) as (c, _):
        assert goi(c, headers=headers).status_code == 422


def test_demo_khong_mo_duoc_man_2(monkeypatch):
    with client(monkeypatch) as (c, _):
        assert goi(c, stage=2).status_code == 403


def test_quyen_va_man_cua_context_phai_khop_request(monkeypatch):
    with client(monkeypatch, context=ngu_canh(stage=1, allowed={1, 2})) as (c, _):
        assert goi(c, stage=2).status_code == 403
    with client(monkeypatch, context=ngu_canh(allowed=set())) as (c, _):
        assert goi(c).status_code == 403


def test_man_duoc_phep_nhung_khong_ton_tai_tra_404(monkeypatch):
    with client(monkeypatch, context=ngu_canh(stage=999)) as (c, _):
        assert goi(c, stage=999).status_code == 404


def test_demo_context_cung_khong_duoc_dung_lich_su_gia_lam_ca_nhan_hoa(monkeypatch):
    ctx = ngu_canh(history=[van(i) for i in range(3)], previous=1.15, source="demo")
    with client(monkeypatch, context=ctx) as (c, _):
        data = goi(c).json()
    assert data["context_source"] == "demo"
    assert data["sample_count"] == 0
    assert data["adjustments"]["enemy_speed_multiplier"] == 1.0


def test_tat_tinh_nang_tra_404_ke_ca_manifest_khong_co(monkeypatch, tmp_path):
    with client(monkeypatch, enabled=False, manifest=tmp_path / "missing.json") as (c, _):
        assert goi(c).status_code == 404


def test_thieu_context_that_va_demo_tat_tra_503(monkeypatch):
    with client(monkeypatch, demo=False) as (c, _):
        assert goi(c).status_code == 503


@pytest.mark.parametrize("context", [{"player_id": "fake"}, "fake"])
def test_context_server_sai_kieu_tra_503(monkeypatch, context):
    with client(monkeypatch, context=context) as (c, _):
        assert goi(c).status_code == 503


def test_nhat_ky_backend_mau_thuan_tra_503_khong_lo_chi_tiet(monkeypatch):
    ctx = ngu_canh(history=[van(0, "thang", 1)])
    with client(monkeypatch, context=ctx) as (c, _):
        r = goi(c)
    assert r.status_code == 503
    assert "diem" not in r.text
    assert "game-0000" not in r.text


def test_context_bi_sua_bang_model_copy_van_duoc_kiem_tra_lai(monkeypatch):
    ctx = ngu_canh().model_copy(update={"he_so_truoc": float("nan")})
    with client(monkeypatch, context=ctx) as (c, _):
        assert goi(c).status_code == 503


def test_context_dependency_co_the_duoc_backend_thay_the(monkeypatch):
    from api.de_xuat_do_kho import lay_ngu_canh_de_xuat
    with client(monkeypatch, demo=False) as (c, app):
        app.dependency_overrides[lay_ngu_canh_de_xuat] = lambda: ngu_canh(stage=2)
        assert goi(c, stage=2, headers={}).status_code == 200


@pytest.mark.parametrize("doi", [{"id": True}, {"id": 1.0}, {"so_xu": 0}, {"so_xu": 24.0}, {"tep": ""}])
def test_manifest_sai_thi_component_khong_san_sang(monkeypatch, tmp_path, doi):
    from api.de_xuat_do_kho import de_xuat_do_kho_da_nap
    payload = json.loads((TILES / "man_choi.json").read_text(encoding="utf-8"))
    payload["man"][0].update(doi)
    tep = tmp_path / "bad.json"
    tep.write_text(json.dumps(payload), encoding="utf-8")
    with client(monkeypatch, manifest=tep) as (c, app):
        assert goi(c).status_code == 503
        assert de_xuat_do_kho_da_nap(app) is False


def test_flag_demo_khong_hop_le_khong_lam_sap_app(monkeypatch):
    with client(monkeypatch, AI_DIFFICULTY_DEMO="bad") as (c, _):
        assert goi(c).status_code == 503


def test_chua_chay_lifespan_tra_503():
    from api.de_xuat_do_kho import router
    app = FastAPI()
    app.include_router(router)
    with TestClient(app) as c:
        assert goi(c).status_code == 503


def test_app_chung_dang_ky_router_va_health(monkeypatch):
    import api.main
    import config
    monkeypatch.setattr(config, "ENABLED", {"de_xuat_do_kho"})
    monkeypatch.setenv("AI_DIFFICULTY_DEMO", "true")
    with TestClient(api.main.app) as c:
        assert goi(c).status_code == 200
        assert c.get("/api/health").json()["da_nap"]["de_xuat_do_kho"] is True
        assert URL in c.get("/openapi.json").json()["paths"]
    assert api.main.app.state.de_xuat_do_kho is None
