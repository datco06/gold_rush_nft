from __future__ import annotations

from io import BytesIO
from collections import deque

from PIL import Image, ImageOps, UnidentifiedImageError

from .nhan_vat_ai import KICH_THUOC_ANH_XEM_TRUOC


class LoiAnhKhongHopLe(ValueError):
    pass


def tao_sprite_sheet_4x4(data: bytes, *, kich_thuoc_o: int = 16) -> bytes:
    """Tạo PNG sprite sheet 4x4 ổn định từ ảnh AI một khung hình.

    Provider hiện trả ảnh toàn thân tĩnh, vì vậy MVP lặp khung hình đã pixel
    hóa vào 16 ô. API giữ nguyên để có thể thay bằng bộ sinh animation sau.
    """
    if type(kich_thuoc_o) is not int or not 4 <= kich_thuoc_o <= 64:
        raise ValueError("Kích thước ô sprite không hợp lệ")
    png = chuan_hoa_anh(data)
    with Image.open(BytesIO(png)) as source:
        rgba = source.convert("RGBA")
        # Tách nền heuristic từ bốn góc (chỉ xóa vùng liên thông gần màu góc,
        # không ảnh hưởng vùng nhân vật có màu khác biệt rõ).
        px = rgba.load()
        seen: set[tuple[int, int]] = set()
        queue: deque[tuple[int, int]] = deque()
        for point in ((0, 0), (rgba.width - 1, 0), (0, rgba.height - 1), (rgba.width - 1, rgba.height - 1)):
            queue.append(point)
        while queue:
            x, y = queue.popleft()
            if (x, y) in seen:
                continue
            seen.add((x, y))
            base = px[x, y]
            if base[3] == 0:
                continue
            # Chỉ lấy vùng màu tương đối phẳng quanh điểm bắt đầu của từng góc.
            if max(base[:3]) - min(base[:3]) > 220:
                continue
            px[x, y] = (base[0], base[1], base[2], 0)
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < rgba.width and 0 <= ny < rgba.height and (nx, ny) not in seen:
                    candidate = px[nx, ny]
                    if max(abs(candidate[i] - base[i]) for i in range(3)) <= 24:
                        queue.append((nx, ny))
        quantized = rgba.quantize(colors=32, method=Image.Quantize.FASTOCTREE).convert("RGBA")
        frame = quantized.resize((kich_thuoc_o, kich_thuoc_o), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", (kich_thuoc_o * 4, kich_thuoc_o * 4), (0, 0, 0, 0))
        for row in range(4):
            for col in range(4):
                canvas.paste(frame, (col * kich_thuoc_o, row * kich_thuoc_o))
        with BytesIO() as output:
            canvas.save(output, format="PNG", optimize=True)
            return output.getvalue()


def chuan_hoa_anh(
    data: bytes,
    *,
    gioi_han_byte: int = 5 * 1024 * 1024,
    gioi_han_canh: int = 2048,
    gioi_han_pixel: int = 4 * 1024 * 1024,
) -> bytes:
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
