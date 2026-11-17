import base64
from io import BytesIO
import json

import httpx
from PIL import Image
import pytest

from core.providers.anh import LoiProviderAnh

URL = "https://image.example/v1/images/generations"


def provider(client=None, **kw):
    from core.providers.anh_http import ImagesGenerationsAnh
    return ImagesGenerationsAnh(url=URL, model="image-model-test", client=client, **kw)


def goi(p):
    return p.sinh(system_prompt="One static pixel-art character.", user_prompt='{"description":"Thợ mỏ"}')


def envelope(raw=b"image-bytes"):
    return {"data": [{"b64_json": base64.b64encode(raw).decode("ascii")}]}


def test_contract_mot_anh_png_nen_trong_suot_key_chi_o_header():
    requests = []
    def handler(request):
        requests.append(request)
        assert request.method == "POST"
        assert str(request.url) == URL
        assert request.headers["Authorization"] == "Bearer secret-test"
        assert request.headers["Accept"] == "application/json"
        assert set(request.extensions["timeout"].values()) == {7.0}
        body = json.loads(request.content)
        assert body["model"] == "image-model-test"
        assert body["n"] == 1
        assert body["size"] == "1024x1024"
        assert body["output_format"] == "png"
        assert body["background"] == "transparent"
        assert body["quality"] == "low"
        assert body["stream"] is False
        assert "response_format" not in body
        assert body["prompt"].startswith("One static pixel-art character.")
        assert body["prompt"].endswith('{"description":"Thợ mỏ"}')
        assert "secret-test" not in request.content.decode()
        return httpx.Response(200, json=envelope())
    with httpx.Client(transport=httpx.MockTransport(handler)) as c:
        p = provider(c, api_key="secret-test", timeout_seconds=7)
        assert p.generation_source == "image_model"
        assert goi(p) == b"image-bytes"
        assert not c.is_closed
        assert "secret-test" not in repr(p)
    assert len(requests) == 1


def test_client_tu_tao_duoc_dong_va_local_khong_can_key(monkeypatch):
    import core.providers.anh_http as module
    real_client = httpx.Client
    clients = []
    def handler(request):
        assert "Authorization" not in request.headers
        return httpx.Response(200, json=envelope())
    def make_client():
        c = real_client(transport=httpx.MockTransport(handler))
        clients.append(c)
        return c
    monkeypatch.setattr(module.httpx, "Client", make_client)
    assert goi(provider()) == b"image-bytes"
    assert clients[0].is_closed


@pytest.mark.parametrize("status", [201, 302, 401, 429, 500])
def test_http_sai_status_khong_retry_khong_follow_redirect(status):
    requests = []
    def handler(request):
        requests.append(request)
        return httpx.Response(status, headers={"Location": "https://other.example/private"}, text="secret-test private-prompt")
    with httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=True) as c:
        with pytest.raises(LoiProviderAnh) as exc:
            goi(provider(c, api_key="secret-test"))
        assert not c.is_closed
    assert len(requests) == 1
    assert "secret-test" not in str(exc.value)
    assert "private" not in str(exc.value)


@pytest.mark.parametrize("error", [httpx.ConnectError, httpx.ReadTimeout, httpx.RemoteProtocolError])
def test_loi_mang_khong_retry_va_thong_bao_khong_lo_key(error):
    calls = []
    def handler(request):
        calls.append(request)
        raise error("secret-test private-prompt", request=request)
    with httpx.Client(transport=httpx.MockTransport(handler)) as c:
        with pytest.raises(LoiProviderAnh) as exc:
            goi(provider(c))
    assert len(calls) == 1
    assert "secret-test" not in str(exc.value)
    assert "private-prompt" not in str(exc.value)


@pytest.mark.parametrize("body", [
    {}, [], {"data": []}, {"data": {}}, {"data": [None]},
    {"data": [{"url": "https://other.example/private.png"}]},
    {"data": [{"b64_json": None}]}, {"data": [{"b64_json": ""}]},
    {"data": [{"b64_json": 123}]}, {"data": [{"b64_json": "not base64!"}]},
    {"data": [{"b64_json": "ảnh"}]}, {"data": [{"b64_json": "YQ"}]},
    {"data": [{"b64_json": "YQ=="}, {"b64_json": "Yg=="}]},
    {"error": {"message": "private-prompt"}, "data": [{"b64_json": "YQ=="}]},
])
def test_envelope_sai_base64_hong_hoac_url_khong_duoc_tai(body):
    calls = []
    def handler(request):
        calls.append(request)
        return httpx.Response(200, json=body)
    with httpx.Client(transport=httpx.MockTransport(handler)) as c:
        with pytest.raises(LoiProviderAnh):
            goi(provider(c))
    assert len(calls) == 1


@pytest.mark.parametrize("body", [b"not-json", b"x" * (8 * 1024 * 1024 + 1), b"[" * 2000 + b"0" + b"]" * 2000],
                         ids=["invalid-json", "over-8-MiB", "nested-too-deep"])
def test_json_hong_hoac_qua_lon_bi_chan(body):
    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, content=body))) as c:
        with pytest.raises(LoiProviderAnh):
            goi(provider(c))


def test_anh_giai_ma_qua_5_MiB_bi_chan():
    body = envelope(b"x" * (5 * 1024 * 1024 + 1))
    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, json=body))) as c:
        with pytest.raises(LoiProviderAnh):
            goi(provider(c))


def test_doc_stream_co_gioi_han_va_dong_response_som():
    class Stream(httpx.SyncByteStream):
        read = 0
        closed = False
        def __iter__(self):
            for _ in range(3000):
                self.read += 1
                yield b"x" * 4096
        def close(self):
            self.closed = True
    stream = Stream()
    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, stream=stream))) as c:
        with pytest.raises(LoiProviderAnh):
            goi(provider(c))
    assert stream.closed
    assert stream.read < 3000


@pytest.mark.parametrize("timeout", [0, -1, 61, True, "10", float("nan"), float("inf")])
def test_timeout_huu_han_va_co_gioi_han(timeout):
    with pytest.raises(ValueError):
        provider(timeout_seconds=timeout)


@pytest.mark.parametrize("url", ["", "file:///secret", "https://user:secret@image.example/generate",
    "https://image.example/generate?api_key=secret", "https://image.example/generate#secret", None])
def test_chan_url_sai_hoac_chua_key(url):
    from core.providers.anh_http import ImagesGenerationsAnh
    with pytest.raises(ValueError):
        ImagesGenerationsAnh(url=url, model="image-test")


@pytest.mark.parametrize("model", [None, "", " ", 123])
def test_model_phai_duoc_chi_ro(model):
    from core.providers.anh_http import ImagesGenerationsAnh
    with pytest.raises(ValueError):
        ImagesGenerationsAnh(url=URL, model=model)


@pytest.mark.parametrize("key", [123, "bad\nkey", "bad\rkey", "khóa"])
def test_key_sai_khong_duoc_gui(key):
    with pytest.raises(ValueError):
        provider(api_key=key)


@pytest.mark.parametrize("prompt", [None, "", " ", "x" * 16001, "bad\ud800"])
def test_prompt_sai_khong_goi_mang(prompt):
    def handler(request):
        raise AssertionError("Không được gửi request với prompt sai")
    with httpx.Client(transport=httpx.MockTransport(handler)) as c:
        with pytest.raises(LoiProviderAnh):
            provider(c).sinh(system_prompt="pixel-art", user_prompt=prompt)


def test_factory_mac_dinh_tat_va_khong_goi_mang_khi_khoi_tao(monkeypatch):
    from core.providers.anh_http import provider_anh_tu_moi_truong
    def no_network(*a, **kw):
        raise AssertionError("Không được tạo HTTP client lúc khởi tạo provider")
    monkeypatch.setattr(httpx, "Client", no_network)
    assert provider_anh_tu_moi_truong({}) is None
    assert provider_anh_tu_moi_truong({"AI_IMAGE_ENABLED": "false", "AI_IMAGE_API_KEY": "secret"}) is None
    p = provider_anh_tu_moi_truong({"AI_IMAGE_ENABLED": "true", "AI_IMAGE_URL": "http://127.0.0.1:9000/v1/images/generations", "AI_IMAGE_MODEL": "local-image", "AI_IMAGE_TIMEOUT_SECONDS": "8"})
    assert p.model == "local-image"
    assert p.timeout_seconds == 8


@pytest.mark.parametrize("env", [
    {"AI_IMAGE_ENABLED": "wrong"}, {"AI_IMAGE_ENABLED": "true"},
    {"AI_IMAGE_ENABLED": "true", "AI_IMAGE_URL": URL, "AI_IMAGE_MODEL": "image-test", "AI_IMAGE_TIMEOUT_SECONDS": "bad"},
])
def test_factory_config_sai_bao_loi(env):
    from core.providers.anh_http import provider_anh_tu_moi_truong
    with pytest.raises(ValueError):
        provider_anh_tu_moi_truong(env)


@pytest.mark.parametrize("raw,source", [(None, "image_model"), (b"bad image", "demo")], ids=["valid-image", "bad-image-fallback"])
def test_noi_pipeline_chuan_hoa_va_fallback(raw, source):
    from core.ai_nhan_vat import tao_anh_nhan_vat
    from core.nhan_vat_ai import YeuCauTaoNhanVat
    from core.providers.anh import AnhMauOffline
    from pathlib import Path
    if raw is None:
        with Image.new("RGBA", (1024, 1024), (30, 80, 200, 128)) as image, BytesIO() as buf:
            image.save(buf, format="PNG")
            raw = buf.getvalue()
    demo = AnhMauOffline(Path(__file__).resolve().parents[2] / "gold_rush/assets/images")
    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, json=envelope(raw)))) as c:
        result = tao_anh_nhan_vat(YeuCauTaoNhanVat(description="Thợ mỏ"), demo_provider=demo, provider=provider(c))
    assert result.generation_source == source
    with Image.open(BytesIO(result.png)) as image:
        assert image.size == (128, 128)
        assert image.mode == "RGBA"
        assert image.format == "PNG"

def test_khong_giai_nen_http_truoc_khi_ap_dung_gioi_han():
    class Stream(httpx.SyncByteStream):
        closed = False
        def __iter__(self):
            raise AssertionError("Không được giải nén body ngoài giới hạn")
            yield b""
        def close(self):
            self.closed = True
    stream = Stream()
    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, headers={"content-encoding": "gzip"}, stream=stream))) as c:
        with pytest.raises(LoiProviderAnh):
            goi(provider(c))
    assert stream.closed

def test_http_that_qua_may_chu_cuc_bo_khong_dung_dich_vu_ben_ngoai(monkeypatch):
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from threading import Thread
    from core.providers.anh_http import ImagesGenerationsAnh
    calls = []
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            calls.append((self.path, payload, self.headers.get("Authorization")))
            body = json.dumps(envelope(b"local-image-bytes")).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *args):
            pass
    monkeypatch.setenv("NO_PROXY", "127.0.0.1")
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/v1/images/generations"
            p = ImagesGenerationsAnh(url=url, model="local-test", api_key="secret-test", timeout_seconds=2)
            assert goi(p) == b"local-image-bytes"
        finally:
            server.shutdown()
            thread.join(timeout=5)
    assert len(calls) == 1
    assert calls[0][0] == "/v1/images/generations"
    assert calls[0][1]["model"] == "local-test"
    assert calls[0][2] == "Bearer secret-test"
