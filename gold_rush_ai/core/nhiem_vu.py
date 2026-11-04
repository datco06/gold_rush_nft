"""Schema nhiệm vụ dùng chung cho provider, nghiệp vụ và API về sau.

collect_coins: target là số xu; finish_before_time: target luôn là 1 màn;
finish_with_max_hits: target là số lần trúng đòn tối đa khi hoàn thành màn.
Đề xuất AI chỉ chứa nội dung/mục tiêu; server sở hữu ID, màn, nguồn và thưởng.
"""
from __future__ import annotations

from typing import Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator


class _Schema(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True, frozen=True)


class YeuCauTaoNhiemVu(_Schema):
    """player_id là tham chiếu, không phải bằng chứng xác thực hoặc mở khóa màn."""

    stage_id: int = Field(ge=1, le=1000)
    player_id: str | None = Field(default=None, min_length=1, max_length=64,
                                  pattern=r"^[A-Za-z0-9_-]+$")


class DeXuatNhiemVu(_Schema):
    title: str = Field(min_length=1, max_length=80)
    description: str = Field(min_length=1, max_length=500)
    objective: Literal["collect_coins", "finish_before_time", "finish_with_max_hits"]
    target: int = Field(ge=0, le=100000)
    time_limit_seconds: int | None = Field(default=None, ge=1, le=3600)
    difficulty: Literal["easy", "medium", "hard"]

    @model_validator(mode="after")
    def kiem_tra_muc_tieu(self) -> Self:
        if self.objective == "collect_coins" and self.target < 1:
            raise ValueError("Nhiệm vụ nhặt xu cần target ít nhất 1")
        if self.objective == "finish_before_time":
            if self.target != 1 or self.time_limit_seconds is None:
                raise ValueError("Nhiệm vụ hoàn thành trước hạn cần target=1 và thời hạn")
        # Gameplay hiện có 100 máu, mất 25/lần: trúng lần thứ tư là thua.
        if self.objective == "finish_with_max_hits" and self.target > 3:
            raise ValueError("Số lần trúng đòn tối đa phải nằm trong 0..3")
        return self


class PhanThuongNhiemVu(_Schema):
    """MVP chưa có chính sách thưởng quest được backend duyệt: chỉ cho phép 0."""

    gold: int = Field(default=0, ge=0, le=0)


class NhiemVu(DeXuatNhiemVu):
    """Phản hồi cho một nhiệm vụ mới, chưa xác minh hoàn thành hoặc cấp thưởng."""

    id: str = Field(min_length=7, max_length=64, pattern=r"^quest_[A-Za-z0-9_-]+$")
    stage_id: int = Field(ge=1, le=1000)
    reward: PhanThuongNhiemVu = Field(default_factory=PhanThuongNhiemVu)
    status: Literal["offered"] = "offered"
    generation_source: Literal["llm", "rule_based", "demo"]
    schema_version: Literal[1] = 1
