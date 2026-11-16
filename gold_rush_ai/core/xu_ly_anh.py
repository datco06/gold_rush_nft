from __future__ import annotations

from io import BytesIO
from collections import deque

from PIL import Image, ImageOps, UnidentifiedImageError

from .nhan_vat_ai import KICH_THUOC_ANH_XEM_TRUOC

KICH_THUOC_O_SPRITE = 64
KICH_THUOC_SHEET_SPRITE = KICH_THUOC_O_SPRITE * 4


class LoiAnhKhongHopLe(ValueError):
    pass


def _chuan_khung_nhan_vat(anh: Image.Image, kich_thuoc: int) -> Image.Image:
    """Đưa nhân vật về cùng khung, đáy chạm đáy ô như sprite George."""
    rgba = anh.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox()
    khung = Image.new("RGBA", (kich_thuoc, kich_thuoc), (0, 0, 0, 0))
    if bbox is None:
        rgba.close()
        return khung
    crop = rgba.crop(bbox)
    rgba.close()
    gioi_han = max(1, kich_thuoc - 2)
    ti_le = min(gioi_han / crop.width, gioi_han / crop.height)
    kich_thuoc_moi = (
        max(1, round(crop.width * ti_le)),
        max(1, round(crop.height * ti_le)),
    )
    fitted = crop.resize(kich_thuoc_moi, Image.Resampling.NEAREST)
    crop.close()
    khung.paste(
        fitted,
        ((kich_thuoc - fitted.width) // 2, kich_thuoc - fitted.height),
        fitted,
    )
    fitted.close()
    return khung


def _kiem_tra_luoi_nguon(data: bytes) -> None:
    """Chặn ảnh không vuông trước khi tách cell, không tự cắt theo lưới giả."""
    if not isinstance(data, bytes):
        raise LoiAnhKhongHopLe("Sprite sheet AI cần dữ liệu PNG hợp lệ")
    try:
        with Image.open(BytesIO(data), formats=("PNG", "JPEG", "WEBP")) as source:
            rong, cao = source.size
            if rong != cao or rong < 4 or rong % 4 != 0:
                raise LoiAnhKhongHopLe(
                    "Sprite sheet AI phải là ảnh vuông có kích thước chia hết cho 4"
                )
    except LoiAnhKhongHopLe:
        raise
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError):
        raise LoiAnhKhongHopLe("Không đọc được sprite sheet AI") from None


def _kiem_tra_cac_frame(frames: list[Image.Image]) -> None:
    """Kiểm tra đủ 16 frame và loại ảnh rỗng/không đồng nhất nghiêm trọng."""
    if len(frames) != 16:
        raise LoiAnhKhongHopLe("Sprite sheet AI phải có đúng 16 frame")
    hop_le: list[tuple[int, int]] = []
    for frame in frames:
        bbox = frame.getchannel("A").getbbox()
        if bbox is None:
            raise LoiAnhKhongHopLe("Sprite sheet AI có frame rỗng")
        rong = bbox[2] - bbox[0]
        cao = bbox[3] - bbox[1]
        if rong < 2 or cao < 2:
            raise LoiAnhKhongHopLe("Sprite sheet AI có frame không hợp lệ")
        hop_le.append((rong, cao))
    chieu_cao = [cao for _, cao in hop_le]
    if min(chieu_cao) / max(chieu_cao) < 0.25:
        raise LoiAnhKhongHopLe("Tỉ lệ nhân vật giữa các frame không đồng nhất")


def tao_sprite_sheet_4x4(
    data: bytes, *, kich_thuoc_o: int = 16, la_sprite_sheet: bool = False
) -> bytes:
    """Tạo PNG sprite sheet 4x4 từ ảnh đơn hoặc sheet AI.

    Ảnh demo/ảnh cũ được lặp một khung hình. Ảnh model mới được prompt theo
    layout george_hiep_si.png nên giữ nguyên 4 hàng × 4 frame.
    """
    if type(kich_thuoc_o) is not int or not 4 <= kich_thuoc_o <= 64:
        raise ValueError("Kích thước ô sprite không hợp lệ")
    if type(la_sprite_sheet) is not bool:
        raise ValueError("Cờ sprite sheet không hợp lệ")
    if la_sprite_sheet:
        _kiem_tra_luoi_nguon(data)
    png = chuan_hoa_anh(data, kich_thuoc=kich_thuoc_o * 4)
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
        canvas = Image.new("RGBA", (kich_thuoc_o * 4, kich_thuoc_o * 4), (0, 0, 0, 0))
        if la_sprite_sheet:
            cell_width = quantized.width // 4
            cell_height = quantized.height // 4
            if cell_width < 1 or cell_height < 1 or cell_width != cell_height:
                raise LoiAnhKhongHopLe("Sprite sheet AI phải là lưới vuông 4x4")
            raw_frames: list[Image.Image] = []
            for row in range(4):
                for col in range(4):
                    raw_frames.append(quantized.crop((
                        col * cell_width,
                        row * cell_height,
                        (col + 1) * cell_width,
                        (row + 1) * cell_height,
                    )))
            try:
                _kiem_tra_cac_frame(raw_frames)
                for index, cell in enumerate(raw_frames):
                    frame = _chuan_khung_nhan_vat(cell, kich_thuoc_o)
                    canvas.paste(
                        frame,
                        ((index % 4) * kich_thuoc_o, (index // 4) * kich_thuoc_o),
                    )
                    frame.close()
            finally:
                for cell in raw_frames:
                    cell.close()
        else:
            frame = _chuan_khung_nhan_vat(quantized, kich_thuoc_o)
            for row in range(4):
                for col in range(4):
                    canvas.paste(frame, (col * kich_thuoc_o, row * kich_thuoc_o))
            frame.close()
        with BytesIO() as output:
            canvas.save(output, format="PNG", optimize=True)
            return output.getvalue()


def tao_debug_sprite_sheet_4x4(
    data: bytes, *, la_sprite_sheet: bool = True
) -> bytes:
    """Tạo bản PNG kiểm tra 256x256 có lưới đỏ 4x4, không dùng trong gameplay."""
    from PIL import ImageDraw

    normalized = tao_sprite_sheet_4x4(
        data, kich_thuoc_o=KICH_THUOC_O_SPRITE, la_sprite_sheet=la_sprite_sheet
    )
    with Image.open(BytesIO(normalized)) as sheet:
        debug = sheet.convert("RGBA")
        draw = ImageDraw.Draw(debug)
        mau = (255, 64, 64, 220)
        for index in range(5):
            point = index * KICH_THUOC_O_SPRITE
            draw.line((point, 0, point, KICH_THUOC_SHEET_SPRITE - 1), fill=mau, width=1)
            draw.line((0, point, KICH_THUOC_SHEET_SPRITE - 1, point), fill=mau, width=1)
        with BytesIO() as output:
            debug.save(output, format="PNG", optimize=True)
            debug.close()
            return output.getvalue()


def chuan_hoa_anh(
    data: bytes,
    *,
    kich_thuoc: int = KICH_THUOC_ANH_XEM_TRUOC,
    gioi_han_byte: int = 5 * 1024 * 1024,
    gioi_han_canh: int = 2048,
    gioi_han_pixel: int = 4 * 1024 * 1024,
) -> bytes:
    if type(kich_thuoc) is not int or not 1 <= kich_thuoc <= gioi_han_canh:
        raise ValueError("Kích thước ảnh chuẩn hóa không hợp lệ")
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
                canh = kich_thuoc
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
