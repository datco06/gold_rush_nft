from __future__ import annotations

from collections.abc import Awaitable, Callable
import asyncio
import math
import logging

from fastapi import FastAPI, HTTPException, Request

from core.ngu_canh_ai import BanChupNguoiChoiAI
from core.schemas_nhan_vat import NguoiChoiXacThuc

NguonDuLieuAI = Callable[[Request], Awaitable[BanChupNguoiChoiAI | None]]
NguonXacThucAI = Callable[[Request], Awaitable[NguoiChoiXacThuc | None]]
log = logging.getLogger(__name__)


def gan_nguon_xac_thuc_ai(app: FastAPI, nguon: NguonXacThucAI, *, thoi_gian_cho: float = 5) -> None:
    if not callable(nguon):
        raise ValueError("Cần hàm async cung cấp thông tin xác thực SIWE hợp lệ")
    if (isinstance(thoi_gian_cho, bool) or not isinstance(thoi_gian_cho, (int, float))
            or not math.isfinite(thoi_gian_cho) or not 0 < thoi_gian_cho <= 60):
        raise ValueError("Thời gian chờ nguồn xác thực phải trong (0, 60] giây")
    app.state.ai_auth_source = nguon
    app.state.ai_auth_source_timeout = float(thoi_gian_cho)


def gan_nguon_du_lieu_ai(app: FastAPI, nguon: NguonDuLieuAI, *, thoi_gian_cho: float = 5) -> None:
    if not callable(nguon):
        raise ValueError("Cần hàm async cung cấp dữ liệu AI đã xác minh")
    if (isinstance(thoi_gian_cho, bool) or not isinstance(thoi_gian_cho, (int, float))
            or not math.isfinite(thoi_gian_cho) or not 0 < thoi_gian_cho <= 60):
        raise ValueError("Thời gian chờ nguồn AI phải trong (0, 60] giây")
    app.state.ai_player_source = nguon
    app.state.ai_player_source_timeout = float(thoi_gian_cho)


async def lay_ban_chup_ai(request: Request) -> BanChupNguoiChoiAI | None:
    nguon = getattr(request.app.state, "ai_player_source", None)
    if nguon is None:
        return None
    try:
        snapshot = await asyncio.wait_for(nguon(request),
            timeout=getattr(request.app.state, "ai_player_source_timeout", 5))
    except Exception as e:
        log.warning("Nguồn dữ liệu AI chưa sẵn sàng (%s)", type(e).__name__)
        raise HTTPException(503, "Nguồn dữ liệu người chơi chưa sẵn sàng") from None
    if snapshot is None:
        raise HTTPException(401, "Chưa xác thực người chơi")
    if not isinstance(snapshot, BanChupNguoiChoiAI):
        raise HTTPException(503, "Snapshot người chơi từ backend không hợp lệ")
    try:
        return BanChupNguoiChoiAI.model_validate(snapshot.model_dump(warnings=False), strict=True)
    except ValueError:
        raise HTTPException(503, "Snapshot người chơi từ backend không hợp lệ") from None
