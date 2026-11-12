from __future__ import annotations

from collections.abc import Sequence
from random import Random
from typing import Literal
from uuid import uuid4

from .kiem_tra_nhiem_vu import kiem_tra_nhiem_vu
from .luoi import BanDo
from .man_choi import ManChoi, de_xuat_gioi_han, giay_vong_tham
from .nhiem_vu import DeXuatNhiemVu, NhiemVu


class KhongCoNhiemVuPhuHop(ValueError):
    pass


def _khoa(nv: DeXuatNhiemVu, stage_id: int) -> tuple[int, str, int, int | None]:
    return stage_id, nv.objective, nv.target, nv.time_limit_seconds


def tao_nhiem_vu_du_phong(
    man: ManChoi,
    ban_do: BanDo,
    *,
    lich_su: Sequence[NhiemVu] = (),
    do_kho: Literal["easy", "medium", "hard"] = "easy",
    rng: Random | None = None,
) -> NhiemVu:
    if do_kho not in ("easy", "medium", "hard"):
        raise ValueError("Độ khó phải là easy, medium hoặc hard")
    if man.gioi_han_giay < 0:
        raise KhongCoNhiemVuPhuHop("Thời gian của màn không được âm")

    probe = DeXuatNhiemVu(title="Kiểm tra màn", description="Thu thập một đồng xu.",
                         objective="collect_coins", target=1, difficulty="easy")
    try:
        kiem_tra_nhiem_vu(probe, man, ban_do)
    except ValueError as e:
        raise KhongCoNhiemVuPhuHop(str(e)) from e

    ti_le_xu, trung_toi_da, ti_le_gio = {
        "easy": (((1, 4), (1, 2)), 3, 10),
        "medium": (((1, 2), (3, 4)), 1, 9),
        "hard": (((3, 4), (1, 1)), 0, 8),
    }[do_kho]
    targets = sorted({max(1, (man.so_xu * tu + mau - 1) // mau) for tu, mau in ti_le_xu})
    han_goc = man.gioi_han_giay or de_xuat_gioi_han(giay_vong_tham(ban_do))
    han = max(1, min(3600, han_goc * ti_le_gio // 10))

    mau_nhiem_vu = [
        {"title": "Thợ mỏ chăm chỉ", "description": f"Thu thập {target} đồng xu trong màn {man.id}.",
         "objective": "collect_coins", "target": target}
        for target in targets
    ]
    mau_nhiem_vu += [
        {"title": "Cuộc đua tìm vàng",
         "description": f"Nhặt hết {man.so_xu} đồng xu và hoàn thành màn {man.id} trong {han} giây.",
         "objective": "finish_before_time", "target": 1, "time_limit_seconds": han},
        {"title": "Thợ mỏ thận trọng",
         "description": f"Hoàn thành màn {man.id} với không quá {trung_toi_da} lần trúng đòn.",
         "objective": "finish_with_max_hits", "target": trung_toi_da},
    ]
    hop_le = []
    for mau in mau_nhiem_vu:
        try:
            dx = DeXuatNhiemVu(**mau, difficulty=do_kho)
            hop_le.append(kiem_tra_nhiem_vu(dx, man, ban_do))
        except ValueError:
            continue

    gan_day = [nv for nv in lich_su if nv.stage_id == man.id][-5:]
    khoa_cuoi = _khoa(gan_day[-1], man.id) if gan_day else None
    lua_chon = [dx for dx in hop_le if _khoa(dx, man.id) != khoa_cuoi]
    if not lua_chon:
        raise KhongCoNhiemVuPhuHop("Không có nhiệm vụ mới hợp lệ khác mục tiêu vừa sử dụng")
    lan_dung = {_khoa(nv, man.id): i for i, nv in enumerate(gan_day)}
    lau_nhat = min(lan_dung.get(_khoa(dx, man.id), -1) for dx in lua_chon)
    lua_chon = [dx for dx in lua_chon if lan_dung.get(_khoa(dx, man.id), -1) == lau_nhat]
    dx = (rng if rng is not None else Random()).choice(lua_chon)
    return NhiemVu(**dx.model_dump(), id=f"quest_{uuid4().hex}", stage_id=man.id,
                   generation_source="rule_based")
