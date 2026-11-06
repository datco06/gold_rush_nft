"""API quản lý nhiệm vụ, nhận thưởng và kết nối AI Quest (Người 3)."""
from __future__ import annotations

import logging
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from core.csdl import lay_csdl
from core.quan_ly_nhiem_vu import (
    lay_danh_sach_nhiem_vu,
    lay_ngu_canh_cho_ai,
    nhan_thuong,
    tao_nhiem_vu,
)
from core.tien_trinh import lay_tien_trinh

log = logging.getLogger("api.nhiem_vu")
router = APIRouter(prefix="/api/quests", tags=["Nhiệm vụ & AI Quest"])

MA_PLAYER = r"^[A-Za-z0-9_-]{3,64}$"


class YeuCauNhanThuong(BaseModel):
    player_id: str = Field(..., pattern=MA_PLAYER, description="Mã người chơi")
    quest_id: str = Field(..., min_length=3, max_length=64, description="Mã nhiệm vụ")


class YeuCauGanNhiemVuAI(BaseModel):
    player_id: str = Field(..., pattern=MA_PLAYER, description="Mã người chơi nhận nhiệm vụ")
    title: str = Field(..., min_length=3, max_length=100, description="Tiêu đề nhiệm vụ")
    description: str = Field(..., min_length=5, max_length=300, description="Nội dung mô tả")
    target_type: str = Field(..., description="Loại mục tiêu: hoan_thanh_man, nhat_xu, choi_khong_trung_don, toc_do")
    target_count: int = Field(1, ge=1, le=100, description="Số lượng cần đạt")
    reward_exp: int = Field(50, ge=0, le=1000, description="EXP thưởng")
    reward_gold: int = Field(0, ge=0, le=500, description="Vàng thưởng")
    reward_items: list[dict[str, Any]] = Field(default_factory=list, description="Vật phẩm thưởng kèm theo")
    expires_at: Optional[str] = Field(None, description="Thời hạn nhiệm vụ (ISO 8601 nếu có)")


@router.get("/active")
def lay_nhiem_vu_hien_co(
    player_id: str = Query(..., pattern=MA_PLAYER, description="Mã người chơi"),
    bao_gom_da_nhan: bool = Query(False, description="Có lấy cả nhiệm vụ đã nhận thưởng không"),
):
    """Lấy danh sách nhiệm vụ của người chơi (mặc định lấy các nhiệm vụ đang làm và chưa nhận thưởng)."""
    with lay_csdl() as conn:
        tt = lay_tien_trinh(conn, player_id)
        if tt is None:
            raise HTTPException(404, f"Không tìm thấy người chơi {player_id}")

        ds = lay_danh_sach_nhiem_vu(conn, player_id)
        if not bao_gom_da_nhan:
            ds = [q for q in ds if q["status"] != "da_nhan"]

    return {
        "player_id": player_id,
        "tong_so": len(ds),
        "nhiem_vu": ds,
    }


@router.post("/claim")
def nhan_thuong_nhiem_vu(yc: YeuCauNhanThuong):
    """Nhận thưởng nhiệm vụ khi đã hoàn thành (tự động cộng EXP và gửi vật phẩm vào kho đồ)."""
    with lay_csdl() as conn:
        try:
            kq = nhan_thuong(conn, yc.player_id, yc.quest_id)
        except ValueError as e:
            raise HTTPException(400, str(e))

    return {
        "thanh_cong": True,
        "thong_bao": f"Đã nhận thưởng nhiệm vụ {yc.quest_id} thành công",
        "ket_qua": kq,
    }


@router.get("/ai-context")
def lay_ngu_canh_ai(
    player_id: str = Query(..., pattern=MA_PLAYER, description="Mã người chơi"),
):
    """Cung cấp ngữ cảnh tiến trình cho module Generative AI (Người 3) để sinh Quest phù hợp."""
    with lay_csdl() as conn:
        try:
            ctx = lay_ngu_canh_cho_ai(conn, player_id)
        except ValueError as e:
            raise HTTPException(404, str(e))
    return ctx


@router.post("/ai-assign", status_code=201)
def gan_nhiem_vu_ai(yc: YeuCauGanNhiemVuAI):
    """Người 3 (Generative AI) gọi endpoint này để gán nhiệm vụ vừa sinh cho người chơi."""
    with lay_csdl() as conn:
        tt = lay_tien_trinh(conn, yc.player_id)
        if tt is None:
            raise HTTPException(404, f"Không tìm thấy người chơi {yc.player_id}")
        try:
            q = tao_nhiem_vu(
                conn,
                player_id=yc.player_id,
                title=yc.title,
                description=yc.description,
                target_type=yc.target_type,
                target_count=yc.target_count,
                reward_exp=yc.reward_exp,
                reward_gold=yc.reward_gold,
                reward_items=yc.reward_items,
                quest_type="ai_generated",
                expires_at=yc.expires_at,
            )
        except ValueError as e:
            raise HTTPException(422, str(e))

    return {
        "thanh_cong": True,
        "thong_bao": "Đã gán nhiệm vụ AI thành công",
        "nhiem_vu": q,
    }

