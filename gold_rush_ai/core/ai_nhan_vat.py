from __future__ import annotations

from dataclasses import dataclass
import json
import logging
from typing import Literal

from .nhan_vat_ai import YeuCauTaoNhanVat
from .providers.anh import LoiProviderAnh, NhaCungCapAnh
from .xu_ly_anh import LoiAnhKhongHopLe, chuan_hoa_anh

log = logging.getLogger(__name__)

SYSTEM_PROMPT = (
    "Create a 64x64 pixel-art game character sprite sheet matching the imported "
    "george_hiep_si.png layout: a transparent 4x4 grid of sixteen 16x16 frames. "
    "Use four rows for down, left, right, and up directions, in that order; "
    "each row contains four walking frames of the same full-body character. "
    "Keep the character centered inside every cell, with consistent scale, "
    "Return one static PNG sheet with crisp square pixels, a limited color palette, "
    "and transparent background. "
    "Do not create a poster, collage, text, border, or single large portrait. "
    "The user JSON contains the character description."
)


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
    if provider is not None:
        try:
            nguon = getattr(provider, "generation_source", None)
            if nguon not in ("demo", "image_model"):
                raise LoiProviderAnh("Nguồn provider ảnh không hợp lệ")
            raw = provider.sinh(system_prompt=SYSTEM_PROMPT, user_prompt=user_prompt)
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
    raw = demo_provider.sinh(system_prompt=SYSTEM_PROMPT, user_prompt=user_prompt)
    return KetQuaTaoAnh(png=chuan_hoa_anh(raw), generation_source="demo")
