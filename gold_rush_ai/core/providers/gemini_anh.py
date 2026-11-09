from __future__ import annotations

import base64
from collections.abc import Mapping
from contextlib import nullcontext
import json
import math
import os
from typing import Literal

import httpx

from .anh import LoiProviderAnh

_GIOI_HAN_JSON = 8 * 1024 * 1024
_GIOI_HAN_ANH = 5 * 1024 * 1024


class GeminiRestAnhProvider:
    """Adapter tích hợp Gemini / Imagen Image Generation qua REST API của Google AI Studio.

    Hỗ trợ cả endpoint predict (Imagen 3) và generateImages / generateContent.
    Bảo đảm:
    - Không hardcode API key.
    - Không log secret hay prompt nhạy cảm.
    - Kiểm soát timeout, dung lượng JSON và kích thước ảnh.
    - Tuân thủ protocol NhaCungCapAnh với generation_source='image_model'.
    """

    generation_source: Literal["image_model"] = "image_model"

    def __init__(
        self,
        *,
        api_key: str | None = None,
        model: str = "imagen-3.0-generate-002",
        base_url: str = "https://generativelanguage.googleapis.com",
        timeout_seconds: float = 15.0,
        client: httpx.Client | None = None,
    ):
        if not isinstance(model, str) or not model.strip():
            raise ValueError("Cần cấu hình model Gemini")
        try:
            endpoint = httpx.URL(base_url)
        except (httpx.InvalidURL, ValueError, TypeError):
            raise ValueError("Base URL Gemini không hợp lệ") from None
        if endpoint.scheme not in ("http", "https") or not endpoint.host:
            raise ValueError("Base URL Gemini cần scheme HTTP(S)")
        if (
            isinstance(timeout_seconds, bool)
            or not isinstance(timeout_seconds, (int, float))
            or not math.isfinite(timeout_seconds)
            or not 0 < timeout_seconds <= 60
        ):
            raise ValueError("Timeout Gemini phải nằm trong (0, 60] giây")
        if api_key is not None and (
            not isinstance(api_key, str)
            or not 1 <= len(api_key) <= 4096
            or not api_key.isascii()
            or any(ord(c) <= 32 or ord(c) >= 127 for c in api_key)
        ):
            raise ValueError("API key Gemini không hợp lệ")

        self.model = model.strip()
        self.base_url = endpoint
        self.timeout_seconds = float(timeout_seconds)
        self._api_key = api_key
        self._client = client

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        try:
            for prompt in (system_prompt, user_prompt):
                if (
                    not isinstance(prompt, str)
                    or not prompt.strip()
                    or len(prompt.encode("utf-8")) > 16000
                ):
                    raise LoiProviderAnh("Prompt sinh ảnh Gemini không hợp lệ")
        except UnicodeError:
            raise LoiProviderAnh("Prompt sinh ảnh Gemini không hợp lệ") from None

        full_prompt = (
            f"{system_prompt}\n\n"
            f"User requested character specification (JSON):\n{user_prompt}\n\n"
            "Style: pixel-art, crisp square pixels, retro 16-bit game asset, centered single frame."
        )

        url = f"{str(self.base_url).rstrip('/')}/v1beta/models/{self.model}:predict"
        payload = {
            "instances": [{"prompt": full_prompt}],
            "parameters": {
                "sampleCount": 1,
                "aspectRatio": "1:1",
                "outputOptions": {"mimeType": "image/png"},
            },
        }

        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Accept-Encoding": "identity",
        }
        if self._api_key:
            headers["x-goog-api-key"] = self._api_key

        try:
            manager = nullcontext(self._client) if self._client is not None else httpx.Client()
            with manager as client:
                with client.stream(
                    "POST",
                    url,
                    json=payload,
                    headers=headers,
                    timeout=self.timeout_seconds,
                    follow_redirects=False,
                ) as response:
                    if response.status_code != 200:
                        raise LoiProviderAnh(f"Dịch vụ Gemini trả mã lỗi {response.status_code}")
                    if response.headers.get("content-encoding", "identity").strip().lower() != "identity":
                        raise LoiProviderAnh("Phản hồi Gemini dùng encoding chưa hỗ trợ")
                    body = bytearray()
                    for chunk in response.iter_bytes(chunk_size=4096):
                        if len(body) + len(chunk) > _GIOI_HAN_JSON:
                            raise LoiProviderAnh("Phản hồi Gemini vượt giới hạn dung lượng")
                        body.extend(chunk)

            data = json.loads(body)
            raw_base64 = self._trich_xuat_base64(data)
            raw_bytes = base64.b64decode(raw_base64, validate=True)
            if not raw_bytes or len(raw_bytes) > _GIOI_HAN_ANH:
                raise LoiProviderAnh("Dữ liệu ảnh Gemini rỗng hoặc vượt giới hạn")
            return raw_bytes
        except (httpx.HTTPError, ValueError, TypeError, RecursionError):
            raise LoiProviderAnh("Không nhận được phản hồi sinh ảnh Gemini hợp lệ") from None

    @staticmethod
    def _trich_xuat_base64(data: dict) -> str:
        if not isinstance(data, dict) or "error" in data:
            raise LoiProviderAnh("Phản hồi Gemini chứa thông báo lỗi")

        # 1. Format Imagen 3 (:predict) -> predictions[0].bytesBase64Encoded
        predictions = data.get("predictions")
        if isinstance(predictions, list) and len(predictions) >= 1 and isinstance(predictions[0], dict):
            b64 = predictions[0].get("bytesBase64Encoded")
            if isinstance(b64, str) and b64:
                return b64

        # 2. Format generateImages -> generatedImages[0].image.imageBytes
        gen_images = data.get("generatedImages")
        if isinstance(gen_images, list) and len(gen_images) >= 1 and isinstance(gen_images[0], dict):
            img_obj = gen_images[0].get("image")
            if isinstance(img_obj, dict):
                b64 = img_obj.get("imageBytes")
                if isinstance(b64, str) and b64:
                    return b64

        # 3. Format generateContent -> candidates[0].content.parts[0].inlineData.data
        candidates = data.get("candidates")
        if isinstance(candidates, list) and len(candidates) >= 1 and isinstance(candidates[0], dict):
            parts = candidates[0].get("content", {}).get("parts", [])
            for part in parts:
                inline = part.get("inlineData", {})
                b64 = inline.get("data")
                if isinstance(b64, str) and b64:
                    return b64

        raise LoiProviderAnh("Cấu trúc phản hồi ảnh Gemini không đúng định dạng mong đợi")


def gemini_provider_tu_moi_truong(
    moi_truong: Mapping[str, str] | None = None, *, client: httpx.Client | None = None
) -> GeminiRestAnhProvider | None:
    """Tạo provider Gemini nếu môi trường bật AI_IMAGE_ENABLED=true và cấu hình GEMINI_API_KEY hoặc AI_IMAGE_PROVIDER=gemini."""
    env = os.environ if moi_truong is None else moi_truong
    bat = env.get("AI_IMAGE_ENABLED", "false").strip().lower()
    if bat not in ("true", "1"):
        return None

    provider_type = env.get("AI_IMAGE_PROVIDER", "").strip().lower()
    gemini_key = env.get("GEMINI_API_KEY", "").strip() or env.get("AI_IMAGE_API_KEY", "").strip()

    # Chỉ kích hoạt adapter Gemini nếu chỉ định rõ hoặc có GEMINI_API_KEY mà không có AI_IMAGE_URL
    if provider_type != "gemini" and not (gemini_key and not env.get("AI_IMAGE_URL")):
        return None

    timeout_str = env.get("AI_IMAGE_TIMEOUT_SECONDS", "15")
    try:
        timeout = float(timeout_str)
    except ValueError:
        raise ValueError("AI_IMAGE_TIMEOUT_SECONDS không hợp lệ") from None

    model = env.get("AI_IMAGE_MODEL", "").strip() or "imagen-3.0-generate-002"
    base_url = env.get("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com").strip()

    return GeminiRestAnhProvider(
        api_key=gemini_key or None,
        model=model,
        base_url=base_url,
        timeout_seconds=timeout,
        client=client,
    )
