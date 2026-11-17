from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from .ca_nhan_hoa_do_kho import de_xuat_do_kho
from .man_choi import ManChoi
from .nhat_ky import NhatKyVan


class LoiHoSoNhiemVu(ValueError):
    pass


class HoSoNhiemVu(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True, allow_inf_nan=False)
    level: int = Field(ge=1, le=1000)
    recent_history: tuple[NhatKyVan, ...] = Field(default=(), max_length=1000)


def chon_do_kho_nhiem_vu(man: ManChoi, ho_so: HoSoNhiemVu) -> Literal["easy", "medium", "hard"]:
    if not isinstance(ho_so, HoSoNhiemVu):
        raise LoiHoSoNhiemVu("Cần hồ sơ nhiệm vụ từ backend")
    try:
        profile = HoSoNhiemVu.model_validate(ho_so.model_dump(warnings=False), strict=True)
        de_xuat = de_xuat_do_kho(man, profile.recent_history)
    except ValueError:
        raise LoiHoSoNhiemVu("Hồ sơ nhiệm vụ từ backend không hợp lệ") from None
    tran = 0 if profile.level <= 2 else 1 if profile.level <= 4 else 2
    cac_muc: tuple[Literal["easy", "medium", "hard"], ...] = ("easy", "medium", "hard")
    return cac_muc[min(tran, cac_muc.index(de_xuat.difficulty))]
