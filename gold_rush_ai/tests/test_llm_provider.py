"""HTTP giả lập tại transport; không gửi request tới dịch vụ LLM thật."""
import json

import httpx
import pytest


def provider(client, **kw):
    from core.providers.llm import ChatCompletionsLLM

    return ChatCompletionsLLM(url="https://llm.example/v1/chat/completions",
                              model="model-demo", client=client, **kw)


def goi(p):
    return p.sinh(system_prompt="Chỉ trả JSON.", user_prompt="Tạo nội dung nhiệm vụ.")


def test_gui_dung_contract_json_key_chi_trong_header_va_timeout_huu_han():
    def handler(request):
        body = json.loads(request.content)
        assert request.method == "POST"
        assert str(request.url) == "https://llm.example/v1/chat/completions"
        assert request.headers["Authorization"] == "Bearer key-test"
        assert body["model"] == "model-demo"
        assert body["messages"] == [
            {"role": "system", "content": "Chỉ trả JSON."},
            {"role": "user", "content": "Tạo nội dung nhiệm vụ."},
        ]
        assert body["stream"] is False
        assert body["max_tokens"] == 1024
        assert body["response_format"] == {"type": "json_object"}
        assert "key-test" not in request.content.decode()
        assert set(request.extensions["timeout"].values()) == {7.0}
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": '{"title":"Thợ mỏ"}'}}]})

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        p = provider(client, api_key="key-test", timeout_seconds=7)
        assert goi(p) == '{"title":"Thợ mỏ"}'
        assert not client.is_closed
        assert "key-test" not in repr(p)


def test_local_provider_khong_can_key():
    def handler(request):
        assert "Authorization" not in request.headers
        return httpx.Response(200, json={"choices": [{"message": {"content": "{}"}}]})

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        assert goi(provider(client)) == "{}"


@pytest.mark.parametrize("error", [httpx.ReadTimeout, httpx.ConnectError])
def test_loi_mang_duoc_chuan_hoa_khong_retry_hoac_lo_key(error):
    from core.providers.llm import LoiProviderLLM

    requests = []
    def handler(request):
        requests.append(request)
        raise error("key-test không được lộ", request=request)

    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(LoiProviderLLM) as exc:
            goi(provider(client, api_key="key-test"))
    assert len(requests) == 1
    assert "key-test" not in str(exc.value)


@pytest.mark.parametrize("status", [401, 429, 500, 302])
def test_http_loi_hoac_redirect_khong_duoc_tin_tuong(status):
    from core.providers.llm import LoiProviderLLM

    requests = []
    def handler(request):
        requests.append(request)
        return httpx.Response(status, headers={"Location": "https://other.example/"}, text="key-test")

    with httpx.Client(transport=httpx.MockTransport(handler), follow_redirects=True) as client:
        with pytest.raises(LoiProviderLLM) as exc:
            goi(provider(client, api_key="key-test"))
    assert len(requests) == 1
    assert "key-test" not in str(exc.value)


@pytest.mark.parametrize("body", [
    {}, {"choices": []}, {"choices": [{"message": {"content": None}}]},
    {"choices": [{"message": {"content": []}}]},
    {"choices": [{"message": {"content": " "}}]},
    {"choices": [{"finish_reason": "length", "message": {"content": "{}"}}]},
    {"choices": [{"message": {"content": "{}", "refusal": "Không hỗ trợ"}}]},
])
def test_chan_envelope_sai_hoac_noi_dung_bi_cat(body):
    from core.providers.llm import LoiProviderLLM

    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, json=body))) as client:
        with pytest.raises(LoiProviderLLM):
            goi(provider(client))


@pytest.mark.parametrize("body", [b"not-json", b"x" * 65537, b"[" * 10000 + b"0" + b"]" * 10000],
                         ids=["invalid-json", "oversized", "nested-too-deep"])
def test_chan_response_hong_hoac_qua_lon(body):
    from core.providers.llm import LoiProviderLLM

    with httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, content=body))) as client:
        with pytest.raises(LoiProviderLLM):
            goi(provider(client))


@pytest.mark.parametrize("timeout", [0, -1, 61, float("nan"), float("inf"), True, "10"])
def test_timeout_phai_huu_han_va_co_gioi_han(timeout):
    from core.providers.llm import ChatCompletionsLLM

    with pytest.raises(ValueError):
        ChatCompletionsLLM(url="https://llm.example/chat", model="demo", timeout_seconds=timeout)


@pytest.mark.parametrize("url", ["", "file:///secret", "https://key@llm.example/chat", "https://llm.example/chat?key=secret"])
def test_url_config_khong_nhan_scheme_sai_hoac_key_trong_url(url):
    from core.providers.llm import ChatCompletionsLLM

    with pytest.raises(ValueError):
        ChatCompletionsLLM(url=url, model="demo")


def test_cau_hinh_mac_dinh_tat_chi_bat_khi_duoc_chi_ro():
    from core.providers.llm import provider_tu_moi_truong

    assert provider_tu_moi_truong({}) is None
    assert provider_tu_moi_truong({"LLM_ENABLED": "false", "LLM_API_KEY": "key-test"}) is None
    p = provider_tu_moi_truong({
        "LLM_ENABLED": "true", "LLM_CHAT_URL": "http://127.0.0.1:11434/v1/chat/completions",
        "LLM_MODEL": "model-local", "LLM_TIMEOUT_SECONDS": "20",
    })
    assert p.model == "model-local"
    assert p.timeout_seconds == 20


@pytest.mark.parametrize("env", [
    {"LLM_ENABLED": "wrong"}, {"LLM_ENABLED": "true"},
    {"LLM_ENABLED": "true", "LLM_CHAT_URL": "https://llm.example/chat", "LLM_MODEL": "demo", "LLM_TIMEOUT_SECONDS": "bad"},
])
def test_cau_hinh_bat_nhung_khong_hop_le_bao_loi_ro_rang(env):
    from core.providers.llm import provider_tu_moi_truong

    with pytest.raises(ValueError):
        provider_tu_moi_truong(env)
