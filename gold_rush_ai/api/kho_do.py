"""API quản lý kho đồ và trang bị cho người chơi (Bảo vệ theo phiên SIWE)."""
from __future__ import annotations

import logging
from typing import Annotated, Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

import config
from api.auth_guard import NguoiChoiXacThuc, kiem_tra_csrf_va_origin, lay_nguoi_choi_hien_tai
from core.csdl import lay_csdl
from core.kho_do import dong_bo_vat_pham_nft, lay_kho_do
from core.tien_trinh import doi_trang_bi, lay_hoac_tao_nguoi_choi, lay_tien_trinh
from core.xac_minh_ve_onchain import LoiXacMinhVe, XacMinhVeOnchain

log = logging.getLogger("api.kho_do")
router = APIRouter(prefix="/api", tags=["Kho đồ & Trang bị"])


class YeuCauDoiTrangBi(BaseModel):
    """Payload yêu cầu đổi trang bị."""
    model_config = ConfigDict(extra="forbid", frozen=True)

    loai: Literal["weapon", "character"] = Field(..., description="Loại trang bị: weapon hoặc character")
    item_id: str = Field(..., min_length=1, max_length=64, description="Mã vật phẩm muốn trang bị")


class VatPhamNFTDongBo(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    item_id: str = Field(..., min_length=1, max_length=64)
    item_type: str = Field(..., min_length=1, max_length=32)
    token_id: int = Field(..., ge=1)
    metadata: dict = Field(default_factory=dict)


class YeuCauDongBoNFT(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    vat_pham: list[VatPhamNFTDongBo] = Field(..., min_length=1, max_length=27)


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


@router.post("/inventory/sync-nft")
def dong_bo_kho_nft(
    yc: YeuCauDongBoNFT,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Đọc quyền sở hữu ERC-1155 thật rồi đồng bộ SQLite của người chơi."""
    kiem_tra_csrf_va_origin(request, player)
    hop_dong = (config.HOP_DONG_VAT_PHAM or "").strip()
    rpc_url = (config.BLOCKCHAIN_RPC_URL or "").strip()
    if not hop_dong or not rpc_url:
        raise HTTPException(503, "Chưa cấu hình RPC hoặc hợp đồng NFT vật phẩm.")

    verifier = XacMinhVeOnchain(
        rpc_url=rpc_url,
        contract_address=hop_dong,
        chain_id=config.CHAIN_ID,
        timeout_seconds=config.RPC_TIMEOUT_SECONDS,
    )
    try:
        verifier.xac_minh_chain_id()
        so_du = [
            {
                **item.model_dump(),
                "quantity": verifier.lay_balance_erc1155(player.wallet_address, item.token_id),
            }
            for item in yc.vat_pham
        ]
    except LoiXacMinhVe as e:
        raise HTTPException(503, e.message) from None

    with lay_csdl() as conn:
        lay_hoac_tao_nguoi_choi(conn, player_id=player.user_id, wallet_address=player.wallet_address)
        dong_bo_vat_pham_nft(conn, player.user_id, hop_dong, config.CHAIN_ID, so_du)
    return {
        "thanh_cong": True,
        "wallet": player.wallet_address,
        "so_du": [{"token_id": x["token_id"], "quantity": x["quantity"]} for x in so_du],
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
