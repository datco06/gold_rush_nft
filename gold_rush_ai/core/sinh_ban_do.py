"""Sinh bản đồ Gold Rush theo thủ tục (Procedural Content Generation — PCG).

Ý tưởng: không vẽ tay từng màn mà để thuật toán sinh, rồi DÙNG AI CỔ ĐIỂN (BFS/A*)
để KIỂM ĐỊNH bản đồ trước khi đưa cho người chơi. Ba bước:

  1. Sinh vật cản bằng automat tế bào (cellular automata): rải ngẫu nhiên rồi "làm mịn"
     vài vòng → thành từng cụm rừng/đá trông tự nhiên thay vì lấm tấm như nhiễu.
  2. Giữ lại VÙNG LIÊN THÔNG chứa George; mọi túi đất bị bao kín bị lấp thành cây
     → không bao giờ có đồng xu "nhìn thấy mà không lấy được".
  3. Đặt đồng xu bằng lấy mẫu điểm xa nhất (farthest-point sampling) theo KHOẢNG CÁCH ĐƯỜNG ĐI
     (không phải đường chim bay) → xu trải đều khắp bản đồ; kẻ địch đặt cách George đủ xa.

Đầu ra là tệp .tmx cùng định dạng, cùng tên lớp, cùng tileset với `assets/tiles/gold_rush.tmx`
→ app Flutter nạp được ngay, không sửa dòng Dart nào.
"""
from __future__ import annotations

import random
from collections import deque

from .luoi import KICH_THUOC_O, LANG_GIENG, BanDo, kiem_tra_choi_duoc

# Chỉ số ô trong tileset (gid trong Tiled = chỉ số + 1) — khớp cong-cu/sinh_tai_nguyen.py
CO, CO_HOA, DUONG, NUOC, CAY, DA, SAN_KC, TUONG, CHAN = range(9)


def _khoang_cach_bfs(chan, so_cot, so_hang, dau):
    """Khoảng cách đường đi (số bước) từ `dau` tới mọi ô đi được."""
    kc = {dau: 0}
    q = deque([dau])
    while q:
        c, h = q.popleft()
        for dx, dy in LANG_GIENG:
            x, y = c + dx, h + dy
            if 0 <= x < so_cot and 0 <= y < so_hang and not chan[y][x] and (x, y) not in kc:
                kc[(x, y)] = kc[(c, h)] + 1
                q.append((x, y))
    return kc


def sinh(seed: int = 0, so_cot: int = 40, so_hang: int = 30, mat_do: float = 0.36,
         vong_lam_min: int = 3, so_xu: int = 24, so_zombie: int = 5, so_skeleton: int = 4,
         cach_george_toi_thieu: int = 12) -> dict:
    """Sinh một bản đồ. Cùng `seed` + cùng tham số → cùng bản đồ (tái lập được, như notebook).

    `mat_do` ~ độ rậm vật cản ban đầu (0.30 thưa … 0.45 rất rậm, dạng mê cung hang động).
    Trả về dict gồm các lưới, danh sách đối tượng và chỉ số đánh giá.
    """
    rnd = random.Random(seed)
    W, H = so_cot, so_hang
    vien = lambda x, y: x < 2 or y < 2 or x >= W - 2 or y >= H - 2

    # --- 1. Automat tế bào -------------------------------------------------
    o = [[vien(x, y) or rnd.random() < mat_do for x in range(W)] for y in range(H)]
    for _ in range(vong_lam_min):
        moi = [[False] * W for _ in range(H)]
        for y in range(H):
            for x in range(W):
                if vien(x, y):
                    moi[y][x] = True
                    continue
                dem = sum(o[y + dy][x + dx]
                          for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dx or dy))
                # Luật 4-5 kinh điển: ≥ 5 láng giềng là vật cản → thành vật cản;
                # đang là vật cản và có ≥ 4 láng giềng vật cản → giữ nguyên
                moi[y][x] = dem >= 5 or (o[y][x] and dem >= 4)
        o = moi

    # Một đường chữ thập luôn thông để bản đồ có "xương sống" dễ định hướng
    gx, gy = W // 2, H // 2
    nen = [[NUOC if vien(x, y) else CO for x in range(W)] for y in range(H)]
    for x in range(2, W - 2):
        o[gy][x] = False
        nen[gy][x] = DUONG
    for y in range(2, H - 2):
        o[y][gx] = False
        nen[y][gx] = DUONG

    # --- 2. Giữ vùng liên thông chứa George --------------------------------
    george = (gx, 3)
    while o[george[1]][george[0]]:
        george = (george[0], george[1] + 1)
    kc = _khoang_cach_bfs(o, W, H, george)
    for y in range(H):
        for x in range(W):
            if not o[y][x] and (x, y) not in kc:
                o[y][x] = True                    # lấp túi đất kín

    trang_tri = [[-1] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if o[y][x] and not vien(x, y):
                trang_tri[y][x] = CAY if rnd.random() < 0.7 else DA
            elif not o[y][x] and nen[y][x] == CO and rnd.random() < 0.08:
                nen[y][x] = CO_HOA

    # --- 3. Đặt đồng xu và kẻ địch -----------------------------------------
    o_trong = sorted(kc)                          # sorted → không phụ thuộc thứ tự dict
    xu = [max(o_trong, key=lambda p: kc[p])]      # xu đầu tiên ở xa George nhất
    kc_toi_xu = _khoang_cach_bfs(o, W, H, xu[0])
    while len(xu) < min(so_xu, len(o_trong) - 1):
        # điểm xa tập xu hiện có nhất (theo đường đi); thêm nhiễu nhỏ để không quá đều
        ung_vien = [p for p in o_trong if p != george and p not in xu]
        p = max(ung_vien, key=lambda q: kc_toi_xu.get(q, 0) + rnd.random() * 2)
        xu.append(p)
        kc_moi = _khoang_cach_bfs(o, W, H, p)
        kc_toi_xu = {q: min(kc_toi_xu.get(q, 1 << 30), kc_moi.get(q, 1 << 30)) for q in o_trong}

    da_dat = set(xu) | {george}
    xa = [p for p in o_trong if kc[p] >= cach_george_toi_thieu and p not in da_dat]
    rnd.shuffle(xa)
    can = so_zombie + so_skeleton
    if len(xa) < can:
        raise ValueError("Bản đồ quá chật để đặt kẻ địch — giảm mat_do hoặc cach_george_toi_thieu")
    ke_dich = [("zombie", *p) for p in xa[:so_zombie]] + [("skeleton", *p) for p in xa[so_zombie:can]]

    doi_tuong = [("george", *george)] + [("coin", *p) for p in xu] + ke_dich
    ban_do = BanDo(W, H, o, doi_tuong)
    loi = kiem_tra_choi_duoc(ban_do)
    if loi:                                       # không bao giờ xảy ra nếu thuật toán đúng
        raise AssertionError(loi)

    duong_xu = [kc[p] for p in xu]
    chi_so = {
        "seed": seed,
        "ti_le_di_duoc": round(len(kc) / ((W - 4) * (H - 4)), 3),
        "duong_tb_toi_xu": round(sum(duong_xu) / len(duong_xu), 1),
        "duong_xa_nhat_toi_xu": max(duong_xu),
        "ke_dich_gan_nhat": min(kc[(c, h)] for _, c, h in ke_dich),
    }
    return {"nen": nen, "trang_tri": trang_tri, "chan": o, "doi_tuong": doi_tuong,
            "ban_do": ban_do, "chi_so": chi_so}


def thanh_tmx(kq: dict) -> str:
    """Ghi ra chuỗi .tmx đúng định dạng game đang dùng (4 lớp: Nen, TrangTri, VaCham, DoiTuong)."""
    nen, trang_tri, chan, doi_tuong = kq["nen"], kq["trang_tri"], kq["chan"], kq["doi_tuong"]
    H, W = len(nen), len(nen[0])

    def csv(luoi, f):
        return ",\n".join(",".join(str(f(v)) for v in hang) for hang in luoi)

    def lop(sid, ten, luoi, f, hien=True):
        an = "" if hien else ' visible="0"'
        return (f'  <layer id="{sid}" name="{ten}" width="{W}" height="{H}"{an}>\n'
                f'   <data encoding="csv">\n{csv(luoi, f)}\n</data>\n  </layer>\n')

    dt = "".join(
        f'   <object id="{i}" name="{ten}" x="{c * KICH_THUOC_O + KICH_THUOC_O / 2:g}" '
        f'y="{h * KICH_THUOC_O + KICH_THUOC_O / 2:g}" width="0" height="0"/>\n'
        for i, (ten, c, h) in enumerate(doi_tuong, start=1))
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" '
            f'width="{W}" height="{H}" tilewidth="{KICH_THUOC_O}" tileheight="{KICH_THUOC_O}" infinite="0" '
            f'nextlayerid="6" nextobjectid="{len(doi_tuong) + 1}">\n'
            f' <tileset firstgid="1" name="gold_rush" tilewidth="{KICH_THUOC_O}" tileheight="{KICH_THUOC_O}" '
            f'tilecount="9" columns="9">\n'
            f'  <image source="../images/tileset.png" width="{KICH_THUOC_O * 9}" height="{KICH_THUOC_O}"/>\n'
            ' </tileset>\n'
            + lop(1, "Nen", nen, lambda v: v + 1)
            + lop(2, "TrangTri", trang_tri, lambda v: 0 if v < 0 else v + 1)
            + lop(3, "VaCham", chan, lambda v: CHAN + 1 if v else 0, hien=False)
            + '  <objectgroup id="4" name="DoiTuong">\n' + dt + "  </objectgroup>\n</map>\n")
