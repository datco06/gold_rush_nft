"""Router API quản lý và xác minh tiến trình màn chơi của người chơi SIWE (Giai đoạn 8).

Endpoints:
- GET  /api/ai/tien-trinh: Lấy tổng quan tiến trình và danh sách màn 1–6 đã hoàn thành.
- POST /api/ai/tien-trinh/xac-minh: Xác minh và ghi nhận hoàn thành màn chơi có bằng chứng (CSRF + Origin).
- GET  /api/ai/tien-trinh/{stage_id}: Lấy chi tiết bằng chứng hoàn thành của một màn chơi cụ thể.

Quy định bảo mật:
- Bắt buộc xác thực ví SIWE qua cookie HttpOnly `gr_session`.
- Chặn đứng mọi phiên demo gắn header `X-Demo-Player` (HTTP 401).
- Chống giả mạo Origin và CSRF đối với các thao tác ghi dữ liệu (mutation).
- Chống replay attack bằng UNIQUE replay_key trong SQLite.
- Phân lập dữ liệu hoàn toàn: Ví A chỉ xem và ghi nhận được tiến trình của Ví A.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Path as FPath, Request
from pydantic import BaseModel, ConfigDict, Field

import config
from api.ngu_canh_ai import gan_nguon_du_lieu_ai
from api.nhan_vat_ai import kiem_tra_csrf_va_origin, lay_nguoi_choi_xac_thuc
from api.tien_trinh_adapter import tao_tien_trinh_adapter
from core.blockchain_verifier import LoiBlockchainRPC, tao_blockchain_verifier_tu_moi_truong
from core.man_choi import doc as doc_man_choi
from core.schemas_nhan_vat import NguoiChoiXacThuc
from core.tien_trinh_storage import (
    BanGhiTienTrinh,
    KhoTienTrinh,
    LoiKhoTienTrinh,
    LoiQuyenTienTrinh,
    LoiReplayTienTrinh,
)
from core.tien_trinh_verifier import DichVuXacMinhTienTrinh, LoiXacMinhTienTrinh

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/ai/tien-trinh", tags=["AI tiến trình người chơi"])

TEN_CAC_MAN: dict[int, str] = {
    1: "Đồng cỏ",
    2: "Rừng thưa",
    3: "Hang đá",
    4: "Rừng rậm",
    5: "Thung lũng xương",
    6: "Mỏ vàng",
}


# ===========================================================================
# SCHEMAS
# ===========================================================================

class ChiTietManChoi(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    stage_id: int = Field(ge=1, le=6)
    name: str
    status: Literal["completed", "unlocked", "locked"]
    verification_source: str | None = None
    completed_at: str | None = None


class PhanHoiTienTrinh(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    owner_user_id: str
    verified_wallet_address: str
    completed_stage_ids: list[int]
    allowed_stage_ids: list[int]
    stages: list[ChiTietManChoi]
    total_completed: int
    is_character_unlocked: bool


class YeuCauXacMinhTienTrinh(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)
    stage_id: int = Field(ge=1, le=6)
    evidence_type: Literal["referee_log", "blockchain_tx"]
    evidence: str = Field(min_length=8, max_length=128)


# ===========================================================================
# DEPENDENCY & LIFECYCLE
# ===========================================================================

def khoi_dong_tien_trinh(app: FastAPI) -> None:
    """Khởi tạo KhoTienTrinh, DichVuXacMinhTienTrinh và gắn adapter vào app.state."""
    enabled = (
        "tien_trinh" in config.ENABLED
        or "auth" in config.ENABLED
        or getattr(app.state, "auth_service", None) is not None
        or getattr(app.state, "ai_auth_source", None) is not None
        or "AUTH_CSRF_SECRET" in os.environ
        or "AUTH_DATABASE_URL" in os.environ
        or "AI_PROGRESS_DB" in os.environ
    )
    if not enabled:
        return

    try:
        db_path = os.environ.get("AI_PROGRESS_DB", config.AI_PROGRESS_DB)
        kho = KhoTienTrinh(db_path)
        app.state.kho_tien_trinh = kho

        # Nạp danh sách màn từ man_choi.json nếu có
        cac_man = None
        if config.MAN_CHOI.exists():
            try:
                cac_man = doc_man_choi(config.MAN_CHOI)
            except Exception as e:
                log.warning("Không nạp được man_choi.json trong khoi_dong_tien_trinh (%s)", e)

        bc_verifier = tao_blockchain_verifier_tu_moi_truong()

        so_phieu_path = Path(os.environ.get("SO_PHIEU", config.SO_PHIEU))
        so_ve_path = Path(os.environ.get("SO_VE", config.SO_VE))
        nhat_ky_dir = Path(os.environ.get("NHAT_KY_DIR", config.NHAT_KY_DIR))

        dich_vu = DichVuXacMinhTienTrinh(
            kho=kho,
            nhat_ky_dir=nhat_ky_dir,
            so_phieu_path=so_phieu_path,
            so_ve_path=so_ve_path,
            cac_man=cac_man,
            ban_do_dir=config.BAN_DO_DIR,
            blockchain_verifier=bc_verifier,
        )
        app.state.dich_vu_tien_trinh = dich_vu

        # Gắn adapter tiến trình vào app.state.ai_player_source
        adapter = tao_tien_trinh_adapter(kho)
        gan_nguon_du_lieu_ai(app, adapter)
        log.info("Đã khởi tạo thành công hệ thống tiến trình người chơi và gắn ai_player_source.")
    except Exception as e:
        log.error("Không thể khởi động hệ thống tiến trình người chơi (%s)", type(e).__name__)


def tien_trinh_da_nap(app: FastAPI) -> bool:
    return getattr(app.state, "kho_tien_trinh", None) is not None and getattr(app.state, "dich_vu_tien_trinh", None) is not None


def lay_dich_vu_tien_trinh(request: Request) -> DichVuXacMinhTienTrinh:
    dv = getattr(request.app.state, "dich_vu_tien_trinh", None)
    if dv is None:
        raise HTTPException(503, "Dịch vụ tiến trình chưa sẵn sàng")
    return dv


def lay_kho_tien_trinh(request: Request) -> KhoTienTrinh:
    kho = getattr(request.app.state, "kho_tien_trinh", None)
    if kho is None:
        raise HTTPException(503, "Kho tiến trình chưa sẵn sàng")
    return kho


# ===========================================================================
# ENDPOINTS
# ===========================================================================

@router.get("", response_model=PhanHoiTienTrinh)
def lay_tien_trinh_nguoi_choi(
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    kho: Annotated[KhoTienTrinh, Depends(lay_kho_tien_trinh)],
) -> PhanHoiTienTrinh:
    """Truy xuất tổng quan tiến trình vượt màn của người chơi đang đăng nhập."""
    try:
        ban_ghis = kho.lay_tien_trinh(player.user_id)
    except LoiKhoTienTrinh:
        raise HTTPException(503, "Không đọc được tiến trình người chơi") from None

    ban_ghi_map = {bg.stage_id: bg for bg in ban_ghis if bg.completion_status == "completed"}
    completed_ids = sorted(ban_ghi_map.keys())

    stages_detail: list[ChiTietManChoi] = []
    for s_id in range(1, 7):
        name = TEN_CAC_MAN.get(s_id, f"Màn {s_id}")
        if s_id in ban_ghi_map:
            bg = ban_ghi_map[s_id]
            stages_detail.append(ChiTietManChoi(
                stage_id=s_id,
                name=name,
                status="completed",
                verification_source=bg.verification_source,
                completed_at=bg.completed_at,
            ))
        else:
            stages_detail.append(ChiTietManChoi(
                stage_id=s_id,
                name=name,
                status="unlocked",
                verification_source=None,
                completed_at=None,
            ))

    is_unlocked = frozenset(range(1, 7)) <= frozenset(completed_ids)

    return PhanHoiTienTrinh(
        owner_user_id=player.user_id,
        verified_wallet_address=player.wallet_address,
        completed_stage_ids=completed_ids,
        allowed_stage_ids=list(range(1, 7)),
        stages=stages_detail,
        total_completed=len(completed_ids),
        is_character_unlocked=is_unlocked,
    )


@router.post("/xac-minh", response_model=BanGhiTienTrinh, dependencies=[Depends(kiem_tra_csrf_va_origin)])
def xac_minh_tien_trinh(
    yc: YeuCauXacMinhTienTrinh,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    dich_vu: Annotated[DichVuXacMinhTienTrinh, Depends(lay_dich_vu_tien_trinh)],
) -> BanGhiTienTrinh:
    """Xác minh bằng chứng hoàn thành màn (referee_log hoặc blockchain_tx) và ghi nhận."""
    try:
        if yc.evidence_type == "referee_log":
            return dich_vu.xac_minh_referee_log(
                player=player,
                stage_id=yc.stage_id,
                ma_van=yc.evidence,
            )
        elif yc.evidence_type == "blockchain_tx":
            return dich_vu.xac_minh_blockchain_tx(
                player=player,
                stage_id=yc.stage_id,
                tx_hash=yc.evidence,
            )
        else:
            raise HTTPException(422, "Loại bằng chứng không được hỗ trợ")
    except LoiReplayTienTrinh as e:
        raise HTTPException(409, str(e)) from None
    except LoiQuyenTienTrinh as e:
        raise HTTPException(403, str(e)) from None
    except LoiXacMinhTienTrinh as e:
        raise HTTPException(422, str(e)) from None
    except LoiBlockchainRPC as e:
        raise HTTPException(503, f"Lỗi kết nối RPC blockchain: {e}") from None
    except LoiKhoTienTrinh as e:
        raise HTTPException(503, str(e)) from None


@router.get("/{stage_id}", response_model=BanGhiTienTrinh)
def chi_tiet_tien_trinh_man(
    stage_id: Annotated[int, FPath(ge=1, le=6)],
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    kho: Annotated[KhoTienTrinh, Depends(lay_kho_tien_trinh)],
) -> BanGhiTienTrinh:
    """Xem chi tiết bằng chứng hoàn thành của một màn cụ thể (chỉ chủ sở hữu)."""
    bg = kho.lay_ban_ghi(player.user_id, stage_id)
    if bg is None or bg.completion_status != "completed":
        raise HTTPException(404, f"Màn {stage_id} chưa được ghi nhận hoàn thành")
    return bg
