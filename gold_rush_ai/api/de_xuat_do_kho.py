from __future__ import annotations

from dataclasses import dataclass, field
import logging
import os
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from api.nhiem_vu import NguCanhNguoiChoi, StageID
from api.ngu_canh_ai import lay_ban_chup_ai
from core.ngu_canh_ai import BanChupNguoiChoiAI
from core.ca_nhan_hoa_do_kho import DeXuatDoKho, de_xuat_do_kho
from core.man_choi import ManChoi, doc
from core.nhat_ky import NhatKyVan

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/ai/do-kho", tags=["AI đề xuất độ khó"])


class YeuCauDeXuatDoKho(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    stage_id: StageID


class NguCanhDeXuatDoKho(BaseModel):
    """Snapshot do backend chọn đúng người và màn, lịch sử từ cũ đến mới."""

    model_config = ConfigDict(extra="forbid", strict=True, frozen=True, allow_inf_nan=False)
    nguoi_choi: NguCanhNguoiChoi
    stage_id: StageID
    lich_su: tuple[NhatKyVan, ...] = Field(default=(), max_length=1000)
    he_so_truoc: float = Field(default=1.0, ge=0.8, le=1.15)


class PhanHoiDeXuatDoKho(DeXuatDoKho):
    stage_id: StageID
    context_source: Literal["verified", "demo"]


@dataclass
class TrangThaiDeXuatDoKho:
    enabled: bool = False
    demo_enabled: bool = False
    cac_man: dict[int, ManChoi] = field(default_factory=dict)


def khoi_dong_de_xuat_do_kho(app: FastAPI) -> None:
    import config

    state = TrangThaiDeXuatDoKho(enabled="de_xuat_do_kho" in config.ENABLED)
    app.state.de_xuat_do_kho = state
    if not state.enabled:
        return
    try:
        demo = os.environ.get("AI_DIFFICULTY_DEMO", "false").strip().lower()
        if demo not in ("true", "false", "1", "0"):
            raise ValueError("AI_DIFFICULTY_DEMO không hợp lệ")
        cac_man = doc(config.MAN_CHOI)
        if not cac_man:
            raise ValueError("Danh sách màn trống")
        for man in cac_man.values():
            de_xuat_do_kho(man, ())
        state.demo_enabled = demo in ("true", "1")
        state.cac_man = cac_man
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as e:
        log.error("Không khởi động được API đề xuất độ khó (%s)", type(e).__name__)


def de_xuat_do_kho_da_nap(app: FastAPI) -> bool:
    state = getattr(app.state, "de_xuat_do_kho", None)
    return state is not None and state.enabled and bool(state.cac_man)


def lay_trang_thai(request: Request) -> TrangThaiDeXuatDoKho:
    state = getattr(request.app.state, "de_xuat_do_kho", None)
    if state is None:
        raise HTTPException(503, "API đề xuất độ khó chưa được khởi tạo")
    if not state.enabled:
        raise HTTPException(404, "Thành phần đề xuất độ khó đang tắt")
    if not state.cac_man:
        raise HTTPException(503, "API đề xuất độ khó chưa sẵn sàng")
    return state


async def lay_ngu_canh_de_xuat(
    request: Request,
    state: Annotated[TrangThaiDeXuatDoKho, Depends(lay_trang_thai)],
    x_demo_player: Annotated[str | None, Header(alias="X-Demo-Player", min_length=1, max_length=64,
                                               pattern=r"^[A-Za-z0-9_-]+$")] = None,
) -> NguCanhDeXuatDoKho | BanChupNguoiChoiAI:
    snapshot = await lay_ban_chup_ai(request)
    if snapshot is not None:
        return snapshot
    ctx = getattr(request.state, "ai_difficulty_context", None)
    if ctx is not None:
        if not isinstance(ctx, NguCanhDeXuatDoKho):
            raise HTTPException(503, "Ngữ cảnh đề xuất độ khó từ backend không hợp lệ")
        try:
            return NguCanhDeXuatDoKho.model_validate(ctx.model_dump(warnings=False), strict=True)
        except ValueError:
            raise HTTPException(503, "Ngữ cảnh đề xuất độ khó từ backend không hợp lệ") from None
    if not state.demo_enabled:
        raise HTTPException(503, "Chưa có ngữ cảnh lịch sử người chơi đã xác minh")
    if x_demo_player is None:
        raise HTTPException(422, "Cần X-Demo-Player cho phiên demo")
    return NguCanhDeXuatDoKho(
        nguoi_choi=NguCanhNguoiChoi(player_id=x_demo_player,
            allowed_stage_ids=frozenset({1}), context_source="demo"), stage_id=1)


@router.post("/de-xuat", response_model=PhanHoiDeXuatDoKho)
def de_xuat(
    yc: YeuCauDeXuatDoKho,
    ctx: Annotated[NguCanhDeXuatDoKho | BanChupNguoiChoiAI, Depends(lay_ngu_canh_de_xuat)],
    state: Annotated[TrangThaiDeXuatDoKho, Depends(lay_trang_thai)],
) -> PhanHoiDeXuatDoKho:
    if isinstance(ctx, BanChupNguoiChoiAI):
        ctx = NguCanhDeXuatDoKho(
            nguoi_choi=NguCanhNguoiChoi(player_id=ctx.player_id,
                allowed_stage_ids=ctx.allowed_stage_ids),
            stage_id=yc.stage_id, lich_su=ctx.recent_history,
            he_so_truoc=ctx.previous_speed_multipliers.get(yc.stage_id, 1.0))
    nguoi = ctx.nguoi_choi
    if (yc.stage_id != ctx.stage_id or yc.stage_id not in nguoi.allowed_stage_ids
            or (nguoi.context_source == "demo" and yc.stage_id != 1)):
        raise HTTPException(403, "Màn chưa được ngữ cảnh người chơi cho phép")
    man = state.cac_man.get(yc.stage_id)
    if man is None:
        raise HTTPException(404, "Không có màn được yêu cầu")
    try:
        if nguoi.context_source == "demo":
            kq = de_xuat_do_kho(man, ())
        else:
            kq = de_xuat_do_kho(man, ctx.lich_su, he_so_truoc=ctx.he_so_truoc)
    except ValueError:
        log.warning("Ngữ cảnh lịch sử không hợp lệ cho đề xuất độ khó")
        raise HTTPException(503, "Dữ liệu đề xuất độ khó từ backend chưa sẵn sàng") from None
    return PhanHoiDeXuatDoKho(**kq.model_dump(), stage_id=yc.stage_id,
                             context_source=nguoi.context_source)
