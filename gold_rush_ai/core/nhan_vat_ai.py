from __future__ import annotations

from typing import Literal, Self
import unicodedata

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

KICH_THUOC_ANH_XEM_TRUOC = 128


class _Schema(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True, frozen=True)


class YeuCauTaoNhanVat(_Schema):
    description: str = Field(min_length=1, max_length=500)

    @field_validator("description")
    @classmethod
    def _kiem_tra_ky_tu(cls, value: str) -> str:
        if any(unicodedata.category(ch) == "Cc" and ch not in "\n\r\t" for ch in value):
            raise ValueError("Mô tả có ký tự điều khiển không hợp lệ")
        return value


class AnhNhanVat(_Schema):
    image_id: str = Field(min_length=36, max_length=36, pattern=r"^img_[0-9a-f]{32}$")
    image_url: str = Field(min_length=1, max_length=100)
    width: int = Field(ge=KICH_THUOC_ANH_XEM_TRUOC, le=KICH_THUOC_ANH_XEM_TRUOC)
    height: int = Field(ge=KICH_THUOC_ANH_XEM_TRUOC, le=KICH_THUOC_ANH_XEM_TRUOC)
    status: Literal["ready"] = "ready"
    generation_source: Literal["demo", "image_model"]
    schema_version: int = Field(default=1, ge=1, le=1)

    @model_validator(mode="after")
    def _kiem_tra_duong_dan(self) -> Self:
        if self.image_url != f"/api/ai/nhan-vat/anh/{self.image_id}":
            raise ValueError("URL ảnh phải khớp endpoint ảnh và ID do máy chủ cấp")
        return self
