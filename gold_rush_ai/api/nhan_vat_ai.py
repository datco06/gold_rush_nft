"""Tạo và lấy preview nhân vật qua ID, có cache request theo người/phiên.

ENABLED có 'nhan_vat_ai'; AI_IMAGE_DEMO=true cho X-Demo-Player.
AI_IMAGE_DB, AI_IMAGE_TTL_SECONDS và AI_IMAGE_MAX_IMAGES cấu hình kho ảnh.
Backend cấp NguCanhNguoiChoi tại request.state.ai_image_player sau xác minh,
hoặc thay dependency lay_ngu_canh_anh. Provider mặc định là demo offline.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import logging
import os
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Path, Request
from fastapi.responses import Response

from api.nhiem_vu import NguCanhNguoiChoi
from core.ai_nhan_vat import tao_anh_nhan_vat
from core.dich_vu_anh import DichVuAnh
from core.kho_anh import KhoAnh, LoiKhoAnh, XungDotYeuCauAnh
from core.nhan_vat_ai import AnhNhanVat, YeuCauTaoNhanVat
from core.providers.anh import AnhMauOffline, LoiProviderAnh

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/ai/nhan-vat", tags=["AI ảnh nhân vật"])


class PhanHoiAnhNhanVat(AnhNhanVat):
    context_source: Literal["verified", "demo"]


@dataclass
class TrangThaiNhanVatAI:
    enabled: bool = False
    demo_enabled: bool = False
    kho: KhoAnh | None = None
    service: DichVuAnh | None = None
    demo_service: DichVuAnh | None = None


def khoi_dong_nhan_vat_ai(app: FastAPI) -> None:
    import config

    state = TrangThaiNhanVatAI(enabled="nhan_vat_ai" in config.ENABLED)
    app.state.nhan_vat_ai = state
    if not state.enabled:
        return
    try:
        demo = os.environ.get("AI_IMAGE_DEMO", "false").strip().lower()
        if demo not in ("true", "false", "1", "0"):
            raise ValueError("AI_IMAGE_DEMO không hợp lệ")
        ttl = int(os.environ.get("AI_IMAGE_TTL_SECONDS", "86400"))
        capacity = int(os.environ.get("AI_IMAGE_MAX_IMAGES", "200"))
        provider_demo = AnhMauOffline(config.APP_FLUTTER / "assets" / "images")
        for description in ("Nhân vật", "Thợ mỏ", "Hiệp sĩ", "Cao bồi"):
            tao_anh_nhan_vat(YeuCauTaoNhanVat(description=description), demo_provider=provider_demo)
        kho = KhoAnh(os.environ.get("AI_IMAGE_DB", config.DATA_DIR / "anh_nhan_vat" / "images.sqlite3"),
                     han_luu_giay=ttl, so_anh_toi_da=capacity)
        kho.don_het_han()
        state.kho = kho
        state.service = DichVuAnh(kho, demo_provider=provider_demo)
        state.demo_service = DichVuAnh(kho, demo_provider=provider_demo)
        state.demo_enabled = demo in ("true", "1")
    except (OSError, ValueError, TypeError, LoiKhoAnh, LoiProviderAnh) as e:
        log.error("Không khởi động được API ảnh nhân vật (%s)", type(e).__name__)


def nhan_vat_ai_da_nap(app: FastAPI) -> bool:
    state = getattr(app.state, "nhan_vat_ai", None)
    return state is not None and state.enabled and state.service is not None


def lay_trang_thai(request: Request) -> TrangThaiNhanVatAI:
    state = getattr(request.app.state, "nhan_vat_ai", None)
    if state is None:
        raise HTTPException(503, "API ảnh nhân vật chưa được khởi tạo")
    if not state.enabled:
        raise HTTPException(404, "Thành phần ảnh nhân vật đang tắt")
    if state.service is None or state.kho is None:
        raise HTTPException(503, "API ảnh nhân vật chưa sẵn sàng")
    return state


def lay_ngu_canh_anh(
    request: Request,
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
    x_demo_player: Annotated[str | None, Header(alias="X-Demo-Player", min_length=1, max_length=64,
                                               pattern=r"^[A-Za-z0-9_-]+$")] = None,
) -> NguCanhNguoiChoi:
    ctx = getattr(request.state, "ai_image_player", None)
    if ctx is not None:
        if not isinstance(ctx, NguCanhNguoiChoi):
            raise HTTPException(503, "Ngữ cảnh người chơi từ backend không hợp lệ")
        try:
            return NguCanhNguoiChoi.model_validate(ctx.model_dump(warnings=False), strict=True)
        except ValueError:
            raise HTTPException(503, "Ngữ cảnh người chơi từ backend không hợp lệ") from None
    if not state.demo_enabled:
        raise HTTPException(503, "Chưa có ngữ cảnh người chơi đã xác minh")
    if x_demo_player is None:
        raise HTTPException(422, "Cần X-Demo-Player cho phiên demo")
    return NguCanhNguoiChoi(player_id=x_demo_player, context_source="demo")


def _player_key(ctx: NguCanhNguoiChoi) -> str:
    return sha256(f"{ctx.context_source}:{ctx.player_id}".encode("ascii")).hexdigest()


@router.post("/tao", response_model=PhanHoiAnhNhanVat)
def tao_anh(
    yc: YeuCauTaoNhanVat,
    ctx: Annotated[NguCanhNguoiChoi, Depends(lay_ngu_canh_anh)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
    request_id: Annotated[str, Header(alias="Idempotency-Key", min_length=1, max_length=64,
                                     pattern=r"^[A-Za-z0-9_-]+$")],
) -> PhanHoiAnhNhanVat:
    service = state.demo_service if ctx.context_source == "demo" else state.service
    try:
        anh = service.tao(player_id=_player_key(ctx), request_id=request_id, yeu_cau=yc)
    except XungDotYeuCauAnh:
        raise HTTPException(409, "Idempotency-Key đã được dùng cho mô tả khác") from None
    except (LoiKhoAnh, LoiProviderAnh, ValueError):
        raise HTTPException(503, "Chưa tạo được ảnh nhân vật hợp lệ; hãy thử lại sau") from None
    return PhanHoiAnhNhanVat(**anh.model_dump(), context_source=ctx.context_source)


@router.get("/anh/{image_id}", response_class=Response, responses={200: {"content": {"image/png": {}}}})
def lay_anh(
    image_id: Annotated[str, Path(min_length=36, max_length=36, pattern=r"^img_[0-9a-f]{32}$")],
    ctx: Annotated[NguCanhNguoiChoi, Depends(lay_ngu_canh_anh)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> Response:
    try:
        anh = state.kho.doc_cho_nguoi(_player_key(ctx), image_id)
    except (LoiKhoAnh, ValueError):
        raise HTTPException(503, "Chưa đọc được ảnh nhân vật hợp lệ") from None
    if anh is None:
        raise HTTPException(404, "Không có ảnh khả dụng cho người chơi")
    return Response(content=anh[1], media_type="image/png",
                    headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})