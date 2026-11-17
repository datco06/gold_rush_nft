#!/usr/bin/env python3
"""Tạo mã đổi thưởng Gold Rush và ảnh QR PNG.

QR chỉ chứa chuỗi mã ngẫu nhiên. Phần thưởng được lưu ở SQLite theo hash của
mã, nên người chơi không thể sửa số vàng/tokenId bằng cách chỉnh QR.

Ví dụ:
  python scripts/tao_ma_qr_qua_tang.py --type gold --amount 500 --max-uses 10
  python scripts/tao_ma_qr_qua_tang.py --type item --token-id 9 --amount 1 \
      --name "Súng Hắc Long" --expires-at 2026-12-31T23:59:59+00:00
"""
from __future__ import annotations

import argparse
import hashlib
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ModuleNotFoundError as exc:  # Pillow đã có trong requirements.txt của dự án.
    raise SystemExit("Thiếu Pillow. Cài dependency hiện có của gold_rush_ai rồi chạy lại.") from exc

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import config  # noqa: E402
from core.csdl import khoi_tao_csdl, lay_csdl  # noqa: E402


def _hash_ma(ma: str) -> str:
    return hashlib.sha256(ma.strip().upper().encode("utf-8")).hexdigest()


def _timestamp(value: str | None) -> float | None:
    if not value:
        return None
    raw = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        raise argparse.ArgumentTypeError("Hạn dùng phải là ISO-8601, ví dụ 2026-12-31T23:59:59+00:00") from None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.timestamp()


def _new_code() -> str:
    # 26 ký tự entropy cao, dễ nhập lại và không chứa ký tự gây nhầm lẫn.
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "GR-" + "".join(secrets.choice(alphabet) for _ in range(26))


# ---------------------------------------------------------------------------
# QR byte-mode tối thiểu, Version 3-L (29x29, tối đa 53 byte ASCII).
# Không cần package QR bên ngoài; Pillow chỉ dùng để ghi PNG.
# ---------------------------------------------------------------------------
_GF_EXP = [0] * 512
_GF_LOG = [0] * 256
_x = 1
for _i in range(255):
    _GF_EXP[_i] = _x
    _GF_LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    _GF_EXP[_i] = _GF_EXP[_i - 255]


def _gf_mul(a: int, b: int) -> int:
    return 0 if a == 0 or b == 0 else _GF_EXP[_GF_LOG[a] + _GF_LOG[b]]


def _rs_generator(degree: int) -> list[int]:
    generator = [1]
    for i in range(degree):
        out = [0] * (len(generator) + 1)
        factor = _GF_EXP[i]
        for j, value in enumerate(generator):
            out[j] ^= value
            out[j + 1] ^= _gf_mul(value, factor)
        generator = out
    return generator


def _ecc(data: bytes, degree: int = 15) -> bytes:
    generator = _rs_generator(degree)
    remainder = [0] * degree
    for value in data:
        factor = value ^ remainder[0]
        remainder = remainder[1:] + [0]
        for i in range(degree):
            remainder[i] ^= _gf_mul(generator[i + 1], factor)
    return bytes(remainder)


def _format_bits(mask: int) -> int:
    # Error correction L = 01 in QR format information.
    value = (1 << 3) | mask
    remainder = value << 10
    while remainder.bit_length() >= 11:
        remainder ^= 0x537 << (remainder.bit_length() - 11)
    return ((value << 10) | remainder) ^ 0x5412


def _set_finder(matrix: list[list[bool | None]], left: int, top: int) -> None:
    size = len(matrix)
    for dy in range(-1, 8):
        for dx in range(-1, 8):
            x, y = left + dx, top + dy
            if 0 <= x < size and 0 <= y < size:
                matrix[y][x] = 0 <= dx <= 6 and 0 <= dy <= 6 and (
                    dx in (0, 6) or dy in (0, 6) or (2 <= dx <= 4 and 2 <= dy <= 4)
                )


def _set_alignment(matrix: list[list[bool | None]], center_x: int, center_y: int) -> None:
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            matrix[center_y + dy][center_x + dx] = max(abs(dx), abs(dy)) in (0, 2)


def _qr_matrix(payload: str) -> list[list[bool]]:
    raw = payload.encode("ascii")
    if len(raw) > 53:
        raise ValueError("Mã quá dài cho QR Version 3-L")

    bits = [0, 1, 0, 0]  # byte mode
    bits += [(len(raw) >> (7 - i)) & 1 for i in range(8)]
    for byte in raw:
        bits += [(byte >> (7 - i)) & 1 for i in range(8)]
    bits += [0] * min(4, 8 * 55 - len(bits))
    bits += [0] * ((8 - len(bits) % 8) % 8)
    data = bytearray()
    for i in range(0, len(bits), 8):
        data.append(sum(bits[i + j] << (7 - j) for j in range(8)))
    pad = (0xEC, 0x11)
    for i in range(len(data), 55):
        data.append(pad[(i - len(data)) % 2])
    codewords = bytes(data) + _ecc(bytes(data))

    size = 29
    matrix: list[list[bool | None]] = [[None] * size for _ in range(size)]
    _set_finder(matrix, 0, 0)
    _set_finder(matrix, size - 7, 0)
    _set_finder(matrix, 0, size - 7)
    for i in range(8, size - 8):
        if matrix[6][i] is None:
            matrix[6][i] = i % 2 == 0
        if matrix[i][6] is None:
            matrix[i][6] = i % 2 == 0
    _set_alignment(matrix, 22, 22)
    matrix[size - 8][8] = True

    format_value = _format_bits(0)
    for i in range(15):
        value = bool((format_value >> i) & 1)
        if i < 6:
            matrix[i][8] = value
        elif i < 8:
            matrix[i + 1][8] = value
        else:
            matrix[size - 15 + i][8] = value
        if i < 8:
            matrix[8][size - i - 1] = value
        elif i < 9:
            matrix[8][15 - i] = value
        else:
            matrix[8][15 - i - 1] = value

    data_bits = [((byte >> (7 - bit)) & 1) for byte in codewords for bit in range(8)]
    bit_index = 0
    column = size - 1
    upward = True
    while column > 0:
        if column == 6:
            column -= 1
        rows = range(size - 1, -1, -1) if upward else range(size)
        for row in rows:
            for x in (column, column - 1):
                if matrix[row][x] is None:
                    value = data_bits[bit_index] if bit_index < len(data_bits) else 0
                    bit_index += 1
                    # Format information above declares mask pattern 0. The
                    # mask must be applied to every data/ECC module; omitting
                    # this XOR produces a QR-looking image that decoders
                    # cannot validate.
                    if (row + x) % 2 == 0:
                        value ^= 1
                    matrix[row][x] = bool(value)
        upward = not upward
        column -= 2
    return [[bool(cell) for cell in row] for row in matrix]


def _write_qr_png(payload: str, destination: Path, scale: int = 10) -> None:
    matrix = _qr_matrix(payload)
    quiet = 4
    side = (len(matrix) + quiet * 2) * scale
    image = Image.new("RGB", (side, side), "white")
    draw = ImageDraw.Draw(image)
    for y, row in enumerate(matrix):
        for x, dark in enumerate(row):
            if dark:
                left = (x + quiet) * scale
                top = (y + quiet) * scale
                draw.rectangle((left, top, left + scale - 1, top + scale - 1), fill="black")
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="PNG")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Tạo mã QR đổi quà Gold Rush.")
    parser.add_argument("--type", choices=("gold", "item"), required=True, dest="reward_type")
    parser.add_argument("--amount", type=int, required=True, help="Số vàng hoặc số NFT")
    parser.add_argument("--token-id", type=int, default=None, help="Bắt buộc với item, 1–27; gold luôn là 0")
    parser.add_argument("--max-uses", type=int, required=True, help="Tổng số lượt nhận")
    parser.add_argument("--per-wallet-limit", type=int, default=1, help="Số lượt tối đa mỗi ví")
    parser.add_argument("--expires-at", type=_timestamp, help="ISO-8601, bỏ trống nếu không hết hạn")
    active = parser.add_mutually_exclusive_group()
    active.add_argument("--active", action="store_true", dest="active", default=True)
    active.add_argument("--inactive", action="store_false", dest="active")
    parser.add_argument("--name", default="Quà tặng Gold Rush")
    parser.add_argument("--image-url", default="")
    parser.add_argument("--rarity", default="")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "data" / "qua_tang" / "qr")
    parser.add_argument("--db", type=Path, default=None, help="Ghi vào DB khác thay vì CSDL_PATH")
    return parser


def main() -> int:
    args = _parser().parse_args()
    if args.amount <= 0 or args.max_uses <= 0 or args.per_wallet_limit <= 0:
        raise SystemExit("amount, max-uses và per-wallet-limit phải lớn hơn 0")
    if args.reward_type == "gold":
        if args.token_id not in (None, 0):
            raise SystemExit("Vàng chỉ dùng tokenId = 0")
        token_id = 0
    else:
        if args.token_id is None or not 1 <= args.token_id <= 27:
            raise SystemExit("Vật phẩm phải có tokenId từ 1 đến 27")
        token_id = args.token_id
    if args.db is not None:
        import core.csdl as csdl
        csdl.CSDL_PATH = args.db
    khoi_tao_csdl()
    code = _new_code()
    with lay_csdl() as conn:
        conn.execute(
            """INSERT INTO gift_codes
            (code_hash, reward_type, token_id, amount, name, image_url, rarity, expires_at, max_uses, per_wallet_limit, active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                _hash_ma(code), args.reward_type, token_id, args.amount, args.name,
                args.image_url, args.rarity, args.expires_at, args.max_uses,
                args.per_wallet_limit, int(args.active),
            ),
        )
    output = args.output_dir / f"{code}.png"
    _write_qr_png(code, output)
    expiry = None if args.expires_at is None else datetime.fromtimestamp(args.expires_at, timezone.utc).isoformat()
    print(f"Mã đổi thưởng: {code}")
    print(f"Loại: {args.reward_type} | tokenId: {token_id} | số lượng: {args.amount}")
    print(f"Tổng lượt: {args.max_uses} | mỗi ví: {args.per_wallet_limit} | kích hoạt: {args.active}")
    print(f"Hạn dùng: {expiry or 'không hết hạn'}")
    print(f"QR PNG: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
