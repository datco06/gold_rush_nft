from __future__ import annotations

from typing import Literal

from ..quota_ai import KhoQuotaAI
from .anh import NhaCungCapAnh
from .llm import NhaCungCapLLM


class AnhCoQuota:
    def __init__(self, provider: NhaCungCapAnh, quota: KhoQuotaAI, player_id: str, gioi_han: int):
        self.provider = provider
        self.quota = quota
        self.player_id = player_id
        self.gioi_han = gioi_han

    @property
    def generation_source(self) -> Literal["demo", "image_model"]:
        return self.provider.generation_source

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        self.quota.tieu_thu(self.player_id, "image", self.gioi_han)
        return self.provider.sinh(system_prompt=system_prompt, user_prompt=user_prompt)


class LLMCoQuota:
    def __init__(self, provider: NhaCungCapLLM, quota: KhoQuotaAI, player_id: str, gioi_han: int):
        self.provider = provider
        self.quota = quota
        self.player_id = player_id
        self.gioi_han = gioi_han

    def sinh(self, *, system_prompt: str, user_prompt: str) -> str:
        self.quota.tieu_thu(self.player_id, "quest", self.gioi_han)
        return self.provider.sinh(system_prompt=system_prompt, user_prompt=user_prompt)
