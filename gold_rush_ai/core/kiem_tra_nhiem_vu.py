from __future__ import annotations

import math

from .luoi import KICH_THUOC_O, BanDo, kiem_tra_choi_duoc, tim_duong
from .man_choi import TOC_DO_GEORGE, ManChoi
from .nhiem_vu import DeXuatNhiemVu


def _giay_thu_thap(ban_do: BanDo, so_xu: int) -> int:
    o = ban_do.cac_diem("george")[0]
    con = set(ban_do.cac_diem("coin"))
    so_buoc = 0
    for _ in range(so_xu):
        cac_duong = [(tim_duong(ban_do, o, xu), xu) for xu in sorted(con)]
        toi_duoc = [(len(duong), xu) for duong, xu in cac_duong if duong is not None]
        if not toi_duoc:
            raise ValueError("Không tìm được đường đi trên bản đồ để nhặt đủ xu")
        buoc, o = min(toi_duoc)
        so_buoc += buoc
        con.remove(o)
    return math.ceil(so_buoc * KICH_THUOC_O / TOC_DO_GEORGE * 1.5 + 5)


def kiem_tra_nhiem_vu(de_xuat: DeXuatNhiemVu, man: ManChoi, ban_do: BanDo) -> DeXuatNhiemVu:
    loi_ban_do = kiem_tra_choi_duoc(ban_do)
    if loi_ban_do:
        raise ValueError("Dữ liệu bản đồ không hợp lệ: " + "; ".join(loi_ban_do))
    cac_xu = ban_do.cac_diem("coin")
    if len(cac_xu) != man.so_xu or len(set(cac_xu)) != len(cac_xu):
        raise ValueError("Số xu trong manifest không khớp các vị trí xu riêng biệt trên bản đồ")

    if de_xuat.objective == "collect_coins":
        if de_xuat.target > man.so_xu:
            raise ValueError("Mục tiêu xu vượt số xu có trên bản đồ")
        so_xu_can_nhat = de_xuat.target
    else:
        so_xu_can_nhat = man.so_xu

    han = de_xuat.time_limit_seconds
    if man.gioi_han_giay > 0:
        if han is not None and han > man.gioi_han_giay:
            raise ValueError("Thời hạn nhiệm vụ vượt thời gian của màn")
        han = man.gioi_han_giay if han is None else han
    if han is not None and han < _giay_thu_thap(ban_do, so_xu_can_nhat):
        raise ValueError("Thời hạn quá ngắn so với lộ trình thu thập xu và biên an toàn demo")
    return de_xuat
