from contextlib import contextmanager
from io import BytesIO
from pathlib import Path
import sqlite3

from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
import pytest

ASSETS = Path(__file__).resolve().parents[2] / "gold_rush/assets/images"
URL = "/api/ai/nhan-vat/tao"
HEADERS = {"X-Demo-Player": "demo_a", "Idempotency-Key": "request_1"}


def nguoi_da_hoan_thanh(player_id):
    from api.nhan_vat_ai import NguCanhAnhNhanVat
    return NguCanhAnhNhanVat(player_id=player_id, allowed_stage_ids=frozenset(range(1, 7)),
                             completed_stage_ids=frozenset(range(1, 7)))


@contextmanager
def client(tmp_path, monkeypatch, *, enabled=True, demo=True, context=None, **env):
    import config
    from api.nhan_vat_ai import khoi_dong_nhan_vat_ai, router
    monkeypatch.setattr(config, "ENABLED", {"nhan_vat_ai"} if enabled else set())
    monkeypatch.setattr(config, "APP_FLUTTER", ASSETS.parents[1])
    monkeypatch.setenv("AI_IMAGE_DB", str(tmp_path / "images.sqlite3"))
    monkeypatch.setenv("AI_IMAGE_ENABLED", "false")
    monkeypatch.setenv("AI_IMAGE_DEMO", "true" if demo else "false")
    monkeypatch.setenv("AI_IMAGE_TTL_SECONDS", "86400")
    monkeypatch.setenv("AI_IMAGE_MAX_IMAGES", "200")
    for name, value in env.items():
        monkeypatch.setenv(name, value)
    app = FastAPI()
    if context is not None:
        @app.middleware("http")
        async def gan_context(request, call_next):
            request.state.ai_image_player = context
            return await call_next(request)
    app.include_router(router)
    khoi_dong_nhan_vat_ai(app)
    with TestClient(app) as c:
        yield c, app


def tao(c, description="Thợ mỏ mũ vàng", headers=None):
    return c.post(URL, json={"description": description}, headers=HEADERS if headers is None else headers)


def test_demo_tao_va_lay_png_hop_le(tmp_path, monkeypatch):
    from api.nhan_vat_ai import PhanHoiAnhNhanVat
    with client(tmp_path, monkeypatch) as (c, _):
        r = tao(c)
        assert r.status_code == 200
        meta = PhanHoiAnhNhanVat.model_validate(r.json())
        assert meta.generation_source == meta.context_source == "demo"
        image = c.get(meta.image_url, headers={"X-Demo-Player": "demo_a"})
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/png"
    assert image.headers["cache-control"] == "no-store"
    assert image.headers["x-content-type-options"] == "nosniff"
    with Image.open(BytesIO(image.content)) as decoded:
        assert decoded.size == (128, 128)
        assert decoded.mode == "RGBA"


def test_retry_khong_tao_anh_moi_va_doi_mo_ta_tra_409(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, _):
        first, again = tao(c), tao(c)
        assert first.status_code == again.status_code == 200
        assert first.json() == again.json()
        assert tao(c, description="Cao bồi").status_code == 409
        assert tao(c, description="Cao bồi", headers={**HEADERS, "Idempotency-Key": "request_2"}).status_code == 200
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        assert conn.execute("SELECT COUNT(*) FROM anh_nhan_vat").fetchone()[0] == 2


def test_get_anh_chi_duoc_trong_dung_phien(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch) as (c, _):
        a = tao(c).json()
        assert c.get(a["image_url"], headers={"X-Demo-Player": "demo_b"}).status_code == 404
        assert c.get(a["image_url"], headers={"X-Demo-Player": "demo_a"}).status_code == 200
        b = tao(c, headers={**HEADERS, "X-Demo-Player": "demo_b"}).json()
        assert a["image_id"] != b["image_id"]


@pytest.mark.parametrize("body", [{}, {"description": ""}, {"description": "a" * 501},
    {"description": True}, {"description": "bad\x00text"},
    {"description": "Thợ mỏ", "provider": "paid"},
    {"description": "Thợ mỏ", "image_url": "https://example.test/image.png"}])
def test_input_sai_tra_422(tmp_path, monkeypatch, body):
    with client(tmp_path, monkeypatch) as (c, _):
        assert c.post(URL, json=body, headers=HEADERS).status_code == 422


@pytest.mark.parametrize("headers", [{"X-Demo-Player": "demo_a"}, {"Idempotency-Key": "request_1"},
    {**HEADERS, "Idempotency-Key": "../bad"}, {**HEADERS, "X-Demo-Player": "../bad"}])
def test_header_sai_hoac_thieu_tra_422(tmp_path, monkeypatch, headers):
    with client(tmp_path, monkeypatch) as (c, _):
        assert tao(c, headers=headers).status_code == 422


def test_feature_tat_khong_tao_db(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, enabled=False) as (c, _):
        assert tao(c).status_code == 404
    assert not (tmp_path / "images.sqlite3").exists()


def test_demo_tat_can_context_backend(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, demo=False) as (c, _):
        assert tao(c).status_code == 503


def test_context_backend_va_demo_khong_doc_cheo_namespace(tmp_path, monkeypatch):
    from api.nhan_vat_ai import lay_ngu_canh_anh
    with client(tmp_path, monkeypatch) as (c, app):
        demo = tao(c).json()
        app.dependency_overrides[lay_ngu_canh_anh] = lambda: nguoi_da_hoan_thanh("demo_a")
        verified = tao(c).json()
        assert verified["context_source"] == "verified"
        assert c.get(demo["image_url"]).status_code == 404
        assert c.get(verified["image_url"]).status_code == 200
        assert demo["image_id"] != verified["image_id"]


def test_demo_khong_goi_provider_model_ke_ca_khi_co_context_server(tmp_path, monkeypatch):
    from api.nhiem_vu import NguCanhNguoiChoi
    class KhongDuocGoi:
        generation_source = "image_model"
        def sinh(self, **kw):
            raise AssertionError("Demo không được gọi model")
    ctx = NguCanhNguoiChoi(player_id="trusted_demo", context_source="demo")
    with client(tmp_path, monkeypatch, context=ctx) as (c, app):
        app.state.nhan_vat_ai.service.provider = KhongDuocGoi()
        assert tao(c).json()["generation_source"] == "demo"


def test_ngu_canh_verified_co_the_noi_provider_da_cau_hinh(tmp_path, monkeypatch):
    class ProviderGia:
        generation_source = "image_model"
        calls = 0
        def sinh(self, **kw):
            self.calls += 1
            with Image.new("RGBA", (16, 16), "red") as image, BytesIO() as buf:
                image.save(buf, format="PNG")
                return buf.getvalue()
    provider = ProviderGia()
    with client(tmp_path, monkeypatch, demo=False, context=nguoi_da_hoan_thanh("real_player")) as (c, app):
        app.state.nhan_vat_ai.service.provider = provider
        a, b = tao(c), tao(c)
        assert a.status_code == b.status_code == 200
        assert a.json() == b.json()
        assert a.json()["generation_source"] == "image_model"
        assert a.json()["context_source"] == "verified"
    assert provider.calls == 1


@pytest.mark.parametrize("ctx", [{"player_id": "fake"}, "fake"])
def test_context_backend_sai_kieu_tra_503(tmp_path, monkeypatch, ctx):
    with client(tmp_path, monkeypatch, context=ctx) as (c, _):
        assert tao(c).status_code == 503


def test_het_han_tra_404_va_retry_cung_key_co_the_tao_lai(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, AI_IMAGE_TTL_SECONDS="10") as (c, app):
        clock = [1000.0]
        app.state.nhan_vat_ai.kho.lay_thoi_gian = lambda: clock[0]
        a = tao(c).json()
        clock[0] = 1010.0
        assert c.get(a["image_url"], headers=HEADERS).status_code == 404
        b = tao(c).json()
        assert a["image_id"] != b["image_id"]


def test_kho_day_va_du_lieu_hong_tra_503(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, AI_IMAGE_MAX_IMAGES="1") as (c, _):
        a = tao(c).json()
        assert tao(c, headers={**HEADERS, "Idempotency-Key": "new_request"}).status_code == 503
        with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
            conn.execute("UPDATE anh_nhan_vat SET checksum = 'private-path'")
        r = c.get(a["image_url"], headers=HEADERS)
        assert r.status_code == 503
        assert "private-path" not in r.text


@pytest.mark.parametrize("env", [{"AI_IMAGE_DEMO": "bad"}, {"AI_IMAGE_TTL_SECONDS": "no"},
    {"AI_IMAGE_MAX_IMAGES": "0"}])
def test_cau_hinh_sai_tra_503_khong_lam_sap_app(tmp_path, monkeypatch, env):
    from api.nhan_vat_ai import nhan_vat_ai_da_nap
    with client(tmp_path, monkeypatch, **env) as (c, app):
        assert tao(c).status_code == 503
        assert nhan_vat_ai_da_nap(app) is False


def test_thieu_tai_nguyen_demo_khong_bao_ready(tmp_path, monkeypatch):
    import config
    from api.nhan_vat_ai import khoi_dong_nhan_vat_ai, nhan_vat_ai_da_nap
    with client(tmp_path, monkeypatch) as (c, app):
        monkeypatch.setattr(config, "APP_FLUTTER", tmp_path / "missing-app")
        khoi_dong_nhan_vat_ai(app)
        assert tao(c).status_code == 503
        assert nhan_vat_ai_da_nap(app) is False


def test_router_health_va_shutdown_app_chung(tmp_path, monkeypatch):
    import api.main
    import config
    monkeypatch.setattr(config, "ENABLED", {"nhan_vat_ai"})
    monkeypatch.setenv("AI_IMAGE_DEMO", "true")
    monkeypatch.setenv("AI_IMAGE_DB", str(tmp_path / "images.sqlite3"))
    with TestClient(api.main.app) as c:
        assert tao(c).status_code == 200
        assert c.get("/api/health").json()["da_nap"]["nhan_vat_ai"] is True
        assert URL in c.get("/openapi.json").json()["paths"]
    assert api.main.app.state.nhan_vat_ai is None

def test_config_noi_http_provider_vao_context_verified(tmp_path, monkeypatch):
    import base64
    import httpx
    import api.nhan_vat_ai as module
    from core.providers.anh_http import provider_anh_tu_moi_truong
    calls = []
    with Image.new("RGBA", (1024, 1024), "red") as image, BytesIO() as buf:
        image.save(buf, format="PNG")
        encoded = base64.b64encode(buf.getvalue()).decode("ascii")
    def handler(request):
        calls.append(request)
        assert request.headers["Authorization"] == "Bearer secret-test"
        return httpx.Response(200, json={"data": [{"b64_json": encoded}]})
    with httpx.Client(transport=httpx.MockTransport(handler)) as upstream:
        monkeypatch.setattr(module, "provider_anh_tu_moi_truong", lambda: provider_anh_tu_moi_truong(client=upstream))
        with client(tmp_path, monkeypatch, demo=False, context=nguoi_da_hoan_thanh("trusted"),
                    AI_IMAGE_ENABLED="true", AI_IMAGE_URL="https://image.example/v1/images/generations",
                    AI_IMAGE_MODEL="image-test", AI_IMAGE_API_KEY="secret-test") as (c, _):
            first, repeated = tao(c), tao(c)
            assert first.status_code == repeated.status_code == 200
            assert first.json() == repeated.json()
            assert first.json()["generation_source"] == "image_model"
            assert first.json()["context_source"] == "verified"
            assert tao(c, description="Cao bồi").status_code == 409
            image = c.get(first.json()["image_url"])
            assert image.status_code == 200
            with Image.open(BytesIO(image.content)) as decoded:
                assert decoded.size == (128, 128)
                assert decoded.getpixel((64, 64)) == (255, 0, 0, 255)
    assert len(calls) == 1


def test_provider_da_bat_nhung_phien_demo_khong_goi_http(tmp_path, monkeypatch):
    import httpx
    import api.nhan_vat_ai as module
    from core.providers.anh_http import provider_anh_tu_moi_truong
    def handler(request):
        raise AssertionError("Không được gọi provider trả phí trong phiên demo")
    with httpx.Client(transport=httpx.MockTransport(handler)) as upstream:
        monkeypatch.setattr(module, "provider_anh_tu_moi_truong", lambda: provider_anh_tu_moi_truong(client=upstream))
        with client(tmp_path, monkeypatch, AI_IMAGE_ENABLED="true", AI_IMAGE_URL="https://image.example/v1/images/generations", AI_IMAGE_MODEL="image-test") as (c, app):
            assert app.state.nhan_vat_ai.service.provider is not None
            assert tao(c).json()["generation_source"] == "demo"


def test_provider_http_loi_fallback_demo_co_nhan_va_retry_khong_goi_lai(tmp_path, monkeypatch, caplog):
    import httpx
    import api.nhan_vat_ai as module
    from core.providers.anh_http import provider_anh_tu_moi_truong
    calls = []
    def handler(request):
        calls.append(request)
        return httpx.Response(429, text="secret-test private-prompt")
    with httpx.Client(transport=httpx.MockTransport(handler)) as upstream:
        monkeypatch.setattr(module, "provider_anh_tu_moi_truong", lambda: provider_anh_tu_moi_truong(client=upstream))
        with client(tmp_path, monkeypatch, demo=False, context=nguoi_da_hoan_thanh("trusted"),
                    AI_IMAGE_ENABLED="true", AI_IMAGE_URL="https://image.example/v1/images/generations", AI_IMAGE_MODEL="image-test") as (c, _):
            first, repeated = tao(c), tao(c)
            assert first.status_code == repeated.status_code == 200
            assert first.json() == repeated.json()
            assert first.json()["generation_source"] == "demo"
            assert first.json()["context_source"] == "verified"
    assert len(calls) == 1
    assert "secret-test" not in caplog.text
    assert "private-prompt" not in caplog.text


def test_cau_hinh_provider_sai_van_cho_phep_demo_khong_lo_config(tmp_path, monkeypatch, caplog):
    with client(tmp_path, monkeypatch, AI_IMAGE_ENABLED="true", AI_IMAGE_URL="https://secret-test@image.example/generate", AI_IMAGE_MODEL="image-test") as (c, _):
        assert tao(c).status_code == 200
        assert tao(c).json()["generation_source"] == "demo"
    assert "Cấu hình provider ảnh" in caplog.text
    assert "secret-test" not in caplog.text


def test_quota_anh_tra_429_nhung_cache_va_nguoi_khac_van_dung_duoc(tmp_path, monkeypatch):
    from api.nhan_vat_ai import lay_ngu_canh_anh
    class ProviderDem:
        generation_source = "image_model"
        calls = 0
        def sinh(self, **kw):
            self.calls += 1
            with Image.new("RGBA", (16, 16), "red") as image, BytesIO() as buf:
                image.save(buf, format="PNG")
                return buf.getvalue()
    provider = ProviderDem()
    ctx = nguoi_da_hoan_thanh("trusted")
    with client(tmp_path, monkeypatch, demo=False, context=ctx,
                AI_IMAGE_DAILY_LIMIT="1") as (c, app):
        app.state.nhan_vat_ai.service.provider = provider
        first = tao(c)
        assert first.status_code == 200
        blocked = tao(c, headers={"Idempotency-Key": "request_2"})
        assert blocked.status_code == 429
        assert 1 <= int(blocked.headers["Retry-After"]) <= 86400
        assert tao(c).json() == first.json()
        assert c.get(first.json()["image_url"]).status_code == 200
        assert provider.calls == 1
        app.dependency_overrides[lay_ngu_canh_anh] = lambda: nguoi_da_hoan_thanh("other")
        assert tao(c).status_code == 200
        assert provider.calls == 2


def test_quota_anh_hong_chan_provider_va_tra_503(tmp_path, monkeypatch):
    class KhongDuocGoi:
        generation_source = "image_model"
        def sinh(self, **kw):
            raise AssertionError("Quota hỏng không được gọi provider")
    with client(tmp_path, monkeypatch, demo=False,
                context=nguoi_da_hoan_thanh("trusted")) as (c, app):
        app.state.nhan_vat_ai.service.provider = KhongDuocGoi()
        (tmp_path / "quota.sqlite3").write_bytes(b"broken quota")
        response = tao(c)
        assert response.status_code == 503
        assert str(tmp_path) not in response.text


def test_quota_anh_khong_hoan_luot_khi_luu_ket_qua_that_bai(tmp_path, monkeypatch):
    class ProviderDem:
        generation_source = "image_model"
        calls = 0
        def sinh(self, **kw):
            self.calls += 1
            with Image.new("RGBA", (16, 16), "red") as image, BytesIO() as buf:
                image.save(buf, format="PNG")
                return buf.getvalue()
    provider = ProviderDem()
    with client(tmp_path, monkeypatch, demo=False,
                context=nguoi_da_hoan_thanh("trusted"), AI_IMAGE_DAILY_LIMIT="1") as (c, app):
        app.state.nhan_vat_ai.service.provider = provider
        with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
            conn.execute("""CREATE TRIGGER chan_luu BEFORE INSERT ON anh_nhan_vat
                            BEGIN SELECT RAISE(ABORT, 'write failed'); END""")
        assert tao(c).status_code == 503
        with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
            assert conn.execute("SELECT COUNT(*) FROM anh_nhan_vat").fetchone()[0] == 0
            conn.execute("DROP TRIGGER chan_luu")
        assert tao(c).status_code == 429
        assert provider.calls == 1


@pytest.mark.parametrize("env", [
    {"AI_IMAGE_DAILY_LIMIT": "-1"}, {"AI_IMAGE_DAILY_LIMIT": "1.5"},
    {"AI_IMAGE_DAILY_LIMIT": "10001"}, {"AI_QUOTA_DB": ":memory:"},
])
def test_quota_anh_cau_hinh_sai_tra_503(tmp_path, monkeypatch, env):
    with client(tmp_path, monkeypatch, **env) as (c, _):
        assert tao(c).status_code == 503


def test_quota_anh_khong_cho_chung_file_voi_kho_anh(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, AI_QUOTA_DB=str(tmp_path / "images.sqlite3")) as (c, _):
        assert tao(c).status_code == 503


def test_demo_anh_khong_tieu_quota_ke_ca_khi_gioi_han_khong(tmp_path, monkeypatch):
    with client(tmp_path, monkeypatch, AI_IMAGE_DAILY_LIMIT="0") as (c, _):
        assert tao(c).status_code == 200
    with sqlite3.connect(tmp_path / "quota.sqlite3") as conn:
        assert conn.execute("SELECT COUNT(*) FROM quota_ai").fetchone()[0] == 0


def test_danh_tinh_verified_chua_co_tien_trinh_khong_du_quyen_tao_anh(tmp_path, monkeypatch):
    from api.nhiem_vu import NguCanhNguoiChoi
    ctx = NguCanhNguoiChoi(player_id="trusted", allowed_stage_ids=frozenset(range(1, 7)))
    class KhongDuocGoi:
        generation_source = "image_model"
        def sinh(self, **kw):
            raise AssertionError("Chỉ danh tính không đủ quyền tạo ảnh")
    with client(tmp_path, monkeypatch, demo=False, context=ctx) as (c, app):
        app.state.nhan_vat_ai.service.provider = KhongDuocGoi()
        assert tao(c).status_code == 403
