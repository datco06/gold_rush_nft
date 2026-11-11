"""Adapter kết nối hệ thống SIWE Auth với Backend AI (Giai đoạn 5).

Chức năng:
- Đọc và thẩm định cookie HttpOnly `gr_session` qua `AuthService` và SQLite database thật.
- Khai thác danh tính người chơi `user_id` và `wallet_address` đã xác thực bằng chữ ký EIP-4361.
- Bảo đảm nguyên tắc Fail-Closed: từ chối phiên demo, phiên hết hạn, phiên bị thu hồi hoặc lỗi database.
- Tích hợp với vòng đời ứng dụng thông qua `gan_nguon_xac_thuc_ai(app, adapter)`.
"""
from __future__ import annotations

import logging
import re
from typing import Awaitable, Callable

from fastapi import FastAPI, HTTPException, Request

from auth.config import AuthConfig
from auth.service import AuthService, AuthServiceError
from api.ngu_canh_ai import gan_nguon_xac_thuc_ai
from core.schemas_nhan_vat import NguoiChoiXacThuc

log = logging.getLogger(__name__)


def tao_auth_adapter(
    auth_service: AuthService,
    auth_config: AuthConfig | None = None,
) -> Callable[[Request], Awaitable[NguoiChoiXacThuc | None]]:
    """Tạo hàm async adapter xác thực người chơi từ cookie `gr_session` và AuthService."""

    async def adapter(request: Request) -> NguoiChoiXacThuc | None:
        # 1. Từ chối yêu cầu gắn header demo cho các API quản lý nhân vật chính thức
        if request.headers.get("X-Demo-Player"):
            raise HTTPException(
                status_code=401,
                detail="Tài khoản demo không có quyền quản lý nhân vật chính thức.",
            )

        # 2. Đọc cookie HttpOnly `gr_session`
        token = request.cookies.get("gr_session")
        if not token:
            return None

        # Kiểm tra định dạng token (64 hex characters)
        if not re.fullmatch(r"[0-9a-f]{64}", token):
            raise HTTPException(
                status_code=401,
                detail={"code": "SESSION_INVALID", "message": "Phiên đăng nhập không hợp lệ."},
            )

        # 3. Tra cứu session trong database qua AuthService
        try:
            me = auth_service.get_authenticated_session(token)
        except AuthServiceError as e:
            if e.code == "SESSION_REVOKED":
                raise HTTPException(
                    status_code=401,
                    detail={"code": "SESSION_REVOKED", "message": "Phiên đăng nhập đã bị thu hồi."},
                )
            elif e.code == "SESSION_EXPIRED":
                raise HTTPException(
                    status_code=401,
                    detail={"code": "SESSION_EXPIRED", "message": "Phiên đăng nhập đã hết hạn."},
                )
            elif e.code in ("GRANT_INVALID", "GRANT_EXPIRED"):
                raise HTTPException(
                    status_code=401,
                    detail={"code": "SESSION_INVALID", "message": "Quyền đăng ký không hợp lệ hoặc đã hết hạn."},
                )
            elif e.code == "CHAIN_NOT_ALLOWED":
                raise HTTPException(
                    status_code=403,
                    detail={"code": "CHAIN_NOT_ALLOWED", "message": "Mạng của phiên không còn được phép; hãy xác thực lại."},
                )
            elif e.code in ("DATABASE_BUSY", "DATABASE_ERROR"):
                raise HTTPException(
                    status_code=503,
                    detail={"code": "AUTH_UNAVAILABLE", "message": "Hệ thống xác thực tạm thời không sẵn sàng."},
                )
            else:
                raise HTTPException(
                    status_code=401,
                    detail={"code": "SESSION_INVALID", "message": "Phiên đăng nhập không hợp lệ."},
                )
        except Exception as e:
            log.error("Lỗi cơ sở dữ liệu khi kiểm tra phiên SIWE: %s", type(e).__name__)
            raise HTTPException(
                status_code=503,
                detail={"code": "AUTH_UNAVAILABLE", "message": "Hệ thống xác thực tạm thời không sẵn sàng."},
            )

        # 4. Kiểm tra tính hợp lệ của người dùng và địa chỉ ví
        if not me.user or not me.user.wallet_address:
            raise HTTPException(
                status_code=401,
                detail={"code": "SESSION_INVALID", "message": "Phiên đăng nhập không chứa thông tin ví hợp lệ."},
            )

        wallet = me.user.wallet_address
        if not re.fullmatch(r"^0x[0-9a-fA-F]{40}$", wallet):
            raise HTTPException(
                status_code=503,
                detail="Địa chỉ ví người chơi trong cơ sở dữ liệu không đúng chuẩn Ethereum.",
            )

        user_id = str(me.user.id)
        player = NguoiChoiXacThuc(user_id=user_id, wallet_address=wallet)

        # Lưu thông tin đã xác thực vào request.state để dùng trong request hiện tại
        request.state.ai_auth_user = player
        request.state.ai_session = me
        request.state.ai_session_token = token

        return player

    return adapter


def tich_hop_auth_vao_app(app: FastAPI, auth_service: AuthService, auth_config: AuthConfig) -> None:
    """Gắn AuthService và AuthConfig vào app.state và kích hoạt nguồn xác thực AI."""
    app.state.auth_service = auth_service
    app.state.auth_config = auth_config
    adapter = tao_auth_adapter(auth_service, auth_config)
    gan_nguon_xac_thuc_ai(app, adapter)

