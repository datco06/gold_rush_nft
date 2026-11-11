"""API quản lý tiến trình người chơi (Cấp độ, EXP, Màn đã mở, Nhân vật).

Tuân thủ nguyên tắc bảo mật:
- Bắt buộc xác thực SIWE qua cookie HttpOnly `gr_session` (Fail-Closed).
- Không chấp nhận player_id hay wallet tự khai từ client query params.
- Mọi thao tác thay đổi dữ liệu (mutation) đều yêu cầu kiểm tra Origin và CSRF token.
- Chống replay bằng chứng qua UNIQUE constraint trong SQLite.
"""
from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from api.auth_guard import NguoiChoiXacThuc, kiem_tra_csrf_va_origin, lay_nguoi_choi_hien_tai
from core.csdl import lay_csdl
from core.tien_trinh import hoan_thanh_man, lay_hoac_tao_nguoi_choi, lay_tien_trinh

log = logging.getLogger("api.tien_trinh")
router = APIRouter(prefix="/api/progress", tags=["Tiến trình người chơi"])


class YeuCauHoanThanhMan(BaseModel):
    """Payload xác nhận hoàn thành màn chơi có kèm bằng chứng."""
    model_config = ConfigDict(extra="forbid", frozen=True)

    stage_id: int = Field(..., ge=1, le=6, description="Màn chơi chính từ 1 đến 6")
    evidence_id: str = Field(
        ...,
        min_length=8,
        max_length=128,
        description="Mã ván hoặc bằng chứng hợp lệ đã được kiểm định",
    )


@router.get("")
@router.get("/")
def lay_thong_tin_tien_trinh(
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Lấy thông tin tiến trình của người chơi hiện tại (màn mở, EXP, cấp độ, trang bị).

    Danh tính được xác thực qua phiên SIWE (Fail-Closed).
    Nếu người chơi chưa có bản ghi, hệ thống sẽ tự động khởi tạo tiến trình ban đầu.
    """
    with lay_csdl() as conn:
        tt = lay_hoac_tao_nguoi_choi(
            conn,
            player_id=player.user_id,
            wallet_address=player.wallet_address,
        )
    if tt is None:
        raise HTTPException(500, "Không thể khởi tạo hoặc truy xuất tiến trình người chơi")
    return tt


@router.post("/complete-stage", status_code=200)
def xac_nhan_hoan_thanh_man(
    yc: YeuCauHoanThanhMan,
    request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Ghi nhận hoàn thành màn chơi và nhận thưởng EXP có bằng chứng hợp lệ (Fail-Closed).

    Quy tắc Zero-Trust:
    1. Bắt buộc kiểm tra Origin và CSRF token qua `kiem_tra_csrf_va_origin`.
    2. Chỉ chấp nhận các màn hợp lệ từ 1 đến 6.
    3. Bằng chứng (evidence_id) phải được xác minh từ nguồn có thẩm quyền:
       - Đã ký phiếu vàng trọng tài (SoPhieu) khớp với địa chỉ ví SIWE của người chơi.
       - Hoặc bản ghi trọng tài đã thẩm định (is_verified = 1) và thuộc quyền sở hữu của người chơi.
       - Hoặc dịch vụ xác minh `tien_trinh_verifier` từ `feature/ai` (nếu đã tích hợp).
    4. Tuyệt đối KHÔNG tin tưởng telemetry thô (is_verified = 0) hoặc evidence_id không tồn tại.
    5. Chống replay: Mỗi bằng chứng chỉ được nhận thưởng đúng một lần trên toàn hệ thống.
    """
    kiem_tra_csrf_va_origin(request, player)

    with lay_csdl() as conn:
        cur = conn.cursor()

        # 1. Chống replay: Kiểm tra xem bằng chứng đã được ghi nhận thưởng trong CSDL chưa
        cur.execute("SELECT player_id, stage_id FROM stage_rewards WHERE evidence_id = ?", (yc.evidence_id,))
        da_nhan = cur.fetchone()
        if da_nhan is not None:
            raise HTTPException(status_code=409, detail="Bằng chứng này đã được sử dụng để nhận thưởng trước đó.")

        da_xac_minh = False
        user_wallet = player.wallet_address.lower()

        # 2. Kiểm tra nếu có dịch vụ xác minh chuyên trách từ feature/ai (DichVuXacMinhTienTrinh)
        verifier = getattr(request.app.state, "tien_trinh_verifier", None)
        if verifier is not None:
            try:
                verifier.xac_minh_referee_log(player, yc.stage_id, yc.evidence_id)
                da_xac_minh = True
            except Exception as e_vf:
                raise HTTPException(status_code=422, detail=f"Xác minh tiến trình thất bại: {e_vf}")

        # 3. Thẩm định qua Sổ Phiếu trọng tài Backend (SoPhieu)
        if not da_xac_minh:
            from config import SO_PHIEU
            from core.trong_tai import SoPhieu
            if SO_PHIEU.exists():
                so = SoPhieu(SO_PHIEU)
                phieu = so.lay(yc.evidence_id)
                if phieu is not None:
                    # Kiểm tra quyền sở hữu ví
                    if phieu.get("vi", "").lower() != user_wallet:
                        raise HTTPException(status_code=403, detail="Bằng chứng ván chơi này thuộc về địa chỉ ví khác.")
                    if int(phieu.get("man", 1)) != yc.stage_id:
                        raise HTTPException(status_code=400, detail=f"Màn trong bằng chứng ({phieu.get('man')}) không khớp màn yêu cầu ({yc.stage_id}).")
                    da_xac_minh = True

        # 4. Thẩm định qua bảng kết quả trận đấu đã được kiểm định (match_results với is_verified = 1)
        if not da_xac_minh:
            cur.execute("SELECT * FROM match_results WHERE ma_van = ?", (yc.evidence_id,))
            tran = cur.fetchone()
            if tran is None:
                # Fail-closed: Không tìm thấy bằng chứng trong CSDL
                raise HTTPException(status_code=404, detail="Không tìm thấy bằng chứng hợp lệ cho ván chơi này.")

            # Telemetry thô chưa qua trọng tài thẩm định (is_verified != 1) -> TỪ CHỐI
            if tran["is_verified"] != 1:
                raise HTTPException(status_code=422, detail="Bằng chứng chưa được thẩm định có thẩm quyền cho người chơi này.")

            # BẢO MẬT P0: Tuyệt đối KHÔNG tin cậy player_id tự khai từ telemetry.
            # CHỈ tin verified_wallet nếu được ghi bởi luồng xác minh đáng tin cậy.
            verified_wallet = (tran["verified_wallet"] or "").strip().lower()
            if not verified_wallet:
                raise HTTPException(status_code=422, detail="Bằng chứng thiếu thông tin ví đã xác minh từ trọng tài.")

            # Quyền sở hữu bắt buộc phải khớp với địa chỉ ví SIWE của người chơi
            if verified_wallet != user_wallet:
                raise HTTPException(status_code=403, detail="Bằng chứng thuộc về địa chỉ ví khác.")

            if tran["ket_qua"] != "thang":
                raise HTTPException(status_code=400, detail="Bằng chứng ván chơi không phải là một chiến thắng.")
            if tran["hop_le"] != 1:
                raise HTTPException(status_code=422, detail=f"Bằng chứng ván chơi không hợp lệ: {tran['ly_do_tu_choi']}.")
            if tran["man"] != yc.stage_id:
                raise HTTPException(status_code=400, detail=f"Màn trong bằng chứng ({tran['man']}) không khớp màn yêu cầu ({yc.stage_id}).")

            da_xac_minh = True

        if not da_xac_minh:
            raise HTTPException(status_code=422, detail="Không thể xác minh bằng chứng ván chơi. Tiến trình bị khóa.")

        # 5. Cập nhật tiến trình atomic trong CSDL
        try:
            tt_moi = hoan_thanh_man(
                conn,
                player_id=player.user_id,
                stage_id=yc.stage_id,
                evidence_id=yc.evidence_id,
            )
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))

    return {
        "thanh_cong": True,
        "thong_bao": f"Đã ghi nhận hoàn thành màn {yc.stage_id}",
        "tien_trinh": tt_moi,
    }
