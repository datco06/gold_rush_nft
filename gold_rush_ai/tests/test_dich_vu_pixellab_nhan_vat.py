from io import BytesIO

from PIL import Image

from core.dich_vu_pixellab_nhan_vat import DichVuPixelLabNhanVat
from core.kho_anh import KhoAnh
from core.nhan_vat_ai import YeuCauTaoNhanVat


class FakePixelLab:
    generation_source = "image_model"
    supports_sprite_sheet = True

    def __init__(self):
        self.calls = 0

    def sinh(self, *, system_prompt: str, user_prompt: str) -> bytes:
        assert "PixelLab" in system_prompt
        assert "Thợ mỏ" in user_prompt
        self.calls += 1
        with Image.new("RGBA", (256, 256), (0, 0, 0, 0)) as image:
            image.putpixel((32, 32), (255, 200, 40, 255))
            output = BytesIO()
            image.save(output, format="PNG")
            return output.getvalue()


def test_luong_pixellab_rieng_luu_preview_va_idempotency(tmp_path):
    provider = FakePixelLab()
    service = DichVuPixelLabNhanVat(
        KhoAnh(tmp_path / "images.sqlite3"), provider
    )
    request = YeuCauTaoNhanVat(description="Thợ mỏ")

    first = service.tao(player_id="player_1", request_id="request_1", yeu_cau=request)
    second = service.tao(player_id="player_1", request_id="request_1", yeu_cau=request)

    assert first == second
    assert first.generation_source == "image_model"
    assert provider.calls == 1
