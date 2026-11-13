import base64
import json

import httpx
import pytest

from core.providers.anh import LoiProviderAnh
from core.providers.cloudflare_anh import (
    DEFAULT_MODEL,
    CloudflareWorkersAnh,
    cloudflare_provider_tu_moi_truong,
)


ACCOUNT_ID = "0123456789abcdef0123456789abcdef"
TOKEN = "test-token-without-secret-value"
URL = (
    "https://api.cloudflare.com/client/v4/accounts/"
    f"{ACCOUNT_ID}/ai/run/{DEFAULT_MODEL}"
)


def provider(client=None, **kwargs):
    return CloudflareWorkersAnh(
        account_id=ACCOUNT_ID,
        api_token=TOKEN,
        client=client,
        **kwargs,
    )


def goi(p):
    return p.sinh(
        system_prompt="Create one centered pixel-art character.",
        user_prompt='{"description":"Thợ mỏ"}',
    )


def envelope(raw=b"jpeg-image-bytes"):
    return {
        "success": True,
        "errors": [],
        "messages": [],
        "result": {"image": base64.b64encode(raw).decode("ascii")},
    }


def test_request_dung_rest_contract_va_token_chi_o_header():
    requests = []

    def handler(request):
        requests.append(request)
        assert request.method == "POST"
        assert str(request.url) == URL
        assert request.headers["Authorization"] == f"Bearer {TOKEN}"
        assert request.headers["Content-Type"].startswith("application/json")
        assert request.headers["Accept-Encoding"] == "identity"
        assert set(request.extensions["timeout"].values()) == {17.0}
        body = json.loads(request.content)
        assert set(body) == {"prompt", "steps"}
        assert body["steps"] == 4
        assert body["prompt"].startswith("Create one centered pixel-art character.")
        assert body["prompt"].endswith('{"description":"Thợ mỏ"}')
        assert TOKEN.encode() not in request.content
        return httpx.Response(200, json=envelope())

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        p = provider(client, timeout_seconds=17)
        assert goi(p) == b"jpeg-image-bytes"
        assert p.generation_source == "image_model"
        assert not client.is_closed
        assert TOKEN not in repr(p)
    assert len(requests) == 1


@pytest.mark.parametrize(
    "body",
    [
        {"image": base64.b64encode(b"top-level").decode("ascii")},
        {"success": True, "result": base64.b64encode(b"result-string").decode("ascii")},
        {
            "success": True,
            "result": {
                "image": "data:image/jpeg;charset=utf-8;base64,"
                + base64.b64encode(b"data-uri").decode("ascii")
            },
        },
    ],
)
def test_doc_cac_dang_response_base64_hop_le(body):
    with httpx.Client(
        transport=httpx.MockTransport(lambda request: httpx.Response(200, json=body))
    ) as client:
        assert goi(provider(client)) in (b"top-level", b"result-string", b"data-uri")


@pytest.mark.parametrize("content_type", ["image/jpeg", "image/png"])
def test_ho_tro_response_anh_nhi_phan(content_type):
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda request: httpx.Response(
                200, content=b"raw-image", headers={"Content-Type": content_type}
            )
        )
    ) as client:
        assert goi(provider(client)) == b"raw-image"


@pytest.mark.parametrize("status", [201, 302, 400, 401, 403, 404, 429, 500, 503])
def test_http_sai_khong_follow_redirect_va_khong_lo_du_lieu(status):
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(
            status,
            text=f"{TOKEN} private-prompt",
            headers={"Location": "https://other.example/private"},
        )

    with httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=True) as client:
        with pytest.raises(LoiProviderAnh) as exc:
            goi(provider(client))
    assert len(calls) == 1
    assert TOKEN not in str(exc.value)
    assert "private-prompt" not in str(exc.value)


@pytest.mark.parametrize(
    "body",
    [
        {},
        [],
        {"success": False, "result": {"image": "YQ=="}},
        {"success": True, "errors": [{"message": "private"}]},
        {"success": True, "result": {}},
        {"success": True, "result": {"image": ""}},
        {"success": True, "result": {"image": "not base64!"}},
        {"success": True, "result": {"image": "YQ"}},
        {"success": True, "result": {"image": "data:text/html;base64,YQ=="}},
    ],
)
def test_chan_envelope_va_base64_khong_hop_le(body):
    with httpx.Client(
        transport=httpx.MockTransport(lambda request: httpx.Response(200, json=body))
    ) as client:
        with pytest.raises(LoiProviderAnh):
            goi(provider(client))


@pytest.mark.parametrize(
    "account_id",
    ["", "short", "g" * 32, "a" * 31, "a" * 33, "a" * 16 + "/" + "a" * 15, None],
)
def test_account_id_phai_dung_dinh_dang(account_id):
    with pytest.raises(ValueError):
        CloudflareWorkersAnh(account_id=account_id, api_token=TOKEN)


@pytest.mark.parametrize("token", ["", "bad token", "bad\ntoken", "khóa", None, 123])
def test_token_khong_hop_le(token):
    with pytest.raises(ValueError):
        CloudflareWorkersAnh(account_id=ACCOUNT_ID, api_token=token)


@pytest.mark.parametrize(
    "model",
    ["", "flux", "@cf/one", "@cf/vendor/model/extra", "@cf/vendor/../model", None],
)
def test_model_id_khong_duoc_doi_endpoint_tuy_y(model):
    with pytest.raises(ValueError):
        CloudflareWorkersAnh(account_id=ACCOUNT_ID, api_token=TOKEN, model=model)


@pytest.mark.parametrize("steps", [0, 9, -1, True, 4.0, "4"])
def test_steps_nam_trong_gioi_han_tai_lieu(steps):
    with pytest.raises(ValueError):
        provider(steps=steps)


@pytest.mark.parametrize("timeout", [0, -1, 61, True, "60", float("nan"), float("inf")])
def test_timeout_huu_han_va_khong_qua_60_giay(timeout):
    with pytest.raises(ValueError):
        provider(timeout_seconds=timeout)


@pytest.mark.parametrize("prompt", [None, "", " ", "x" * 2049])
def test_prompt_sai_khong_goi_mang(prompt):
    def handler(request):
        raise AssertionError("Không được gọi mạng")

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(LoiProviderAnh):
            provider(client).sinh(system_prompt="pixel-art", user_prompt=prompt)


def test_factory_cloudflare_va_truong_hop_chua_dien_token():
    assert cloudflare_provider_tu_moi_truong({}) is None
    env = {
        "CLOUDFLARE_ACCOUNT_ID": ACCOUNT_ID,
        "CLOUDFLARE_API_TOKEN": TOKEN,
        "CLOUDFLARE_IMAGE_MODEL": DEFAULT_MODEL,
        "CLOUDFLARE_IMAGE_STEPS": "3",
        "AI_IMAGE_TIMEOUT_SECONDS": "45",
    }
    p = cloudflare_provider_tu_moi_truong(env)
    assert p is not None
    assert p.model == DEFAULT_MODEL
    assert p.steps == 3
    assert p.timeout_seconds == 45


@pytest.mark.parametrize(
    "env",
    [
        {"CLOUDFLARE_ACCOUNT_ID": ACCOUNT_ID},
        {"CLOUDFLARE_API_TOKEN": TOKEN},
        {"CLOUDFLARE_ACCOUNT_ID": ACCOUNT_ID, "CLOUDFLARE_API_TOKEN": TOKEN, "CLOUDFLARE_IMAGE_STEPS": "bad"},
    ],
)
def test_factory_bao_loi_cau_hinh_thieu_hoac_sai(env):
    with pytest.raises(ValueError):
        cloudflare_provider_tu_moi_truong(env)


def test_factory_chung_chon_cloudflare_thay_vi_openai_gemini():
    from core.providers.anh_http import provider_anh_tu_moi_truong

    p = provider_anh_tu_moi_truong(
        {
            "AI_IMAGE_ENABLED": "true",
            "AI_IMAGE_PROVIDER": "cloudflare",
            "CLOUDFLARE_ACCOUNT_ID": ACCOUNT_ID,
            "CLOUDFLARE_API_TOKEN": TOKEN,
            "CLOUDFLARE_IMAGE_MODEL": DEFAULT_MODEL,
            "AI_IMAGE_URL": "https://openai.example/khong-duoc-goi",
            "GEMINI_API_KEY": "gemini-khong-duoc-dung",
        }
    )
    assert isinstance(p, CloudflareWorkersAnh)
