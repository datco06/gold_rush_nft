from contextlib import contextmanager
from pathlib import Path
import sqlite3
import asyncio

from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest
from pydantic import ValidationError

from core.nhat_ky import NhatKyVan

APP = Path(__file__).resolve().parents[2] / "gold_rush"
QUEST = "/api/ai/nhiem-vu/tao"
DIFFICULTY = "/api/ai/do-kho/de-xuat"
IMAGE = "/api/ai/nhan-vat/tao"
CALLS = [(QUEST, {"stage_id":1}), (DIFFICULTY, {"stage_id":1}),
         (IMAGE, {"description":"Thợ mỏ"})]
HEADERS = {"Authorization":"Bearer session_a", "Idempotency-Key":"request_1"}


def snapshot(player="player_a", completed=frozenset(range(1, 7)), **kw):
    from core.ngu_canh_ai import BanChupNguoiChoiAI
    return BanChupNguoiChoiAI(player_id=player, level=8,
        allowed_stage_ids=frozenset(range(1, 8)), completed_stage_ids=completed, **kw)


@contextmanager
def client(tmp_path, monkeypatch, source, *, demo=False, source_timeout=5):
    import config
    from api.ngu_canh_ai import gan_nguon_du_lieu_ai
    from api.nhiem_vu import khoi_dong_nhiem_vu, router as quests
    from api.de_xuat_do_kho import khoi_dong_de_xuat_do_kho, router as difficulty
    from api.nhan_vat_ai import khoi_dong_nhan_vat_ai, router as images
    monkeypatch.setattr(config, "ENABLED", {"nhiem_vu", "de_xuat_do_kho", "nhan_vat_ai"})
    monkeypatch.setattr(config, "APP_FLUTTER", APP)
    monkeypatch.setattr(config, "BAN_DO_DIR", APP / "assets/tiles")
    monkeypatch.setattr(config, "MAN_CHOI", APP / "assets/tiles/man_choi.json")
    for name in ("AI_QUEST_DEMO", "AI_DIFFICULTY_DEMO", "AI_IMAGE_DEMO"):
        monkeypatch.setenv(name, "true" if demo else "false")
    for name in ("LLM_ENABLED", "AI_IMAGE_ENABLED"):
        monkeypatch.setenv(name, "false")
    monkeypatch.setenv("AI_QUEST_DB", str(tmp_path / "quests.sqlite3"))
    monkeypatch.setenv("AI_IMAGE_DB", str(tmp_path / "images.sqlite3"))
    app = FastAPI()
    for router in (quests, difficulty, images):
        app.include_router(router)
    gan_nguon_du_lieu_ai(app, source, thoi_gian_cho=source_timeout)
    khoi_dong_nhiem_vu(app)
    khoi_dong_de_xuat_do_kho(app)
    khoi_dong_nhan_vat_ai(app)
    with TestClient(app) as c:
        yield c, app


def test_nguon_chung_cap_dung_nguoi_ho_so_va_quyen_cho_ba_api(tmp_path, monkeypatch):
    history = tuple(NhatKyVan(ma_van=f"game-{i:04d}", phien_ban_app="1.3.0",
        ket_qua="thang", diem=480, giay=120) for i in range(3))
    a = snapshot(recent_history=history, previous_speed_multipliers={1:1.1})
    b = snapshot("player_b")
    async def source(request):
        return {"Bearer session_a":a, "Bearer session_b":b}.get(request.headers.get("Authorization"))
    with client(tmp_path, monkeypatch, source) as (c, _):
        quest = c.post(QUEST, json={"stage_id":1}, headers=HEADERS)
        assert quest.status_code == 200
        assert quest.json()["context_source"] == "verified"
        assert quest.json()["difficulty"] == "hard"
        diff = c.post(DIFFICULTY, json={"stage_id":1}, headers=HEADERS)
        assert diff.status_code == 200
        assert diff.json()["sample_count"] == 3
        assert diff.json()["adjustments"]["enemy_speed_multiplier"] == 1.15
        image = c.post(IMAGE, json={"description":"Thợ mỏ"}, headers=HEADERS)
        assert image.status_code == 200
        url = image.json()["image_url"]
        assert c.get(url, headers=HEADERS).status_code == 200
        assert c.get(url, headers={"Authorization":"Bearer session_b"}).status_code == 404
        assert c.post(QUEST, json={"stage_id":8}, headers=HEADERS).status_code == 403


@pytest.mark.parametrize("path,body", CALLS)
def test_chua_xac_thuc_khong_duoc_roi_ve_demo(tmp_path, monkeypatch, path, body):
    async def source(request):
        return None
    with client(tmp_path, monkeypatch, source, demo=True) as (c, _):
        r = c.post(path, json=body, headers={**HEADERS,"X-Demo-Player":"fake"})
        assert r.status_code == 401


@pytest.mark.parametrize("path,body", CALLS)
@pytest.mark.parametrize("kind", ["error", "dict", "invalid"])
def test_nguon_loi_hoac_snapshot_sai_tra_503_khong_ro_ve_demo(tmp_path, monkeypatch, path, body, kind):
    good = snapshot()
    async def source(request):
        if kind == "error":
            raise RuntimeError("secret-path token-private")
        if kind == "dict":
            return {"player_id":"fake"}
        return good.model_copy(update={"level": True})
    with client(tmp_path, monkeypatch, source, demo=True) as (c, _):
        r = c.post(path, json=body, headers={**HEADERS,"X-Demo-Player":"fake"})
        assert r.status_code == 503
        assert "secret-path" not in r.text and "token-private" not in r.text


@pytest.mark.parametrize("completed", [frozenset(), frozenset(range(1, 6)), frozenset(range(2, 8))])
def test_tao_anh_can_hoan_thanh_dung_sau_man_khong_chi_mo_khoa(tmp_path, monkeypatch, completed):
    snap = snapshot(completed=completed)
    async def source(request):
        return snap
    class KhongDuocGoi:
        generation_source = "image_model"
        def sinh(self, **kw):
            raise AssertionError("Chưa đủ quyền không được gọi provider")
    with client(tmp_path, monkeypatch, source, demo=True) as (c, app):
        app.state.nhan_vat_ai.service.provider = KhongDuocGoi()
        assert c.post(IMAGE, json={"description":"Thợ mỏ"},
                      headers={**HEADERS,"X-Demo-Player":"fake"}).status_code == 403
    with sqlite3.connect(tmp_path / "quota.sqlite3") as conn:
        assert conn.execute("SELECT COUNT(*) FROM quota_ai").fetchone()[0] == 0


def test_quyen_tao_anh_duoc_kiem_tra_lai_nhung_anh_cu_van_doc_dung_chu(tmp_path, monkeypatch):
    current = [snapshot()]
    async def source(request):
        return current[0]
    with client(tmp_path, monkeypatch, source) as (c, _):
        first = c.post(IMAGE, json={"description":"Thợ mỏ"}, headers=HEADERS)
        assert first.status_code == 200
        current[0] = snapshot(completed=frozenset(range(1, 6)))
        assert c.post(IMAGE, json={"description":"Thợ mỏ"}, headers=HEADERS).status_code == 403
        assert c.get(first.json()["image_url"], headers=HEADERS).status_code == 200
        assert c.post(IMAGE, json={"description":"Thợ mỏ", "completed_stage_ids":[1,2,3,4,5,6]},
                      headers=HEADERS).status_code == 422


def test_do_kho_chon_dung_lich_su_va_he_so_theo_man_request(tmp_path, monkeypatch):
    from core.man_choi import doc
    m = doc(APP / "assets/tiles/man_choi.json")[2]
    history = tuple(NhatKyVan(ma_van=f"game-{i:04d}", phien_ban_app="1.3.0", man=2,
        ban_do=m.tep, ket_qua="thua", diem=0, giay=120) for i in range(3))
    snap = snapshot(recent_history=history, previous_speed_multipliers={1:0.95,2:1.1})
    async def source(request):
        return snap
    with client(tmp_path, monkeypatch, source) as (c, _):
        r = c.post(DIFFICULTY, json={"stage_id":2}, headers=HEADERS)
        assert r.status_code == 200
        assert r.json()["difficulty"] == "easy"
        assert r.json()["adjustments"]["enemy_speed_multiplier"] == 1.05
        assert c.post(DIFFICULTY, json={"stage_id":8}, headers=HEADERS).status_code == 403
        assert c.post(DIFFICULTY, json={"stage_id":1,"previous_speed_multipliers":{1:0.8}},
                      headers=HEADERS).status_code == 422


def test_snapshot_tu_choi_tien_trinh_mau_thuan_va_he_so_sai():
    from core.ngu_canh_ai import BanChupNguoiChoiAI
    with pytest.raises(ValidationError):
        BanChupNguoiChoiAI(player_id="a",level=1,allowed_stage_ids=frozenset({1}),
                           completed_stage_ids=frozenset({1,2}))
    with pytest.raises(ValidationError):
        snapshot(previous_speed_multipliers={1:float("nan")})
    with pytest.raises(ValidationError):
        snapshot(previous_speed_multipliers={True:1.0})


def test_nguon_qua_han_bi_huy_va_tra_503(tmp_path, monkeypatch):
    da_huy = []
    async def source(request):
        try:
            await asyncio.Event().wait()
        finally:
            da_huy.append(True)
    with client(tmp_path, monkeypatch, source, demo=True, source_timeout=0.01) as (c, _):
        r = c.post(QUEST, json={"stage_id":1}, headers={**HEADERS,"X-Demo-Player":"fake"})
        assert r.status_code == 503
    assert da_huy == [True]


@pytest.mark.parametrize("timeout", [True, 0, float("nan"), 61])
def test_dang_ky_nguon_tu_choi_timeout_sai(timeout):
    from api.ngu_canh_ai import gan_nguon_du_lieu_ai
    async def source(request):
        return None
    with pytest.raises(ValueError):
        gan_nguon_du_lieu_ai(FastAPI(), source, thoi_gian_cho=timeout)
