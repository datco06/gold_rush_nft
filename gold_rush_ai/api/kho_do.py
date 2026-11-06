"""API quản lý kho đồ và trang bị cho người chơi."""
from __future__ import annotations

import logging
from typing import Literal, Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from core.csdl import lay_csdl
from core.kho_do import lay_kho_do
from core.tien_trinh import doi_trang_bi, lay_tien_trinh

log = logging.getLogger("api.kho_do")
router = APIRouter(prefix="/api", tags=["Kho đồ & Trang bị"])

MA_PLAYER = r"^[A-Za-z0-9_-]{3,64}$"


class YeuCauDoiTrangBi(BaseModel):
    player_id: str = Field(..., pattern=MA_PLAYER, description="Mã người chơi")
    loai: Literal["weapon", "character"] = Field(..., description="Loại trang bị: weapon hoặc character")
    item_id: str = Field(..., min_length=1, max_length=64, description="Mã vật phẩm muốn trang bị")


@router.get("/inventory")
def lay_danh_sach_kho_do(
    player_id: str = Query(..., pattern=MA_PLAYER, description="Mã người chơi"),
    loai: Optional[str] = Query(None, description="Lọc theo loại: weapon, character, potion, material"),
):
    """Lấy danh sách vật phẩm người chơi đang sở hữu trong kho đồ."""
    loai_loc = loai if isinstance(loai, str) else None
    with lay_csdl() as conn:
        tt = lay_tien_trinh(conn, player_id)
        if tt is None:
            raise HTTPException(404, f"Không tìm thấy người chơi {player_id}")
        items = lay_kho_do(conn, player_id, loai=loai_loc)

    return {
        "player_id": player_id,
        "so_luong_vat_pham": len(items),
        "kho_do": items,
    }


@router.post("/equipment/select")
def chon_trang_bi(yc: YeuCauDoiTrangBi):
    """Yêu cầu đổi trang bị (vũ khí hoặc nhân vật).

    Chỉ cho phép đổi nếu người chơi thực sự sở hữu vật phẩm đó trong kho đồ.
    """
    with lay_csdl() as conn:
        try:
            tt_moi = doi_trang_bi(conn, yc.player_id, yc.loai, yc.item_id)
        except ValueError as e:
            raise HTTPException(400, str(e))

    return {
        "thanh_cong": True,
        "thong_bao": f"Đã trang bị {yc.loai} '{yc.item_id}' thành công",
        "equipped_weapon_id": tt_moi["equipped_weapon_id"],
        "equipped_character_id": tt_moi["equipped_character_id"],
    }
