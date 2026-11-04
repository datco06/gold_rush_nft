"""Danh sách MÀN CHƠI — một tệp JSON dùng chung cho app, máy chủ và hợp đồng.

Tệp gốc: `gold_rush/assets/tiles/man_choi.json` (nằm cạnh các bản đồ .tmx).
  * App Flutter nạp nó bằng `rootBundle` để dựng màn hình chọn màn.
  * Máy chủ trọng tài đọc nó để biết màn nào có giới hạn thời gian, cọc bao nhiêu, thưởng bao nhiêu.
  * Ignition (gold_rush_chain) đọc nó để gọi `datMan(id, coc, thuongToiDa)` lúc triển khai.
Một nguồn sự thật → ba bên không bao giờ lệch nhau. Kiểm thử `tests/test_man_choi.py` canh điều đó.

Luật cọc (xem tài liệu, chương "Màn chơi và cọc vàng"):
  * coc = 0  → màn LUYỆN TẬP: không mất gì khi thua, nhận số xu nhặt được như bản 1.2.
  * coc > 0  → vào màn phải ĐẶT CỌC (hợp đồng đốt `coc` vàng ngay khi vào).
               Hoàn thành  → phiếu hoàn lại cọc + số xu + thưởng.
               Không hoàn thành (chết, hết giờ, bỏ ngang, tắt trình duyệt) → mất cọc, không cần làm gì thêm.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

from .luoi import KICH_THUOC_O, LANG_GIENG, BanDo, doc_tmx

TOC_DO_GEORGE = 74.0      # px/giây — CauHinh.tocDoGeorge bên app


@dataclass(frozen=True)
class ManChoi:
    id: int
    ten: str
    mo_ta: str
    tep: str                 # tên tệp .tmx trong assets/tiles/
    gioi_han_giay: int       # 0 = không giới hạn
    he_so_ke_dich: float     # nhân vào tốc độ zombie/skeleton
    coc: int                 # vàng đặt cọc khi vào màn (0 = luyện tập)
    thuong: int              # vàng thưởng thêm khi hoàn thành (ngoài số xu)
    so_xu: int               # số đồng xu trên bản đồ
    sao: int                 # độ khó hiển thị 1–5

    @property
    def mien_phi(self) -> bool:
        return self.coc == 0

    @property
    def thuong_toi_da(self) -> int:
        """Số vàng lớn nhất MỘT phiếu của màn này được ghi (chưa kể cọc hoàn lại) — `thuongToiDa` trên chuỗi."""
        return self.so_xu + self.thuong


def doc(tep: str | Path) -> dict[int, ManChoi]:
    du_lieu = json.loads(Path(tep).read_text(encoding="utf-8"))
    ds = {}
    for m in du_lieu["man"]:
        mc = ManChoi(**m)
        if mc.id in ds:
            raise ValueError(f"Trùng id màn {mc.id}")
        if mc.id <= 0 or mc.coc < 0 or mc.thuong < 0 or mc.so_xu <= 0:
            raise ValueError(f"Màn {mc.id}: thông số không hợp lệ")
        if not mc.mien_phi and mc.gioi_han_giay <= 0:
            raise ValueError(f"Màn {mc.id} có cọc thì phải có giới hạn thời gian")
        if Path(mc.tep).name != mc.tep:
            raise ValueError(f"Màn {mc.id}: tên tệp bản đồ không được chứa thư mục")
        ds[mc.id] = mc
    return ds


def kiem_tra_khop_ban_do(ds: dict[int, ManChoi], thu_muc: Path) -> list[str]:
    """Số xu ghi trong JSON phải đúng số xu trong tệp .tmx — sai là phiếu bị từ chối oan."""
    loi = []
    for m in ds.values():
        tep = Path(thu_muc) / m.tep
        if not tep.exists():
            loi.append(f"Màn {m.id}: thiếu {m.tep}")
            continue
        n = len(doc_tmx(tep).cac_diem("coin"))
        if n != m.so_xu:
            loi.append(f"Màn {m.id}: JSON ghi {m.so_xu} xu, bản đồ có {n}")
    return loi


# ---------------------------------------------------------------------------
# Ước lượng thời gian tối thiểu — căn cứ để đặt giới hạn thời gian cho từng màn
# ---------------------------------------------------------------------------
def _bfs(ban_do: BanDo, dau: tuple[int, int]) -> dict[tuple[int, int], int]:
    kc = {dau: 0}
    hang = [dau]
    for o in hang:                                   # danh sách dùng như hàng đợi
        for dx, dy in LANG_GIENG:
            ke = (o[0] + dx, o[1] + dy)
            if ke not in kc and not ban_do.bi_chan(*ke):
                kc[ke] = kc[o] + 1
                hang.append(ke)
    return kc


def giay_vong_tham(ban_do: BanDo) -> float:
    """Đi tham lam: luôn tới đồng xu GẦN NHẤT (theo đường đi 4 hướng) — số giây đi bộ không dừng.

    Không phải lời giải tối ưu (bài toán người du lịch), nhưng là cận trên đủ tốt và tính nhanh.
    """
    o = ban_do.cac_diem("george")[0]
    con = set(ban_do.cac_diem("coin"))
    tong = 0
    while con:
        kc = _bfs(ban_do, o)
        gan = min(con, key=lambda p: (kc.get(p, math.inf), p))
        tong += kc[gan]
        con.remove(gan)
        o = gan
    return tong * KICH_THUOC_O / TOC_DO_GEORGE


def de_xuat_gioi_han(giay_toi_thieu: float, he_so: float = 1.7, cong_them: float = 25) -> int:
    """Người chơi thật chậm hơn đường tham lam (né quái, đi vòng) → nhân hệ số, cộng thêm, làm tròn 10 s."""
    return int(math.ceil((giay_toi_thieu * he_so + cong_them) / 10) * 10)
