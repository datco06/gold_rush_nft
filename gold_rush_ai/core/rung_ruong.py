"""Quay phần thưởng rương và ký phiếu để CuaHangGoldRush thực thi on-chain."""
from __future__ import annotations

import secrets
import time
import uuid

from .eth_ky import bam_eip712, checksum, dia_chi_tu_khoa, keccak256, ky

TEN_MIEN, PHIEN_BAN_MIEN = "GoldRush", "2"
PHIEU_MO_RUONG = [
    ("nguoiChoi", "address"),
    ("loai", "uint256"),
    ("giaTri", "uint256"),
    ("soLuong", "uint256"),
    ("maRuong", "bytes32"),
    ("hanChot", "uint256"),
]

# 0..7999: vàng (80%), 8000..9499: giáp/giày hiếm (15%), còn lại: súng hiếm (5%).
_VANG = ((4000, 150), (2400, 400), (800, 700), (400, 1000), (400, 50000))
_GIAP_GIAY_HIEM = (16, 17, 18, 25, 26, 27)
_SUNG_HIEM = (7, 8, 9)


def quay_phan_thuong() -> dict:
    """Backend là nơi duy nhất chọn kết quả theo đúng tỷ lệ đã công bố."""
    moc = secrets.randbelow(10000)
    if moc < 8000:
        con_lai = moc
        for do_rong, so_vang in _VANG:
            if con_lai < do_rong:
                return {"loai": "vang", "gia_tri": so_vang, "so_luong": 0, "token_id": 0}
            con_lai -= do_rong
    if moc < 9500:
        return {"loai": "vat_pham", "gia_tri": secrets.choice(_GIAP_GIAY_HIEM), "so_luong": 1, "token_id": 1}
    return {"loai": "vat_pham", "gia_tri": secrets.choice(_SUNG_HIEM), "so_luong": 1, "token_id": 1}


def ky_phieu_mo_ruong(
    nguoi_choi: str,
    phan_thuong: dict,
    khoa_trong_tai: bytes,
    chain_id: int,
    hop_dong: str,
    han_giay: int = 180,
    bay_gio: int | None = None,
) -> dict:
    """Tạo phiếu `moRuong` khớp struct Solidity, không để Flutter tự chọn thưởng."""
    bay_gio = bay_gio if bay_gio is not None else int(time.time())
    ma_ruong = "0x" + keccak256(f"ruong-{uuid.uuid4().hex}".encode()).hex()
    phieu = {
        "nguoiChoi": checksum(nguoi_choi),
        "loai": 0 if phan_thuong["loai"] == "vang" else 1,
        "giaTri": int(phan_thuong["gia_tri"]),
        "soLuong": int(phan_thuong["so_luong"]),
        "maRuong": ma_ruong,
        "hanChot": bay_gio + han_giay,
    }
    mien = {
        "name": TEN_MIEN,
        "version": PHIEN_BAN_MIEN,
        "chainId": chain_id,
        "verifyingContract": hop_dong,
    }
    bam = bam_eip712(mien, "PhieuMoRuong", PHIEU_MO_RUONG, phieu)
    return {
        "phieu": phieu,
        "chu_ky": "0x" + ky(bam, khoa_trong_tai).hex(),
        "bam": "0x" + bam.hex(),
        "trong_tai": dia_chi_tu_khoa(khoa_trong_tai),
    }
