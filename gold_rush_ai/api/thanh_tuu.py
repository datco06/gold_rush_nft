"""Điều kiện và trạng thái nhận huy hiệu SBT.

Endpoint này chỉ mở quyền sau khi match_results đã được backend ghi nhận là
ván thắng hợp lệ. UNIQUE(player_id, achievement_id) chặn nhận lại khi chơi lại.
Mint vẫn do ThanhTuuSBT.sol và dịch vụ SBT Flutter thực hiện.
"""
from __future__ import annotations

import json
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from api.auth_guard import kiem_tra_csrf_va_origin, lay_nguoi_choi_hien_tai, NguoiChoiXacThuc
from core.csdl import lay_csdl
from core.sbt_voucher import DichVuVoucherSBT, LoiCauHinhSBT
import config

router = APIRouter(prefix="/api/thanh-tuu", tags=["thanh-tuu"])

HUY_HIEU = {
    1: {"name": "Thợ mỏ tập sự", "image": "assets/images/huy_hieu/badge_tap_su.png", "stage": 1, "condition": "Hoàn thành và chiến thắng màn 1 lần đầu tiên."},
    2: {"name": "Chiến binh dũng cảm", "image": "assets/images/huy_hieu/badge_dung_cam.png", "stage": 6, "condition": "Hoàn thành và chiến thắng màn 6 lần đầu tiên."},
    3: {"name": "Kẻ chinh phục Boss", "image": "assets/images/huy_hieu/badge_boss_09.png", "stage": 9, "condition": "Hoàn thành màn 9 thành công."},
    4: {"name": "Bậc thầy chinh phục", "image": "assets/images/huy_hieu/badge_chinh_phuc_15.png", "stage": 15, "condition": "Hoàn thành và chiến thắng màn 15 lần đầu tiên."},
    5: {"name": "Huyền thoại Gold Rush", "image": "assets/images/huy_hieu/badge_huyen_thoai_20.png", "stage": 20, "condition": "Hoàn thành và chiến thắng màn 20, kết thúc hành trình phiêu lưu."},
}


class YeuCauDanhGiaHuyHieu(BaseModel):
    ma_van: str = Field(min_length=8, max_length=128)


class YeuCauPhieuSBT(BaseModel):
    achievement_id: int = Field(ge=1, le=5)


def _danh_sach(conn, player_id: str):
    rows = conn.execute(
        "SELECT achievement_id, stage_id, ma_van, eligible_at, claimed_at FROM achievement_progress WHERE player_id = ?",
        (player_id,),
    ).fetchall()
    by_id = {int(r[0]): r for r in rows}
    completed = set()
    progress = conn.execute(
        "SELECT completed_stage_ids FROM player_progress WHERE player_id = ?",
        (player_id,),
    ).fetchone()
    if progress:
        try:
            completed.update(int(x) for x in json.loads(progress[0]))
        except (TypeError, ValueError):
            pass
    result = []
    for badge_id, badge in HUY_HIEU.items():
        row = by_id.get(badge_id)
        da_hoan_thanh = badge["stage"] in completed
        result.append({
            "badge_id": badge_id,
            **badge,
            "eligible": row is not None or da_hoan_thanh,
            "claimed": bool(row and row[4]),
            "ma_van": row[2] if row else None,
            "eligible_at": row[3] if row else None,
        })
    return result


@router.get("")
async def lay_huy_hieu(player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)]):
    with lay_csdl() as conn:
        return {"badges": _danh_sach(conn, player.user_id)}


@router.post("/danh-gia")
async def danh_gia_huy_hieu(
    body: YeuCauDanhGiaHuyHieu,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    kiem_tra_csrf_va_origin(request, player)
    with lay_csdl() as conn:
        conn.execute(
            "INSERT OR IGNORE INTO players (player_id, wallet_address, created_at, last_login) VALUES (?, ?, datetime('now'), datetime('now'))",
            (player.user_id, player.wallet_address.lower()),
        )
        van = conn.execute(
            "SELECT man, ket_qua, hop_le, is_verified, verified_wallet FROM match_results WHERE ma_van = ?",
            (body.ma_van,),
        ).fetchone()
        if van is None:
            raise HTTPException(404, "Không tìm thấy mã ván đã ghi nhận")
        stage_id, ket_qua, hop_le, is_verified, verified_wallet = van
        # Ván thắng đã qua kiểm định trọng tài là đủ để mở quyền huy hiệu.
        # Việc mint SBT vẫn yêu cầu đúng ví ở bước claim on-chain.
        if str(ket_qua).lower() != "thang" or not int(hop_le):
            raise HTTPException(422, "Ván chưa được trọng tài xác minh là chiến thắng hợp lệ")
        badge_id = next((i for i, b in HUY_HIEU.items() if b["stage"] == int(stage_id)), None)
        if badge_id is None:
            return {"new_badges": [], "badges": _danh_sach(conn, player.user_id)}
        da_co = conn.execute(
            "SELECT 1 FROM achievement_progress WHERE player_id = ? AND achievement_id = ?",
            (player.user_id, badge_id),
        ).fetchone() is not None
        conn.execute(
            "INSERT OR IGNORE INTO achievement_progress (player_id, achievement_id, stage_id, ma_van, eligible_at) VALUES (?, ?, ?, ?, datetime('now'))",
            (player.user_id, badge_id, int(stage_id), body.ma_van),
        )
        rows = _danh_sach(conn, player.user_id)
        return {"new_badges": [] if da_co else [b for b in rows if b["badge_id"] == badge_id], "badges": rows}


@router.post("/phieu")
async def cap_phieu_sbt(
    body: YeuCauPhieuSBT,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Cấp phiếu SBT cho thành tích đã được Backend ghi nhận.

    Địa chỉ nhận luôn lấy từ phiên SIWE; client không được chọn ví khác.
    """
    kiem_tra_csrf_va_origin(request, player)
    if not config.SBT_ENABLED or not config.HOP_DONG_SBT:
        raise HTTPException(503, "Tính năng cấp huy hiệu SBT chưa được cấu hình")
    with lay_csdl() as conn:
        row = conn.execute(
            "SELECT claimed_at FROM achievement_progress WHERE player_id = ? AND achievement_id = ?",
            (player.user_id, body.achievement_id),
        ).fetchone()
    if row is None:
        raise HTTPException(403, "Ví chưa đủ điều kiện nhận huy hiệu này")
    if row[0]:
        raise HTTPException(409, "Huy hiệu này đã được Backend ghi nhận là đã nhận")

    try:
        service = DichVuVoucherSBT(
            private_key=config.SBT_SIGNER_PRIVATE_KEY,
            contract_address=config.HOP_DONG_SBT,
            chain_id=config.SBT_CHAIN_ID,
            authorized_signer=config.SBT_AUTHORIZED_SIGNER,
            ttl_seconds=config.SBT_VOUCHER_TTL_SECONDS,
        )
        if not service.da_cau_hinh():
            raise LoiCauHinhSBT("Thiếu cấu hình khóa ký hoặc hợp đồng SBT")
        return service.tao_va_ky(
            player=player.wallet_address,
            achievement_id=body.achievement_id,
        )
    except LoiCauHinhSBT as error:
        raise HTTPException(503, str(error)) from None
    except ValueError as error:
        raise HTTPException(422, str(error)) from None
