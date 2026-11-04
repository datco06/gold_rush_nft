"""Nhật ký ván chơi (telemetry): kiểm tra dữ liệu gửi lên, lưu JSONL, tổng hợp bảng xếp hạng.

Đây là NGUỒN DỮ LIỆU THẬT để huấn luyện lại mô hình độ khó thay cho dữ liệu mô phỏng.
Nguyên tắc dữ liệu cá nhân (Luật Bảo vệ dữ liệu cá nhân 91/2025/QH15):
  * không thu tên thật, email, vị trí GPS, mã thiết bị;
  * `ma_van` là UUID ngẫu nhiên sinh mỗi ván — không nối được các ván với cùng một người;
  * `ten_hien_thi` là biệt danh do người chơi tự gõ, chỉ để hiện trên bảng xếp hạng, có thể bỏ trống.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field


class AnhChup(BaseModel):
    """Ảnh chụp đặc trưng mỗi 10 giây — đúng 5 đặc trưng của hợp đồng trong core/do_kho.py."""
    giay: float = Field(ge=0, le=3600)
    ti_le_mau: float = Field(ge=0, le=1)
    trung_don_moi_phut: float = Field(ge=0, le=100)
    xu_moi_phut: float = Field(ge=0, le=200)
    ti_le_xu: float = Field(ge=0, le=1)
    phut_da_choi: float = Field(ge=0, le=60)


class SuKien(BaseModel):
    loai: Literal["nhat_xu", "trung_don", "ket_thuc"]
    giay: float = Field(ge=0, le=3600)
    x: float = Field(ge=0, le=10000)          # toạ độ thế giới (pixel) — để vẽ bản đồ nhiệt
    y: float = Field(ge=0, le=10000)


class NhatKyVan(BaseModel):
    ma_van: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9-]+$")
    phien_ban_app: str = Field(max_length=20)
    ban_do: str = Field(default="gold_rush.tmx", max_length=60)
    man: int = Field(default=1, ge=1, le=1000)               # id màn trong man_choi.json (bản 1.3)
    ket_qua: Literal["thang", "thua", "bo"]
    giay: float = Field(ge=0, le=3600)
    diem: int = Field(ge=0, le=100000)
    do_kho_thich_ung: bool = False
    ten_hien_thi: str = Field(default="", max_length=20)
    anh_chup: list[AnhChup] = Field(default_factory=list, max_length=400)
    su_kien: list[SuKien] = Field(default_factory=list, max_length=500)
    nhan_luc: str = Field(default="", max_length=40)        # máy chủ GHI ĐÈ lúc lưu — app gửi gì cũng vô nghĩa


def luu(nk: NhatKyVan, thu_muc: Path) -> Path:
    """Ghi thêm một dòng JSON vào tệp của ngày hôm nay (UTC). Mỗi dòng = một ván."""
    thu_muc.mkdir(parents=True, exist_ok=True)
    tep = thu_muc / f"{datetime.now(timezone.utc):%Y-%m-%d}.jsonl"
    dong = nk.model_dump() | {"nhan_luc": datetime.now(timezone.utc).isoformat(timespec="milliseconds")}
    with tep.open("a", encoding="utf-8") as f:
        f.write(json.dumps(dong, ensure_ascii=False) + "\n")
    return tep


def doc_tat_ca(thu_muc: Path) -> list[dict]:
    """Đọc mọi ván đã lưu; bỏ qua dòng hỏng thay vì làm sập cả dashboard."""
    ket_qua = []
    for tep in sorted(Path(thu_muc).glob("*.jsonl")):
        for dong in tep.read_text(encoding="utf-8").splitlines():
            try:
                ket_qua.append(NhatKyVan.model_validate_json(dong).model_dump())
            except ValueError:
                continue
    return ket_qua


def bang_xep_hang(cac_van: list[dict], top: int = 10) -> list[dict]:
    """Điểm cao nhất, hoà điểm thì ai thắng nhanh hơn xếp trên. Ván không tên hiện là 'Ẩn danh'."""
    sap = sorted(cac_van, key=lambda v: (-v["diem"], v["ket_qua"] != "thang", v["giay"]))
    return [{"hang": i + 1, "ten": v["ten_hien_thi"] or "Ẩn danh", "diem": v["diem"],
             "ket_qua": v["ket_qua"], "giay": round(v["giay"], 1)} for i, v in enumerate(sap[:top])]


def thanh_du_lieu_huan_luyen(cac_van: list[dict]):
    """Biến nhật ký thật thành (X, y, nhom) cùng dạng `do_kho.mo_phong()` → dùng lại nguyên `huan_luyen()`.

    Bỏ các ván 'bo' (người chơi thoát giữa chừng): không biết họ sẽ thắng hay thua.
    """
    import numpy as np

    from .do_kho import DAC_TRUNG
    X, y, nhom = [], [], []
    for i, v in enumerate(cac_van):
        if v["ket_qua"] == "bo":
            continue
        for a in v["anh_chup"]:
            X.append([a[k] for k in DAC_TRUNG]); y.append(1 if v["ket_qua"] == "thua" else 0); nhom.append(i)
    return np.array(X, dtype=float), np.array(y), np.array(nhom)


def thong_ke(cac_van: list[dict]) -> dict:
    """Số liệu tổng quan cho dashboard, tách theo có/không bật độ khó thích ứng (để so sánh A/B)."""
    def nhom(vs):
        if not vs:
            return {"so_van": 0}
        xong = [v for v in vs if v["ket_qua"] != "bo"]
        return {
            "so_van": len(vs),
            "ti_le_thang": round(sum(v["ket_qua"] == "thang" for v in xong) / len(xong), 3) if xong else None,
            "ti_le_bo_giua_chung": round(sum(v["ket_qua"] == "bo" for v in vs) / len(vs), 3),
            "giay_trung_binh": round(sum(v["giay"] for v in vs) / len(vs), 1),
            "diem_trung_binh": round(sum(v["diem"] for v in vs) / len(vs), 1),
        }
    return {"tat_ca": nhom(cac_van),
            "co_thich_ung": nhom([v for v in cac_van if v["do_kho_thich_ung"]]),
            "khong_thich_ung": nhom([v for v in cac_van if not v["do_kho_thich_ung"]])}


def loc_su_kien(cac_van: list[dict], loai: str = "trung_don", ban_do: str = "gold_rush.tmx") -> list[dict]:
    """Mọi sự kiện một loại trên một bản đồ — đầu vào cho bản đồ nhiệt."""
    return [e for v in cac_van if v["ban_do"] == ban_do for e in v["su_kien"] if e["loai"] == loai]
