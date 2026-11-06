"""Quản lý và tích hợp Map Generator (Procedural Level Map Generator).

Đặc điểm:
  * Phân biệt rõ Level Map (từng màn 40x30 ô) và World Map (giao diện thế giới của Người 1).
  * Phiên bản thuật toán (Seed Versioning): cùng (seed, algorithm_version) luôn cho ra bản đồ giống nhau.
  * Tích hợp kiểm định đường đi BFS/A* trước khi xuất bản đồ.
  * Hỗ trợ tạo pool bản đồ đóng gói sẵn vào assets của Flutter.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .luoi import doc_tmx, kiem_tra_choi_duoc
from .sinh_ban_do import sinh, thanh_tmx

PHIEN_BAN_THUAT_TOAN = "v1.3"


def sinh_ban_do_hop_le(
    seed: int,
    mat_do: float = 0.36,
    so_cot: int = 40,
    so_hang: int = 30,
    so_xu: int = 24,
    so_zombie: int = 5,
    so_skeleton: int = 4,
    cach_george_toi_thieu: int = 12,
    phien_ban: str = PHIEN_BAN_THUAT_TOAN,
) -> dict[str, Any]:
    """Sinh bản đồ theo seed và kiểm tra tính hợp lệ trước khi bàn giao.

    Ném ValueError nếu bản đồ không chơi được hoặc không thể đặt đối tượng.
    """
    kq = sinh(
        seed=seed,
        so_cot=so_cot,
        so_hang=so_hang,
        mat_do=mat_do,
        so_xu=so_xu,
        so_zombie=so_zombie,
        so_skeleton=so_skeleton,
        cach_george_toi_thieu=cach_george_toi_thieu,
    )

    # Đảm bảo kiểm tra chơi được
    loi = kiem_tra_choi_duoc(kq["ban_do"])
    if loi:
        raise ValueError(f"Bản đồ sinh ra không chơi được (seed={seed}): {', '.join(loi)}")

    tmx_content = thanh_tmx(kq)
    return {
        "seed": seed,
        "phien_ban_thuat_toan": phien_ban,
        "chi_so": kq["chi_so"],
        "noi_dung_tmx": tmx_content,
        "so_xu": len(kq["ban_do"].cac_diem("coin")),
        "so_zombie": len(kq["ban_do"].cac_diem("zombie")),
        "so_skeleton": len(kq["ban_do"].cac_diem("skeleton")),
        "kich_thuoc": (so_cot, so_hang),
    }


def xuat_tep_tmx(
    seed: int,
    thu_muc_xuat: Path,
    ten_tep: str | None = None,
    **kwargs: Any,
) -> Path:
    """Sinh bản đồ và ghi ra tệp .tmx tại thư mục chỉ định."""
    kq = sinh_ban_do_hop_le(seed=seed, **kwargs)
    thu_muc_xuat.mkdir(parents=True, exist_ok=True)
    ten = ten_tep or f"gold_rush_seed_{seed}.tmx"
    duong_dan = thu_muc_xuat / ten
    duong_dan.write_text(kq["noi_dung_tmx"], encoding="utf-8")
    return duong_dan


def quet_pool_ban_do(thu_muc_tiles: Path) -> list[dict[str, Any]]:
    """Quét và kiểm định toàn bộ các bản đồ .tmx trong thư mục assets/tiles/."""
    ds = []
    if not thu_muc_tiles.exists():
        return ds

    for tep in sorted(thu_muc_tiles.glob("*.tmx")):
        try:
            bando = doc_tmx(tep)
            loi = kiem_tra_choi_duoc(bando)
            ds.append({
                "tep": tep.name,
                "hop_le": len(loi) == 0,
                "loi": loi,
                "so_cot": bando.so_cot,
                "so_hang": bando.so_hang,
                "so_xu": len(bando.cac_diem("coin")),
                "so_zombie": len(bando.cac_diem("zombie")),
                "so_skeleton": len(bando.cac_diem("skeleton")),
            })
        except Exception as e:
            ds.append({
                "tep": tep.name,
                "hop_le": False,
                "loi": [str(e)],
            })
    return ds

