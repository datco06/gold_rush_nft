from __future__ import annotations

from datetime import UTC, datetime
import re
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


def chuan_hoa_vi(v: str) -> str:
    if not isinstance(v, str) or not re.fullmatch(r"^0x[0-9a-fA-F]{40}$", v):
        raise ValueError("Địa chỉ ví Ethereum không hợp lệ (cần 0x kèm 40 ký tự hex)")
    return v.lower()


class _Schema(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True, frozen=True)


class NguoiChoiXacThuc(_Schema):
    """Thông tin định danh người chơi đã được xác thực từ phiên SIWE backend.

    Tuyệt đối không lấy từ body/query do client tự khai báo.
    """
    user_id: str = Field(min_length=1, max_length=64)
    wallet_address: str = Field(pattern=r"^0x[0-9a-fA-F]{40}$")
    username: str | None = Field(default=None, min_length=1, max_length=50)

    @field_validator("wallet_address")
    @classmethod
    def _lower_wallet(cls, v: str) -> str:
        return chuan_hoa_vi(v)


class YeuCauLuuNhanVat(_Schema):
    """Yêu cầu lưu nhân vật chính thức từ preview cache vào kho bền vững.

    Quy định: Client KHÔNG ĐƯỢC phép tự gửi owner_user_id hoặc wallet_address.
    Chủ sở hữu được gắn chặt từ phiên SIWE đã xác minh ở backend.
    """
    image_id: str = Field(min_length=36, max_length=36, pattern=r"^img_[0-9a-f]{32}$")
    name: str | None = Field(default=None, min_length=1, max_length=50)


class YeuCauXacNhanOnchain(_Schema):
    """Yêu cầu xác nhận giao dịch đăng ký on-chain đã gửi lên blockchain."""
    transaction_hash: str = Field(min_length=66, max_length=66, pattern=r"^0x[0-9a-fA-F]{64}$")


class ThongTinNhanVat(_Schema):
    """Metadata nhân vật chính thức được lưu bền vững."""
    character_id: str = Field(min_length=37, max_length=37, pattern=r"^char_[0-9a-f]{32}$")
    owner_user_id: str = Field(min_length=1, max_length=64)
    verified_wallet_address: str = Field(pattern=r"^0x[0-9a-f]{40}$")
    character_hash: str = Field(min_length=64, max_length=64, pattern=r"^[0-9a-f]{64}$")
    image_id: str = Field(min_length=36, max_length=36, pattern=r"^img_[0-9a-f]{32}$")
    image_url: str = Field(min_length=1, max_length=120)
    image_storage_ref: str = Field(min_length=1, max_length=120)
    generation_source: Literal["demo", "image_model"]
    created_at: str = Field(min_length=19, max_length=35)
    character_status: Literal["active", "archived"] = "active"
    onchain_status: Literal["not_registered", "pending", "registered", "failed"] = "not_registered"
    transaction_hash: str | None = Field(default=None, pattern=r"^0x[0-9a-fA-F]{64}$")
    name: str | None = Field(default=None, max_length=50)

    # Chuẩn bị cho gameplay (Section 8)
    preview_ready: bool = True
    playable_ready: bool = False
    sprite_format: Literal["static_png_128x128"] = "static_png_128x128"
    gameplay_notes: str = (
        "Ảnh preview 128x128 tĩnh. Cần bộ công cụ cắt/chuyển thành sprite sheet "
        "4 hướng x 4 frame để tích hợp vào Flame engine ở giai đoạn tiếp theo."
    )


class KetQuaKiemTraHash(_Schema):
    """Kết quả kiểm tra toàn vẹn SHA-256 của ảnh nhân vật."""
    character_id: str
    character_hash: str
    computed_hash: str
    is_valid: bool
    byte_count: int
    algorithm: Literal["SHA-256"] = "SHA-256"


class DuLieuChuanBiOnchain(_Schema):
    """Dữ liệu chuẩn bị cho smart contract CharacterRegistry.sol."""
    character_id: str
    owner_wallet: str
    character_hash_bytes32: str = Field(pattern=r"^0x[0-9a-f]{64}$")
    raw_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    onchain_status: Literal["not_registered", "pending", "registered", "failed"]
    chain_id: int
    registry_contract: str | None = None
