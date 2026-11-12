from __future__ import annotations

from typing import Annotated, Self

from pydantic import Field, model_validator

from .ca_nhan_hoa_nhiem_vu import HoSoNhiemVu

StageID = Annotated[int, Field(strict=True, ge=1, le=1000)]
HeSoTocDo = Annotated[float, Field(strict=True, ge=0.8, le=1.15)]


class BanChupNguoiChoiAI(HoSoNhiemVu):
    player_id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    allowed_stage_ids: frozenset[StageID] = frozenset()
    completed_stage_ids: frozenset[StageID] = frozenset()
    previous_speed_multipliers: dict[StageID, HeSoTocDo] = Field(default_factory=dict, max_length=1000)
    user_id: str | None = Field(default=None, min_length=1, max_length=64)
    wallet_address: str | None = Field(default=None, pattern=r"^0x[0-9a-fA-F]{40}$")

    @model_validator(mode="after")
    def kiem_tra_tien_trinh(self) -> Self:
        if not self.completed_stage_ids <= self.allowed_stage_ids:
            raise ValueError("Màn đã hoàn thành phải thuộc các màn được phép")
        return self
