from __future__ import annotations

import asyncio
from dataclasses import dataclass
from hashlib import sha256
import logging
import os
import re
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Path, Request
from fastapi.responses import Response

from api.nhiem_vu import NguCanhNguoiChoi, StageID
from api.ngu_canh_ai import lay_ban_chup_ai
from core.ai_nhan_vat import tao_anh_nhan_vat
from core.dich_vu_anh import DichVuAnh
from core.kho_anh import KhoAnh, LoiKhoAnh, XungDotYeuCauAnh
from core.nhan_vat_ai import AnhNhanVat, YeuCauTaoNhanVat
from core.nhan_vat_storage import (
    GiaoDichDaDuocSuDung,
    KhoNhanVat,
    KhoNhanVatDay,
    LoiKhoNhanVat,
    LoiQuyenTruyCapNhanVat,
    LoiToanVenNhanVat,
    NhanVatKhongTonTai,
    VuotGioiHanNhanVat,
    tinh_character_hash,
)
from core.providers.anh import AnhMauOffline, LoiProviderAnh
from core.providers.anh_http import provider_anh_tu_moi_truong
from core.quota_ai import KhoQuotaAI, LoiQuotaAI, VuotQuotaAI
from core.schemas_nhan_vat import (
    DuLieuChuanBiOnchain,
    KetQuaKiemTraHash,
    NguoiChoiXacThuc,
    ThongTinNhanVat,
    YeuCauLuuNhanVat,
    YeuCauXacNhanOnchain,
)

log = logging.getLogger(__name__)
router = APIRouter(prefix="/api/ai/nhan-vat", tags=["AI ảnh nhân vật"])


class NguCanhAnhNhanVat(NguCanhNguoiChoi):
    context_source: Literal["verified"] = "verified"
    completed_stage_ids: frozenset[StageID] = frozenset()
    user_id: str | None = None
    wallet_address: str | None = None


class PhanHoiAnhNhanVat(AnhNhanVat):
    context_source: Literal["verified", "demo"]


@dataclass
class TrangThaiNhanVatAI:
    enabled: bool = False
    demo_enabled: bool = False
    kho: KhoAnh | None = None
    kho_nhan_vat: KhoNhanVat | None = None
    service: DichVuAnh | None = None
    demo_service: DichVuAnh | None = None


def khoi_dong_nhan_vat_ai(app: FastAPI) -> None:
    import config

    state = TrangThaiNhanVatAI(enabled="nhan_vat_ai" in config.ENABLED)
    app.state.nhan_vat_ai = state
    if not state.enabled:
        return
    try:
        demo = os.environ.get("AI_IMAGE_DEMO", "false").strip().lower()
        if demo not in ("true", "false", "1", "0"):
            raise ValueError("AI_IMAGE_DEMO không hợp lệ")
        ttl = int(os.environ.get("AI_IMAGE_TTL_SECONDS", "86400"))
        capacity = int(os.environ.get("AI_IMAGE_MAX_IMAGES", "200"))
        provider_demo = AnhMauOffline(config.APP_FLUTTER / "assets" / "images")
        for description in ("Nhân vật", "Thợ mỏ", "Hiệp sĩ", "Cao bồi"):
            tao_anh_nhan_vat(YeuCauTaoNhanVat(description=description), demo_provider=provider_demo)
        kho = KhoAnh(os.environ.get("AI_IMAGE_DB", config.DATA_DIR / "anh_nhan_vat" / "images.sqlite3"),
                     han_luu_giay=ttl, so_anh_toi_da=capacity)
        kho.don_het_han()
        state.kho = kho

        char_db = os.environ.get("AI_CHARACTER_DB", config.AI_CHARACTER_DB)
        max_user_chars = int(os.environ.get("AI_MAX_CHARACTERS_PER_USER", str(config.AI_MAX_CHARACTERS_PER_USER)))
        max_total_chars = int(os.environ.get("AI_MAX_CHARACTERS_TOTAL", str(config.AI_MAX_CHARACTERS_TOTAL)))
        state.kho_nhan_vat = KhoNhanVat(
            char_db,
            so_nhan_vat_toi_da=max_total_chars,
            so_nhan_vat_moi_nguoi=max_user_chars,
        )

        try:
            provider = provider_anh_tu_moi_truong()
        except (ValueError, TypeError) as e:
            log.warning("Cấu hình provider ảnh không hợp lệ (%s); dùng mẫu demo", type(e).__name__)
            provider = None
        quota = KhoQuotaAI(os.environ.get("AI_QUOTA_DB", config.DATA_DIR / "quota_ai" / "quota.sqlite3"))
        state.service = DichVuAnh(kho, demo_provider=provider_demo, provider=provider, quota=quota,
            gioi_han_ngay=int(os.environ.get("AI_IMAGE_DAILY_LIMIT", "5")))
        state.demo_service = DichVuAnh(kho, demo_provider=provider_demo)
        state.demo_enabled = demo in ("true", "1")
    except (OSError, ValueError, TypeError, LoiKhoAnh, LoiKhoNhanVat, LoiProviderAnh, LoiQuotaAI) as e:
        log.error("Không khởi động được API ảnh nhân vật (%s)", type(e).__name__)


def nhan_vat_ai_da_nap(app: FastAPI) -> bool:
    state = getattr(app.state, "nhan_vat_ai", None)
    return state is not None and state.enabled and state.service is not None and state.kho_nhan_vat is not None


def lay_trang_thai(request: Request) -> TrangThaiNhanVatAI:
    state = getattr(request.app.state, "nhan_vat_ai", None)
    if state is None:
        raise HTTPException(503, "API ảnh nhân vật chưa được khởi tạo")
    if not state.enabled:
        raise HTTPException(404, "Thành phần ảnh nhân vật đang tắt")
    if state.service is None or state.kho is None:
        raise HTTPException(503, "API ảnh nhân vật chưa sẵn sàng")
    return state


async def lay_ngu_canh_anh(
    request: Request,
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
    x_demo_player: Annotated[str | None, Header(alias="X-Demo-Player", min_length=1, max_length=64,
                                               pattern=r"^[A-Za-z0-9_-]+$")] = None,
) -> NguCanhNguoiChoi:
    snapshot = await lay_ban_chup_ai(request)
    if snapshot is not None:
        return NguCanhAnhNhanVat(
            player_id=snapshot.player_id,
            allowed_stage_ids=snapshot.allowed_stage_ids,
            completed_stage_ids=snapshot.completed_stage_ids,
            user_id=getattr(snapshot, "user_id", None),
            wallet_address=getattr(snapshot, "wallet_address", None),
        )
    ctx = getattr(request.state, "ai_image_player", None)
    if ctx is not None:
        if not isinstance(ctx, NguCanhNguoiChoi):
            raise HTTPException(503, "Ngữ cảnh người chơi từ backend không hợp lệ")
        cls = NguCanhAnhNhanVat if isinstance(ctx, NguCanhAnhNhanVat) else NguCanhNguoiChoi
        try:
            return cls.model_validate(ctx.model_dump(warnings=False), strict=True)
        except ValueError:
            raise HTTPException(503, "Ngữ cảnh người chơi từ backend không hợp lệ") from None
    if not state.demo_enabled:
        raise HTTPException(503, "Chưa có ngữ cảnh người chơi đã xác minh")
    if x_demo_player is None:
        raise HTTPException(422, "Cần X-Demo-Player cho phiên demo")
    return NguCanhNguoiChoi(player_id=x_demo_player, context_source="demo")


async def lay_nguoi_choi_xac_thuc(request: Request) -> NguoiChoiXacThuc:
    """Xác thực người chơi fail-closed dựa trên phiên SIWE backend.

    Quy định bảo mật:
    - Không tin client khai báo ví trong request body/query.
    - Không cấp quyền cho phiên demo (X-Demo-Player bị từ chối 401).
    - Không tự động tạo user giả.
    - Chỉ chấp nhận phiên có user_id và ví Ethereum hợp lệ (0x...).
    """
    # 1. State direct injection (middleware hoặc adapter)
    ctx = getattr(request.state, "ai_auth_user", None)
    if isinstance(ctx, NguoiChoiXacThuc):
        return ctx

    # 2. Hook nguồn xác thực SIWE chuyên biệt (nếu module Auth đăng ký)
    auth_source = getattr(request.app.state, "ai_auth_source", None)
    if auth_source is not None:
        try:
            timeout = getattr(request.app.state, "ai_auth_source_timeout", 5)
            user = await asyncio.wait_for(auth_source(request), timeout=timeout)
            if user is not None:
                if not isinstance(user, NguoiChoiXacThuc):
                    raise HTTPException(503, "Dữ liệu xác thực người chơi từ backend không hợp lệ")
                return NguoiChoiXacThuc.model_validate(user.model_dump(warnings=False), strict=True)
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(503, "Hệ thống xác thực tạm thời không sẵn sàng") from None

    # 3. Snapshot người chơi chung (lay_ban_chup_ai)
    snapshot = await lay_ban_chup_ai(request)
    if snapshot is not None:
        u_id = getattr(snapshot, "user_id", None)
        w_addr = getattr(snapshot, "wallet_address", None)
        p_id = getattr(snapshot, "player_id", "")
        if not w_addr and re.fullmatch(r"^0x[0-9a-fA-F]{40}$", p_id):
            w_addr = p_id
        if not u_id and p_id:
            u_id = p_id
        if u_id and w_addr:
            try:
                return NguoiChoiXacThuc(user_id=str(u_id), wallet_address=str(w_addr))
            except ValueError:
                raise HTTPException(503, "Dữ liệu ví xác thực trong snapshot không hợp lệ")

    # 4. State ai_image_player nếu có
    img_player = getattr(request.state, "ai_image_player", None)
    if img_player is not None and getattr(img_player, "context_source", None) == "verified":
        u_id = getattr(img_player, "user_id", None)
        w_addr = getattr(img_player, "wallet_address", None)
        p_id = getattr(img_player, "player_id", "")
        if not w_addr and re.fullmatch(r"^0x[0-9a-fA-F]{40}$", p_id):
            w_addr = p_id
        if not u_id and p_id:
            u_id = p_id
        if u_id and w_addr:
            try:
                return NguoiChoiXacThuc(user_id=str(u_id), wallet_address=str(w_addr))
            except ValueError:
                raise HTTPException(503, "Dữ liệu ví xác thực không hợp lệ")

    # FAIL-CLOSED: Không có phiên xác thực SIWE hợp lệ
    raise HTTPException(401, "Yêu cầu đăng nhập ví MetaMask qua phiên SIWE đã xác minh")


def _player_key(ctx: NguCanhNguoiChoi) -> str:
    return sha256(f"{ctx.context_source}:{ctx.player_id}".encode("ascii")).hexdigest()


# ---------- Endpoint cũ: Tạo ảnh preview & xem trước ----------

@router.post("/tao", response_model=PhanHoiAnhNhanVat)
def tao_anh(
    yc: YeuCauTaoNhanVat,
    ctx: Annotated[NguCanhNguoiChoi, Depends(lay_ngu_canh_anh)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
    request_id: Annotated[str, Header(alias="Idempotency-Key", min_length=1, max_length=64,
                                     pattern=r"^[A-Za-z0-9_-]+$")],
) -> PhanHoiAnhNhanVat:
    if ctx.context_source == "verified" and (
        not isinstance(ctx, NguCanhAnhNhanVat)
        or not frozenset(range(1, 7)) <= ctx.completed_stage_ids
    ):
        raise HTTPException(403, "Cần hoàn thành đủ màn 1–6 để tạo ảnh nhân vật")
    service = state.demo_service if ctx.context_source == "demo" else state.service
    try:
        anh = service.tao(player_id=_player_key(ctx), request_id=request_id, yeu_cau=yc)
    except VuotQuotaAI as e:
        raise HTTPException(429, "Đã hết lượt gọi AI trong ngày; hãy thử lại sau",
                            headers={"Retry-After": str(e.cho_lai_sau)}) from None
    except XungDotYeuCauAnh:
        raise HTTPException(409, "Idempotency-Key đã được dùng cho mô tả khác") from None
    except (LoiKhoAnh, LoiProviderAnh, LoiQuotaAI, ValueError):
        raise HTTPException(503, "Chưa tạo được ảnh nhân vật hợp lệ; hãy thử lại sau") from None
    return PhanHoiAnhNhanVat(**anh.model_dump(), context_source=ctx.context_source)


@router.get("/anh/{image_id}", response_class=Response, responses={200: {"content": {"image/png": {}}}})
def lay_anh(
    image_id: Annotated[str, Path(min_length=36, max_length=36, pattern=r"^img_[0-9a-f]{32}$")],
    ctx: Annotated[NguCanhNguoiChoi, Depends(lay_ngu_canh_anh)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> Response:
    try:
        anh = state.kho.doc_cho_nguoi(_player_key(ctx), image_id)
    except (LoiKhoAnh, ValueError):
        raise HTTPException(503, "Chưa đọc được ảnh nhân vật hợp lệ") from None
    if anh is None:
        raise HTTPException(404, "Không có ảnh khả dụng cho người chơi")
    return Response(content=anh[1], media_type="image/png",
                    headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})


# ---------- Endpoint mới: Lưu trữ nhân vật bền vững & Quản lý sở hữu ----------

@router.post("/luu", response_model=ThongTinNhanVat, status_code=201)
async def luu_nhan_vat(
    yc: YeuCauLuuNhanVat,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
    request: Request,
) -> ThongTinNhanVat:
    """Lưu chính thức nhân vật đã tạo từ preview cache vào kho lưu trữ bền vững.

    Quyền sở hữu được gắn chặt với user_id và verified_wallet_address của phiên SIWE.
    """
    if state.kho_nhan_vat is None:
        raise HTTPException(503, "Kho lưu trữ nhân vật chưa sẵn sàng")

    # 1. Đọc preview image từ KhoAnh
    try:
        anh_preview = state.kho.doc(yc.image_id)
    except (LoiKhoAnh, ValueError):
        raise HTTPException(503, "Chưa đọc được dữ liệu preview cache") from None

    if anh_preview is None:
        raise HTTPException(404, "Ảnh nhân vật không tồn tại hoặc đã hết hạn trong preview cache")

    meta_preview, png_bytes = anh_preview

    # 2. Kiểm tra quyền sở hữu preview trong yeu_cau_anh:
    # Chỉ người chơi đã tạo preview image trong phiên verified mới được quyền lưu.
    expected_keys = {
        sha256(f"verified:{player.user_id}".encode("ascii")).hexdigest(),
        sha256(f"verified:{player.wallet_address}".encode("ascii")).hexdigest(),
        sha256(f"verified:{player.wallet_address.lower()}".encode("ascii")).hexdigest(),
    }
    img_player = getattr(request.state, "ai_image_player", None)
    if img_player is not None and getattr(img_player, "player_id", None):
        expected_keys.add(sha256(f"verified:{img_player.player_id}".encode("ascii")).hexdigest())

    with state.kho._ket_noi() as conn:
        row = conn.execute("SELECT player_id FROM yeu_cau_anh WHERE image_id = ?", (yc.image_id,)).fetchone()

    if row is None or row["player_id"] not in expected_keys:
        raise HTTPException(403, "Không thể lưu ảnh nhân vật tạo từ phiên demo hoặc của người chơi khác")

    # 3. Lưu vào kho nhân vật bền vững
    try:
        return state.kho_nhan_vat.luu_nhan_vat(
            player=player,
            image_id=yc.image_id,
            image_bytes=png_bytes,
            generation_source=meta_preview.generation_source,
            name=yc.name,
        )
    except VuotGioiHanNhanVat as e:
        raise HTTPException(429, str(e)) from None
    except KhoNhanVatDay as e:
        raise HTTPException(503, str(e)) from None
    except (LoiKhoNhanVat, ValueError):
        raise HTTPException(503, "Không thể lưu nhân vật vào kho lưu trữ bền vững") from None


@router.get("/danh-sach", response_model=list[ThongTinNhanVat])
def danh_sach_nhan_vat(
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> list[ThongTinNhanVat]:
    """Xem danh sách nhân vật thuộc sở hữu của chính ví đang đăng nhập."""
    if state.kho_nhan_vat is None:
        raise HTTPException(503, "Kho lưu trữ nhân vật chưa sẵn sàng")
    try:
        return state.kho_nhan_vat.danh_sach_nhan_vat(player)
    except (LoiKhoNhanVat, ValueError):
        raise HTTPException(503, "Chưa đọc được danh sách nhân vật") from None


@router.get("/{character_id}", response_model=ThongTinNhanVat)
def lay_thong_tin_nhan_vat(
    character_id: Annotated[str, Path(min_length=37, max_length=37, pattern=r"^char_[0-9a-f]{32}$")],
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> ThongTinNhanVat:
    """Xem metadata chi tiết của một nhân vật (chỉ chủ sở hữu)."""
    if state.kho_nhan_vat is None:
        raise HTTPException(503, "Kho lưu trữ nhân vật chưa sẵn sàng")
    try:
        return state.kho_nhan_vat.doc_nhan_vat(character_id, nguoi_yeu_cau=player)
    except NhanVatKhongTonTai:
        raise HTTPException(404, "Nhân vật không tồn tại") from None
    except LoiQuyenTruyCapNhanVat:
        raise HTTPException(403, "Không có quyền truy cập nhân vật này") from None
    except (LoiKhoNhanVat, ValueError):
        raise HTTPException(503, "Chưa đọc được thông tin nhân vật") from None


@router.get("/{character_id}/anh", response_class=Response, responses={200: {"content": {"image/png": {}}}})
def tai_anh_nhan_vat(
    character_id: Annotated[str, Path(min_length=37, max_length=37, pattern=r"^char_[0-9a-f]{32}$")],
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> Response:
    """Tải ảnh PNG nhân vật chính thức từ kho bền vững kèm kiểm tra toàn vẹn SHA-256."""
    if state.kho_nhan_vat is None:
        raise HTTPException(503, "Kho lưu trữ nhân vật chưa sẵn sàng")
    try:
        meta, blob = state.kho_nhan_vat.doc_anh_nhan_vat(character_id, nguoi_yeu_cau=player)
    except NhanVatKhongTonTai:
        raise HTTPException(404, "Nhân vật không tồn tại") from None
    except LoiQuyenTruyCapNhanVat:
        raise HTTPException(403, "Không có quyền tải ảnh nhân vật này") from None
    except LoiToanVenNhanVat:
        raise HTTPException(500, "Dữ liệu ảnh nhân vật bị sai lệch tính toàn vẹn SHA-256") from None
    except (LoiKhoNhanVat, ValueError):
        raise HTTPException(503, "Chưa đọc được ảnh nhân vật") from None
    return Response(
        content=blob,
        media_type="image/png",
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )


@router.get("/{character_id}/kiem-tra-hash", response_model=KetQuaKiemTraHash)
def kiem_tra_hash_nhan_vat(
    character_id: Annotated[str, Path(min_length=37, max_length=37, pattern=r"^char_[0-9a-f]{32}$")],
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> KetQuaKiemTraHash:
    """Kiểm tra và tính lại SHA-256 của ảnh nhân vật để đối soát tính toàn vẹn."""
    if state.kho_nhan_vat is None:
        raise HTTPException(503, "Kho lưu trữ nhân vật chưa sẵn sàng")
    # Kiểm tra quyền sở hữu trước
    try:
        state.kho_nhan_vat.doc_nhan_vat(character_id, nguoi_yeu_cau=player)
    except NhanVatKhongTonTai:
        raise HTTPException(404, "Nhân vật không tồn tại") from None
    except LoiQuyenTruyCapNhanVat:
        raise HTTPException(403, "Không có quyền kiểm tra nhân vật này") from None

    try:
        return state.kho_nhan_vat.kiem_tra_hash(character_id)
    except (LoiKhoNhanVat, ValueError):
        raise HTTPException(503, "Chưa kiểm tra được hash nhân vật") from None


@router.get("/{character_id}/chuan-bi-onchain", response_model=DuLieuChuanBiOnchain)
def chuan_bi_onchain_nhan_vat(
    character_id: Annotated[str, Path(min_length=37, max_length=37, pattern=r"^char_[0-9a-f]{32}$")],
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> DuLieuChuanBiOnchain:
    """Cung cấp dữ liệu đã format đúng chuẩn để chuẩn bị đăng ký character_hash lên blockchain."""
    import config
    if state.kho_nhan_vat is None:
        raise HTTPException(503, "Kho lưu trữ nhân vật chưa sẵn sàng")
    try:
        state.kho_nhan_vat.doc_nhan_vat(character_id, nguoi_yeu_cau=player)
    except NhanVatKhongTonTai:
        raise HTTPException(404, "Nhân vật không tồn tại") from None
    except LoiQuyenTruyCapNhanVat:
        raise HTTPException(403, "Không có quyền truy cập dữ liệu on-chain của nhân vật này") from None

    try:
        return state.kho_nhan_vat.chuan_bi_onchain(
            character_id,
            chain_id=config.CHAIN_ID,
            registry_contract=config.HOP_DONG_DANG_KY_NHAN_VAT or None,
        )
    except (LoiKhoNhanVat, ValueError):
        raise HTTPException(503, "Chưa chuẩn bị được dữ liệu on-chain") from None


@router.post("/{character_id}/xac-minh-onchain", response_model=ThongTinNhanVat)
def xac_minh_onchain(
    character_id: Annotated[str, Path(min_length=37, max_length=37, pattern=r"^char_[0-9a-f]{32}$")],
    yc: YeuCauXacNhanOnchain,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_xac_thuc)],
    state: Annotated[TrangThaiNhanVatAI, Depends(lay_trang_thai)],
) -> ThongTinNhanVat:
    """Cập nhật trạng thái giao dịch đăng ký on-chain dựa trên transaction_hash hợp lệ."""
    if state.kho_nhan_vat is None:
        raise HTTPException(503, "Kho lưu trữ nhân vật chưa sẵn sàng")
    try:
        return state.kho_nhan_vat.xac_nhan_giao_dich_onchain(
            character_id, yc.transaction_hash, nguoi_yeu_cau=player
        )
    except NhanVatKhongTonTai:
        raise HTTPException(404, "Nhân vật không tồn tại") from None
    except LoiQuyenTruyCapNhanVat:
        raise HTTPException(403, "Không có quyền cập nhật nhân vật này") from None
    except GiaoDichDaDuocSuDung as e:
        raise HTTPException(409, str(e)) from None
    except (LoiKhoNhanVat, ValueError):
        raise HTTPException(503, "Không thể cập nhật trạng thái giao dịch on-chain") from None
