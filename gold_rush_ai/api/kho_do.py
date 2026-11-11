"""API quản lý kho đồ và trang bị cho người chơi (Bảo vệ theo phiên SIWE)."""
from __future__ import annotations

import logging
from typing import Annotated, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from api.auth_guard import NguoiChoiXacThuc, kiem_tra_csrf_va_origin, lay_nguoi_choi_hien_tai
from core.csdl import lay_csdl
from core.kho_do import lay_kho_do
from core.tien_trinh import doi_trang_bi, lay_hoac_tao_nguoi_choi, lay_tien_trinh

log = logging.getLogger("api.kho_do")
router = APIRouter(prefix="/api", tags=["Kho đồ & Trang bị"])


class YeuCauDoiTrangBi(BaseModel):
    """Payload yêu cầu đổi trang bị."""
    model_config = ConfigDict(extra="forbid", frozen=True)

    loai: Literal["weapon", "character"] = Field(..., description="Loại trang bị: weapon hoặc character")
    item_id: str = Field(..., min_length=1, max_length=64, description="Mã vật phẩm muốn trang bị")


@router.get("/inventory")
def lay_danh_sach_kho_do(
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
    loai: Optional[str] = Query(None, description="Lọc theo loại: weapon, character, potion, material"),
):
    """Lấy danh sách vật phẩm người chơi đang sở hữu trong kho đồ.

    Người chơi A không thể xem kho đồ của người chơi B.
    """
    loai_loc = loai if isinstance(loai, str) else None
    with lay_csdl() as conn:
        lay_hoac_tao_nguoi_choi(conn, player_id=player.user_id, wallet_address=player.wallet_address)
        items = lay_kho_do(conn, player.user_id, loai=loai_loc)

    return {
        "player_id": player.user_id,
        "so_luong_vat_pham": len(items),
        "kho_do": items,
    }


@router.post("/equipment/select")
def chon_trang_bi(
    yc: YeuCauDoiTrangBi,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Yêu cầu đổi trang bị (vũ khí hoặc nhân vật).

    Bảo mật:
    - Bắt buộc kiểm tra Origin và CSRF.
    - Chỉ cho phép đổi nếu người chơi thực sự sở hữu vật phẩm đó trong kho đồ của mình.
    """
    kiem_tra_csrf_va_origin(request, player)

    with lay_csdl() as conn:
        lay_hoac_tao_nguoi_choi(conn, player_id=player.user_id, wallet_address=player.wallet_address)
        try:
            tt_moi = doi_trang_bi(conn, player.user_id, yc.loai, yc.item_id)
        except ValueError as e:
            raise HTTPException(400, str(e))

    return {
        "thanh_cong": True,
        "thong_bao": f"Đã trang bị {yc.loai} '{yc.item_id}' thành công",
        "equipped_weapon_id": tt_moi["equipped_weapon_id"],
        "equipped_character_id": tt_moi["equipped_character_id"],
    }
