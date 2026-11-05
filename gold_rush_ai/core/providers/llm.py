from __future__ import annotations

from collections.abc import Mapping
from contextlib import nullcontext
import json
import math
import os
from typing import Protocol

import httpx


class LoiProviderLLM(RuntimeError):
    pass


class NhaCungCapLLM(Protocol):
    def sinh(self, *, system_prompt: str, user_prompt: str) -> str:
        ...


class ChatCompletionsLLM:
    def __init__(self, *, url: str, model: str, api_key: str | None = None,
                 timeout_seconds: float = 10, client: httpx.Client | None = None):
        try:
            endpoint = httpx.URL(url)
        except (httpx.InvalidURL, TypeError):
            raise ValueError("URL LLM không hợp lệ") from None
        if (endpoint.scheme not in ("http", "https") or not endpoint.host
                or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment):
            raise ValueError("URL LLM cần HTTP(S), không chứa key hoặc thông tin đăng nhập")
        if not isinstance(model, str) or not model.strip():
            raise ValueError("Cần cấu hình model LLM")
        if (isinstance(timeout_seconds, bool) or not isinstance(timeout_seconds, (int, float))
                or not math.isfinite(timeout_seconds) or not 0 < timeout_seconds <= 60):
            raise ValueError("Timeout LLM phải nằm trong (0, 60] giây")
        self.url = endpoint
        self.model = model.strip()
        self.timeout_seconds = float(timeout_seconds)
        self._api_key = api_key
        self._client = client

    def sinh(self, *, system_prompt: str, user_prompt: str) -> str:
        payload = {
            "model": self.model,
            "messages": [{"role": "system", "content": system_prompt},
                         {"role": "user", "content": user_prompt}],
            "stream": False,
            "max_tokens": 1024,
            "response_format": {"type": "json_object"},
        }
        headers = {"Authorization": f"Bearer {self._api_key}"} if self._api_key else {}
        manager = nullcontext(self._client) if self._client is not None else httpx.Client()
        try:
            with manager as client:
                with client.stream("POST", self.url, json=payload, headers=headers,
                                   timeout=self.timeout_seconds, follow_redirects=False) as response:
                    response.raise_for_status()
                    body = bytearray()
                    for chunk in response.iter_bytes(chunk_size=4096):
                        body.extend(chunk)
                        if len(body) > 65536:
                            raise LoiProviderLLM("Phản hồi LLM vượt giới hạn dung lượng")
            data = json.loads(body)
            choice = data["choices"][0]
            message = choice["message"]
            content = message["content"]
            if (not isinstance(content, str) or not content.strip() or message.get("refusal")
                    or choice.get("finish_reason") not in (None, "stop")):
                raise LoiProviderLLM("LLM không trả nội dung hoàn chỉnh")
            return content
        except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError, RecursionError):
            raise LoiProviderLLM("Không nhận được phản hồi LLM hợp lệ") from None


def provider_tu_moi_truong(moi_truong: Mapping[str, str] | None = None) -> ChatCompletionsLLM | None:
    env = os.environ if moi_truong is None else moi_truong
    bat = env.get("LLM_ENABLED", "false").strip().lower()
    if bat in ("false", "0", ""):
        return None
    if bat not in ("true", "1"):
        raise ValueError("LLM_ENABLED phải là true hoặc false")
    try:
        timeout = float(env.get("LLM_TIMEOUT_SECONDS", "10"))
    except ValueError:
        raise ValueError("LLM_TIMEOUT_SECONDS không hợp lệ") from None
    return ChatCompletionsLLM(url=env.get("LLM_CHAT_URL", ""), model=env.get("LLM_MODEL", ""),
                              api_key=env.get("LLM_API_KEY") or None, timeout_seconds=timeout)
