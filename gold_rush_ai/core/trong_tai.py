"""Máy chủ TRỌNG TÀI: kiểm định một ván chơi rồi ký PHIẾU VÀNG (EIP-712) cho ví người chơi.

Vì sao cần trọng tài: game chạy trên máy người chơi. Nếu app tự báo "tôi nhặt 24 xu" rồi gọi
thẳng hợp đồng để đúc vàng, ai mở DevTools cũng đúc được vô hạn. Hợp đồng `CuaHangGoldRush`
vì vậy chỉ nhận vàng kèm chữ ký của một khoá mà CHỈ máy chủ giữ. Máy chủ chỉ ký sau khi đã
kiểm định nhật ký ván chơi bằng chính các công cụ AI cổ điển đã có (BFS/A* trên bản đồ).

Bản 2 (nhiều màn chơi): phiếu ghi thêm `man` và `ve`. Màn có cọc chỉ được cấp phiếu khi người chơi
HOÀN THÀNH (nhặt hết xu trước khi hết giờ) và ván đó đã được đăng ký "bắt đầu" với đúng số vé
(`SoVe`) — mỗi vé chỉ bắt đầu được MỘT lần, nên không thể "mua vé một lần, chơi lại tới khi thắng".

Giới hạn phải nói rõ với sinh viên: nhật ký do app gửi lên. Kẻ gian đủ kiên nhẫn có thể bịa
một nhật ký "hợp lý" (vị trí xu là công khai). Kiểm định chỉ làm gian lận ĐẮT hơn, không làm
nó KHÔNG THỂ. Muốn chặn hẳn phải để máy chủ tự chạy lại ván (game "máy chủ có thẩm quyền")
— xem tài liệu đề xuất, mục lộ trình.
"""
from __future__ import annotations

import heapq
import json
import math
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from .eth_ky import bam_eip712, checksum, dia_chi_tu_khoa, keccak256, ky
from .luoi import KICH_THUOC_O, BanDo
from .man_choi import ManChoi

# ---- Hợp đồng dữ liệu với Solidity: PHẢI khớp CuaHangGoldRush.sol từng ký tự ----
TEN_MIEN, PHIEN_BAN_MIEN = "GoldRush", "2"
PHIEU = [("nguoiChoi", "address"), ("man", "uint256"), ("ve", "uint256"), ("soVang", "uint256"),
         ("maVan", "bytes32"), ("hanChot", "uint256")]

# ---- Thông số kiểm định ----
TOC_DO_GEORGE = 74.0          # px/giây — CauHinh.tocDoGeorge
DUNG_SAI_THOI_GIAN = 1.15     # cho phép nhanh hơn cận dưới 15% (khung hình, làm tròn)
BAN_KINH_NHAT_XU = 20.0       # px — tâm George cách tâm xu khi va chạm
VANG_TOI_DA_MOI_NGAY = 150    # vàng KIẾM được (xu + thưởng, không tính cọc hoàn lại) mỗi ví mỗi ngày

# ---- Đồng hồ thật của máy chủ cho màn có cọc (chống "chơi trước, nộp sau") ----
SAI_SO_DONG_HO = 3            # giây: nhật ký tới sớm hơn thời lượng ván tự khai quá mức này → bịa
HE_SO_TAM_DUNG = 2.0          # cho phép tạm dừng: nhật ký phải tới trong 2 × giới hạn + 60 s kể từ lúc bắt đầu


@dataclass
class KetQuaKiemDinh:
    hop_le: bool
    so_vang: int
    ly_do: list[str]


def _khoang_cach_ngan_nhat(ban_do: BanDo, dau: tuple[int, int]) -> dict[tuple[int, int], float]:
    """Dijkstra 8 hướng (chéo = √2, chỉ đi chéo khi hai ô cạnh đều trống), tính bằng SỐ Ô.

    Dùng làm CẬN DƯỚI cho quãng đường thật: George đi liên tục nên có thể ngắn hơn đường
    qua tâm ô, vì vậy khi dùng sẽ trừ 1 ô và chia thêm dung sai.
    """
    kc = {dau: 0.0}
    hang = [(0.0, dau)]
    while hang:
        d, (c, h) = heapq.heappop(hang)
        if d > kc[(c, h)]:
            continue
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if not dx and not dy:
                    continue
                ke = (c + dx, h + dy)
                if ban_do.bi_chan(*ke):
                    continue
                if dx and dy and (ban_do.bi_chan(c + dx, h) or ban_do.bi_chan(c, h + dy)):
                    continue
                nd = d + (math.sqrt(2) if dx and dy else 1.0)
                if nd < kc.get(ke, math.inf):
                    kc[ke] = nd
                    heapq.heappush(hang, (nd, ke))
    return kc


def kiem_dinh(nhat_ky: dict, ban_do: BanDo, man: ManChoi | None = None) -> KetQuaKiemDinh:
    """Nhật ký một ván (lược đồ NhatKyVan) có đáng tin để trả vàng không.

    `so_vang` trả về = số xu nhặt được + thưởng (nếu hoàn thành màn). Màn có cọc: không hoàn thành
    → không hợp lệ (cọc đã đốt lúc vào màn, không có gì để trả).
    """
    ly_do = []
    nhat = sorted((e for e in nhat_ky["su_kien"] if e["loai"] == "nhat_xu"), key=lambda e: e["giay"])
    so_vang = len(nhat)
    xu = [(c * KICH_THUOC_O + KICH_THUOC_O / 2, h * KICH_THUOC_O + KICH_THUOC_O / 2)
          for c, h in ban_do.cac_diem("coin")]

    if so_vang == 0:
        ly_do.append("Ván không nhặt được xu nào")
    if so_vang > len(xu):
        ly_do.append(f"Nhặt {so_vang} xu nhưng bản đồ chỉ có {len(xu)}")
    hoan_thanh = nhat_ky.get("ket_qua") == "thang" and so_vang == len(xu) > 0
    if man is not None:
        if man.gioi_han_giay and nhat_ky["giay"] > man.gioi_han_giay + 1:
            ly_do.append(f"Ván kéo dài {nhat_ky['giay']:.0f} s, màn {man.id} chỉ cho {man.gioi_han_giay} s")
        if not man.mien_phi and not hoan_thanh:
            ly_do.append(f"Màn {man.id} có cọc: chỉ trả vàng khi nhặt hết {len(xu)} xu (cọc đã mất)")
    if nhat_ky["diem"] != 20 * so_vang:
        ly_do.append(f"Điểm {nhat_ky['diem']} không khớp {so_vang} lần nhặt xu (20 điểm/xu)")
    if nhat and nhat[-1]["giay"] > nhat_ky["giay"] + 1:
        ly_do.append("Sự kiện xảy ra sau khi ván đã kết thúc")

    # 1. Mỗi lần nhặt phải ở sát một đồng xu CÓ THẬT, và mỗi đồng xu chỉ nhặt một lần
    con_lai = list(range(len(xu)))
    o_nhat = []
    for e in nhat:
        if not con_lai:
            break
        gan = min(con_lai, key=lambda i: math.dist((e["x"], e["y"]), xu[i]))
        if math.dist((e["x"], e["y"]), xu[gan]) > BAN_KINH_NHAT_XU:
            ly_do.append(f"Nhặt xu ở ({e['x']:.0f},{e['y']:.0f}) — không có đồng xu nào ở đó")
            break
        con_lai.remove(gan)
        o_nhat.append((int(xu[gan][0] // KICH_THUOC_O), int(xu[gan][1] // KICH_THUOC_O), e["giay"]))

    # 2. Giữa hai lần nhặt phải đủ thời gian để ĐI BỘ tới (không xuyên tường, không dịch chuyển)
    george = ban_do.cac_diem("george")
    if george and o_nhat and not ly_do:
        truoc = (george[0][0], george[0][1], 0.0)
        for diem in o_nhat:
            kc = _khoang_cach_ngan_nhat(ban_do, truoc[:2]).get(diem[:2])
            if kc is None:
                ly_do.append(f"Xu ở ô {diem[:2]} không tới được từ ô {truoc[:2]}")
                break
            can_duoi = max(kc - 1, 0) * KICH_THUOC_O / TOC_DO_GEORGE / DUNG_SAI_THOI_GIAN
            if diem[2] - truoc[2] < can_duoi:
                ly_do.append(f"Từ ô {truoc[:2]} tới ô {diem[:2]} mất "
                             f"{diem[2] - truoc[2]:.1f} s, đi bộ nhanh nhất "
                             f"cũng cần {can_duoi:.1f} s")
                break
            truoc = diem
    if man is not None and hoan_thanh and not ly_do:
        so_vang += man.thuong
    return KetQuaKiemDinh(not ly_do, so_vang, ly_do)


# ---------------------------------------------------------------------------
# Ký phiếu
# ---------------------------------------------------------------------------
def ma_van_bytes32(ma_van: str) -> str:
    """Mã ván UUID (chuỗi) → bytes32 đưa lên chuỗi. Băm để độ dài cố định, không lộ định dạng."""
    return "0x" + keccak256(ma_van.encode()).hex()


def ky_phieu(nguoi_choi: str, man: int, ve: int, so_vang: int, ma_van: str,
             khoa_trong_tai: bytes, chain_id: int, hop_dong: str, han_giay: int = 900,
             bay_gio: int | None = None) -> dict:
    """Tạo và ký phiếu vàng. Trả về dữ liệu đúng dạng tham số `nhanVang(phieu, chuKy)`."""
    if so_vang <= 0 or man <= 0 or ve < 0:
        raise ValueError("Phiếu không hợp lệ")
    bay_gio = bay_gio if bay_gio is not None else int(time.time())
    phieu = {"nguoiChoi": checksum(nguoi_choi), "man": man, "ve": ve, "soVang": so_vang,
             "maVan": ma_van_bytes32(ma_van), "hanChot": bay_gio + han_giay}
    mien = {"name": TEN_MIEN, "version": PHIEN_BAN_MIEN,
            "chainId": chain_id, "verifyingContract": hop_dong}
    bam = bam_eip712(mien, "PhieuVang", PHIEU, phieu)          # đúng _hashTypedDataV4 của OZ
    return {"phieu": phieu, "chu_ky": "0x" + ky(bam, khoa_trong_tai).hex(),
            "bam": "0x" + bam.hex(), "trong_tai": dia_chi_tu_khoa(khoa_trong_tai)}


def la_dia_chi(s: str) -> bool:
    return isinstance(s, str) and len(s) == 42 and s.startswith("0x") and all(
        c in "0123456789abcdefABCDEF" for c in s[2:])


class _SoJsonl:
    def __init__(self, tep: Path):
        self.tep = Path(tep)
        self.tep.parent.mkdir(parents=True, exist_ok=True)

    def _doc(self) -> list[dict]:
        if not self.tep.exists():
            return []
        return [json.loads(d) for d in self.tep.read_text(encoding="utf-8").splitlines() if d.strip()]

    def _them(self, ban_ghi: dict) -> None:
        with self.tep.open("a", encoding="utf-8") as f:
            f.write(json.dumps(ban_ghi) + "\n")


def _hom_nay() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


class SoPhieu(_SoJsonl):
    """Sổ phiếu đã cấp (JSONL). Mỗi ván MỘT bản ghi; xin lại thì KÝ LẠI đúng nội dung cũ với hạn mới.

    Ký lại an toàn vì hợp đồng chặn đổi hai lần (`daDoi[maVan]`). Nhờ vậy lỗi phía người chơi —
    phiếu hết hạn, đóng tab giữa chừng, MetaMask treo — không bao giờ làm mất vàng đã kiếm.
    """

    def lay(self, ma_van: str) -> dict | None:
        return next((p for p in self._doc() if p["ma_van"] == ma_van), None)

    def da_cap(self, ma_van: str) -> bool:
        return self.lay(ma_van) is not None

    def cua_vi(self, vi: str, so_ngay: int = 7) -> list[dict]:
        moc = time.time() - so_ngay * 86400
        return [p for p in self._doc() if p["vi"].lower() == vi.lower() and p.get("luc", 0) >= moc]

    def vang_hom_nay(self, vi: str) -> int:
        ngay = _hom_nay()
        return sum(p["so_vang"] for p in self._doc() if p["vi"].lower() == vi.lower() and p["ngay"] == ngay)

    def ghi(self, ma_van: str, vi: str, so_vang: int, man: int = 1, ve: int = 0) -> None:
        self._them({"ma_van": ma_van, "vi": vi, "so_vang": so_vang, "man": man, "ve": ve,
                    "ngay": _hom_nay(), "luc": int(time.time())})


class SoVe(_SoJsonl):
    """Sổ BẮT ĐẦU màn có cọc: (ví, số vé) → mã ván + thời điểm bắt đầu theo đồng hồ máy chủ."""

    def lay_theo_van(self, ma_van: str) -> dict | None:
        return next((v for v in self._doc() if v["ma_van"] == ma_van), None)

    def da_dung(self, vi: str, ve: int) -> bool:
        return any(v["vi"].lower() == vi.lower() and v["ve"] == ve for v in self._doc())

    def bat_dau(self, ma_van: str, vi: str, man: int, ve: int, luc: float | None = None) -> dict:
        if self.da_dung(vi, ve):
            raise ValueError("Vé này đã dùng để bắt đầu một ván")
        if self.lay_theo_van(ma_van):
            raise ValueError("Mã ván đã được dùng")
        ban_ghi = {"ma_van": ma_van, "vi": vi, "man": man, "ve": ve,
                   "bat_dau": luc if luc is not None else time.time()}
        self._them(ban_ghi)
        return ban_ghi


def kiem_dong_ho(ve: dict, nhat_ky: dict, man: ManChoi) -> list[str]:
    """So thời lượng ván TỰ KHAI với đồng hồ THẬT của máy chủ (lúc nhận nhật ký)."""
    try:
        nhan = datetime.fromisoformat(nhat_ky["nhan_luc"]).timestamp()
    except (KeyError, ValueError):
        return ["Nhật ký thiếu thời điểm máy chủ nhận"]
    troi = nhan - ve["bat_dau"]
    if troi + SAI_SO_DONG_HO < nhat_ky["giay"]:
        return [f"Ván tự khai {nhat_ky['giay']:.0f} s nhưng nhật ký tới sau {troi:.0f} s "
                "kể từ lúc bắt đầu"]
    if troi > HE_SO_TAM_DUNG * man.gioi_han_giay + 60:
        return [f"Nhật ký tới sau {troi:.0f} s — quá lâu so với giới hạn "
                f"{man.gioi_han_giay} s của màn"]
    return []
