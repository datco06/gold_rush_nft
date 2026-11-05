from io import BytesIO
from pathlib import Path

from PIL import Image, ImageFile, PngImagePlugin
import pytest


def anh_mau(size=(16, 32), *, format="PNG", mode="RGBA", color=(200, 20, 30, 128), **kw):
    with Image.new(mode, size, color) as anh:
        buf = BytesIO()
        anh.save(buf, format=format, **kw)
        return buf.getvalue()


def chuan_hoa(data, **kw):
    from core.xu_ly_anh import chuan_hoa_anh
    return chuan_hoa_anh(data, **kw)


def test_png_rgba_can_giua_giu_ti_le_va_alpha():
    data = chuan_hoa(anh_mau())
    with Image.open(BytesIO(data)) as anh:
        assert anh.format == "PNG"
        assert anh.mode == "RGBA"
        assert anh.size == (128, 128)
        assert getattr(anh, "n_frames", 1) == 1
        assert anh.getpixel((64, 64)) == (200, 20, 30, 128)
        assert anh.getpixel((0, 0)) == (0, 0, 0, 0)
        assert anh.getpixel((31, 64)) == (0, 0, 0, 0)
        assert anh.getpixel((32, 64)) == (200, 20, 30, 128)


def test_phong_nearest_giu_canh_pixel_khong_tao_mau_trung_gian():
    with Image.new("RGB", (2, 1)) as goc:
        goc.putdata([(255, 0, 0), (0, 0, 255)])
        buf = BytesIO()
        goc.save(buf, format="PNG")
    with Image.open(BytesIO(chuan_hoa(buf.getvalue()))) as anh:
        assert anh.getpixel((63, 64)) == (255, 0, 0, 255)
        assert anh.getpixel((64, 64)) == (0, 0, 255, 255)
        assert {mau for _, mau in anh.getcolors()} == {
            (255, 0, 0, 255), (0, 0, 255, 255), (0, 0, 0, 0)}


@pytest.mark.parametrize("format", ["JPEG", "WEBP"])
def test_anh_rgb_cac_dinh_dang_ho_tro_thanh_png(format):
    kw = {"lossless": True} if format == "WEBP" else {}
    data = anh_mau((32, 32), format=format, mode="RGB", color=(20, 30, 40), **kw)
    with Image.open(BytesIO(chuan_hoa(data))) as anh:
        assert anh.format == "PNG"
        assert anh.mode == "RGBA"
        assert all(abs(thuc - mong) <= 3 for thuc, mong in zip(anh.getpixel((64, 64)), (20, 30, 40, 255)))


def test_palette_png_trong_suot_duoc_chuyen_dung():
    with Image.new("P", (2, 1)) as goc:
        goc.putpalette([255, 0, 0, 0, 0, 255] + [0] * 762)
        goc.putdata([0, 1])
        buf = BytesIO()
        goc.save(buf, format="PNG", transparency=0)
    with Image.open(BytesIO(chuan_hoa(buf.getvalue()))) as anh:
        assert anh.getpixel((32, 64))[3] == 0
        assert anh.getpixel((96, 64)) == (0, 0, 255, 255)


def test_loai_metadata_khoi_anh_xem_truoc():
    info = PngImagePlugin.PngInfo()
    info.add_text("Description", "private prompt")
    data = anh_mau(pnginfo=info)
    with Image.open(BytesIO(chuan_hoa(data))) as anh:
        assert anh.info == {}


def test_ton_trong_huong_exif_truoc_khi_can_anh():
    exif = Image.Exif()
    exif[274] = 6
    data = anh_mau((20, 40), format="JPEG", mode="RGB", color=(200, 0, 0), exif=exif)
    with Image.open(BytesIO(chuan_hoa(data))) as anh:
        assert anh.getpixel((0, 64))[3] == 255
        assert anh.getpixel((64, 0))[3] == 0
        assert not anh.getexif()


@pytest.mark.parametrize("size", [(1, 2048), (2048, 1), (1, 1), (2048, 2048)])
def test_anh_hop_le_o_cac_bien_kich_thuoc(size):
    with Image.open(BytesIO(chuan_hoa(anh_mau(size)))) as anh:
        assert anh.size == (128, 128)
        alpha = anh.getchannel('A')
        assert alpha.getextrema()[1] == 128
        trai, tren, phai, duoi = alpha.getbbox()
        assert trai + phai in (127, 128)
        assert tren + duoi in (127, 128)


@pytest.mark.parametrize("data", [b"", b"not an image", b"<svg></svg>", None, "image", bytearray(b"png")],
                         ids=["empty", "junk", "svg", "none", "string", "bytearray"])
def test_tu_choi_du_lieu_khong_phai_anh(data):
    from core.xu_ly_anh import LoiAnhKhongHopLe
    with pytest.raises(LoiAnhKhongHopLe):
        chuan_hoa(data)


@pytest.mark.parametrize("format", ["BMP", "TIFF", "GIF"])
def test_tu_choi_dinh_dang_chua_ho_tro(format):
    from core.xu_ly_anh import LoiAnhKhongHopLe
    with pytest.raises(LoiAnhKhongHopLe):
        chuan_hoa(anh_mau(format=format, mode="RGB", color=(0, 0, 0)))


def test_tu_choi_png_nhieu_frame():
    from core.xu_ly_anh import LoiAnhKhongHopLe
    with Image.new("RGBA", (8, 8), "red") as mot, Image.new("RGBA", (8, 8), "blue") as hai:
        buf = BytesIO()
        mot.save(buf, format="PNG", save_all=True, append_images=[hai], duration=100, loop=0)
    with pytest.raises(LoiAnhKhongHopLe):
        chuan_hoa(buf.getvalue())


def test_tu_choi_png_bi_cat_cuoi_hoac_sai_crc():
    from core.xu_ly_anh import LoiAnhKhongHopLe
    data = anh_mau()
    hong = bytearray(data)
    hong[29] ^= 1
    for loi in (data[:-12], bytes(hong)):
        with pytest.raises(LoiAnhKhongHopLe):
            chuan_hoa(loi)


def test_gioi_han_byte_duoc_kiem_tra_truoc_khi_doc_anh(monkeypatch):
    from core.xu_ly_anh import LoiAnhKhongHopLe
    data = anh_mau()
    def khong_duoc_mo(*args, **kw):
        raise AssertionError("Không được mở ảnh quá dung lượng")
    monkeypatch.setattr(Image, "open", khong_duoc_mo)
    with pytest.raises(LoiAnhKhongHopLe):
        chuan_hoa(data, gioi_han_byte=len(data) - 1)


@pytest.mark.parametrize("size,kw", [((2049, 1), {}), ((100, 100), {"gioi_han_pixel": 9999})])
def test_chan_anh_qua_lon_truoc_khi_giai_ma_pixel(monkeypatch, size, kw):
    from core.xu_ly_anh import LoiAnhKhongHopLe
    data = anh_mau(size)
    def khong_duoc_load(*args, **kw):
        raise AssertionError("Không được giải mã ảnh quá kích thước")
    monkeypatch.setattr(ImageFile.ImageFile, "load", khong_duoc_load)
    with pytest.raises(LoiAnhKhongHopLe):
        chuan_hoa(data, **kw)


@pytest.mark.parametrize("truong", ["gioi_han_byte", "gioi_han_canh", "gioi_han_pixel"])
@pytest.mark.parametrize("value", [0, -1, True, 1.5])
def test_tu_choi_cau_hinh_gioi_han_sai(truong, value):
    with pytest.raises(ValueError):
        chuan_hoa(anh_mau(), **{truong: value})


def test_doc_tai_nguyen_png_that_ma_khong_sua_file_goc():
    tep = Path(__file__).resolve().parents[2] / "gold_rush/assets/images/george.png"
    goc = tep.read_bytes()
    with Image.open(BytesIO(chuan_hoa(goc))) as anh:
        assert anh.format == "PNG"
        assert anh.size == (128, 128)
    assert tep.read_bytes() == goc
