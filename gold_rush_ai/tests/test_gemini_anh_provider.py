import base64
from io import BytesIO
import json
import httpx
from PIL import Image
import pytest

from core.providers.anh import LoiProviderAnh
from core.providers.gemini_anh import GeminiRestAnhProvider, gemini_provider_tu_moi_truong


def tao_anh_b64(color="red", size=(64, 64)):
    with Image.new("RGBA", size, color) as img, BytesIO() as buf:
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode("ascii")


def test_gemini_imagen3_predict_thanh_cong():
    b64_data = tao_anh_b64("green")
    requests_sent = []

    def handler(request: httpx.Request):
        requests_sent.append(request)
        assert request.method == "POST"
        assert ":predict" in str(request.url)
        assert request.headers["x-goog-api-key"] == "test-gemini-secret-key"
        assert request.headers["content-type"] == "application/json"
        body = json.loads(request.content)
        assert "instances" in body
        assert len(body["instances"]) == 1
        assert "Thợ mỏ" in body["instances"][0]["prompt"]
        assert body["parameters"]["sampleCount"] == 1
        assert body["parameters"]["outputOptions"]["mimeType"] == "image/png"

        response_payload = {
            "predictions": [
                {
                    "bytesBase64Encoded": b64_data,
                    "mimeType": "image/png",
                }
            ]
        }
        return httpx.Response(200, json=response_payload)

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(
            api_key="test-gemini-secret-key",
            model="imagen-3.0-generate-002",
            timeout_seconds=8.0,
            client=mock_client,
        )
        assert provider.generation_source == "image_model"
        raw_png = provider.sinh(
            system_prompt="Pixel art character generator.",
            user_prompt='{"description": "Thợ mỏ dũng cảm"}',
        )

    assert len(requests_sent) == 1
    assert raw_png == base64.b64decode(b64_data)
    with Image.open(BytesIO(raw_png)) as img:
        assert img.format == "PNG"


def test_gemini_ho_tro_format_generate_images():
    b64_data = tao_anh_b64("blue")

    def handler(request: httpx.Request):
        return httpx.Response(
            200,
            json={"generatedImages": [{"image": {"imageBytes": b64_data}}]},
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(
            api_key="key-test",
            model="imagen-3.0-generate-002",
            client=mock_client,
        )
        raw_png = provider.sinh(system_prompt="Sys", user_prompt='{"desc": "hero"}')
        assert raw_png == base64.b64decode(b64_data)


def test_gemini_ho_tro_format_inline_data():
    b64_data = tao_anh_b64("yellow")

    def handler(request: httpx.Request):
        return httpx.Response(
            200,
            json={
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "inlineData": {
                                        "mimeType": "image/png",
                                        "data": b64_data,
                                    }
                                }
                            ]
                        }
                    }
                ]
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(
            api_key="key-test",
            model="gemini-2.0-flash-exp",
            client=mock_client,
        )
        raw_png = provider.sinh(system_prompt="Sys", user_prompt='{"desc": "mage"}')
        assert raw_png == base64.b64decode(b64_data)


def test_gemini_loi_api_tra_loi_provider():
    def handler(request: httpx.Request):
        return httpx.Response(500, json={"error": {"message": "Internal error"}})

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="key-test", client=mock_client)
        with pytest.raises(LoiProviderAnh):
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "warrior"}')


def test_gemini_provider_tu_moi_truong():
    # Khi tắt
    assert gemini_provider_tu_moi_truong({"AI_IMAGE_ENABLED": "false"}) is None

    # Khi bật nhưng không có provider=gemini hoặc key
    assert gemini_provider_tu_moi_truong({"AI_IMAGE_ENABLED": "true"}) is None

    # Khi chỉ định AI_IMAGE_PROVIDER=gemini
    p1 = gemini_provider_tu_moi_truong({
        "AI_IMAGE_ENABLED": "true",
        "AI_IMAGE_PROVIDER": "gemini",
        "GEMINI_API_KEY": "AIzaSyTestKey123456",
        "AI_IMAGE_MODEL": "imagen-3.0-generate-002",
        "AI_IMAGE_TIMEOUT_SECONDS": "12",
    })
    assert p1 is not None
    assert p1.model == "imagen-3.0-generate-002"
    assert p1.timeout_seconds == 12.0
    assert p1._api_key == "AIzaSyTestKey123456"
