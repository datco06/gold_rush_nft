from __future__ import annotations

from dataclasses import dataclass, field
from hashlib import sha256
import logging
import os
from pathlib import Path
from typing import Annotated, Literal
from xml.etree.ElementTree import ParseError

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from core.ai_nhiem_vu import KhongCoNhiemVuPhuHop
from core.dich_vu_nhiem_vu import DichVuNhiemVu
from core.kho_nhiem_vu import KhoNhiemVu, LoiKhoNhiemVu, XungDotYeuCauNhiemVu
from core.luoi import BanDo, doc_tmx, kiem_tra_choi_duoc
from core.man_choi import ManChoi, doc
from core.nhiem_vu import NhiemVu, YeuCauTaoNhiemVu
from core.providers.llm import provider_tu_moi_truong

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/ai/nhiem-vu", tags=["AI nhiệm vụ"])
StageID = Annotated[int, Field(strict=True, ge=1, le=1000)]


class NguCanhNguoiChoi(BaseModel):
    """Chỉ tầng backend tạo context verified sau khi xác minh danh tính/tiến trình."""

    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    player_id: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    allowed_stage_ids: frozenset[StageID] = frozenset()
    difficulty: Literal["easy", "medium", "hard"] = "easy"
    context_source: Literal["verified", "demo"] = "verified"


class PhanHoiNhiemVu(NhiemVu):
    context_source: Literal["verified", "demo"]


@dataclass
class TrangThaiNhiemVu:
    enabled: bool = False
    demo_enabled: bool = False
    service: DichVuNhiemVu | None = None
    demo_service: DichVuNhiemVu | None = None
    cac_man: dict[int, ManChoi] = field(default_factory=dict)
    ban_do: dict[int, BanDo] = field(default_factory=dict)


def khoi_dong_nhiem_vu(app: FastAPI):
    import config

    state = TrangThaiNhiemVu(enabled="nhiem_vu" in config.ENABLED)
    app.state.nhiem_vu = state
    if not state.enabled:
        return
    try:
        demo = os.environ.get("AI_QUEST_DEMO", "false").strip().lower()
        if demo not in ("true", "false", "1", "0"):
            raise ValueError("AI_QUEST_DEMO không hợp lệ")
        state.demo_enabled = demo in ("true", "1")
        state.cac_man = doc(config.MAN_CHOI)
        if not state.cac_man:
            raise ValueError("Danh sách màn trống")
        for mid, man in state.cac_man.items():
            if type(man.id) is not int or not 1 <= man.id <= 1000:
                raise ValueError("ID màn không hợp lệ cho nhiệm vụ")
            if type(man.so_xu) is not int or not 1 <= man.so_xu <= 100000:
                raise ValueError("Số xu của màn không hợp lệ")
            if type(man.gioi_han_giay) is not int or man.gioi_han_giay < 0:
                raise ValueError("Thời gian của màn không hợp lệ")
            bd = doc_tmx(config.BAN_DO_DIR / man.tep)
            xu = bd.cac_diem("coin")
            if kiem_tra_choi_duoc(bd) or len(xu) != man.so_xu or len(set(xu)) != len(xu):
                raise ValueError("Manifest hoặc bản đồ không hợp lệ")
            state.ban_do[mid] = bd
        try:
            provider = provider_tu_moi_truong()
        except ValueError:
            log.warning("Cấu hình LLM nhiệm vụ không hợp lệ; dùng rule-based")
            provider = None
        tep = Path(os.environ.get("AI_QUEST_DB", config.DATA_DIR / "nhiem_vu" / "quests.sqlite3"))
        kho = KhoNhiemVu(tep)
        state.service = DichVuNhiemVu(kho, provider=provider)
        state.demo_service = DichVuNhiemVu(kho)
    except (OSError, ValueError, TypeError, KeyError, IndexError, AttributeError, ParseError, LoiKhoNhiemVu) as e:
        log.error("Không khởi động được API nhiệm vụ (%s)", type(e).__name__)


def nhiem_vu_da_nap(app: FastAPI) -> bool:
    state = getattr(app.state, "nhiem_vu", None)
    return state is not None and state.enabled and state.service is not None


def lay_trang_thai(request: Request) -> TrangThaiNhiemVu:
    state = getattr(request.app.state, "nhiem_vu", None)
    if state is None:
        raise HTTPException(503, "API nhiệm vụ chưa được khởi tạo")
    if not state.enabled:
        raise HTTPException(404, "Thành phần nhiệm vụ đang tắt")
    if state.service is None:
        raise HTTPException(503, "API nhiệm vụ chưa sẵn sàng")
    return state


def lay_ngu_canh_nguoi_choi(
    request: Request,
    state: Annotated[TrangThaiNhiemVu, Depends(lay_trang_thai)],
    x_demo_player: Annotated[str | None, Header(alias="X-Demo-Player", min_length=1, max_length=64,
                                               pattern=r"^[A-Za-z0-9_-]+$")] = None,
) -> NguCanhNguoiChoi:
    ctx = getattr(request.state, "ai_quest_player", None)
    if ctx is not None:
        if not isinstance(ctx, NguCanhNguoiChoi):
            raise HTTPException(503, "Ngữ cảnh người chơi từ backend không hợp lệ")
        return ctx
    if not state.demo_enabled:
        raise HTTPException(503, "Chưa có ngữ cảnh người chơi đã xác minh")
    if x_demo_player is None:
        raise HTTPException(422, "Cần X-Demo-Player để phân biệt các phiên demo")
    return NguCanhNguoiChoi(player_id=x_demo_player, allowed_stage_ids=frozenset({1}), context_source="demo")


@router.post("/tao", response_model=PhanHoiNhiemVu)
def tao_nhiem_vu(
    yc: YeuCauTaoNhiemVu,
    ctx: Annotated[NguCanhNguoiChoi, Depends(lay_ngu_canh_nguoi_choi)],
    state: Annotated[TrangThaiNhiemVu, Depends(lay_trang_thai)],
    request_id: Annotated[str, Header(alias="Idempotency-Key", min_length=1, max_length=64,
                                     pattern=r"^[A-Za-z0-9_-]+$")],
) -> PhanHoiNhiemVu:
    if yc.player_id is not None and yc.player_id != ctx.player_id:
        raise HTTPException(403, "Player ID không khớp ngữ cảnh của backend/phiên demo")
    if yc.stage_id not in ctx.allowed_stage_ids or (ctx.context_source == "demo" and yc.stage_id != 1):
        raise HTTPException(403, "Màn chưa được ngữ cảnh người chơi cho phép")
    man = state.cac_man.get(yc.stage_id)
    if man is None:
        raise HTTPException(404, "Không có màn được yêu cầu")
    player_key = sha256(f"{ctx.context_source}:{ctx.player_id}".encode("ascii")).hexdigest()
    service = state.demo_service if ctx.context_source == "demo" else state.service
    try:
        nv = service.tao(player_id=player_key, request_id=request_id, man=man,
                         ban_do=state.ban_do[man.id], do_kho=ctx.difficulty)
    except XungDotYeuCauNhiemVu:
        raise HTTPException(409, "Idempotency-Key đã được dùng cho yêu cầu khác") from None
    except KhongCoNhiemVuPhuHop:
        raise HTTPException(422, "Không có nhiệm vụ khả thi hoặc mới cho màn này") from None
    except LoiKhoNhiemVu:
        raise HTTPException(503, "Không truy cập được kho nhiệm vụ; hãy thử lại") from None
    return PhanHoiNhiemVu(**nv.model_dump(), context_source=ctx.context_source)
