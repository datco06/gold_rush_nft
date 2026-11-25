"""Trang quản trị và API riêng; không thay đổi router người chơi."""
import base64
from datetime import datetime, timezone
import hmac
from io import BytesIO
from pathlib import Path
import re
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import FileResponse
from PIL import Image, ImageDraw
from pydantic import BaseModel, Field, model_validator

import config
from core.admin_session import AdminSessions, COOKIE, TTL, digest
from core.csdl import lay_csdl
from scripts.tao_ma_qr_qua_tang import _new_code, _qr_matrix

STATIC = Path(__file__).resolve().parents[1] / "admin_web"
SECURITY = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'",
}


class Login(BaseModel):
    username: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=200)


class Gift(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    reward_type: Literal["gold", "item"] = "gold"
    amount: int = Field(default=100, ge=1, le=10000)
    token_id: int = Field(default=0, ge=0, le=2147483647)
    max_uses: int = Field(default=1, ge=1, le=10000)
    expires_at: datetime | None = None

    @model_validator(mode="after")
    def validate_reward(self):
        self.name = self.name.strip()
        if not self.name:
            raise ValueError("Tên quà không được để trống")
        if self.reward_type == "item" and self.token_id < 1:
            raise ValueError("Vật phẩm cần token ID lớn hơn 0")
        if self.expires_at is not None:
            if self.expires_at.tzinfo is None or self.expires_at <= datetime.now(timezone.utc):
                raise ValueError("Hạn dùng phải có múi giờ và nằm trong tương lai")
        return self


class Active(BaseModel):
    active: bool


def qr_png(code: str) -> str:
    matrix = _qr_matrix(code)
    scale, quiet = 8, 4
    image = Image.new("RGB", ((len(matrix) + 2 * quiet) * scale,) * 2, "white")
    draw = ImageDraw.Draw(image)
    for y, row in enumerate(matrix):
        for x, dark in enumerate(row):
            if dark:
                left, top = (x + quiet) * scale, (y + quiet) * scale
                draw.rectangle((left, top, left + scale - 1, top + scale - 1), fill="black")
    output = BytesIO()
    image.save(output, format="PNG")
    return base64.b64encode(output.getvalue()).decode("ascii")


def create_admin_router(*, sessions=None, gift_db=None):
    router = APIRouter(tags=["admin"])
    sessions = sessions or AdminSessions(config.DATA_DIR / "admin" / "sessions.sqlite3")

    def mutation(request: Request):
        origin = request.headers.get("origin")
        if request.headers.get("X-Admin-Request") != "1" or (
            origin is not None and origin != str(request.base_url).rstrip("/")
        ):
            raise HTTPException(403, "Yêu cầu quản trị không hợp lệ.")

    def authenticated(request: Request, response: Response):
        response.headers.update(SECURITY)
        token = request.cookies.get(COOKIE, "")
        if not token:
            raise HTTPException(401, "Vui lòng đăng nhập quản trị.")
        session = sessions.verify(token)
        if request.method == "POST":
            mutation(request)
            if not hmac.compare_digest(request.headers.get("X-CSRF-Token", ""), session["csrf"]):
                raise HTTPException(403, "Phiên không hợp lệ. Tải lại trang rồi thử lại.")
        return session

    @router.get("/admin", include_in_schema=False)
    @router.get("/admin/", include_in_schema=False)
    @router.get("/admin/login", include_in_schema=False)
    def page():
        return FileResponse(STATIC / "index.html", headers=SECURITY)

    @router.get("/admin/assets/{name}", include_in_schema=False)
    def asset(name: str):
        if name not in {"admin.css", "admin.js"}:
            raise HTTPException(404)
        return FileResponse(STATIC / name, headers=SECURITY)

    @router.post("/api/admin/login", dependencies=[Depends(mutation)])
    def login(body: Login, request: Request, response: Response):
        token, csrf = sessions.login(body.username, body.password,
            request.client.host if request.client else "unknown", request.cookies.get(COOKIE, ""))
        response.headers.update(SECURITY)
        response.set_cookie(COOKIE, token, max_age=TTL, httponly=True,
            secure=request.url.scheme == "https", samesite="strict", path="/api/admin")
        return {"username": body.username, "csrf": csrf}

    @router.get("/api/admin/me")
    def me(session=Depends(authenticated)):
        return session

    @router.post("/api/admin/logout")
    def logout(request: Request, response: Response, session=Depends(authenticated)):
        sessions.logout(request.cookies.get(COOKIE, ""))
        response.delete_cookie(COOKIE, path="/api/admin", httponly=True, samesite="strict")
        return {"ok": True}

    @router.get("/api/admin/codes")
    def codes(session=Depends(authenticated)):
        with lay_csdl(gift_db) as db:
            summary = dict(db.execute("SELECT COUNT(*) AS total, COALESCE(SUM(used_count), 0) AS used, COALESCE(SUM(active = 0), 0) AS locked FROM gift_codes").fetchone())
            rows = db.execute("SELECT * FROM gift_codes ORDER BY rowid DESC LIMIT 100").fetchall()
        return {"summary": summary, "codes": [dict(row) for row in rows]}

    @router.post("/api/admin/codes", status_code=201)
    def create_code(body: Gift, session=Depends(authenticated)):
        code = _new_code()
        png = qr_png(code)
        with lay_csdl(gift_db) as db:
            db.execute("""INSERT INTO gift_codes
                (code_hash, reward_type, token_id, amount, name, max_uses, per_wallet_limit, expires_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, ?)""",
                (digest(code), body.reward_type, body.token_id if body.reward_type == "item" else 0,
                 body.amount, body.name, body.max_uses, body.expires_at.timestamp() if body.expires_at else None))
        return {"code": code, "qr_png": png}

    @router.post("/api/admin/codes/{code_hash}/active")
    def set_active(code_hash: str, body: Active, session=Depends(authenticated)):
        if not re.fullmatch(r"[0-9a-f]{64}", code_hash):
            raise HTTPException(404, "Không tìm thấy mã.")
        with lay_csdl(gift_db) as db:
            changed = db.execute("UPDATE gift_codes SET active = ? WHERE code_hash = ?", (int(body.active), code_hash))
            if changed.rowcount != 1:
                raise HTTPException(404, "Không tìm thấy mã.")
        return {"ok": True}

    return router
