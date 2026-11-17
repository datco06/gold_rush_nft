from __future__ import annotations

import json

from .ai_nhan_vat import KetQuaTaoAnh
from .kho_anh import KhoAnh
from .nhan_vat_ai import AnhNhanVat, YeuCauTaoNhanVat
from .providers.anh import NhaCungCapAnh


_SYSTEM_PROMPT = """
Create a game-ready pixel-art RPG character using the PixelLab web-test flow.
The provider must return a real 4x4 walking sprite sheet: four directions and
four walking frames per direction, with the same character in every frame.
Keep the background transparent, pixels crisp, and the character centered.
""".strip()


class DichVuPixelLabNhanVat:
    """Luồng PixelLab độc lập cho Xưởng AI.

    Service này không đi qua pipeline AI cũ (quota, fallback, prompt ảnh chung).
    Nó chỉ giữ idempotency/cache preview trong KhoAnh để endpoint lưu nhân vật
    hiện tại có thể tiếp tục chuyển preview vào kho ví mà không đổi hợp đồng.
    """

    def __init__(self, kho: KhoAnh, provider: NhaCungCapAnh):
        if not isinstance(kho, KhoAnh):
            raise ValueError("Cần kho ảnh hợp lệ")
        if getattr(provider, "generation_source", None) != "image_model":
            raise ValueError("PixelLab cần provider ảnh model")
        if not getattr(provider, "supports_sprite_sheet", False):
            raise ValueError("PixelLab cần provider sprite sheet")
        self.kho = kho
        self.provider = provider

    def tao(self, *, player_id: str, request_id: str, yeu_cau: YeuCauTaoNhanVat) -> AnhNhanVat:
        def sinh() -> KetQuaTaoAnh:
            # Giữ payload đơn giản như web test; adapter PixelLab tự thực hiện
            # create-character -> animate-character -> ghép 16 frame.
            user_prompt = json.dumps(
                yeu_cau.model_dump(warnings=False), ensure_ascii=False, separators=(",", ":")
            )
            return KetQuaTaoAnh(
                png=self.provider.sinh(system_prompt=_SYSTEM_PROMPT, user_prompt=user_prompt),
                generation_source="image_model",
            )

        return self.kho.tao_theo_yeu_cau(player_id, request_id, yeu_cau, sinh)
