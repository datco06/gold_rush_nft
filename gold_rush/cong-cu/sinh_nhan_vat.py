"""Sinh sprite sheet cho 3 nhân vật bán trong cửa hàng bằng cách ĐỔI MÀU george.png.

    python3 cong-cu/sinh_nhan_vat.py     # cần Pillow; chạy sau sinh_tai_nguyen.py

Đổi đúng bảng màu P của sinh_tai_nguyen.py: tóc (thành mũ), áo, quần, giày. Bố cục 4 hướng
× 4 khung giữ nguyên nên `TaiNguyen._bonHuong` cắt được y như George.
"""
import os

from PIL import Image

GOC = os.path.join(os.path.dirname(__file__), "..", "assets", "images")
TOC, AO, QUAN, GIAY = (92, 62, 40), (196, 72, 48), (58, 78, 132), (72, 54, 40)

NHAN_VAT = {
    "george_tho_mo.png": {TOC: (240, 196, 40), AO: (40, 110, 170), QUAN: (70, 70, 80)},
    "george_cao_boi.png": {TOC: (128, 84, 40), AO: (150, 95, 50), QUAN: (60, 60, 110), GIAY: (40, 30, 20)},
    "george_hiep_si.png": {TOC: (205, 205, 215), AO: (228, 182, 40), QUAN: (176, 144, 44), GIAY: (120, 120, 130)},
}

goc = Image.open(os.path.join(GOC, "george.png")).convert("RGBA")
for ten, doi in NHAN_VAT.items():
    moi = goc.copy()
    px = moi.load()
    for y in range(moi.height):
        for x in range(moi.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in doi:
                px[x, y] = (*doi[(r, g, b)], a)
    moi.save(os.path.join(GOC, ten))
    print("Đã ghi", ten)
