"""Mật mã Ethereum tối thiểu, viết thuần Python (không cần thư viện ngoài):

  * keccak256 — hàm băm của Ethereum (KHÁC sha3_256 của hashlib: khác byte đệm);
  * secp256k1 — khoá bí mật → địa chỉ, ký có số phục hồi (v = 27/28), s thấp;
  * EIP-712   — băm dữ liệu có cấu trúc, đúng cách `EIP712._hashTypedDataV4` của OpenZeppelin.

Vì sao tự viết: để sinh viên THẤY từng bước (không phải hộp đen), và để máy chủ trọng tài
chạy được ở bất cứ đâu có Python. Trong sản phẩm thật nên dùng thư viện đã kiểm toán
(`eth-account` của Python, `viem`/`ethers` của JavaScript).

Kiểm chứng: `tests/test_eth_ky.py` so với các véc-tơ kiểm thử công khai — keccak256(""),
địa chỉ tài khoản số 0 của Hardhat, và ví dụ "Mail" trong đặc tả EIP-712 (kể cả chữ ký).
"""
from __future__ import annotations

import hashlib
import hmac

# ---------------------------------------------------------------------------
# keccak256
# ---------------------------------------------------------------------------
_RC = [0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
       0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
       0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
       0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
       0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
       0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]
_ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]
_M = (1 << 64) - 1


def _rol(x: int, n: int) -> int:
    return ((x << n) | (x >> (64 - n))) & _M if n else x


def _keccak_f(A):
    for rc in _RC:
        C = [A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4] for x in range(5)]
        D = [C[(x - 1) % 5] ^ _rol(C[(x + 1) % 5], 1) for x in range(5)]
        A = [[A[x][y] ^ D[x] for y in range(5)] for x in range(5)]
        B = [[0] * 5 for _ in range(5)]
        for x in range(5):
            for y in range(5):
                B[y][(2 * x + 3 * y) % 5] = _rol(A[x][y], _ROT[x][y])
        A = [[B[x][y] ^ ((~B[(x + 1) % 5][y]) & B[(x + 2) % 5][y]) for y in range(5)] for x in range(5)]
        A[0][0] ^= rc
    return A


def keccak256(du_lieu: bytes) -> bytes:
    rate = 136
    p = bytearray(du_lieu) + b"\x01"           # Keccak gốc dùng 0x01; SHA3 chuẩn dùng 0x06
    p += b"\x00" * ((-len(p)) % rate)
    p[-1] |= 0x80
    A = [[0] * 5 for _ in range(5)]
    for i in range(0, len(p), rate):
        for j in range(rate // 8):
            A[j % 5][j // 5] ^= int.from_bytes(p[i + 8 * j:i + 8 * j + 8], "little")
        A = _keccak_f(A)
    return b"".join(A[j % 5][j // 5].to_bytes(8, "little") for j in range(4))


# ---------------------------------------------------------------------------
# secp256k1
# ---------------------------------------------------------------------------
P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _cong(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a[0] == b[0] and (a[1] + b[1]) % P == 0:
        return None
    if a == b:
        l = 3 * a[0] * a[0] * pow(2 * a[1], -1, P) % P
    else:
        l = (b[1] - a[1]) * pow(b[0] - a[0], -1, P) % P
    x = (l * l - a[0] - b[0]) % P
    return x, (l * (a[0] - x) - a[1]) % P


def _nhan(k: int, diem=G):
    kq = None
    while k:
        if k & 1:
            kq = _cong(kq, diem)
        diem = _cong(diem, diem)
        k >>= 1
    return kq


def dia_chi_tu_khoa(khoa_bi_mat: bytes) -> str:
    """Khoá bí mật 32 byte → địa chỉ Ethereum dạng checksum (EIP-55)."""
    x, y = _nhan(int.from_bytes(khoa_bi_mat, "big"))
    return checksum(keccak256(x.to_bytes(32, "big") + y.to_bytes(32, "big"))[-20:].hex())


def checksum(dia_chi_hex: str) -> str:
    a = dia_chi_hex.lower().removeprefix("0x")
    h = keccak256(a.encode()).hex()
    return "0x" + "".join(c.upper() if int(h[i], 16) >= 8 else c for i, c in enumerate(a))


def _k_rfc6979(khoa: int, bam: bytes) -> int:
    """Số ngẫu nhiên k TẤT ĐỊNH (RFC 6979) — không bao giờ dùng random() cho k."""
    x = khoa.to_bytes(32, "big")
    h = (int.from_bytes(bam, "big") % N).to_bytes(32, "big")
    V, K = b"\x01" * 32, b"\x00" * 32
    K = hmac.new(K, V + b"\x00" + x + h, hashlib.sha256).digest()
    V = hmac.new(K, V, hashlib.sha256).digest()
    K = hmac.new(K, V + b"\x01" + x + h, hashlib.sha256).digest()
    V = hmac.new(K, V, hashlib.sha256).digest()
    while True:
        V = hmac.new(K, V, hashlib.sha256).digest()
        k = int.from_bytes(V, "big")
        if 1 <= k < N:
            return k
        K = hmac.new(K, V + b"\x00", hashlib.sha256).digest()
        V = hmac.new(K, V, hashlib.sha256).digest()


def ky(bam: bytes, khoa_bi_mat: bytes) -> bytes:
    """Ký bản băm 32 byte → 65 byte r‖s‖v, v ∈ {27, 28}, s nằm nửa dưới (OpenZeppelin chỉ nhận s thấp)."""
    d = int.from_bytes(khoa_bi_mat, "big")
    z = int.from_bytes(bam, "big")
    k = _k_rfc6979(d, bam)
    R = _nhan(k)
    r = R[0] % N
    s = pow(k, -1, N) * (z + r * d) % N
    v = R[1] & 1
    if s > N // 2:                       # chống "dễ uốn" (malleability): đổi sang s thấp, lật v
        s, v = N - s, v ^ 1
    return r.to_bytes(32, "big") + s.to_bytes(32, "big") + bytes([27 + v])


def phuc_hoi(bam: bytes, chu_ky: bytes) -> str:
    """Từ bản băm + chữ ký suy ra địa chỉ người ký — đúng việc `ecrecover` làm trên chuỗi."""
    r, s, v = int.from_bytes(chu_ky[:32], "big"), int.from_bytes(chu_ky[32:64], "big"), chu_ky[64] - 27
    x = r
    y = pow((x * x * x + 7) % P, (P + 1) // 4, P)
    if y & 1 != v:
        y = P - y
    z = int.from_bytes(bam, "big")
    rinv = pow(r, -1, N)
    Q = _cong(_nhan(s * rinv % N, (x, y)), _nhan((-z * rinv) % N))
    return checksum(keccak256(Q[0].to_bytes(32, "big") + Q[1].to_bytes(32, "big"))[-20:].hex())


# ---------------------------------------------------------------------------
# EIP-712 (chỉ những kiểu tĩnh cần dùng: address, uintN, bytes32, string)
# ---------------------------------------------------------------------------
def _ma_hoa_gia_tri(kieu: str, gia_tri) -> bytes:
    if kieu == "string":
        return keccak256(gia_tri.encode("utf-8"))
    if kieu == "bytes32":
        b = bytes.fromhex(gia_tri.removeprefix("0x")) if isinstance(gia_tri, str) else gia_tri
        if len(b) != 32:
            raise ValueError("bytes32 phải đúng 32 byte")
        return b
    if kieu == "address":
        return int(gia_tri, 16).to_bytes(32, "big")
    if kieu.startswith("uint"):
        if not 0 <= int(gia_tri) < 2 ** int(kieu[4:] or 256):
            raise ValueError(f"{gia_tri} vượt phạm vi {kieu}")
        return int(gia_tri).to_bytes(32, "big")
    raise ValueError(f"Chưa hỗ trợ kiểu {kieu}")


def chuoi_kieu(ten: str, truong: list[tuple[str, str]]) -> str:
    """'PhieuVang(address nguoiChoi,uint256 soVang,...)' — phải KHỚP TỪNG KÝ TỰ với Solidity."""
    return f"{ten}(" + ",".join(f"{k} {t}" for t, k in truong) + ")"


def bam_cau_truc(ten: str, truong: list[tuple[str, str]], gia_tri: dict) -> bytes:
    """hashStruct = keccak256(typeHash ‖ encodeData) — chỉ cho struct không lồng nhau."""
    du_lieu = keccak256(chuoi_kieu(ten, truong).encode())
    for t, k in truong:
        du_lieu += _ma_hoa_gia_tri(k, gia_tri[t])
    return keccak256(du_lieu)


MIEN = [("name", "string"), ("version", "string"), ("chainId", "uint256"), ("verifyingContract", "address")]


def bam_eip712(mien: dict, ten: str, truong: list[tuple[str, str]], gia_tri: dict) -> bytes:
    """Bản băm cuối cùng để ký = keccak256(0x1901 ‖ domainSeparator ‖ hashStruct)."""
    return keccak256(b"\x19\x01" + bam_cau_truc("EIP712Domain", MIEN, mien) + bam_cau_truc(ten, truong, gia_tri))
