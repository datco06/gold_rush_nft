from __future__ import annotations

import base64
import binascii
from collections.abc import Mapping
from contextlib import nullcontext
import json
import math
import re
from typing import Literal

import httpx

from .anh import LoiProviderAnh


DEFAULT_MODEL = "@cf/black-forest-labs/flux-1-schnell"
_BASE_URL = "https://api.cloudflare.com/client/v4/accounts"
_GIOI_HAN_JSON = 8 * 1024 * 1024
_GIOI_HAN_ANH = 5 * 1024 * 1024
_ACCOUNT_ID = re.compile(r"^[0-9a-fA-F]{32}$")
_MODEL_ID = re.compile(r"^@cf/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")


class CloudflareWorkersAnh:
    """Sinh ảnh bằng Cloudflare Workers AI REST API."""

    generation_source: Literal["image_model"] = "image_model"

    def __init__(
        self,
        *,
        account_id: str,
        api_token: str,
        model: str = DEFAULT_MODEL,
        steps: int = 4,
        timeout_seconds: float = 60,
        client: httpx.Client | None = None,
    ):
        if not isinstance(account_id, str) or not _ACCOUNT_ID.fullmatch(account_id.strip()):
            raise ValueError("CLOUDFLARE_ACCOUNT_ID không hợp lệ")
        if (
            not isinstance(api_token, str)
            or not 1 <= len(api_token) <= 4096
            or not api_token.isascii()
            or any(ord(char) <= 32 or ord(char) >= 127 for char in api_token)
        ):
            raise ValueError("CLOUDFLARE_API_TOKEN không hợp lệ")
        if not isinstance(model, str) or not _MODEL_ID.fullmatch(model.strip()):
            raise ValueError("CLOUDFLARE_IMAGE_MODEL không hợp lệ")
        if isinstance(steps, bool) or not isinstance(steps, int) or not 1 <= steps <= 8:
            raise ValueError("CLOUDFLARE_IMAGE_STEPS phải nằm trong [1, 8]")
        if (
            isinstance(timeout_seconds, bool)
            or not isinstance(timeout_seconds, (int, float))
            or not math.isfinite(timeout_seconds)
            or not 0 < timeout_seconds <= 60
        ):
            raise ValueError("AI_IMAGE_TIMEOUT_SECONDS phải nằm trong (0, 60] giây")

        self.account_id = account_id.strip().lower()
        self.model = model.strip()
        self.steps = steps
        self.timeout_seconds = float(timeout_seconds)
        self._api_token = api_token
        self._client = client
        self.url = httpx.URL(f"{_BASE_URL}/{self.account_id}/ai/run/{self.model}")

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        prompt = self._tao_prompt(system_prompt, user_prompt)
        headers = {
            "Accept": "application/json, image/jpeg, image/png",
            "Accept-Encoding": "identity",
            "Authorization": f"Bearer {self._api_token}",
            "Content-Type": "application/json",
        }
        try:
            manager = nullcontext(self._client) if self._client is not None else httpx.Client()
            with manager as client:
                with client.stream(
                    "POST",
                    self.url,
                    json={"prompt": prompt, "steps": self.steps},
                    headers=headers,
                    timeout=self.timeout_seconds,
                    follow_redirects=False,
                ) as response:
                    if response.status_code != 200:
                        raise self._loi_http(response.status_code)
                    if response.headers.get("content-encoding", "identity").strip().lower() != "identity":
                        raise LoiProviderAnh("Phản hồi Cloudflare dùng encoding chưa hỗ trợ")
                    content_type = response.headers.get("content-type", "").split(";", 1)[0].strip().lower()
                    limit = _GIOI_HAN_ANH if content_type in ("image/jpeg", "image/png") else _GIOI_HAN_JSON
                    body = bytearray()
                    for chunk in response.iter_bytes(chunk_size=4096):
                        if len(body) + len(chunk) > limit:
                            raise LoiProviderAnh("Phản hồi Cloudflare vượt giới hạn dung lượng")
                        body.extend(chunk)

            if content_type in ("image/jpeg", "image/png"):
                if not body:
                    raise LoiProviderAnh("Cloudflare không trả dữ liệu ảnh")
                return bytes(body)
            return self._doc_anh_base64(body)
        except LoiProviderAnh:
            raise
        except (httpx.HTTPError, ValueError, TypeError, UnicodeError, RecursionError):
            raise LoiProviderAnh("Không nhận được phản hồi Cloudflare hợp lệ") from None

    @staticmethod
    def _tao_prompt(system_prompt: str, user_prompt: str) -> str:
        if not isinstance(system_prompt, str) or not system_prompt.strip():
            raise LoiProviderAnh("Prompt sinh ảnh không hợp lệ")
        if not isinstance(user_prompt, str) or not user_prompt.strip():
            raise LoiProviderAnh("Prompt sinh ảnh không hợp lệ")
        prompt = f"{system_prompt.strip()}\n\nUser description (JSON data):\n{user_prompt.strip()}"
        if len(prompt) > 2048:
            raise LoiProviderAnh("Prompt Cloudflare vượt giới hạn 2048 ký tự")
        return prompt

    @staticmethod
    def _loi_http(status_code: int) -> LoiProviderAnh:
        if status_code in (401, 403):
            return LoiProviderAnh("Cloudflare từ chối thông tin xác thực")
        if status_code == 404:
            return LoiProviderAnh("Không tìm thấy tài khoản hoặc model Cloudflare")
        if status_code == 429:
            return LoiProviderAnh("Đã vượt giới hạn Cloudflare Workers AI")
        if status_code >= 500:
            return LoiProviderAnh("Dịch vụ Cloudflare Workers AI đang không khả dụng")
        return LoiProviderAnh("Cloudflare chưa trả kết quả hợp lệ")

    @staticmethod
    def _doc_anh_base64(body: bytes | bytearray) -> bytes:
        try:
            data = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError, RecursionError):
            raise LoiProviderAnh("Phản hồi Cloudflare không phải JSON hợp lệ") from None
        if not isinstance(data, dict) or data.get("success") is False or data.get("errors"):
            raise LoiProviderAnh("Cloudflare báo lỗi khi sinh ảnh")

        result = data.get("result", data)
        if isinstance(result, dict):
            encoded = result.get("image")
        elif isinstance(result, str):
            encoded = result
        else:
            encoded = None
        if not isinstance(encoded, str) or not encoded:
            raise LoiProviderAnh("Cloudflare không trả ảnh Base64")
        if encoded.startswith("data:"):
            try:
                metadata, encoded = encoded.split(",", 1)
            except ValueError:
                raise LoiProviderAnh("Dữ liệu ảnh Cloudflare không hợp lệ") from None
            if metadata not in (
                "data:image/jpeg;base64",
                "data:image/jpeg;charset=utf-8;base64",
                "data:image/png;base64",
            ):
                raise LoiProviderAnh("Định dạng ảnh Cloudflare chưa hỗ trợ")
        if len(encoded) > 4 * ((_GIOI_HAN_ANH + 2) // 3):
            raise LoiProviderAnh("Ảnh Cloudflare vượt giới hạn dung lượng")
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, binascii.Error):
            raise LoiProviderAnh("Dữ liệu ảnh Cloudflare không phải Base64 hợp lệ") from None
        if not raw or len(raw) > _GIOI_HAN_ANH:
            raise LoiProviderAnh("Ảnh Cloudflare thiếu hoặc vượt giới hạn dung lượng")
        return raw


def cloudflare_provider_tu_moi_truong(
    moi_truong: Mapping[str, str], *, client: httpx.Client | None = None,
) -> CloudflareWorkersAnh | None:
    account_id = moi_truong.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    api_token = moi_truong.get("CLOUDFLARE_API_TOKEN", "").strip()
    if not account_id and not api_token:
        return None
    if not account_id or not api_token:
        raise ValueError("Cần cấu hình cả CLOUDFLARE_ACCOUNT_ID và CLOUDFLARE_API_TOKEN")
    try:
        steps = int(moi_truong.get("CLOUDFLARE_IMAGE_STEPS", "4"))
        timeout = float(moi_truong.get("AI_IMAGE_TIMEOUT_SECONDS", "60"))
    except ValueError:
        raise ValueError("Cấu hình số của Cloudflare không hợp lệ") from None
    return CloudflareWorkersAnh(
        account_id=account_id,
        api_token=api_token,
        model=moi_truong.get("CLOUDFLARE_IMAGE_MODEL", "").strip() or DEFAULT_MODEL,
        steps=steps,
        timeout_seconds=timeout,
        client=client,
    )
