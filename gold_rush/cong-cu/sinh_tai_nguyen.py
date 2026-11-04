#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sinh toan bo tai nguyen goc cho game Gold Rush.

Chay:  python3 cong-cu/sinh_tai_nguyen.py

Sinh ra:
    assets/images/*.png   tileset va sprite sheet
    assets/tiles/*.tmx    ban do Tiled
    assets/audio/*.wav    hieu ung am thanh va nhac nen

Toan bo do hoa va am thanh deu duoc sinh bang ma nguon trong tep nay,
khong sao chep tu bat ky nguon nao khac -> khong vuong ban quyen.
Muon doi phong cach do hoa, sua bang mau PALETTE va cac ham ve ben duoi.
"""

import math
import os
import random
import struct
import wave

from PIL import Image, ImageDraw

GOC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANH = os.path.join(GOC, 'assets', 'images')
TILES = os.path.join(GOC, 'assets', 'tiles')
AUDIO = os.path.join(GOC, 'assets', 'audio')
for d in (ANH, TILES, AUDIO):
    os.makedirs(d, exist_ok=True)

O = 16                      # kich thuoc mot o (pixel)
COT, HANG = 40, 30          # kich thuoc ban do (o)
random.seed(20260922)       # co dinh de moi lan chay ra ket qua giong nhau

# --------------------------------------------------------------------------
# BANG MAU
# --------------------------------------------------------------------------
P = {
    'co1': (106, 170, 100), 'co2': (92, 154, 88), 'co3': (120, 184, 112),
    'hoa_v': (240, 220, 120), 'hoa_t': (235, 245, 250),
    'dat1': (196, 164, 116), 'dat2': (176, 144, 100), 'dat3': (210, 182, 138),
    'nuoc1': (64, 128, 196), 'nuoc2': (48, 106, 172), 'nuoc3': (108, 168, 220),
    'than': (92, 62, 40), 'la1': (46, 110, 62), 'la2': (34, 88, 48), 'la3': (62, 134, 76),
    'da1': (140, 140, 148), 'da2': (108, 108, 118), 'da3': (176, 176, 184),
    'kc1': (208, 198, 232), 'kc2': (184, 172, 214), 'kc3': (228, 220, 246),
    'tuong1': (128, 120, 112), 'tuong2': (98, 92, 86), 'tuong3': (158, 150, 142),

    'da_nguoi': (238, 200, 164), 'toc': (92, 62, 40),
    'ao': (196, 72, 48), 'quan': (58, 78, 132), 'giay': (72, 54, 40),
    'zom_da': (128, 176, 108), 'zom_ao': (92, 76, 60), 'zom_mat': (196, 60, 52),
    'xuong': (232, 230, 216), 'xuong_toi': (188, 186, 172), 'xuong_mat': (40, 40, 48),
    'vang1': (250, 208, 68), 'vang2': (216, 162, 32), 'vang3': (255, 238, 150),

    'den': (26, 26, 32), 'trang': (255, 255, 255),
}


def anh(w, h):
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def nhieu(d, x0, y0, w, h, mau, xac_suat=0.16):
    """Ram vai cham mau ngau nhien cho do hoa bot phang."""
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            if random.random() < xac_suat:
                d.point((x, y), mau)


# --------------------------------------------------------------------------
# 1. TILESET  (9 o, moi o 16x16, xep thanh mot hang ngang)
#    gid trong Tiled = chi so + 1  (firstgid = 1)
# --------------------------------------------------------------------------
TEN_TILE = ['co', 'co_hoa', 'duong', 'nuoc', 'cay', 'da', 'san_kc', 'tuong', 'chan']
CO, CO_HOA, DUONG, NUOC, CAY, DA, SAN_KC, TUONG, CHAN = range(9)


def ve_tileset():
    im, d = anh(O * 9, O)

    def o_tai(i):
        return i * O

    # --- co ---
    x = o_tai(CO)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['co1'])
    nhieu(d, x, 0, O, O, P['co2'], 0.20)
    nhieu(d, x, 0, O, O, P['co3'], 0.12)

    # --- co co hoa ---
    x = o_tai(CO_HOA)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['co1'])
    nhieu(d, x, 0, O, O, P['co2'], 0.18)
    for hx, hy, c in [(3, 4, 'hoa_v'), (10, 7, 'hoa_t'), (6, 12, 'hoa_v'), (12, 2, 'hoa_t')]:
        d.point((x + hx, hy), P[c])
        d.point((x + hx + 1, hy), P[c])
        d.point((x + hx, hy + 1), P[c])

    # --- duong dat ---
    x = o_tai(DUONG)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['dat1'])
    nhieu(d, x, 0, O, O, P['dat2'], 0.22)
    nhieu(d, x, 0, O, O, P['dat3'], 0.14)

    # --- nuoc (co gon song) ---
    x = o_tai(NUOC)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['nuoc1'])
    for y in range(O):
        for xx in range(O):
            if (xx + y * 2) % 7 == 0:
                d.point((x + xx, y), P['nuoc2'])
            elif (xx * 2 + y) % 11 == 0:
                d.point((x + xx, y), P['nuoc3'])

    # --- cay (chan duong) ---
    x = o_tai(CAY)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['co1'])
    nhieu(d, x, 0, O, O, P['co2'], 0.15)
    d.rectangle([x + 7, 11, x + 8, 15], fill=P['than'])
    d.ellipse([x + 2, 1, x + 13, 12], fill=P['la1'])
    d.ellipse([x + 3, 2, x + 9, 8], fill=P['la3'])
    nhieu(d, x + 2, 1, 12, 11, P['la2'], 0.18)

    # --- da (chan duong) ---
    x = o_tai(DA)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['co1'])
    nhieu(d, x, 0, O, O, P['co2'], 0.15)
    d.ellipse([x + 2, 5, x + 13, 14], fill=P['da2'])
    d.ellipse([x + 3, 4, x + 11, 11], fill=P['da1'])
    d.ellipse([x + 5, 5, x + 9, 8], fill=P['da3'])

    # --- san kim cuong ---
    x = o_tai(SAN_KC)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['kc1'])
    d.polygon([(x + 8, 1), (x + 15, 8), (x + 8, 15), (x + 1, 8)], outline=P['kc2'])
    d.polygon([(x + 8, 4), (x + 12, 8), (x + 8, 12), (x + 4, 8)], fill=P['kc3'])

    # --- tuong da (chan duong) ---
    x = o_tai(TUONG)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=P['tuong1'])
    for y in (0, 5, 10):
        d.line([(x, y), (x + O - 1, y)], fill=P['tuong2'])
    for y, off in ((0, 0), (5, 8), (10, 4)):
        d.line([(x + off, y), (x + off, min(y + 5, O - 1))], fill=P['tuong2'])
    nhieu(d, x, 0, O, O, P['tuong3'], 0.10)

    # --- o danh dau va cham (lop nay tat hien thi trong game) ---
    x = o_tai(CHAN)
    d.rectangle([x, 0, x + O - 1, O - 1], fill=(220, 60, 60, 110))

    im.save(os.path.join(ANH, 'tileset.png'))
    return im


# --------------------------------------------------------------------------
# 2. NHAN VAT  (4 hang: xuong / trai / phai / len  x  4 khung hinh)
# --------------------------------------------------------------------------
def ve_nhan_vat(ten, da, ao, quan, kieu='nguoi'):
    """Sinh sprite sheet 64x64: 4 huong x 4 khung, moi khung 16x16.

    Hang 0 = di xuong, 1 = sang trai, 2 = sang phai, 3 = di len.
    Cot 0..3 = dung / buoc chan trai / dung / buoc chan phai.
    """
    im, d = anh(O * 4, O * 4)

    def khung(cot, hang):
        x, y = cot * O, hang * O
        buoc = [0, 1, 0, -1][cot]        # -1, 0, +1: chan nao dua ra truoc
        nhun = 1 if cot % 2 == 1 else 0  # than nhun xuong 1px khi dat chan

        ngang = hang in (1, 2)
        quay_lung = hang == 3

        # Bong do KHONG ve o day: game tu ve bang ma nguon
        # (xem lib/components/hieu_ung.dart, lop Bong).

        # --- chan: hai chan tach roi, lech nhau theo buoc ---
        ct, cp = y + 11 + nhun, y + 11 + nhun
        if buoc > 0:
            d.rectangle([x + 4, ct, x + 6, y + 14], fill=quan)
            d.rectangle([x + 9, cp + 1, x + 11, y + 14], fill=quan)
            d.rectangle([x + 4, y + 14, x + 6, y + 15], fill=P['giay'])
            d.rectangle([x + 9, y + 14, x + 11, y + 15], fill=P['giay'])
        elif buoc < 0:
            d.rectangle([x + 4, ct + 1, x + 6, y + 14], fill=quan)
            d.rectangle([x + 9, cp, x + 11, y + 14], fill=quan)
            d.rectangle([x + 4, y + 14, x + 6, y + 15], fill=P['giay'])
            d.rectangle([x + 9, y + 14, x + 11, y + 15], fill=P['giay'])
        else:
            d.rectangle([x + 5, ct, x + 7, y + 15], fill=quan)
            d.rectangle([x + 8, cp, x + 10, y + 15], fill=quan)
            d.rectangle([x + 5, y + 14, x + 7, y + 15], fill=P['giay'])
            d.rectangle([x + 8, y + 14, x + 10, y + 15], fill=P['giay'])

        # --- than ---
        tx0, tx1 = (x + 5, x + 10) if ngang else (x + 4, x + 11)
        d.rectangle([tx0, y + 7 + nhun, tx1, y + 11 + nhun], fill=ao)

        if kieu == 'xuong':
            # xuong suon
            for i in range(3):
                d.line([(tx0 + 1, y + 8 + nhun + i), (tx1 - 1, y + 8 + nhun + i)],
                       fill=P['xuong_toi'])
                d.point((x + 8, y + 8 + nhun + i), P['xuong'])
        elif kieu == 'zombie':
            # ao rach
            d.point((tx0 + 1, y + 10 + nhun), P['zom_da'])
            d.point((tx1 - 1, y + 9 + nhun), P['zom_da'])

        # --- tay ---
        tay_y = y + 8 + nhun
        if ngang:
            # nhin nghieng: chi thay mot tay, dua ra truoc theo buoc
            ax = (x + 3) if hang == 1 else (x + 11)
            d.rectangle([ax, tay_y - min(buoc, 0), ax + 1, tay_y + 3], fill=da)
        else:
            d.rectangle([x + 2, tay_y + (1 if buoc > 0 else 0), x + 3, tay_y + 3], fill=da)
            d.rectangle([x + 12, tay_y + (1 if buoc < 0 else 0), x + 13, tay_y + 3], fill=da)
            if kieu == 'zombie' and hang == 0:
                # zombie gio hai tay ve phia truoc
                d.rectangle([x + 2, tay_y - 1, x + 3, tay_y + 1], fill=da)
                d.rectangle([x + 12, tay_y - 1, x + 13, tay_y + 1], fill=da)

        # --- dau ---
        hx0, hx1 = (x + 5, x + 10) if ngang else (x + 4, x + 11)
        hy0 = y + 1 + nhun
        d.ellipse([hx0, hy0, hx1, hy0 + 6], fill=da)

        if kieu == 'nguoi':
            d.rectangle([hx0, hy0, hx1, hy0 + 1], fill=P['toc'])
            d.point((hx0, hy0 + 2), P['toc'])
            d.point((hx1, hy0 + 2), P['toc'])
        elif kieu == 'zombie':
            d.rectangle([hx0, hy0, hx1, hy0 + 1], fill=P['zom_ao'])

        # --- mat ---
        mat = P['xuong_mat'] if kieu == 'xuong' else P['den']
        my = hy0 + 4
        if hang == 0:
            d.point((x + 6, my), mat)
            d.point((x + 9, my), mat)
            if kieu == 'xuong':
                d.point((x + 6, my + 1), mat)
                d.point((x + 9, my + 1), mat)
                d.point((x + 8, my + 2), mat)     # mui hoc
        elif hang == 1:
            d.rectangle([x + 5, my, x + 6, my + (1 if kieu == 'xuong' else 0)], fill=mat)
        elif hang == 2:
            d.rectangle([x + 9, my, x + 10, my + (1 if kieu == 'xuong' else 0)], fill=mat)
        # hang 3: quay lung, khong ve mat

        # --- rang cho bo xuong khi nhin thang ---
        if kieu == 'xuong' and hang == 0:
            d.line([(x + 6, my + 3), (x + 9, my + 3)], fill=P['xuong_toi'])

    for hang in range(4):
        for cot in range(4):
            khung(cot, hang)

    im.save(os.path.join(ANH, ten))


# --------------------------------------------------------------------------
# 3. DONG XU  (8 khung xoay, moi khung 16x16, mot hang ngang)
# --------------------------------------------------------------------------
def ve_dong_xu():
    n = 8
    im, d = anh(O * n, O)
    for i in range(n):
        x = i * O
        # be ngang thay doi theo hinh sin -> cam giac dong xu dang xoay
        rong = max(1, int(round(6 * abs(math.cos(math.pi * i / n)))))
        if rong <= 1:
            d.line([(x + 8, 4), (x + 8, 12)], fill=P['vang2'])
            continue
        d.ellipse([x + 8 - rong, 3, x + 7 + rong, 12], fill=P['vang2'])
        d.ellipse([x + 9 - rong, 4, x + 6 + rong, 11], fill=P['vang1'])
        if rong >= 4:
            d.ellipse([x + 10 - rong, 5, x + 4 + rong, 8], fill=P['vang3'])
    im.save(os.path.join(ANH, 'dong_xu.png'))


# --------------------------------------------------------------------------
# 4. JOYSTICK
# --------------------------------------------------------------------------
def ve_joystick():
    im, d = anh(64, 64)
    d.ellipse([0, 0, 63, 63], fill=(20, 24, 32, 90), outline=(255, 255, 255, 110), width=2)
    d.ellipse([20, 20, 43, 43], outline=(255, 255, 255, 60))
    im.save(os.path.join(ANH, 'joystick_nen.png'))

    im, d = anh(28, 28)
    d.ellipse([0, 0, 27, 27], fill=(240, 244, 250, 220), outline=(40, 46, 58, 220), width=2)
    d.ellipse([7, 6, 18, 15], fill=(255, 255, 255, 180))
    im.save(os.path.join(ANH, 'joystick_num.png'))


# --------------------------------------------------------------------------
# 5. BAN DO TILED  (.tmx)
# --------------------------------------------------------------------------
def dung_ban_do():
    """Tra ve (nen, trang_tri, chan, doi_tuong)."""
    nen = [[CO for _ in range(COT)] for _ in range(HANG)]
    trang_tri = [[-1 for _ in range(COT)] for _ in range(HANG)]
    chan = [[0 for _ in range(COT)] for _ in range(HANG)]

    # vien nuoc day 2 o quanh ban do
    for y in range(HANG):
        for x in range(COT):
            if x < 2 or y < 2 or x >= COT - 2 or y >= HANG - 2:
                nen[y][x] = NUOC
                chan[y][x] = 1

    # rai hoa
    for y in range(2, HANG - 2):
        for x in range(2, COT - 2):
            if random.random() < 0.08:
                nen[y][x] = CO_HOA

    # duong chu thap
    gx, gy = COT // 2, HANG // 2
    for x in range(2, COT - 2):
        for dy in (-1, 0, 1):
            nen[gy + dy][x] = DUONG
    for y in range(2, HANG - 2):
        for dx in (-1, 0, 1):
            nen[y][gx + dx] = DUONG

    # vong duong bao quanh
    for x in range(6, COT - 6):
        nen[6][x] = DUONG
        nen[HANG - 7][x] = DUONG
    for y in range(6, HANG - 6):
        nen[y][6] = DUONG
        nen[y][COT - 7] = DUONG

    # khu kim cuong trung tam, quanh la nuoc trang tri
    for y in range(gy - 3, gy + 4):
        for x in range(gx - 4, gx + 5):
            if abs(x - gx) / 4.0 + abs(y - gy) / 3.0 <= 1.0:
                nen[y][x] = SAN_KC
            elif abs(x - gx) / 5.0 + abs(y - gy) / 4.0 <= 1.0 and nen[y][x] != DUONG:
                nen[y][x] = NUOC
                chan[y][x] = 1

    # doan tuong da lam vat can
    for x in range(11, 18):
        trang_tri[9][x] = TUONG
        chan[9][x] = 1
    for y in range(18, 24):
        trang_tri[y][26] = TUONG
        chan[y][26] = 1

    # cay va da rai rac (khong dat len duong)
    for _ in range(90):
        x = random.randint(3, COT - 4)
        y = random.randint(3, HANG - 4)
        if nen[y][x] in (CO, CO_HOA) and trang_tri[y][x] == -1 and chan[y][x] == 0:
            trang_tri[y][x] = CAY if random.random() < 0.65 else DA
            chan[y][x] = 1

    # --- diem xuat hien ---
    doi_tuong = []

    def o_trong(x, y):
        return chan[y][x] == 0

    # George dat o goc tren ben trai cua duong
    for y in range(3, HANG - 3):
        for x in range(3, COT - 3):
            if o_trong(x, y) and nen[y][x] == DUONG:
                doi_tuong.append(('george', x, y))
                break
        if doi_tuong:
            break

    gx0, gy0 = doi_tuong[0][1], doi_tuong[0][2]

    # 24 dong xu
    dat = {(gx0, gy0)}
    dem = 0
    while dem < 24:
        x = random.randint(3, COT - 4)
        y = random.randint(3, HANG - 4)
        if o_trong(x, y) and (x, y) not in dat:
            dat.add((x, y))
            doi_tuong.append(('coin', x, y))
            dem += 1

    # 5 zombie + 4 skeleton, cach George it nhat 9 o
    for ten, so in (('zombie', 5), ('skeleton', 4)):
        dem = 0
        while dem < so:
            x = random.randint(3, COT - 4)
            y = random.randint(3, HANG - 4)
            if o_trong(x, y) and (x, y) not in dat and abs(x - gx0) + abs(y - gy0) >= 9:
                dat.add((x, y))
                doi_tuong.append((ten, x, y))
                dem += 1

    return nen, trang_tri, chan, doi_tuong


def csv_lop(luoi, doi_chieu=lambda v: v + 1):
    dong = []
    for hang in luoi:
        dong.append(','.join(str(doi_chieu(v)) for v in hang))
    return ',\n'.join(dong)


def viet_tmx(nen, trang_tri, chan, doi_tuong):
    def lop_tile(sid, ten, luoi, hien, doi_chieu):
        an = '' if hien else ' visible="0"'
        return (
            f'  <layer id="{sid}" name="{ten}" width="{COT}" height="{HANG}"{an}>\n'
            f'   <data encoding="csv">\n{csv_lop(luoi, doi_chieu)}\n</data>\n'
            f'  </layer>\n'
        )

    dt = []
    for i, (ten, x, y) in enumerate(doi_tuong, start=1):
        # Tiled dat goc doi tuong o goc tren-trai; dat vao giua o cho de tinh
        px = x * O + O / 2
        py = y * O + O / 2
        dt.append(
            f'   <object id="{i}" name="{ten}" x="{px:g}" y="{py:g}" '
            f'width="0" height="0"/>\n'
        )

    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" '
        f'renderorder="right-down" width="{COT}" height="{HANG}" '
        f'tilewidth="{O}" tileheight="{O}" infinite="0" nextlayerid="6" nextobjectid="{len(doi_tuong) + 1}">\n'
        f' <tileset firstgid="1" name="gold_rush" tilewidth="{O}" tileheight="{O}" '
        f'tilecount="9" columns="9">\n'
        f'  <image source="../images/tileset.png" width="{O * 9}" height="{O}"/>\n'
        f' </tileset>\n'
        + lop_tile(1, 'Nen', nen, True, lambda v: v + 1)
        + lop_tile(2, 'TrangTri', trang_tri, True, lambda v: 0 if v < 0 else v + 1)
        + lop_tile(3, 'VaCham', chan, False, lambda v: (CHAN + 1) if v else 0)
        + f'  <objectgroup id="4" name="DoiTuong">\n' + ''.join(dt) + '  </objectgroup>\n'
        + '</map>\n'
    )
    with open(os.path.join(TILES, 'gold_rush.tmx'), 'w', encoding='utf-8') as f:
        f.write(xml)


# --------------------------------------------------------------------------
# 6. AM THANH  (WAV 16-bit mono 22050 Hz, sinh bang cong thuc toan hoc)
# --------------------------------------------------------------------------
TAN_SO = 22050


def viet_wav(ten, mau):
    with wave.open(os.path.join(AUDIO, ten), 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TAN_SO)
        w.writeframes(b''.join(
            struct.pack('<h', max(-32767, min(32767, int(v * 32767)))) for v in mau))


def am_dong_xu():
    """Hai not cao ngan -> cam giac 'ting'."""
    mau = []
    for f, dai in ((988.0, 0.07), (1319.0, 0.14)):
        n = int(TAN_SO * dai)
        for i in range(n):
            t = i / TAN_SO
            bao = math.exp(-14 * t)
            mau.append(0.35 * bao * (math.sin(2 * math.pi * f * t)
                                     + 0.4 * math.sin(4 * math.pi * f * t)))
    return mau


def am_va_cham():
    """Nhieu trang loc thap + sin tram -> tieng no nho."""
    mau = []
    n = int(TAN_SO * 0.32)
    truoc = 0.0
    for i in range(n):
        t = i / TAN_SO
        bao = math.exp(-9 * t)
        nhieu_tr = random.uniform(-1, 1)
        truoc = truoc * 0.72 + nhieu_tr * 0.28      # loc thong thap don gian
        tram = math.sin(2 * math.pi * (140 - 90 * t) * t)
        mau.append(0.5 * bao * (0.6 * truoc + 0.5 * tram))
    return mau


def am_buoc_chan():
    mau = []
    n = int(TAN_SO * 0.10)
    truoc = 0.0
    for i in range(n):
        t = i / TAN_SO
        bao = math.exp(-30 * t)
        truoc = truoc * 0.5 + random.uniform(-1, 1) * 0.5
        mau.append(0.22 * bao * truoc)
    return mau


def nhac_nen():
    """Vong lap 8 giay: giai dieu ngu cung + bass, dang song vuong nhe."""
    nhip = 0.25
    giai_dieu = [0, 3, 5, 7, 10, 7, 5, 3, 0, 3, 7, 10, 12, 10, 7, 5,
                 0, 3, 5, 7, 10, 12, 10, 7, 5, 3, 0, 3, 5, 3, 0, 0]
    bass = [0, 0, 5, 5, 7, 7, 3, 3] * 4

    def hz(nua_cung, goc=220.0):
        return goc * (2 ** (nua_cung / 12.0))

    mau = []
    for i, nc in enumerate(giai_dieu):
        n = int(TAN_SO * nhip)
        f1 = hz(nc + 12)
        f2 = hz(bass[i] - 12)
        for j in range(n):
            t = j / TAN_SO
            bao = min(1.0, t * 40) * math.exp(-2.2 * t)
            # song vuong rat nhe cho giong nhac 8-bit
            v1 = 0.5 if math.sin(2 * math.pi * f1 * t) > 0 else -0.5
            v2 = math.sin(2 * math.pi * f2 * t)
            mau.append(0.16 * bao * v1 + 0.10 * v2)
    return mau


# --------------------------------------------------------------------------
def main():
    print('1/6  tileset.png')
    ve_tileset()

    print('2/6  george.png / zombie.png / skeleton.png')
    ve_nhan_vat('george.png', P['da_nguoi'], P['ao'], P['quan'], kieu='nguoi')
    ve_nhan_vat('zombie.png', P['zom_da'], P['zom_ao'], P['zom_ao'], kieu='zombie')
    ve_nhan_vat('skeleton.png', P['xuong'], P['xuong'], P['xuong_toi'], kieu='xuong')

    print('3/6  dong_xu.png')
    ve_dong_xu()

    print('4/6  joystick_nen.png / joystick_num.png')
    ve_joystick()

    print('5/6  gold_rush.tmx')
    nen, trang_tri, chan, doi_tuong = dung_ban_do()
    viet_tmx(nen, trang_tri, chan, doi_tuong)
    print('     so doi tuong:', len(doi_tuong))

    print('6/6  am thanh')
    viet_wav('dong_xu.wav', am_dong_xu())
    viet_wav('va_cham.wav', am_va_cham())
    viet_wav('buoc_chan.wav', am_buoc_chan())
    viet_wav('nhac_nen.wav', nhac_nen())

    print('Xong. Tat ca tai nguyen nam trong assets/')


if __name__ == '__main__':
    main()
