"""API mở rộng cho Map Generator (Cấu hình bản đồ, Pool bản đồ, Sinh bản đồ theo seed)."""
from __future__ import annotations

import logging
from typing import Literal, Optional

from fastapi import APIRouter, HTTPException, Query, Response

from config import BAN_DO_DIR
from core.quan_ly_ban_do import (
    PHIEN_BAN_THUAT_TOAN,
    quet_pool_ban_do,
    sinh_ban_do_hop_le,
)

log = logging.getLogger("api.ban_do_moi")
router = APIRouter(prefix="/api/maps", tags=["Bản đồ & Map Generator"])


@router.get("/config")
def lay_cau_hinh_ban_do():
    """Lấy thông tin cấu hình hệ thống bản đồ (phiên bản thuật toán, quy chuẩn nạp bản đồ)."""
    return {
        "phien_ban_thuat_toan": PHIEN_BAN_THUAT_TOAN,
        "co_che": {
            "world_map": "Người 1 thiết kế trên Flutter, mở khóa theo unlocked_stage_ids từ Backend",
            "level_map": "Người 5 phụ trách, lưới 40x30 ô, sinh theo seed và kiểm tra bằng BFS/A*",
        },
        "kich_thuoc_chuan": {"so_cot": 40, "so_hang": 30, "kich_thuoc_o": 16},
        "thu_muc_assets": str(BAN_DO_DIR.name),
    }


@router.get("/pool")
def danh_sach_pool_ban_do():
    """Quét và kiểm định danh sách các bản đồ .tmx đã được đóng gói sẵn trong assets/tiles/."""
    ds = quet_pool_ban_do(BAN_DO_DIR)
    hop_le = sum(1 for m in ds if m.get("hop_le"))
    return {
        "tong_so_ban_do": len(ds),
        "so_ban_do_hop_le": hop_le,
        "danh_sach": ds,
    }


@router.get("/generate")
def sinh_ban_do_theo_seed(
    seed: int = Query(..., ge=0, le=10**9, description="Seed khởi tạo bản đồ"),
    mat_do: float = Query(0.36, ge=0.30, le=0.48, description="Mật độ vật cản"),
    dinh_dang: Literal["json", "tmx"] = Query("json", description="Định dạng trả về: json metadata hoặc xml tmx"),
):
    """Sinh bản đồ mới theo seed, chạy qua bộ kiểm định đường đi BFS/A* trước khi trả về."""
    try:
        kq = sinh_ban_do_hop_le(seed=seed, mat_do=mat_do)
    except ValueError as e:
        raise HTTPException(422, str(e))

    if dinh_dang == "tmx":
        return Response(
            kq["noi_dung_tmx"],
            media_type="application/xml",
            headers={
                "Content-Disposition": f'attachment; filename="gold_rush_seed_{seed}.tmx"',
                "X-Algorithm-Version": kq["phien_ban_thuat_toan"],
            },
        )

    # Trả về metadata và các chỉ số đánh giá bản đồ
    return {
        "seed": kq["seed"],
        "phien_ban_thuat_toan": kq["phien_ban_thuat_toan"],
        "kich_thuoc": kq["kich_thuoc"],
        "so_xu": kq["so_xu"],
        "so_zombie": kq["so_zombie"],
        "so_skeleton": kq["so_skeleton"],
        "chi_so": kq["chi_so"],
    }

