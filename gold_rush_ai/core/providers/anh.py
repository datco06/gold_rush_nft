"""Giao diện provider ảnh và demo bằng frame từ tài nguyên game có sẵn.

Adapter dịch vụ thật cần giới hạn thời gian/dung lượng khi tải ảnh và chuyển
lỗi dịch vụ thành LoiProviderAnh. Khởi tạo provider không phát sinh yêu cầu mạng.
"""
from __future__ import annotations

from io import BytesIO
from pathlib import Path
import re
from typing import Literal, Protocol
import unicodedata

from PIL import Image, UnidentifiedImageError

from ..nhan_vat_ai import YeuCauTaoNhanVat


class LoiProviderAnh(RuntimeError):
    """Lỗi provider với thông báo đã lược bỏ key, URL và đường dẫn nội bộ."""


class NhaCungCapAnh(Protocol):
    generation_source: Literal["demo", "image_model"]

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        """Trả byte ảnh hoặc LoiProviderAnh; adapter sở hữu timeout và giới hạn tải."""
        ...


class AnhMauOffline:
    """Chọn mẫu theo từ khóa, lấy frame đầu 16x16 của sprite sheet 64x64.

    File được chọn từ danh sách cố định trong thư mục do server cung cấp.
    Khi có nhiều từ khóa, ưu tiên thợ mỏ, hiệp sĩ, rồi cao bồi.
    """

    generation_source: Literal["demo"] = "demo"

    def __init__(self, thu_muc_anh: str | Path):
        self.thu_muc_anh = Path(thu_muc_anh)

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        try:
            if not isinstance(user_prompt, str) or len(user_prompt.encode("utf-8")) > 4096:
                raise LoiProviderAnh("Mô tả demo không hợp lệ")
            yc = YeuCauTaoNhanVat.model_validate_json(user_prompt)
            mo_ta = unicodedata.normalize("NFC", yc.description).casefold()
            ten_tep = "george.png"
            for mau, tep in (
                (r"\b(?:thợ mỏ|tho mo|miner)\b", "george_tho_mo.png"),
                (r"\b(?:hiệp sĩ|hiep si|knight)\b", "george_hiep_si.png"),
                (r"\b(?:cao bồi|cao boi|cowboy)\b", "george_cao_boi.png"),
            ):
                if re.search(mau, mo_ta):
                    ten_tep = tep
                    break
            gioi_han = 5 * 1024 * 1024
            with (self.thu_muc_anh / ten_tep).open("rb") as tep:
                data = tep.read(gioi_han + 1)
            if len(data) > gioi_han:
                raise LoiProviderAnh("Tài nguyên demo vượt giới hạn dung lượng")
            with Image.open(BytesIO(data), formats=("PNG",)) as sheet:
                if sheet.size != (64, 64) or getattr(sheet, "is_animated", False):
                    raise LoiProviderAnh("Tài nguyên demo cần sprite PNG tĩnh 64x64")
                sheet.verify()
            with Image.open(BytesIO(data), formats=("PNG",)) as sheet:
                sheet.load()
                with (
                    sheet.crop((0, 0, 16, 16)) as frame,
                    frame.convert("RGBA") as rgba,
                    BytesIO() as output,
                ):
                    rgba.info.clear()
                    rgba.save(output, format="PNG")
                    return output.getvalue()
        except (OSError, ValueError, SyntaxError, UnidentifiedImageError, Image.DecompressionBombError):
            raise LoiProviderAnh("Không đọc được mô tả hoặc tài nguyên ảnh mẫu hợp lệ") from None