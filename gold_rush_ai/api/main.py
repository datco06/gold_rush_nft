"""FastAPI backend cho Gold Rush — cùng khuôn với `api/main.py` của notebook AI Web Apps.

Chạy:  uvicorn api.main:app --reload --port 8000      (tài liệu tương tác: /docs)

| Method | Endpoint               | Việc                                                       |
|--------|------------------------|------------------------------------------------------------|
| GET    | /api/health            | trạng thái, thành phần nào đã nạp                           |
| POST   | /api/nhat-ky           | app gửi nhật ký một ván (telemetry)                        |
| GET    | /api/bang-xep-hang     | top điểm cao                                               |
| GET    | /api/thong-ke          | số liệu tổng quan, tách theo bật/tắt độ khó thích ứng       |
| GET    | /api/su-kien           | sự kiện (vd. trúng đòn) kèm toạ độ — vẽ bản đồ nhiệt       |
| POST   | /api/do-kho/du-doan    | dự đoán xác suất thua từ 5 đặc trưng (kiểm tra chéo với app)|
| GET    | /api/mo-hinh/do-kho    | tải tệp mô hình hiện hành (app cập nhật mô hình không cần phát hành lại) |
| GET    | /api/ban-do/sinh       | sinh bản đồ .tmx mới theo seed                             |
| POST   | /api/tro-ly            | trợ lý gợi ý cách chơi (RAG rút gọn)                        |
| GET    | /api/man               | danh sách màn chơi (man_choi.json)                          |
| POST   | /api/man/bat-dau       | đăng ký bắt đầu màn có cọc: (ví, số vé) → mã ván, MỘT lần    |
| GET    | /api/man/ve            | vé (ví, số vé) đã dùng để bắt đầu ván nào chưa                |
| GET    | /api/vang/cau-hinh     | chainId, địa chỉ hợp đồng, địa chỉ trọng tài (app hiển thị)   |
| POST   | /api/vang/phieu        | kiểm định ván → ký PHIẾU VÀNG EIP-712 (xin lại = ký lại)     |
| GET    | /api/vang/cho-nhan     | mọi phiếu đã cấp cho một ví trong 7 ngày (ký lại hạn mới)    |
"""
import json
import logging
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # import được config, core khi chạy uvicorn

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field

from config import (BAN_DO_DIR, CHAIN_ID, CORS_ORIGINS, ENABLED, HOP_DONG_CUA_HANG, KB_DIR, MAN_CHOI,
                    MAX_NHAT_KY_KB, MO_HINH_DO_KHO, NHAT_KY_DIR, SO_PHIEU, SO_VE, TRONG_TAI_KHOA)
from core import do_kho, man_choi, nhat_ky, sinh_ban_do, trong_tai
from core.eth_ky import dia_chi_tu_khoa
from core.luoi import doc_tmx
from core.tro_ly import TroLy

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("api")
STATE: dict = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Nạp MỘT LẦN lúc khởi động; một thành phần lỗi không làm sập cả server
    if "do_kho" in ENABLED:
        try:
            STATE["do_kho"] = json.loads(MO_HINH_DO_KHO.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            log.error("không nạp được mô hình độ khó %s: %s", MO_HINH_DO_KHO, e)
    if "vang" in ENABLED:
        try:
            STATE["man_choi"] = man_choi.doc(MAN_CHOI)
            for loi in man_choi.kiem_tra_khop_ban_do(STATE["man_choi"], BAN_DO_DIR):
                log.error("man_choi.json: %s", loi)
        except (OSError, ValueError, TypeError) as e:
            log.error("không nạp được danh sách màn %s: %s", MAN_CHOI, e)
    if "tro_ly" in ENABLED:
        try:
            STATE["tro_ly"] = TroLy(KB_DIR)
        except (OSError, ValueError) as e:
            log.error("không nạp được kho tri thức %s: %s", KB_DIR, e)
    yield
    STATE.clear()


app = FastAPI(title="Gold Rush AI API", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=CORS_ORIGINS, allow_methods=["*"], allow_headers=["*"])


@app.middleware("http")
async def do_thoi_gian(request: Request, call_next):
    t0 = time.perf_counter()
    response = await call_next(request)
    response.headers["X-Process-Time-ms"] = f"{(time.perf_counter() - t0) * 1000:.1f}"
    return response


def _can(ten: str):
    if ten not in ENABLED:
        raise HTTPException(404, f"Thành phần '{ten}' đang tắt (biến ENABLED)")
    if ten in ("do_kho", "tro_ly") and ten not in STATE:
        raise HTTPException(503, f"'{ten}' chưa nạp được — xem log và /api/health")


@app.get("/api/health")
def health():
    return {"status": "ok", "bat": sorted(ENABLED),
            "da_nap": {"do_kho": "do_kho" in STATE, "tro_ly": "tro_ly" in STATE},
            "phien_ban_mo_hinh": STATE.get("do_kho", {}).get("phien_ban")}


# ---------- Nhật ký & bảng xếp hạng ----------
@app.post("/api/nhat-ky", status_code=201)
async def nhan_nhat_ky(request: Request):
    _can("nhat_ky")
    than = await request.body()
    if len(than) > MAX_NHAT_KY_KB * 1024:
        raise HTTPException(413, f"Nhật ký vượt quá {MAX_NHAT_KY_KB} KB")
    try:
        nk = nhat_ky.NhatKyVan.model_validate_json(than)
    except ValueError as e:
        raise HTTPException(422, f"Nhật ký không hợp lệ: {e}")
    # Idempotent: app gửi lại khi mạng chập chờn → không lưu trùng, không ghi đè bản đầu
    if any(v["ma_van"] == nk.ma_van for v in nhat_ky.doc_tat_ca(NHAT_KY_DIR)):
        return {"da_luu": True, "ma_van": nk.ma_van, "trung": True}
    nhat_ky.luu(nk, NHAT_KY_DIR)
    return {"da_luu": True, "ma_van": nk.ma_van}


@app.get("/api/bang-xep-hang")
def xep_hang(top: int = Query(10, ge=1, le=100)):
    _can("nhat_ky")
    return {"bang": nhat_ky.bang_xep_hang(nhat_ky.doc_tat_ca(NHAT_KY_DIR), top)}


@app.get("/api/thong-ke")
def thong_ke():
    _can("nhat_ky")
    return nhat_ky.thong_ke(nhat_ky.doc_tat_ca(NHAT_KY_DIR))


@app.get("/api/su-kien")
def su_kien(loai: str = Query("trung_don", pattern="^(nhat_xu|trung_don|ket_thuc)$"),
            ban_do: str = Query("gold_rush.tmx", max_length=60)):
    _can("nhat_ky")
    return {"su_kien": nhat_ky.loc_su_kien(nhat_ky.doc_tat_ca(NHAT_KY_DIR), loai, ban_do)}


# ---------- Mô hình độ khó ----------
class YeuCauDoKho(BaseModel):
    dac_trung: list[float] = Field(min_length=len(do_kho.DAC_TRUNG), max_length=len(do_kho.DAC_TRUNG))


@app.post("/api/do-kho/du-doan")
def du_doan_do_kho(yc: YeuCauDoKho):
    _can("do_kho")
    mh = STATE["do_kho"]
    p = do_kho.du_doan(mh, yc.dac_trung)
    return {"p_thua": round(p, 6), "he_so_toc_do": round(do_kho.he_so_toc_do(p), 4),
            "phien_ban": mh["phien_ban"], "dac_trung": mh["dac_trung"]}


@app.get("/api/mo-hinh/do-kho")
def tai_mo_hinh():
    _can("do_kho")
    return FileResponse(MO_HINH_DO_KHO, media_type="application/json", filename=MO_HINH_DO_KHO.name)


# ---------- Sinh bản đồ ----------
@app.get("/api/ban-do/sinh")
def sinh_ban_do_moi(seed: int = Query(0, ge=0, le=10**9), mat_do: float = Query(0.42, ge=0.30, le=0.48)):
    _can("ban_do")
    try:
        kq = sinh_ban_do.sinh(seed=seed, mat_do=mat_do)
    except ValueError as e:                      # bản đồ quá chật để đặt kẻ địch
        raise HTTPException(422, str(e))
    return Response(sinh_ban_do.thanh_tmx(kq), media_type="application/xml",
                    headers={"X-Chi-So": json.dumps(kq["chi_so"]),
                             "Content-Disposition": f'attachment; filename="gold_rush_{seed}.tmx"'})


# ---------- Trợ lý ----------
class CauHoi(BaseModel):
    cau_hoi: str = Field(min_length=1, max_length=300)


@app.post("/api/tro-ly")
def tro_ly(yc: CauHoi):
    _can("tro_ly")
    return STATE["tro_ly"].hoi(yc.cau_hoi)


# ---------- Màn chơi + vàng → phiếu ký cho hợp đồng CuaHangGoldRush ----------
def _cac_man() -> dict:
    _can("vang")
    if "man_choi" not in STATE:
        raise HTTPException(503, "Chưa nạp được man_choi.json — xem log máy chủ")
    return STATE["man_choi"]


def _khoa_trong_tai() -> bytes:
    _can("vang")
    if not TRONG_TAI_KHOA or not trong_tai.la_dia_chi(HOP_DONG_CUA_HANG):
        raise HTTPException(503, "Chưa cấu hình TRONG_TAI_KHOA / HOP_DONG_CUA_HANG")
    return bytes.fromhex(TRONG_TAI_KHOA.removeprefix("0x"))


@app.get("/api/man")
def danh_sach_man():
    return {"man": [vars(m) | {"thuong_toi_da": m.thuong_toi_da} for m in _cac_man().values()]}


@app.get("/api/vang/cau-hinh")
def cau_hinh_vang():
    khoa = _khoa_trong_tai()
    return {"chain_id": CHAIN_ID, "hop_dong": HOP_DONG_CUA_HANG, "trong_tai": dia_chi_tu_khoa(khoa)}


MA_VAN = r"^[A-Za-z0-9-]+$"
DIA_CHI = r"^0x[0-9a-fA-F]{40}$"


class YeuCauBatDau(BaseModel):
    ma_van: str = Field(min_length=8, max_length=64, pattern=MA_VAN)
    vi: str = Field(min_length=42, max_length=42, pattern=DIA_CHI)
    man: int = Field(ge=1, le=1000)
    ve: int = Field(ge=1)


@app.post("/api/man/bat-dau", status_code=201)
def bat_dau_man(yc: YeuCauBatDau):
    """App gọi NGAY TRƯỚC khi thả George vào màn có cọc, sau khi giao dịch vaoMan đã vào khối.

    Máy chủ không đọc chuỗi: nếu vé là bịa thì phiếu cấp ra cũng bị hợp đồng từ chối (SaiVe).
    """
    m = _cac_man().get(yc.man)
    if m is None:
        raise HTTPException(404, f"Không có màn {yc.man}")
    if m.mien_phi:
        raise HTTPException(422, f"Màn {yc.man} là màn luyện tập, không cần vé")
    try:
        trong_tai.SoVe(SO_VE).bat_dau(yc.ma_van, yc.vi, yc.man, yc.ve)
    except ValueError as e:
        raise HTTPException(409, str(e))
    return {"da_bat_dau": True, "gioi_han_giay": m.gioi_han_giay}


@app.get("/api/man/ve")
def ve_da_dung(vi: str = Query(min_length=42, max_length=42, pattern=DIA_CHI), ve: int = Query(ge=1)):
    _cac_man()
    return {"da_dung": trong_tai.SoVe(SO_VE).da_dung(vi, ve)}


class YeuCauPhieu(BaseModel):
    ma_van: str = Field(min_length=8, max_length=64, pattern=MA_VAN)
    vi: str = Field(min_length=42, max_length=42, pattern=DIA_CHI)


def _ky(khoa: bytes, ban_ghi: dict) -> dict:
    return trong_tai.ky_phieu(ban_ghi["vi"], ban_ghi.get("man", 1), ban_ghi.get("ve", 0),
                              ban_ghi["so_vang"], ban_ghi["ma_van"], khoa, CHAIN_ID, HOP_DONG_CUA_HANG)


@app.post("/api/vang/phieu")
def cap_phieu(yc: YeuCauPhieu):
    khoa = _khoa_trong_tai()
    cac_man = _cac_man()
    so = trong_tai.SoPhieu(SO_PHIEU)
    cu = so.lay(yc.ma_van)
    if cu is not None:                                       # xin lại: ký lại đúng nội dung, hạn mới
        if cu["vi"].lower() != yc.vi.lower():
            raise HTTPException(409, "Ván này đã cấp phiếu cho một ví khác")
        return _ky(khoa, cu)

    van = next((v for v in nhat_ky.doc_tat_ca(NHAT_KY_DIR) if v["ma_van"] == yc.ma_van), None)
    if van is None:
        raise HTTPException(404, "Không có nhật ký của ván này (app đã gửi /api/nhat-ky chưa?)")
    m = cac_man.get(van["man"])
    if m is None:
        raise HTTPException(422, f"Không có màn {van['man']}")
    if Path(van["ban_do"]).name != m.tep:
        raise HTTPException(422, f"Màn {m.id} dùng bản đồ {m.tep}, nhật ký ghi {van['ban_do']}")
    tep_ban_do = BAN_DO_DIR / m.tep
    if not tep_ban_do.exists():
        raise HTTPException(422, f"Máy chủ không có bản đồ {m.tep}")

    kq = trong_tai.kiem_dinh(van, doc_tmx(tep_ban_do), m)
    ly_do = list(kq.ly_do)
    ve = 0
    if not m.mien_phi:
        bd = trong_tai.SoVe(SO_VE).lay_theo_van(yc.ma_van)
        if bd is None or bd["vi"].lower() != yc.vi.lower() or bd["man"] != m.id:
            ly_do.append("Ván màn có cọc chưa được đăng ký bắt đầu với ví này")
        else:
            ly_do += trong_tai.kiem_dong_ho(bd, van, m)
            ve = bd["ve"]
    if ly_do:
        log.warning("từ chối phiếu %s: %s", yc.ma_van, ly_do)
        raise HTTPException(422, {"ly_do": ly_do})
    if so.vang_hom_nay(yc.vi) + kq.so_vang > trong_tai.VANG_TOI_DA_MOI_NGAY:
        raise HTTPException(429, f"Ví đã nhận đủ {trong_tai.VANG_TOI_DA_MOI_NGAY} vàng hôm nay")
    so.ghi(yc.ma_van, yc.vi, kq.so_vang, m.id, ve)
    return _ky(khoa, so.lay(yc.ma_van))


@app.get("/api/vang/cho-nhan")
def phieu_cho_nhan(vi: str = Query(min_length=42, max_length=42, pattern=DIA_CHI)):
    """Mọi phiếu đã cấp cho ví này trong 7 ngày, ký lại với hạn mới.

    Máy chủ không biết phiếu nào đã nộp lên chuỗi — app tự lọc bằng `daDoi(maVan)` (và `ve(vi)` với màn
    có cọc). Nhờ đó tải lại trang, đổi máy, MetaMask treo… đều không làm mất vàng đã kiếm.
    """
    khoa = _khoa_trong_tai()
    return {"phieu": [_ky(khoa, p) | {"ma_van": p["ma_van"]} for p in trong_tai.SoPhieu(SO_PHIEU).cua_vi(vi)]}
