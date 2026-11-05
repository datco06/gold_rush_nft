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
    "Create one full-body pixel-art game character, front view, centered and fully visible. "
    "Use a square composition, a single static image with transparent background, "
    "crisp square pixels and a limited color palette. "
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
            log.warning("Provider ảnh không khả dụng (%s); dùng mẫu demo", type(e).__name__)
        else:
            return KetQuaTaoAnh(png=png, generation_source=nguon)
    if getattr(demo_provider, "generation_source", None) != "demo":
        raise LoiProviderAnh("Provider dự phòng cần khai báo nguồn demo")
    raw = demo_provider.sinh(system_prompt=SYSTEM_PROMPT, user_prompt=user_prompt)
    return KetQuaTaoAnh(png=chuan_hoa_anh(raw), generation_source="demo")
