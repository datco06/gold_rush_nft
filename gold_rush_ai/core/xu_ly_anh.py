"""Kiểm tra byte ảnh và chuẩn hóa PNG tĩnh RGBA để xem trước.

PNG/JPEG/WebP được nhận theo định dạng giải mã thực. Giới hạn mặc định là
5 MiB dữ liệu, 2048 pixel/cạnh và 4 Mi pixel; caller có thể hạ giới hạn.
Ảnh được giữ tỷ lệ, phóng/thu nearest-neighbor và căn giữa trên nền trong suốt.
"""
from __future__ import annotations

from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from .nhan_vat_ai import KICH_THUOC_ANH_XEM_TRUOC


class LoiAnhKhongHopLe(ValueError):
    """Byte đầu vào không phải ảnh tĩnh hợp lệ trong giới hạn cho phép."""


def chuan_hoa_anh(
    data: bytes,
    *,
    gioi_han_byte: int = 5 * 1024 * 1024,
    gioi_han_canh: int = 2048,
    gioi_han_pixel: int = 4 * 1024 * 1024,
) -> bytes:
    """Trả PNG RGBA 128x128; kiểm tra kích thước trước khi giải mã pixel.

    Tầng tải ảnh cần áp dụng giới hạn byte trong lúc nhận dữ liệu mạng.
    Hàm này nhận byte hoàn chỉnh và xử lý ảnh trong bộ nhớ.
    """
    for value in (gioi_han_byte, gioi_han_canh, gioi_han_pixel):
        if type(value) is not int or value < 1:
            raise ValueError("Giới hạn ảnh phải là số nguyên dương")
    if not isinstance(data, bytes) or not data or len(data) > gioi_han_byte:
        raise LoiAnhKhongHopLe("Dữ liệu ảnh trống, sai kiểu hoặc quá dung lượng")
    try:
        with Image.open(BytesIO(data), formats=("PNG", "JPEG", "WEBP")) as goc:
            if goc.format not in ("PNG", "JPEG", "WEBP"):
                raise LoiAnhKhongHopLe("Định dạng ảnh chưa được hỗ trợ")
            rong, cao = goc.size
            if (not 1 <= rong <= gioi_han_canh or not 1 <= cao <= gioi_han_canh
                    or rong * cao > gioi_han_pixel):
                raise LoiAnhKhongHopLe("Ảnh vượt giới hạn kích thước")
            if getattr(goc, "is_animated", False) or getattr(goc, "n_frames", 1) != 1:
                raise LoiAnhKhongHopLe("Ảnh xem trước cần có đúng một frame")
            goc.verify()
        # verify kiểm tra cấu trúc/CRC; mở lại để giải mã đầy đủ dữ liệu ảnh.
        with Image.open(BytesIO(data), formats=("PNG", "JPEG", "WEBP")) as goc:
            goc.load()
            with (
                ImageOps.exif_transpose(goc) as dung_huong,
                dung_huong.convert("RGBA") as rgba,
            ):
                canh = KICH_THUOC_ANH_XEM_TRUOC
                ti_le = min(canh / rgba.width, canh / rgba.height)
                kich_thuoc = (
                    max(1, round(rgba.width * ti_le)),
                    max(1, round(rgba.height * ti_le)),
                )
                with (
                    rgba.resize(kich_thuoc, Image.Resampling.NEAREST) as thu_phong,
                    Image.new("RGBA", (canh, canh), (0, 0, 0, 0)) as ket_qua,
                ):
                    vi_tri = ((canh - thu_phong.width) // 2, (canh - thu_phong.height) // 2)
                    ket_qua.paste(thu_phong, vi_tri)
                    with BytesIO() as output:
                        ket_qua.save(output, format="PNG")
                        return output.getvalue()
    except LoiAnhKhongHopLe:
        raise
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError):
        raise LoiAnhKhongHopLe("Không đọc được dữ liệu ảnh hợp lệ") from None