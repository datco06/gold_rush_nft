"""Đọc bản đồ .tmx của Gold Rush và tìm đường A* trên lưới va chạm.

Đây là BẢN THAM CHIẾU bằng Python của `lib/ai/tim_duong.dart` bên app:
cùng thuật toán, cùng thứ tự xét ô láng giềng, cùng cách phá thế hoà.
Dùng để:
  * kiểm thử bản đồ (mọi đồng xu có tới được không) trước khi đưa vào game;
  * sinh ca kiểm thử chung cho cả hai ngôn ngữ.
"""
from __future__ import annotations

import heapq
import xml.etree.ElementTree as ET
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path

KICH_THUOC_O = 16

# Thứ tự láng giềng PHẢI giống bên Dart: phải, trái, xuống, lên.
LANG_GIENG = ((1, 0), (-1, 0), (0, 1), (0, -1))


@dataclass
class BanDo:
    """Bản đồ đã đọc: lưới chặn + các điểm xuất hiện (tính theo Ô, không theo pixel)."""
    so_cot: int
    so_hang: int
    chan: list[list[bool]]                      # chan[hang][cot]
    doi_tuong: list[tuple[str, int, int]] = field(default_factory=list)

    def bi_chan(self, cot: int, hang: int) -> bool:
        if cot < 0 or hang < 0 or cot >= self.so_cot or hang >= self.so_hang:
            return True                          # ngoài bản đồ coi như chặn
        return self.chan[hang][cot]

    def cac_diem(self, ten: str) -> list[tuple[int, int]]:
        return [(c, h) for t, c, h in self.doi_tuong if t == ten]


def doc_tmx(duong_dan: str | Path, lop_va_cham: str = "VaCham", lop_doi_tuong: str = "DoiTuong") -> BanDo:
    """Đọc tệp .tmx (CSV) — cùng quy ước với `BanDo` bên Dart: ô có gid ≠ 0 ở lớp VaCham là ô chặn."""
    goc = ET.parse(duong_dan).getroot()
    so_cot, so_hang = int(goc.get("width")), int(goc.get("height"))
    chan = [[False] * so_cot for _ in range(so_hang)]
    for lop in goc.iter("layer"):
        if lop.get("name") != lop_va_cham:
            continue
        so = [int(v) for v in lop.find("data").text.replace("\n", "").split(",") if v.strip()]
        if len(so) != so_cot * so_hang:
            raise ValueError(f"Lớp {lop_va_cham} có {len(so)} ô, cần {so_cot * so_hang}")
        for i, gid in enumerate(so):
            chan[i // so_cot][i % so_cot] = gid != 0
    doi_tuong = []
    for nhom in goc.iter("objectgroup"):
        if nhom.get("name") != lop_doi_tuong:
            continue
        for o in nhom.iter("object"):
            x, y = float(o.get("x")), float(o.get("y"))
            doi_tuong.append((o.get("name"), int(x // KICH_THUOC_O), int(y // KICH_THUOC_O)))
    return BanDo(so_cot, so_hang, chan, doi_tuong)


def tim_duong(ban_do: BanDo, dau: tuple[int, int], dich: tuple[int, int],
              gioi_han_o: int = 2000) -> list[tuple[int, int]] | None:
    """A* 4 hướng, chi phí mỗi bước = 1, heuristic Manhattan (chấp nhận được → đường ngắn nhất).

    Trả về danh sách ô từ SAU ô đầu tới ô đích (rỗng nếu đầu == đích), hoặc None nếu không có đường
    hoặc đã xét quá `gioi_han_o` ô (chặn chi phí tính toán mỗi khung hình).
    Phá thế hoà: f nhỏ hơn trước, rồi h nhỏ hơn (ưu tiên ô gần đích), rồi thứ tự được đưa vào hàng đợi.
    """
    if ban_do.bi_chan(*dau) or ban_do.bi_chan(*dich):
        return None
    if dau == dich:
        return []

    def h(o):
        return abs(o[0] - dich[0]) + abs(o[1] - dich[1])

    g = {dau: 0}
    cha: dict[tuple[int, int], tuple[int, int]] = {}
    dem = 0
    mo = [(h(dau), h(dau), dem, dau)]
    da_dong = set()
    while mo:
        _, _, _, o = heapq.heappop(mo)
        if o in da_dong:
            continue                              # bản ghi cũ (đã có g tốt hơn)
        if o == dich:
            duong = [o]
            while duong[-1] in cha and cha[duong[-1]] != dau:
                duong.append(cha[duong[-1]])
            return duong[::-1]
        da_dong.add(o)
        if len(da_dong) > gioi_han_o:
            return None
        for dx, dy in LANG_GIENG:
            ke = (o[0] + dx, o[1] + dy)
            if ke in da_dong or ban_do.bi_chan(*ke):
                continue
            g_moi = g[o] + 1
            if g_moi < g.get(ke, 1 << 30):
                g[ke] = g_moi
                cha[ke] = o
                dem += 1
                heapq.heappush(mo, (g_moi + h(ke), h(ke), dem, ke))
    return None


def vung_toi_duoc(ban_do: BanDo, dau: tuple[int, int]) -> set[tuple[int, int]]:
    """BFS: mọi ô đi tới được từ `dau`. Dùng để kiểm tra bản đồ có chơi được không."""
    if ban_do.bi_chan(*dau):
        return set()
    da = {dau}
    hang_doi = deque([dau])
    while hang_doi:
        c, h = hang_doi.popleft()
        for dx, dy in LANG_GIENG:
            ke = (c + dx, h + dy)
            if ke not in da and not ban_do.bi_chan(*ke):
                da.add(ke)
                hang_doi.append(ke)
    return da


def kiem_tra_choi_duoc(ban_do: BanDo) -> list[str]:
    """Trả về danh sách lỗi; rỗng = bản đồ chơi được (George tới được mọi đồng xu)."""
    loi = []
    george = ban_do.cac_diem("george")
    if len(george) != 1:
        return [f"Cần đúng 1 điểm 'george', đang có {len(george)}"]
    vung = vung_toi_duoc(ban_do, george[0])
    if not vung:
        return ["George đứng trên ô chặn"]
    for ten in ("coin", "zombie", "skeleton"):
        for c, h in ban_do.cac_diem(ten):
            if ban_do.bi_chan(c, h):
                loi.append(f"{ten} tại ô ({c},{h}) nằm trên ô chặn")
            elif ten == "coin" and (c, h) not in vung:
                loi.append(f"coin tại ô ({c},{h}) không tới được từ George")
    if not ban_do.cac_diem("coin"):
        loi.append("Bản đồ không có đồng xu nào")
    return loi
