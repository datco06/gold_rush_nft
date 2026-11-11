"""Adapter kết nối kho lưu trữ tiến trình SIWE với nguồn dữ liệu AI (ai_player_source).

Nhiệm vụ:
- Cung cấp hàm async adapter tuân thủ đúng signature `NguonDuLieuAI` của `gan_nguon_du_lieu_ai(app, adapter)`.
- Xác thực danh tính người chơi qua `ai_auth_source` (cookie HttpOnly `gr_session` và SIWE AuthService).
- Truy vấn tiến trình màn chơi (1–6) có bằng chứng hợp lệ từ `KhoTienTrinh`.
- Sinh `BanChupNguoiChoiAI` chính thức, bảo đảm `completed_stage_ids` phản ánh đúng thực tế chơi.
- Tuân thủ nguyên tắc Fail-Closed: khi session không hợp lệ, trả về `None`; khi DB lỗi, trả về HTTP 503.
"""
from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
import logging

from fastapi import HTTPException, Request

from core.ngu_canh_ai import BanChupNguoiChoiAI
from core.schemas_nhan_vat import NguoiChoiXacThuc
from core.tien_trinh_storage import KhoTienTrinh

log = logging.getLogger(__name__)


def tao_tien_trinh_adapter(
    kho: KhoTienTrinh,
) -> Callable[[Request], Awaitable[BanChupNguoiChoiAI | None]]:
    """Tạo hàm async adapter cung cấp snapshot tiến trình người chơi từ KhoTienTrinh."""

    async def adapter(request: Request) -> BanChupNguoiChoiAI | None:
        # 1. Xác thực danh tính người chơi từ phiên SIWE
        # Không tin cậy bất kỳ header hoặc body client tự khai báo
        auth_source = getattr(request.app.state, "ai_auth_source", None)
        player: NguoiChoiXacThuc | None = None

        if auth_source is not None:
            try:
                timeout = getattr(request.app.state, "ai_auth_source_timeout", 5)
                player = await asyncio.wait_for(auth_source(request), timeout=timeout)
            except HTTPException:
                raise
            except Exception as e:
                log.warning("Lỗi truy vấn nguồn xác thực trong tien_trinh_adapter: %s", type(e).__name__)
                raise HTTPException(503, "Hệ thống xác thực tạm thời không sẵn sàng") from None

        if player is None:
            # Fallback sang request.state.ai_auth_user (dành riêng cho test fixture nội bộ)
            ctx = getattr(request.state, "ai_auth_user", None)
            if isinstance(ctx, NguoiChoiXacThuc):
                player = ctx

        if player is None:
            # Không có phiên đăng nhập SIWE hợp lệ -> trả None để lay_ban_chup_ai trả 401
            return None

        # 2. Truy xuất các màn đã hoàn thành hợp lệ có bằng chứng của chính user này
        try:
            completed = kho.lay_cac_man_hoan_thanh(player.user_id)
        except Exception as e:
            log.warning("Không đọc được tiến trình từ KhoTienTrinh (%s)", type(e).__name__)
            raise HTTPException(503, "Dịch vụ tiến trình chưa sẵn sàng") from None

        # 3. Tập các màn được phép (trong Gold Rush, cả 6 màn đều thuộc man_choi.json)
        allowed = frozenset(range(1, 7))

        # 4. Trả về BanChupNguoiChoiAI
        return BanChupNguoiChoiAI(
            player_id=player.user_id,
            user_id=player.user_id,
            wallet_address=player.wallet_address,
            level=max(len(completed), 1),
            allowed_stage_ids=allowed,
            completed_stage_ids=completed,
        )

    return adapter

