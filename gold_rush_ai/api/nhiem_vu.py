"""API quản lý nhiệm vụ, nhận thưởng và kết nối AI Quest (Bảo vệ danh tính SIWE)."""
from __future__ import annotations

import logging
from typing import Annotated, Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from api.auth_guard import NguoiChoiXacThuc, kiem_tra_csrf_va_origin, lay_nguoi_choi_hien_tai
from core.csdl import lay_csdl
from core.quan_ly_nhiem_vu import (
    lay_danh_sach_nhiem_vu,
    lay_ngu_canh_cho_ai,
    nhan_thuong,
    tao_nhiem_vu,
)
from core.tien_trinh import lay_hoac_tao_nguoi_choi, lay_tien_trinh

log = logging.getLogger("api.nhiem_vu")
router = APIRouter(prefix="/api/quests", tags=["Nhiệm vụ & AI Quest"])

GIOI_HAN_EXP_AI_QUEST = 150


class YeuCauNhanThuong(BaseModel):
    """Payload nhận thưởng nhiệm vụ."""
    model_config = ConfigDict(extra="forbid", frozen=True)

    quest_id: str = Field(..., min_length=3, max_length=64, description="Mã nhiệm vụ")


class YeuCauGanNhiemVuAI(BaseModel):
    """Payload đề xuất gán nhiệm vụ từ AI.

    Quy tắc an toàn:
    - Phần thưởng do Server kiểm soát và áp trần chính sách.
    - Không cho phép client tùy tiện cấp on-chain gold hoặc vật phẩm giá trị cao trong SQLite.
    """
    model_config = ConfigDict(extra="forbid", frozen=True)

    title: str = Field(..., min_length=3, max_length=100, description="Tiêu đề nhiệm vụ")
    description: str = Field(..., min_length=5, max_length=300, description="Nội dung mô tả")
    target_type: str = Field(..., description="Loại mục tiêu: hoan_thanh_man, nhat_xu, choi_khong_trung_don, toc_do")
    target_count: int = Field(1, ge=1, le=100, description="Số lượng cần đạt")
    reward_exp: int = Field(50, ge=0, le=GIOI_HAN_EXP_AI_QUEST, description=f"EXP thưởng (tối đa {GIOI_HAN_EXP_AI_QUEST})")
    expires_at: Optional[str] = Field(None, description="Thời hạn nhiệm vụ (ISO 8601 nếu có)")


@router.get("/active")
def lay_nhiem_vu_hien_co(
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
    bao_gom_da_nhan: bool = Query(False, description="Có lấy cả nhiệm vụ đã nhận thưởng không"),
):
    """Lấy danh sách nhiệm vụ của người chơi hiện tại (Fail-Closed)."""
    with lay_csdl() as conn:
        lay_hoac_tao_nguoi_choi(conn, player_id=player.user_id, wallet_address=player.wallet_address)
        ds = lay_danh_sach_nhiem_vu(conn, player.user_id)
        if not bao_gom_da_nhan:
            ds = [q for q in ds if q["status"] != "da_nhan"]

    return {
        "player_id": player.user_id,
        "tong_so": len(ds),
        "nhiem_vu": ds,
    }


@router.post("/claim")
def nhan_thuong_nhiem_vu(
    yc: YeuCauNhanThuong,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Nhận thưởng nhiệm vụ khi đã hoàn thành (Atomic, chống double-claim và race condition)."""
    kiem_tra_csrf_va_origin(request, player)

    with lay_csdl() as conn:
        try:
            kq = nhan_thuong(conn, player.user_id, yc.quest_id)
        except ValueError as e:
            raise HTTPException(400, str(e))

    return {
        "thanh_cong": True,
        "thong_bao": f"Đã nhận thưởng nhiệm vụ {yc.quest_id} thành công",
        "ket_qua": kq,
    }


@router.get("/ai-context")
def lay_ngu_canh_ai(
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Cung cấp ngữ cảnh tiến trình của người chơi hiện tại cho module Generative AI."""
    with lay_csdl() as conn:
        lay_hoac_tao_nguoi_choi(conn, player_id=player.user_id, wallet_address=player.wallet_address)
        try:
            ctx = lay_ngu_canh_cho_ai(conn, player.user_id)
        except ValueError as e:
            raise HTTPException(404, str(e))
    return ctx


@router.post("/ai-assign", status_code=201)
def gan_nhiem_vu_ai(
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Endpoint gán nhiệm vụ AI qua HTTP bị khóa hoàn toàn (Fail-Closed).

    Chống bypass & farming: Không cho phép bất kỳ external HTTP client nào
    (kể cả đã xác thực SIWE hay cố tình thay đổi cờ trạng thái) tự gán nhiệm vụ nhận thưởng.
    Nhiệm vụ AI chỉ được tạo thông qua hàm nghiệp vụ nội bộ `tao_nhiem_vu_ai_noi_bo`
    trong code phía server của hệ thống AI.
    """
    raise HTTPException(
        status_code=403,
        detail={
            "code": "AI_ASSIGN_RESTRICTED",
            "message": "Endpoint tạo nhiệm vụ AI qua HTTP bị khóa hoàn toàn (Fail-Closed). Nhiệm vụ AI chỉ được tạo thông qua dịch vụ máy chủ nội bộ.",
        },
    )
