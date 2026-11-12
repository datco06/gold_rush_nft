from __future__ import annotations

from collections.abc import Sequence
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from .man_choi import ManChoi
from .nhat_ky import NhatKyVan

SO_VAN_TOI_THIEU = 3
CUA_SO_LICH_SU = 10
DIEM_MOI_XU = 20
BUOC_HE_SO_TOI_DA = 0.05


class _Schema(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True, allow_inf_nan=False)


class DieuChinhTocDo(_Schema):
    enemy_speed_multiplier: float = Field(ge=0.8, le=1.15)


class DeXuatDoKho(_Schema):
    difficulty: Literal["easy", "medium", "hard"]
    performance_score: float | None = Field(ge=0, le=1)
    reason: str = Field(min_length=1, max_length=500)
    adjustments: DieuChinhTocDo
    source: Literal["rule_based", "fallback"]
    sample_count: int = Field(ge=0, le=CUA_SO_LICH_SU)
    schema_version: Literal[1] = 1

    @field_validator("schema_version", mode="before")
    @classmethod
    def _kiem_tra_phien_ban(cls, value: object) -> int:
        if type(value) is not int or value != 1:
            raise ValueError("schema_version cần số nguyên 1")
        return value


def de_xuat_do_kho(
    man: ManChoi,
    lich_su: Sequence[NhatKyVan],
    *,
    he_so_truoc: float = 1.0,
) -> DeXuatDoKho:
    if (not isinstance(man, ManChoi) or type(man.id) is not int or not 1 <= man.id <= 1000
            or type(man.so_xu) is not int or not 1 <= man.so_xu <= 100000
            or not isinstance(man.tep, str) or not man.tep.strip()):
        raise ValueError("Thông tin màn không hợp lệ cho đề xuất độ khó")
    truoc = DieuChinhTocDo(enemy_speed_multiplier=he_so_truoc).enemy_speed_multiplier
    cac_van: dict[str, NhatKyVan] = {}
    for nk in lich_su:
        if not isinstance(nk, NhatKyVan):
            raise ValueError("Lịch sử cần các nhật ký NhatKyVan đã xác minh")
        nk = NhatKyVan.model_validate(nk.model_dump(warnings=False), strict=True)
        if nk.man != man.id or nk.ban_do != man.tep or nk.ket_qua == "bo":
            continue
        if nk.diem % DIEM_MOI_XU or nk.diem > man.so_xu * DIEM_MOI_XU:
            raise ValueError("Điểm của ván không khớp số xu của màn")
        if nk.ket_qua == "thang" and nk.diem != man.so_xu * DIEM_MOI_XU:
            raise ValueError("Ván thắng cần thu thập đủ số xu của màn")
        cu = cac_van.get(nk.ma_van)
        if cu is not None and (cu.ket_qua, cu.diem) != (nk.ket_qua, nk.diem):
            raise ValueError("Cùng mã ván có kết quả mâu thuẫn")
        cac_van[nk.ma_van] = nk
    gan_day = list(cac_van.values())[-CUA_SO_LICH_SU:]
    n = len(gan_day)
    score = None
    do_kho = "medium"
    source = "fallback"
    muc_tieu = 1.0
    reason = (f"Có {n} ván có kết quả, cần ít nhất {SO_VAN_TOI_THIEU} ván. "
              "Đề xuất trung tính, đưa dần hệ số về 1.0.")
    if n >= SO_VAN_TOI_THIEU:
        ti_le_thang = sum(nk.ket_qua == "thang" for nk in gan_day) / n
        ti_le_xu = sum(nk.diem / (DIEM_MOI_XU * man.so_xu) for nk in gan_day) / n
        score = round((0.7 * ti_le_thang + 0.3 * ti_le_xu), 6)
        if score < 0.4:
            do_kho = "easy"
        elif score >= 0.75:
            do_kho = "hard"
        source = "rule_based"
        muc_tieu = min(1.15, max(0.8, 1.0 + 0.4 * (score - 0.5)))
        ten_muc = {"easy": "dễ", "medium": "trung bình", "hard": "khó"}[do_kho]
        reason = (f"{n} ván gần nhất, tỷ lệ thắng {ti_le_thang:.0%}, "
                  f"trung bình thu thập {ti_le_xu:.0%} số xu. Đề xuất mức {ten_muc}.")
    thay_doi = min(BUOC_HE_SO_TOI_DA, max(-BUOC_HE_SO_TOI_DA, muc_tieu - truoc))
    he_so = round(truoc + thay_doi, 12)
    return DeXuatDoKho(difficulty=do_kho, performance_score=score, reason=reason,
                      adjustments=DieuChinhTocDo(enemy_speed_multiplier=he_so),
                      source=source, sample_count=n)
