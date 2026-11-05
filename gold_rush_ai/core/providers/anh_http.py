"""HTTP adapter cho Images API trả data[0].b64_json, tương thích GPT Image.

Không tự chọn URL/model hoặc gọi mạng lúc khởi tạo. Chỉ một POST, không retry,
không tải URL ảnh từ response. Pipeline ai_nhan_vat kiểm tra ảnh và chuẩn hóa.
Contract: https://developers.openai.com/api/reference/resources/images/methods/generate
"""
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


class ImagesGenerationsAnh:
    """Sinh một PNG vuông; timeout áp dụng cho mỗi thao tác HTTP.

    URL/model do server cấu hình, cần hỗ trợ output_format=png, nền trong suốt
    và dữ liệu base64. Client inject thuộc caller; client tự tạo được đóng.
    Không có deadline tổng cho toàn bộ thời gian sinh và đọc stream.
    """

    generation_source: Literal["image_model"] = "image_model"

    def __init__(self, *, url: str, model: str, api_key: str | None = None,
                 timeout_seconds: float = 10, client: httpx.Client | None = None):
        try:
            endpoint = httpx.URL(url)
        except (httpx.InvalidURL, ValueError, TypeError):
            raise ValueError("URL sinh ảnh không hợp lệ") from None
        if (endpoint.scheme not in ("http", "https") or not endpoint.host
                or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment):
            raise ValueError("URL sinh ảnh cần HTTP(S), không chứa key hoặc thông tin đăng nhập")
        if not isinstance(model, str) or not model.strip():
            raise ValueError("Cần cấu hình model sinh ảnh")
        if (isinstance(timeout_seconds, bool) or not isinstance(timeout_seconds, (int, float))
                or not math.isfinite(timeout_seconds) or not 0 < timeout_seconds <= 60):
            raise ValueError("Timeout sinh ảnh phải nằm trong (0, 60] giây")
        if api_key is not None and (
            not isinstance(api_key, str) or not 1 <= len(api_key) <= 4096
            or not api_key.isascii() or any(ord(c) <= 32 or ord(c) >= 127 for c in api_key)
        ):
            raise ValueError("API key sinh ảnh không hợp lệ")
        self.url = endpoint
        self.model = model.strip()
        self.timeout_seconds = float(timeout_seconds)
        self._api_key = api_key
        self._client = client

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        try:
            for prompt in (system_prompt, user_prompt):
                if (not isinstance(prompt, str) or not prompt.strip()
                        or len(prompt.encode("utf-8")) > 16000):
                    raise LoiProviderAnh("Prompt sinh ảnh không hợp lệ")
        except UnicodeError:
            raise LoiProviderAnh("Prompt sinh ảnh không hợp lệ") from None
        payload = {
            "model": self.model,
            "prompt": f"{system_prompt}\n\nUser description (JSON data):\n{user_prompt}",
            "n": 1,
            "size": "1024x1024",
            "output_format": "png",
            "background": "transparent",
            "quality": "low",
            "stream": False,
        }
        headers = {"Accept": "application/json", "Accept-Encoding": "identity"}
        if self._api_key:
            headers["Authorization"] = f"Bearer {self._api_key}"
        try:
            manager = nullcontext(self._client) if self._client is not None else httpx.Client()
            with manager as client:
                with client.stream("POST", self.url, json=payload, headers=headers,
                                   timeout=self.timeout_seconds, follow_redirects=False) as response:
                    if response.status_code != 200:
                        raise LoiProviderAnh("Dịch vụ ảnh chưa trả kết quả hợp lệ")
                    # Không giải nén HTTP trước khi giới hạn byte dữ liệu.
                    if response.headers.get("content-encoding", "identity").strip().lower() != "identity":
                        raise LoiProviderAnh("Phản hồi ảnh dùng encoding chưa hỗ trợ")
                    body = bytearray()
                    for chunk in response.iter_bytes(chunk_size=4096):
                        if len(body) + len(chunk) > _GIOI_HAN_JSON:
                            raise LoiProviderAnh("Phản hồi sinh ảnh vượt giới hạn dung lượng")
                        body.extend(chunk)
            data = json.loads(body)
            if not isinstance(data, dict) or "error" in data:
                raise LoiProviderAnh("Phản hồi sinh ảnh không hợp lệ")
            images = data.get("data")
            if (not isinstance(images, list) or len(images) != 1
                    or not isinstance(images[0], dict)):
                raise LoiProviderAnh("Cần đúng một ảnh trong phản hồi")
            encoded = images[0].get("b64_json")
            if (not isinstance(encoded, str) or not encoded
                    or len(encoded) > 4 * ((_GIOI_HAN_ANH + 2) // 3)):
                raise LoiProviderAnh("Dữ liệu ảnh thiếu hoặc vượt giới hạn")
            raw = base64.b64decode(encoded, validate=True)
            if not raw or len(raw) > _GIOI_HAN_ANH:
                raise LoiProviderAnh("Dữ liệu ảnh thiếu hoặc vượt giới hạn")
            return raw
        except (httpx.HTTPError, ValueError, TypeError, RecursionError):
            # Không đưa body/URL/header/prompt vào lỗi hoặc retry có thể tính phí.
            raise LoiProviderAnh("Không nhận được phản hồi sinh ảnh hợp lệ") from None


def provider_anh_tu_moi_truong(
    moi_truong: Mapping[str, str] | None = None, *, client: httpx.Client | None = None,
) -> ImagesGenerationsAnh | None:
    """Chỉ tạo provider khi AI_IMAGE_ENABLED=true; không tự nạp .env hay gọi mạng."""
    env = os.environ if moi_truong is None else moi_truong
    bat = env.get("AI_IMAGE_ENABLED", "false").strip().lower()
    if bat in ("false", "0", ""):
        return None
    if bat not in ("true", "1"):
        raise ValueError("AI_IMAGE_ENABLED phải là true hoặc false")
    try:
        timeout = float(env.get("AI_IMAGE_TIMEOUT_SECONDS", "10"))
    except ValueError:
        raise ValueError("AI_IMAGE_TIMEOUT_SECONDS không hợp lệ") from None
    return ImagesGenerationsAnh(
        url=env.get("AI_IMAGE_URL", ""), model=env.get("AI_IMAGE_MODEL", ""),
        api_key=env.get("AI_IMAGE_API_KEY") or None, timeout_seconds=timeout, client=client,
    )