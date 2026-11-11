import base64
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import httpx
from PIL import Image
import pytest

from core.ai_nhan_vat import tao_anh_nhan_vat
from core.nhan_vat_ai import YeuCauTaoNhanVat
from core.providers.anh import AnhMauOffline, LoiProviderAnh
from core.providers.gemini_anh import (
    DEFAULT_MODEL,
    ChanDoanLoi429,
    GeminiRestAnhProvider,
    LoiQuotaGemini,
    gemini_provider_tu_moi_truong,
    phan_tich_loi_429,
)
from core.xu_ly_anh import chuan_hoa_anh

ASSETS = Path(__file__).resolve().parents[2] / "gold_rush/assets/images"


def tao_anh_b64(color="red", size=(64, 64)):
    with Image.new("RGBA", size, color) as img, BytesIO() as buf:
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode("ascii")


def test_gemini_flash_image_generate_content_payload_chinh_xac():
    """Kiểm thử cấu trúc request payload thực tế của gemini-3.1-flash-image qua :generateContent.

    Bắt buộc:
    - Có generationConfig.imageConfig.aspectRatio = "1:1".
    - Tuyệt đối không chứa generationConfig.imageGenerationConfig (tránh lỗi HTTP 400).
    - Có generationConfig.responseModalities = ["IMAGE"].
    - Có contents.parts.text.
    - Đúng endpoint :generateContent với model gemini-3.1-flash-image.
    - Header x-goog-api-key an toàn, không lộ trong URL.
    - Parse thành công inlineData Base64 và chuẩn hóa PNG 128x128 tính SHA-256.
    """
    b64_data = tao_anh_b64("green", (100, 100))
    requests_sent = []
    secret_key = "test-gemini-secret-key-12345"

    def handler(request: httpx.Request):
        requests_sent.append(request)
        assert request.method == "POST"
        assert f"/v1beta/models/gemini-3.1-flash-image:generateContent" in str(request.url)
        assert "key=" not in str(request.url)  # Không lộ key trong query URL
        assert request.headers["x-goog-api-key"] == secret_key
        assert request.headers["content-type"] == "application/json"

        body = json.loads(request.content)
        # 1. Cấu trúc contents.parts.text
        assert "contents" in body
        assert len(body["contents"]) == 1
        assert "parts" in body["contents"][0]
        assert len(body["contents"][0]["parts"]) == 1
        assert "text" in body["contents"][0]["parts"][0]
        assert "Thợ mỏ" in body["contents"][0]["parts"][0]["text"]

        # 2. Cấu trúc generationConfig và imageConfig chuẩn Google GenAI REST
        assert "generationConfig" in body
        gen_cfg = body["generationConfig"]
        assert gen_cfg.get("responseModalities") == ["IMAGE"]
        assert "imageConfig" in gen_cfg
        assert gen_cfg["imageConfig"].get("aspectRatio") == "1:1"
        assert "imageGenerationConfig" not in gen_cfg, "LỖI: imageGenerationConfig không được phép xuất hiện!"

        response_payload = {
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
        }
        return httpx.Response(200, json=response_payload)

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(
            api_key=secret_key,
            model="gemini-3.1-flash-image",
            timeout_seconds=10.0,
            client=mock_client,
        )
        assert provider.generation_source == "image_model"
        raw_png = provider.sinh(
            system_prompt="Pixel art character generator.",
            user_prompt='{"description": "Thợ mỏ đào vàng"}',
        )

    assert len(requests_sent) == 1
    assert raw_png == base64.b64decode(b64_data)

    # Chuẩn hóa ảnh qua Pillow thành PNG 128x128 RGBA và tính SHA-256
    png_128 = chuan_hoa_anh(raw_png)
    assert len(png_128) > 0
    with Image.open(BytesIO(png_128)) as img:
        assert img.format == "PNG"
        assert img.size == (128, 128)
    char_hash = sha256(png_128).hexdigest()
    assert len(char_hash) == 64


def test_gemini_tra_ve_ca_text_va_anh_van_trich_xuat_chinh_xac():
    """Khi model trả về cả suy nghĩ/caption (text part) và ảnh (inlineData part), hệ thống vẫn trích xuất đúng ảnh."""
    b64_data = tao_anh_b64("cyan", (64, 64))

    def handler(request: httpx.Request):
        return httpx.Response(
            200,
            json={
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": "Thinking Process: Generating a retro pixel-art miner with gold pouch..."
                                },
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
        provider = GeminiRestAnhProvider(api_key="test-key", model="gemini-3.1-flash-image", client=mock_client)
        raw_png = provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')
        assert raw_png == base64.b64decode(b64_data)


def test_gemini_imagen_predict_tuong_thich_nguoc():
    """Hỗ trợ tương thích ngược cho các mô hình có tiền tố 'imagen' gọi endpoint :predict."""
    b64_data = tao_anh_b64("purple")
    requests_sent = []

    def handler(request: httpx.Request):
        requests_sent.append(request)
        assert ":predict" in str(request.url)
        body = json.loads(request.content)
        assert "instances" in body
        assert body["parameters"]["sampleCount"] == 1
        return httpx.Response(
            200,
            json={"predictions": [{"bytesBase64Encoded": b64_data, "mimeType": "image/png"}]},
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(
            api_key="test-key",
            model="imagen-custom-proxy",
            client=mock_client,
        )
        raw_png = provider.sinh(system_prompt="Sys", user_prompt='{"description": "hero"}')
        assert raw_png == base64.b64decode(b64_data)
    assert len(requests_sent) == 1


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
            model="gemini-3.1-flash-image",
            client=mock_client,
        )
        raw_png = provider.sinh(system_prompt="Sys", user_prompt='{"desc": "hero"}')
        assert raw_png == base64.b64decode(b64_data)


def test_gemini_ho_tro_format_interactions_output_image():
    b64_data = tao_anh_b64("orange")

    def handler(request: httpx.Request):
        return httpx.Response(
            200,
            json={"output_image": {"data": b64_data}},
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(
            api_key="key-test",
            model="gemini-3.1-flash-image",
            client=mock_client,
        )
        raw_png = provider.sinh(system_prompt="Sys", user_prompt='{"desc": "hero"}')
        assert raw_png == base64.b64decode(b64_data)


def test_gemini_phat_hien_text_thay_vi_anh():
    """Khi người dùng chỉ định model chỉ trả text (ví dụ gemini-1.5-flash không tạo ảnh)."""
    def handler(request: httpx.Request):
        return httpx.Response(
            200,
            json={
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": "Here is a description of a pixel art miner wearing a yellow helmet..."
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
            model="gemini-1.5-flash",
            client=mock_client,
        )
        with pytest.raises(LoiProviderAnh) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"description": "Thợ mỏ"}')
        assert "trả về văn bản thay vì hình ảnh" in str(exc_info.value)
        assert DEFAULT_MODEL in str(exc_info.value)


def test_gemini_loi_api_key_401_khong_lo_key():
    secret_key = "test-secret-key-xyz-999"

    def handler(request: httpx.Request):
        return httpx.Response(
            401,
            json={
                "error": {
                    "code": 401,
                    "message": f"API key {secret_key} is not valid.",
                    "status": "API_KEY_INVALID",
                }
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key=secret_key, client=mock_client)
        with pytest.raises(LoiProviderAnh) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')
        msg = str(exc_info.value)
        assert "API key Gemini không hợp lệ" in msg
        # Tuyệt đối không để lộ secret key trong message
        assert secret_key not in msg


def test_gemini_loi_404_model_imagen_cu_co_huong_dan():
    """Khi gọi model Imagen cũ bị Google đóng tháng 8/2026, thông báo phải giải thích rõ lý do."""
    def handler(request: httpx.Request):
        return httpx.Response(
            404,
            json={
                "error": {
                    "code": 404,
                    "message": "models/imagen-3.0-generate-002 is not found for API version v1beta, or is not supported for predict.",
                    "status": "NOT_FOUND",
                }
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", model="imagen-3.0-generate-002", client=mock_client)
        with pytest.raises(LoiProviderAnh) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')
        msg = str(exc_info.value)
        assert "HTTP 404" in msg
        assert "tháng 8/2026" in msg


def test_gemini_loi_400_bao_dung_nguyen_nhan_tu_google():
    """HTTP 400 từ Google (ví dụ sai field name) phải được thông báo chính xác nguyên nhân."""
    error_detail = 'Invalid JSON payload received. Unknown name "imageGenerationConfig" at \'generation_config\': Cannot find field.'

    def handler(request: httpx.Request):
        return httpx.Response(
            400,
            json={
                "error": {
                    "code": 400,
                    "message": error_detail,
                    "status": "INVALID_ARGUMENT",
                }
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", model="gemini-3.1-flash-image", client=mock_client)
        with pytest.raises(LoiProviderAnh) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')
        msg = str(exc_info.value)
        assert "HTTP 400" in msg
        assert "imageGenerationConfig" in msg


def test_gemini_loi_429_quota_exceeded():
    def handler(request: httpx.Request):
        return httpx.Response(
            429,
            json={"error": {"code": 429, "message": "Resource exhausted", "status": "RESOURCE_EXHAUSTED"}},
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", client=mock_client)
        with pytest.raises(LoiProviderAnh) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')
        assert "vượt quá hạn ngạch" in str(exc_info.value)


def test_gemini_loi_timeout():
    def handler(request: httpx.Request):
        raise httpx.ReadTimeout("Connection timed out")

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", timeout_seconds=5.0, client=mock_client)
        with pytest.raises(LoiProviderAnh) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')
        assert "Hết thời gian chờ" in str(exc_info.value)


def test_gemini_loi_api_tra_loi_provider():
    def handler(request: httpx.Request):
        return httpx.Response(500, json={"error": {"message": "Internal error"}})

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="key-test", client=mock_client)
        with pytest.raises(LoiProviderAnh) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "warrior"}')
        assert "500" in str(exc_info.value)


def test_gemini_live_tat_fallback_nem_loi_thay_vi_tra_demo():
    """Khi cho_phep_fallback=False, lỗi từ Gemini Live được re-raise để người dùng biết chính xác lý do."""
    def handler(request: httpx.Request):
        return httpx.Response(401, json={"error": {"status": "API_KEY_INVALID"}})

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        live_provider = GeminiRestAnhProvider(api_key="bad-key", client=mock_client)
        demo_provider = AnhMauOffline(ASSETS)

        # 1. Khi bật fallback (mặc định), tự lùi về demo
        kq_fallback = tao_anh_nhan_vat(
            YeuCauTaoNhanVat(description="Thợ mỏ vàng"),
            demo_provider=demo_provider,
            provider=live_provider,
            cho_phep_fallback=True,
        )
        assert kq_fallback.generation_source == "demo"

        # 2. Khi tắt fallback (Gemini Live nghiêm ngặt), ném thẳng lỗi ra ngoài
        with pytest.raises(LoiProviderAnh) as exc_info:
            tao_anh_nhan_vat(
                YeuCauTaoNhanVat(description="Thợ mỏ vàng"),
                demo_provider=demo_provider,
                provider=live_provider,
                cho_phep_fallback=False,
            )
        assert "API key Gemini không hợp lệ" in str(exc_info.value)


def test_gemini_provider_tu_moi_truong():
    # Khi tắt
    assert gemini_provider_tu_moi_truong({"AI_IMAGE_ENABLED": "false"}) is None

    # Khi bật nhưng không có provider=gemini hoặc key
    assert gemini_provider_tu_moi_truong({"AI_IMAGE_ENABLED": "true"}) is None

    # Khi chỉ định AI_IMAGE_PROVIDER=gemini, mặc định lấy DEFAULT_MODEL
    p1 = gemini_provider_tu_moi_truong({
        "AI_IMAGE_ENABLED": "true",
        "AI_IMAGE_PROVIDER": "gemini",
        "GEMINI_API_KEY": "test-key-12345",
        "AI_IMAGE_TIMEOUT_SECONDS": "12",
    })
    assert p1 is not None
    assert p1.model == DEFAULT_MODEL
    assert p1.timeout_seconds == 12.0
    assert p1._api_key == "test-key-12345"

    # Khi cấu hình model tùy chỉnh
    p2 = gemini_provider_tu_moi_truong({
        "AI_IMAGE_ENABLED": "true",
        "GEMINI_API_KEY": "test-key-67890",
        "AI_IMAGE_MODEL": "gemini-3.1-flash-image",
    })
    assert p2 is not None
    assert p2._api_key == "test-key-67890"
    assert p2.model == "gemini-3.1-flash-image"


def test_gemini_chan_doan_429_quota_bang_khong_violation():
    """Kiểm thử chẩn đoán lỗi 429 khi Google trả quotaValue = 0 (Free Tier / chưa cấp quota)."""
    payload_google = {
        "error": {
            "code": 429,
            "message": "Quota exceeded for quota metric 'GenerateContent requests per minute' and limit 'GenerateContent requests per minute' of service 'generativelanguage.googleapis.com'.",
            "status": "RESOURCE_EXHAUSTED",
            "details": [
                {
                    "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                    "violations": [
                        {
                            "subject": "project:123456789",
                            "description": "Quota exceeded for quota metric 'GenerateContent requests per minute' and limit 'GenerateContent requests per minute' (limit: 0).",
                            "quotaMetric": "generativelanguage.googleapis.com/generate_content_requests",
                            "quotaId": "GenerateContentRequestsPerMinute",
                            "quotaValue": "0",
                        }
                    ],
                },
                {
                    "@type": "type.googleapis.com/google.rpc.RetryInfo",
                    "retryDelay": "0s",
                },
            ],
        }
    }

    call_count = 0

    def handler(request: httpx.Request):
        nonlocal call_count
        call_count += 1
        return httpx.Response(429, json=payload_google)

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(
            api_key="valid-key",
            model="gemini-2.5-flash-image",
            client=mock_client,
        )
        with pytest.raises(LoiQuotaGemini) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')

    assert call_count == 1  # Không tự động retry khi gặp 429
    err = exc_info.value
    assert isinstance(err, LoiProviderAnh)
    assert err.chan_doan.loai_quota == "quota_zero"
    assert err.chan_doan.quota_value == "0"
    assert err.chan_doan.quota_id == "GenerateContentRequestsPerMinute"
    assert "Hạn ngạch bằng 0" in str(err)
    assert "Free Tier" in str(err)


def test_gemini_chan_doan_429_quota_bang_khong_error_info_metadata():
    """Kiểm thử chẩn đoán quota 0 thông qua ErrorInfo metadata."""
    payload_google = {
        "error": {
            "code": 429,
            "message": "Resource has been exhausted (e.g. check quota).",
            "status": "RESOURCE_EXHAUSTED",
            "details": [
                {
                    "@type": "type.googleapis.com/google.rpc.ErrorInfo",
                    "reason": "RATE_LIMIT_EXCEEDED",
                    "domain": "googleapis.com",
                    "metadata": {
                        "quota_limit": "0",
                        "quota_limit_value": "0",
                        "quota_metric": "generativelanguage.googleapis.com/generate_content_requests",
                    },
                }
            ],
        }
    }

    def handler(request: httpx.Request):
        return httpx.Response(429, json=payload_google)

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", client=mock_client)
        with pytest.raises(LoiQuotaGemini) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')

    err = exc_info.value
    assert err.chan_doan.loai_quota == "quota_zero"
    assert err.chan_doan.quota_value == "0"


def test_gemini_chan_doan_429_gioi_han_phut_voi_retry_delay_va_header():
    """Kiểm thử giới hạn theo phút với retryDelay và header Retry-After."""
    payload_google = {
        "error": {
            "code": 429,
            "message": "Quota exceeded for quota metric 'GenerateContent requests per minute'.",
            "status": "RESOURCE_EXHAUSTED",
            "details": [
                {
                    "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                    "violations": [
                        {
                            "description": "Per-minute rate limit reached.",
                            "quotaMetric": "generativelanguage.googleapis.com/generate_content_requests",
                            "quotaId": "GenerateContentRequestsPerMinute",
                            "quotaValue": "15",
                        }
                    ],
                },
                {
                    "@type": "type.googleapis.com/google.rpc.RetryInfo",
                    "retryDelay": "24.5s",
                },
            ],
        }
    }

    def handler(request: httpx.Request):
        return httpx.Response(429, json=payload_google, headers={"Retry-After": "30"})

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", client=mock_client)
        with pytest.raises(LoiQuotaGemini) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')

    err = exc_info.value
    assert err.chan_doan.loai_quota == "rate_limit_minute"
    assert err.chan_doan.retry_delay == "24.5s"
    assert err.chan_doan.retry_after == "30"
    assert "Vượt giới hạn lượt gọi theo phút" in str(err)
    assert "24.5s" in str(err)


def test_gemini_chan_doan_429_gioi_han_ngay():
    """Kiểm thử hết quota ngày (Requests Per Day)."""
    payload_google = {
        "error": {
            "code": 429,
            "message": "Daily request limit exceeded.",
            "status": "RESOURCE_EXHAUSTED",
            "details": [
                {
                    "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                    "violations": [
                        {
                            "description": "Daily request quota reached.",
                            "quotaMetric": "generativelanguage.googleapis.com/generate_content_requests",
                            "quotaId": "GenerateContentRequestsPerDay",
                            "quotaValue": "50",
                        }
                    ],
                }
            ],
        }
    }

    def handler(request: httpx.Request):
        return httpx.Response(429, json=payload_google)

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", client=mock_client)
        with pytest.raises(LoiQuotaGemini) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')

    err = exc_info.value
    assert err.chan_doan.loai_quota == "daily_quota_exhausted"
    assert "Hết hạn ngạch theo ngày" in str(err)


def test_gemini_chan_doan_429_chua_du_thong_tin():
    """Kiểm thử khi Google chỉ trả RESOURCE_EXHAUSTED chung chung."""
    payload_google = {
        "error": {
            "code": 429,
            "message": "Resource has been exhausted.",
            "status": "RESOURCE_EXHAUSTED",
        }
    }

    def handler(request: httpx.Request):
        return httpx.Response(429, json=payload_google)

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key="valid-key", client=mock_client)
        with pytest.raises(LoiQuotaGemini) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')

    err = exc_info.value
    assert err.chan_doan.loai_quota == "insufficient_info"
    assert "Chưa đủ thông tin phân loại" in str(err)


def test_gemini_chan_doan_429_khong_lo_api_key_hoac_secret():
    """Bảo đảm API key hoặc pattern AIza... trong response không bị rò rỉ ra ngoài log/exception."""
    secret_key = "AIzaSyD-SecretApiKeyTest9876543210123"
    payload_google = {
        "error": {
            "code": 429,
            "message": f"Quota exceeded for project with key {secret_key}.",
            "status": "RESOURCE_EXHAUSTED",
            "details": [
                {
                    "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                    "violations": [
                        {
                            "description": f"Key {secret_key} reached limit: 0",
                            "quotaValue": "0",
                        }
                    ],
                }
            ],
        }
    }

    def handler(request: httpx.Request):
        return httpx.Response(429, json=payload_google)

    with httpx.Client(transport=httpx.MockTransport(handler)) as mock_client:
        provider = GeminiRestAnhProvider(api_key=secret_key, client=mock_client)
        with pytest.raises(LoiQuotaGemini) as exc_info:
            provider.sinh(system_prompt="Sys", user_prompt='{"desc": "miner"}')

    err_str = str(exc_info.value)
    assert secret_key not in err_str
    assert "[REDACTED_API_KEY]" in err_str
    assert exc_info.value.chan_doan.loai_quota == "quota_zero"

