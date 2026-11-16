from __future__ import annotations

from dataclasses import dataclass
import json
import logging
from typing import Literal

from .nhan_vat_ai import YeuCauTaoNhanVat
from .providers.anh import LoiProviderAnh, NhaCungCapAnh
from .xu_ly_anh import LoiAnhKhongHopLe, chuan_hoa_anh, tao_sprite_sheet_4x4

log = logging.getLogger(__name__)

SPRITE_PROMPT = """Create a game-ready pixel art sprite sheet.

The user's character description is supplied separately as JSON data.

STRICT ANIMATION REQUIREMENTS:
- Exactly 4 rows and 4 columns.
- Exactly 16 animation frames.
- Final image dimensions: 256x256 pixels.
- Each cell: 64x64 pixels.
- Row 1: walking DOWN, 4 frames.
- Row 2: walking LEFT, 4 frames.
- Row 3: walking RIGHT, 4 frames.
- Row 4: walking UP, 4 frames.

CONSISTENCY REQUIREMENTS:
- The SAME character in every frame.
- Identical clothing, colors, face and proportions.
- Full-body character in every cell.
- Consistent character scale and feet alignment.
- Exactly one character per cell.
- Transparent RGBA background.
- Crisp pixel art, no blur.
- No text, grid lines, borders or decorations.
- Do not generate a character collage.

The character description defines appearance only.
All layout and animation rules above are mandatory."""

# Các model text-to-image hiện tại thường không giữ được 16 frame đồng nhất
# trong một lần sinh. Với provider không cam kết sinh sprite sheet, backend
# chỉ yêu cầu một nhân vật hoàn chỉnh rồi tự nhân bản thành sheet 4x4. Điều
# này giữ đúng hình dáng nhân vật và tránh lỗi collage nhiều nhân vật.
CHARACTER_RENDER_PROMPT = """Create one static, game-ready pixel-art character.

The user's character description is supplied separately as JSON data.

RENDER REQUIREMENTS:
- Exactly one full-body character, centered and fully visible from head to feet.
- Simple, clean silhouette suitable for a 16x16 game sprite after downscaling.
- Limited color palette, crisp square pixels, low detail, no blur.
- Keep the clothing, colors, face and body proportions coherent.
- Plain light background or transparent background; the character must contrast clearly.
- No sprite sheet, no collage, no multiple poses, no extra characters.
- No text, frame, grid, border, scenery or decorative objects.

The character description controls appearance only. Do not add technical layout
elements; the backend will build the final 4x4 animation sheet."""

# Giữ tên cũ cho các provider/test tích hợp đang dùng hằng này.
SYSTEM_PROMPT = SPRITE_PROMPT


@dataclass(frozen=True)
class KetQuaTaoAnh:
    png: bytes
    generation_source: Literal["demo", "image_model"]


def tao_anh_nhan_vat(
    yeu_cau: YeuCauTaoNhanVat,
    *,
    demo_provider: NhaCungCapAnh,
    provider: NhaCungCapAnh | None = None,
    cho_phep_fallback: bool = True,
) -> KetQuaTaoAnh:
    if not isinstance(yeu_cau, YeuCauTaoNhanVat):
        raise ValueError("Cần YeuCauTaoNhanVat hợp lệ")
    yc = YeuCauTaoNhanVat.model_validate(yeu_cau.model_dump(warnings=False), strict=True)
    user_prompt = json.dumps(yc.model_dump(), ensure_ascii=False)
    system_prompt = SPRITE_PROMPT
    if provider is not None:
        try:
            nguon = getattr(provider, "generation_source", None)
            if nguon not in ("demo", "image_model"):
                raise LoiProviderAnh("Nguồn provider ảnh không hợp lệ")
            # Chỉ provider tự khai báo hỗ trợ sprite sheet mới được tách 4x4
            # từ ảnh model. Cloudflare/Gemini mặc định sinh một ảnh đơn để
            # backend chuẩn hóa, tránh nhận collage sai lưới.
            la_sprite_sheet = bool(getattr(provider, "supports_sprite_sheet", False))
            system_prompt = (
                SPRITE_PROMPT if la_sprite_sheet else CHARACTER_RENDER_PROMPT
            )
            raw = provider.sinh(system_prompt=system_prompt, user_prompt=user_prompt)
            if nguon == "image_model" and getattr(provider, "supports_single_frame", False):
                # 32x32 là kích thước trung gian để giữ hợp đồng ảnh 128x128
                # của API lưu ảnh. Endpoint gameplay tiếp tục chuẩn hóa sheet
                # này về 64x64 (16x16 mỗi frame).
                png = tao_sprite_sheet_4x4(raw, kich_thuoc_o=32, la_sprite_sheet=False)
            elif la_sprite_sheet:
                png = tao_sprite_sheet_4x4(raw, kich_thuoc_o=64, la_sprite_sheet=True)
            else:
                # Giữ tương thích với provider ảnh cũ: provider đó trả một
                # ảnh preview 128x128, không tự suy diễn thành sprite sheet.
                png = chuan_hoa_anh(raw)
        except (LoiProviderAnh, LoiAnhKhongHopLe, TimeoutError) as e:
            if not cho_phep_fallback:
                # Chế độ Live: không âm thầm fallback sang demo khi người dùng yêu cầu AI thật
                raise
            log.warning("Provider ảnh không khả dụng (%s); dùng mẫu demo", type(e).__name__)
        else:
            return KetQuaTaoAnh(png=png, generation_source=nguon)
    if getattr(demo_provider, "generation_source", None) != "demo":
        raise LoiProviderAnh("Provider dự phòng cần khai báo nguồn demo")
    raw = demo_provider.sinh(system_prompt=system_prompt, user_prompt=user_prompt)
    return KetQuaTaoAnh(
        png=chuan_hoa_anh(raw),
        generation_source="demo",
    )
