"""API quản lý tiến trình người chơi (Cấp độ, EXP, Màn đã mở, Nhân vật)."""
from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from core.csdl import lay_csdl
from core.tien_trinh import lay_hoac_tao_nguoi_choi, lay_tien_trinh

log = logging.getLogger("api.tien_trinh")
router = APIRouter(prefix="/api", tags=["Tiến trình"])

MA_PLAYER = r"^[A-Za-z0-9_-]{3,64}$"
DIA_CHI_VI = r"^0x[0-9a-fA-F]{40}$"


@router.get("/progress")
def lay_thong_tin_tien_trinh(
    player_id: str = Query(..., pattern=MA_PLAYER, description="Mã định danh người chơi"),
    wallet: Optional[str] = Query(None, pattern=DIA_CHI_VI, description="Địa chỉ ví (nếu có)"),
    ten_hien_thi: Optional[str] = Query(None, max_length=30, description="Tên hiển thị"),
):
    """Lấy thông tin tiến trình của người chơi (màn mở, EXP, cấp độ, trang bị).

    Nếu người chơi chưa tồn tại, hệ thống sẽ tự động khởi tạo tiến trình ban đầu (Màn 1 mở, cấp 1, kiếm gỗ).
    """
    vi = wallet if isinstance(wallet, str) else None
    ten = ten_hien_thi if isinstance(ten_hien_thi, str) else ""

    with lay_csdl() as conn:
        tt = lay_hoac_tao_nguoi_choi(
            conn,
            player_id=player_id,
            wallet_address=vi,
            ten_hien_thi=ten,
        )
    if tt is None:
        raise HTTPException(500, "Không thể khởi tạo hoặc truy xuất tiến trình người chơi")
    return tt
