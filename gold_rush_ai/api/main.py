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
| POST   | /api/ai/nhiem-vu/tao   | tạo nhiệm vụ, lưu lịch sử và xử lý retry                    |
| GET    | /api/man               | danh sách màn chơi (man_choi.json)                          |
| POST   | /api/man/bat-dau       | đăng ký bắt đầu màn có cọc: (ví, số vé) → mã ván, MỘT lần    |
| GET    | /api/man/ve            | vé (ví, số vé) đã dùng để bắt đầu ván nào chưa                |
| GET    | /api/vang/cau-hinh     | chainId, địa chỉ hợp đồng, địa chỉ trọng tài (app hiển thị)   |
| POST   | /api/vang/phieu        | kiểm định ván → ký PHIẾU VÀNG EIP-712 (xin lại = ký lại)     |
| GET    | /api/vang/cho-nhan     | mọi phiếu đã cấp cho một ví trong 7 ngày (ký lại hạn mới)    |
"""
import json
import logging
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from ipaddress import ip_address
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))   # import được config, core khi chạy uvicorn

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field
from alembic.config import Config as AlembicConfig
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import inspect, select
from starlette.responses import JSONResponse

from auth.config import AuthConfigError, load_auth_config
from auth.database import create_auth_engine, create_session_factory
from auth.models import Base
from auth.router import create_auth_router
from auth.service import AuthService
from api.auth_adapter import tich_hop_auth_vao_app

from config import (BAN_DO_DIR, CHAIN_ID, CORS_ORIGINS, ENABLED, HOP_DONG_CUA_HANG, KB_DIR, MAN_CHOI,
                    MAX_NHAT_KY_KB, MO_HINH_DO_KHO, NHAT_KY_DIR, SO_PHIEU, SO_VE, TRONG_TAI_KHOA)
from api.auth_guard import kiem_tra_csrf_va_origin, lay_nguoi_choi_hien_tai, NguoiChoiXacThuc
from core import do_kho, man_choi, nhat_ky, sinh_ban_do, trong_tai
from core.csdl import khoi_tao_csdl, lay_csdl
from core.eth_ky import dia_chi_tu_khoa
from core.luoi import doc_tmx
from core.quan_ly_nhiem_vu import cap_nhat_tien_do
from core.tro_ly import TroLy
from core.xac_minh_ve_onchain import (
    XacMinhVeOnchain,
    LoiCauHinhVe,
    LoiKetNoiRPC,
    LoiVeKhongHopLe,
    LoiXacMinhVe,
)

from api.ban_do_moi import router as ban_do_router
from api.kho_do import router as kho_do_router
from api.nhiem_vu import router as nhiem_vu_router
from api.tien_trinh import router as tien_trinh_router
from api.thanh_tuu import router as thanh_tuu_router

from api.ai_nhiem_vu import khoi_dong_nhiem_vu, nhiem_vu_da_nap, router as router_nhiem_vu
from api.de_xuat_do_kho import (de_xuat_do_kho_da_nap, khoi_dong_de_xuat_do_kho,
                                 router as router_de_xuat_do_kho)
from api.nhan_vat_ai import khoi_dong_nhan_vat_ai, nhan_vat_ai_da_nap, router as router_nhan_vat_ai
from api.ai_tien_trinh import khoi_dong_tien_trinh, tien_trinh_da_nap, router as router_tien_trinh

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("api")
STATE: dict = {}
_BACKEND_DIRECTORY = Path(__file__).resolve().parents[1]


def _is_loopback(host: str) -> bool:
    if host == "localhost":
        return True
    try:
        return ip_address(host).is_loopback
    except ValueError:
        return False


def _cho_phep_private_network(config=None) -> bool:
    """Xác định có cho phép CORS Private Network Access hay không.

    Quy định bảo mật:
    - CHỈ cho phép trong môi trường phát triển cục bộ (local development).
    - TUYỆT ĐỐI KHÔNG tự động bật trong môi trường production/live hoặc khi dùng cookie_secure=True (HTTPS).
    - Nếu biến môi trường CORS_ALLOW_PRIVATE_NETWORK được đặt rõ:
        - "true" / "1": cho phép (chỉ khi không ở production).
        - "false" / "0": từ chối hoàn toàn.
    - Mặc định local dev: cho phép nếu không có cờ production, cookie không yêu cầu secure,
      và tất cả origin trong allowlist đều thuộc localhost/loopback.
    """
    env = os.environ.get("ENVIRONMENT", "").strip().lower()
    app_env = os.environ.get("APP_ENV", "").strip().lower()
    node_env = os.environ.get("NODE_ENV", "").strip().lower()
    if any(p in (env, app_env, node_env) for p in ("prod", "production", "live")):
        return False

    explicit = os.environ.get("CORS_ALLOW_PRIVATE_NETWORK", "").strip().lower()
    if explicit in ("false", "0"):
        return False
    if explicit in ("true", "1"):
        return True

    if config is not None:
        if getattr(config, "cookie_secure", False):
            return False
        for origin in getattr(config, "cors_origins", ()):
            parsed = urlsplit(origin)
            host = parsed.hostname or ""
            if parsed.scheme != "http" or not _is_loopback(host):
                return False
        return True

    for origin in CORS_ORIGINS:
        try:
            parsed = urlsplit(origin.strip())
            host = parsed.hostname or ""
            if parsed.scheme != "http" or not _is_loopback(host):
                return False
        except Exception:
            return False
    return True


class _LifespanCORSMiddleware:
    """Use the validated startup snapshot, without loading secrets on import.

    Starlette constructs middleware before entering lifespan. Delegate HTTP to
    its standard CORSMiddleware once AuthConfig is available; refresh the cache
    for a later lifespan. No requests are served without a successful startup.
    """

    def __init__(self, app):
        self.app = app
        self._config = None
        self._cors = None
        self._allow_pn = None

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        config = getattr(scope["app"].state, "auth_config", None)
        allow_pn = _cho_phep_private_network(config)
        if config is None:
            if "auth" in ENABLED or "AUTH_CSRF_SECRET" in os.environ:
                response = JSONResponse(
                    status_code=503,
                    content={"detail": {"code": "AUTH_UNAVAILABLE", "message": "Auth chưa khởi tạo thành công."}},
                    headers={"Cache-Control": "no-store"},
                )
                await response(scope, receive, send)
                return
            if self._cors is None or self._allow_pn != allow_pn:
                self._cors = CORSMiddleware(
                    self.app,
                    allow_origins=CORS_ORIGINS,
                    allow_methods=["*"],
                    allow_headers=["*"],
                    allow_private_network=allow_pn,
                )
                self._allow_pn = allow_pn
            await self._cors(scope, receive, send)
            return
        if config is not self._config or self._allow_pn != allow_pn:
            self._cors = CORSMiddleware(
                self.app,
                allow_origins=list(config.cors_origins),
                allow_credentials=True,
                allow_methods=["GET", "POST", "OPTIONS"],
                allow_headers=[
                    "Content-Type",
                    "X-CSRF-Token",
                    "X-Gold-Rush-Auth",
                    "Idempotency-Key",
                    "X-Demo-Player",
                ],
                allow_private_network=allow_pn,
            )
            self._config = config
            self._allow_pn = allow_pn
        await self._cors(scope, receive, send)


def _check_auth_database(engine):
    """Read schema/revision only; never create a DB, tables or run migrations."""
    try:
        if engine.dialect.name == "sqlite":
            database = engine.url.database
            if database in (None, "", ":memory:") or not Path(database).is_file():
                raise ValueError("Auth requires an existing migrated database.")
        expected = set(ScriptDirectory.from_config(
            AlembicConfig(str(_BACKEND_DIRECTORY / "alembic.ini")),
        ).get_heads())
        with engine.connect() as connection:
            tables = set(inspect(connection).get_table_names())
            if not expected or not (set(Base.metadata.tables) | {"alembic_version"}) <= tables:
                raise ValueError("Auth schema is missing.")
            if set(MigrationContext.configure(connection).get_current_heads()) != expected:
                raise ValueError("Auth schema revision is not current.")
            # Also detect missing columns without reading any account data.
            for table in Base.metadata.sorted_tables:
                connection.execute(select(table).limit(0)).close()
    except Exception:
        # Driver/SQL exceptions can include connection strings or credentials.
        raise RuntimeError(
            "AUTH_DATABASE_NOT_READY: kiểm tra AUTH_DATABASE_URL, driver, quyền truy cập "
            "và schema; chạy Alembic upgrade head riêng trước khi khởi động."
        ) from None


@asynccontextmanager
async def _game_lifespan(app: FastAPI):
    # Khởi tạo CSDL SQLite nếu chưa có
    try:
        khoi_tao_csdl()
        log.info("CSDL SQLite đã được khởi tạo/sẵn sàng")
    except Exception as e:
        log.error("Không khởi tạo được CSDL SQLite: %s", e)

    # Nạp MỘT LẦN lúc khởi động; một thành phần lỗi không làm sập cả server
    khoi_dong_nhiem_vu(app)
    khoi_dong_de_xuat_do_kho(app)
    khoi_dong_nhan_vat_ai(app)
    khoi_dong_tien_trinh(app)
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
    try:
        yield
    finally:
        STATE.clear()
        app.state.nhiem_vu = None
        app.state.de_xuat_do_kho = None
        app.state.nhan_vat_ai = None
        app.state.kho_tien_trinh = None
        app.state.dich_vu_tien_trinh = None
        app.state.ai_player_source = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    auth_enabled = (
        "auth" in ENABLED
        or "AUTH_CSRF_SECRET" in os.environ
        or "AUTH_DATABASE_URL" in os.environ
    )
    if not auth_enabled:
        async with _game_lifespan(app):
            yield
        return

    try:
        auth_cfg = load_auth_config()
    except AuthConfigError as error:
        raise RuntimeError(f"AUTH_CONFIG_INVALID: {error}") from None

    try:
        options = {"base_directory": _BACKEND_DIRECTORY} if auth_cfg.database_url.startswith("sqlite") else {}
        engine = create_auth_engine(auth_cfg, **options)
    except Exception:
        raise RuntimeError("AUTH_DATABASE_NOT_READY: kiểm tra AUTH_DATABASE_URL và driver đồng bộ đã cài.") from None

    mounted = []
    try:
        _check_auth_database(engine)
        factory = create_session_factory(engine)
        router = create_auth_router(auth_cfg, factory)
        auth_service = AuthService(auth_cfg, factory)
        tich_hop_auth_vao_app(app, auth_service, auth_cfg)
        previous = {id(route) for route in app.router.routes}
        app.include_router(router)
        mounted = [route for route in app.router.routes if id(route) not in previous]
        app.openapi_schema = None
        app.state.auth_engine = engine
        app.state.auth_session_factory = factory
        app.state.auth_config = auth_cfg
        app.state.auth_service = auth_service
        async with _game_lifespan(app):
            yield
    finally:
        mounted_ids = {id(route) for route in mounted}
        app.router.routes[:] = [route for route in app.router.routes if id(route) not in mounted_ids]
        app.openapi_schema = None
        for name in ("auth_config", "auth_session_factory", "auth_engine", "auth_service", "ai_auth_source"):
            if hasattr(app.state, name):
                delattr(app.state, name)
        try:
            engine.dispose()
        except Exception:
            raise RuntimeError("AUTH_DATABASE_SHUTDOWN_FAILED: không đóng được Engine Auth.") from None


app = FastAPI(title="Gold Rush AI API", version="1.0.0", lifespan=lifespan)
app.add_middleware(_LifespanCORSMiddleware)

# Đăng ký các router mở rộng (Tiến trình, Kho đồ, Nhiệm vụ, Bản đồ)
app.include_router(tien_trinh_router)
app.include_router(thanh_tuu_router)
app.include_router(kho_do_router)
app.include_router(nhiem_vu_router)
app.include_router(ban_do_router)

# Đăng ký các router AI
app.include_router(router_nhiem_vu)
app.include_router(router_de_xuat_do_kho)
app.include_router(router_nhan_vat_ai)
app.include_router(router_tien_trinh)


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
def health(request: Request):
    return {"status": "ok", "bat": sorted(ENABLED),
            "da_nap": {"do_kho": "do_kho" in STATE, "tro_ly": "tro_ly" in STATE,
                       "nhiem_vu": nhiem_vu_da_nap(request.app),
                       "de_xuat_do_kho": de_xuat_do_kho_da_nap(request.app),
                       "nhan_vat_ai": nhan_vat_ai_da_nap(request.app),
                       "tien_trinh": tien_trinh_da_nap(request.app)},
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

    # Lưu dữ liệu trận đấu vào CSDL phục vụ đối soát trọng tài và thống kê
    # Telemetry KHÔNG tự động cấp EXP, mở khóa màn hay ghi nhận nhiệm vụ nếu chưa qua xác thực SIWE
    try:
        with lay_csdl() as conn:
            so_xu_nhat = len([e for e in nk.su_kien if e.loai == "nhat_xu"])
            so_trung_don = len([e for e in nk.su_kien if e.loai == "trung_don"])

            # Kiểm tra hợp lệ bằng trọng tài nếu có màn và bản đồ
            hop_le = 0
            ly_do = ""
            tep_tmx = BAN_DO_DIR / Path(nk.ban_do).name
            if tep_tmx.exists():
                try:
                    m_info = _cac_man().get(nk.man) if "vang" in ENABLED and "man_choi" in STATE else None
                    kd = trong_tai.kiem_dinh(nk.model_dump(), doc_tmx(tep_tmx), m_info)
                    hop_le = 1 if kd.hop_le else 0
                    ly_do = "; ".join(kd.ly_do)
                except Exception as e_kd:
                    ly_do = f"Lỗi kiểm định: {e_kd}"

            player_id_ghi = nk.player_id or "anonymous"
            conn.execute(
                """INSERT INTO match_results
                   (ma_van, player_id, man, seed, ket_qua, so_xu, giay, hop_le, ly_do_tu_choi, is_verified, verified_by, verified_wallet, created_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 'telemetry_unverified', '', datetime('now'))
                   ON CONFLICT(ma_van) DO UPDATE SET
                       man = excluded.man,
                       ket_qua = excluded.ket_qua,
                       so_xu = excluded.so_xu,
                       giay = excluded.giay,
                       hop_le = excluded.hop_le,
                       ly_do_tu_choi = excluded.ly_do_tu_choi
                   WHERE match_results.is_verified = 0""",
                (nk.ma_van, player_id_ghi, nk.man, None, nk.ket_qua, so_xu_nhat, nk.giay, hop_le, ly_do),
            )
    except Exception as e:
        log.warning("Lỗi ghi nhận kết quả ván %s: %s", nk.ma_van, e)

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
    ma_van: str | None = Field(default=None, min_length=8, max_length=64, pattern=MA_VAN)
    vi: str | None = Field(default=None, min_length=42, max_length=42, pattern=DIA_CHI)
    man: int = Field(ge=1, le=1000)
    ve: int = Field(default=0, ge=0)


@app.post("/api/man/bat-dau", status_code=201)
async def bat_dau_man(
    yc: YeuCauBatDau,
    request: Request,
    player: NguoiChoiXacThuc = Depends(lay_nguoi_choi_hien_tai),
):
    """App gọi NGAY TRƯỚC khi thả George vào màn (cả màn có cọc và màn miễn phí).

    Bảo mật & Phân quyền:
    - Bắt buộc phiên đăng nhập SIWE hợp lệ (Fail-Closed, 401 nếu chưa xác thực).
    - Lấy danh tính ví từ phiên SIWE; nếu body gửi kèm `vi`, bắt buộc phải khớp (403 nếu sai khác).
    - Mutation qua cookie phiên bắt buộc kiểm tra Origin và CSRF token (403 nếu thiếu hoặc sai).
    - Với màn có cọc: yêu cầu vé hợp lệ (ve >= 1) từ giao dịch vaoMan on-chain.
    - Với màn miễn phí: cho phép đăng ký vé bắt đầu ván (ve = 0) để ràng buộc danh tính ví với mã ván,
      ngăn chặn nguy cơ chiếm đoạt phiếu (voucher hijacking) và gian lận. Truyền ve > 0 vào màn miễn phí sẽ bị từ chối 422.
    - Không cho phép đăng ký lại mã ván đã tồn tại trong SoVe (409 Conflict).
    - Nếu client không truyền mã ván, server sinh ngẫu nhiên an toàn bằng UUID v4.
    """
    kiem_tra_csrf_va_origin(request, player)

    vi_xac_thuc = player.wallet_address
    if yc.vi and yc.vi.lower() != vi_xac_thuc.lower():
        raise HTTPException(403, "Địa chỉ ví yêu cầu không khớp với phiên đăng nhập SIWE")

    m = _cac_man().get(yc.man)
    if m is None:
        raise HTTPException(404, f"Không có màn {yc.man}")

    if m.mien_phi:
        if yc.ve > 0:
            raise HTTPException(422, f"Màn {yc.man} là màn luyện tập, không cần vé")
        ve_ghi = 0
    else:
        if yc.ve < 1:
            raise HTTPException(422, f"Màn {yc.man} là màn có cọc, yêu cầu số vé hợp lệ (ve >= 1)")
        ve_ghi = yc.ve

        # 1. Chống replay số vé đã bắt đầu
        if trong_tai.SoVe(SO_VE).da_dung(vi_xac_thuc, yc.ve):
            raise HTTPException(409, f"Vé {yc.ve} của ví {vi_xac_thuc} đã được dùng cho ván chơi khác")

        # 2. Xác minh trạng thái vé on-chain qua RPC tin cậy (Fail-Closed)
        verifier = getattr(request.app.state, "onchain_ticket_verifier", None)
        if verifier is None:
            verifier = XacMinhVeOnchain()
        try:
            verifier.xac_minh_ve_hop_le_de_vao_man(vi_xac_thuc, yc.man, yc.ve)
        except LoiCauHinhVe as e:
            log.warning("Lỗi cấu hình xác minh vé on-chain: %s", e)
            raise HTTPException(503, f"Hệ thống xác minh blockchain chưa sẵn sàng: {e.message}") from None
        except LoiKetNoiRPC as e:
            log.warning("Lỗi kết nối RPC khi xác minh vé on-chain: %s", e)
            raise HTTPException(503, f"Không thể kết nối RPC xác minh vé on-chain: {e.message}") from None
        except LoiVeKhongHopLe as e:
            log.info("Vé cọc on-chain không hợp lệ: %s", e)
            raise HTTPException(422, f"Vé cọc on-chain không hợp lệ: {e.message}") from None
        except Exception as e:
            log.error("Lỗi bất ngờ khi xác minh vé on-chain: %s", e)
            raise HTTPException(503, f"Lỗi xác minh vé on-chain (Fail-Closed): {e}") from None

    ma_van_ghi = yc.ma_van if yc.ma_van else f"van-{uuid.uuid4().hex}"

    try:
        trong_tai.SoVe(SO_VE).bat_dau(ma_van_ghi, vi_xac_thuc, yc.man, ve_ghi)
    except ValueError as e:
        raise HTTPException(409, str(e))
    return {"da_bat_dau": True, "ma_van": ma_van_ghi, "vi": vi_xac_thuc, "gioi_han_giay": m.gioi_han_giay}


@app.get("/api/man/ve")
def ve_da_dung(vi: str = Query(min_length=42, max_length=42, pattern=DIA_CHI), ve: int = Query(ge=1)):
    _cac_man()
    return {"da_dung": trong_tai.SoVe(SO_VE).da_dung(vi, ve)}


class YeuCauPhieu(BaseModel):
    ma_van: str = Field(min_length=8, max_length=64, pattern=MA_VAN)
    vi: str | None = Field(default=None, min_length=42, max_length=42, pattern=DIA_CHI)


def _ky(khoa: bytes, ban_ghi: dict) -> dict:
    return trong_tai.ky_phieu(ban_ghi["vi"], ban_ghi.get("man", 1), ban_ghi.get("ve", 0),
                              ban_ghi["so_vang"], ban_ghi["ma_van"], khoa, CHAIN_ID, HOP_DONG_CUA_HANG)


@app.post("/api/vang/phieu")
async def cap_phieu(
    yc: YeuCauPhieu,
    request: Request,
    player: NguoiChoiXacThuc = Depends(lay_nguoi_choi_hien_tai),
):
    """Cấp phiếu nhận vàng EIP-712 sau khi trọng tài kiểm định ván chơi.

    Bảo mật:
    - Bắt buộc phiên đăng nhập SIWE hợp lệ (Fail-Closed, 401 nếu chưa xác thực).
    - Ví được lấy từ phiên SIWE; nếu body gửi kèm `vi`, bắt buộc phải khớp (403 nếu sai khác).
    - Mutation qua cookie bắt buộc kiểm tra Origin và CSRF token.
    - Chặn Voucher Hijacking: nếu ván đã đăng ký vé cho ví khác trong SoVe -> 403 Forbidden.
    - Ký lại phiếu cũ: chỉ cho phép đúng chủ sở hữu ví của phiếu cũ đó.
    - Chỉ cập nhật verified_wallet vào match_results khi danh tính ví đã được xác thực an toàn qua SIWE.
    """
    kiem_tra_csrf_va_origin(request, player)

    vi_xac_thuc = player.wallet_address
    if yc.vi and yc.vi.lower() != vi_xac_thuc.lower():
        raise HTTPException(403, "Địa chỉ ví yêu cầu không khớp với phiên đăng nhập SIWE")

    khoa = _khoa_trong_tai()
    cac_man = _cac_man()
    so = trong_tai.SoPhieu(SO_PHIEU)
    so_ve = trong_tai.SoVe(SO_VE)

    # 1. Nhánh xin ký lại: Chỉ ký lại phiếu ĐÃ TỒN TẠI trong SoPhieu và ĐÚNG chủ sở hữu ví
    # Tuyệt đối không tạo phiếu mới, không cấp thêm vàng
    cu = so.lay(yc.ma_van)
    if cu is not None:
        if cu["vi"].lower() != vi_xac_thuc.lower():
            raise HTTPException(409, "Ván này đã cấp phiếu cho một ví khác")
        return _ky(khoa, cu)

    # 2. Đọc nhật ký ván chơi từ telemetry store
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

    # 3. Bắt buộc ván phải có ticket trong SoVe trước khi phát Voucher mới cho BẤT KỲ màn nào (kể cả màn 1)
    # Fail-closed tuyệt đối: Nếu thiếu ticket -> từ chối (403 cho màn miễn phí, 422 cho màn có cọc)
    bd = so_ve.lay_theo_van(yc.ma_van)
    if bd is None:
        if m.mien_phi:
            raise HTTPException(403, "Ván chơi chưa được đăng ký bắt đầu (thiếu ticket SoVe)")
        else:
            raise HTTPException(422, {"ly_do": ["Ván màn có cọc chưa được đăng ký bắt đầu với ví này"]})

    # 4. Nếu ví trong ticket khác ví SIWE xác thực -> từ chối 403 Forbidden (chống Voucher Hijacking)
    if bd["vi"].lower() != vi_xac_thuc.lower():
        log.warning("Voucher Hijacking bị chặn: Ván %s thuộc ví %s, nhưng ví %s xin phiếu",
                    yc.ma_van, bd["vi"], vi_xac_thuc)
        raise HTTPException(403, "Ván chơi này đã được đăng ký bắt đầu cho một địa chỉ ví khác")

    # 5. Bắt buộc màn trong ticket khớp chính xác màn trong nhật ký
    if bd["man"] != m.id:
        raise HTTPException(422, f"Màn trong đăng ký ticket ({bd['man']}) không khớp màn nhật ký ({m.id})")

    # 6. Kiểm định ván và quy tắc vé theo loại màn
    kq = trong_tai.kiem_dinh(van, doc_tmx(tep_ban_do), m)
    ly_do = list(kq.ly_do)
    ve = 0

    if m.mien_phi:
        # Với màn miễn phí, ticket.ve bắt buộc phải bằng 0
        if bd.get("ve", 0) != 0:
            ly_do.append(f"Màn {m.id} là màn miễn phí, ticket.ve phải bằng 0 (nhận {bd.get('ve')})")
        ve = 0
    else:
        # Với màn có cọc, ticket.ve bắt buộc >= 1 và giữ kiểm tra đồng hồ/luật cọc
        if bd.get("ve", 0) < 1:
            ly_do.append(f"Màn {m.id} là màn có cọc, ticket.ve phải >= 1 (nhận {bd.get('ve')})")
        else:
            ly_do += trong_tai.kiem_dong_ho(bd, van, m)
            ve = bd["ve"]

    if ly_do:
        log.warning("từ chối phiếu %s: %s", yc.ma_van, ly_do)
        raise HTTPException(422, {"ly_do": ly_do})
    if so.vang_hom_nay(vi_xac_thuc) + kq.so_vang > trong_tai.VANG_TOI_DA_MOI_NGAY:
        raise HTTPException(429, f"Ví đã nhận đủ {trong_tai.VANG_TOI_DA_MOI_NGAY} vàng hôm nay")
    so.ghi(yc.ma_van, vi_xac_thuc, kq.so_vang, m.id, ve)

    # 1. Cập nhật verified_wallet vào match_results khi danh tính ví đã được xác thực qua SIWE và SoVe
    try:
        with lay_csdl() as conn:
            conn.execute(
                """UPDATE match_results
                   SET is_verified = 1, verified_by = 'referee_voucher', verified_wallet = ?
                   WHERE ma_van = ?""",
                (vi_xac_thuc.lower(), yc.ma_van),
            )
    except Exception as e_mr:
        log.warning("Không thể cập nhật match_results verified: %s", e_mr)

    # 2. Tự động ghi nhận tiến trình vào KhoTienTrinh (phục vụ mở khóa AI Character)
    kho_tt = getattr(app.state, "kho_tien_trinh", None)
    auth_srv = getattr(app.state, "auth_service", None)
    if kho_tt is not None and auth_srv is not None:
        try:
            with auth_srv._factory() as db:
                from auth.models import User
                u = db.scalar(select(User).where(User.wallet_address == vi_xac_thuc.lower()))
                if u is not None:
                    kho_tt.ghi_nhan_hoan_thanh(
                        owner_user_id=str(u.id),
                        verified_wallet_address=vi_xac_thuc.lower(),
                        stage_id=m.id,
                        completion_status="completed",
                        verification_source="referee_validation",
                        completion_evidence={"ma_van": yc.ma_van, "so_vang": kq.so_vang, "ve": ve},
                        replay_key=f"referee:{yc.ma_van}",
                    )
        except Exception as e:
            log.warning("Không thể tự động ghi nhận tiến trình từ cap_phieu (%s)", e)
    return _ky(khoa, so.lay(yc.ma_van))


@app.get("/api/vang/cho-nhan")
def phieu_cho_nhan(vi: str = Query(min_length=42, max_length=42, pattern=DIA_CHI)):
    """Mọi phiếu đã cấp cho ví này trong 7 ngày, ký lại với hạn mới.

    Máy chủ không biết phiếu nào đã nộp lên chuỗi — app tự lọc bằng `daDoi(maVan)` (và `ve(vi)` với màn
    có cọc). Nhờ đó tải lại trang, đổi máy, MetaMask treo… đều không làm mất vàng đã kiếm.
    """
    khoa = _khoa_trong_tai()
    return {"phieu": [_ky(khoa, p) | {"ma_van": p["ma_van"]} for p in trong_tai.SoPhieu(SO_PHIEU).cua_vi(vi)]}
