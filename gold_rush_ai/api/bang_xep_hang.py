"""Read-only authenticated weekly leaderboard, independent of raw telemetry ranking."""
from typing import Annotated
from contextlib import closing
from threading import Lock
import sqlite3

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy import select
from pydantic import BaseModel, ConfigDict, Field

import config
from auth.models import User
from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai, kiem_tra_csrf_va_origin
from config import CHAIN_ID
from core.bang_xep_hang import bang_tuan
from core.csdl import ket_noi, bay_gio_iso
from core.bang_xep_hang_tong_the import BoNhoBangTongThe, xep_hang, phan_hoi
from core.nguon_bang_tong_the import doc_man_hoan_thanh, doc_so_du_va_huy_hieu

router = APIRouter(prefix='/api/bang-xep-hang', tags=['bang-xep-hang'])
_cache_init = Lock()


class CapHoSo(BaseModel):
    model_config = ConfigDict(strict=True, extra='forbid')
    level: int = Field(ge=1, le=21)
    expected_wallet: str = Field(pattern=r'^0x[0-9a-fA-F]{40}$')
    expected_chain_id: int = Field(ge=1, le=2**256-1)


@router.post('/cap-ho-so')
def dong_bo_cap_ho_so(
    data: CapHoSo, request: Request,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    """Save only cosmetic Profile Level; identity comes from SIWE, never the body."""
    kiem_tra_csrf_va_origin(request, player)
    wallet = player.wallet_address.lower()
    if data.expected_wallet.lower() != wallet or data.expected_chain_id != CHAIN_ID:
        raise HTTPException(409, 'Phiên tài khoản hoặc mạng đã thay đổi.')
    try:
        with closing(ket_noi()) as db:
            db.execute('BEGIN IMMEDIATE')
            old = db.execute('SELECT wallet_address FROM player_profile_levels WHERE user_id=? AND chain_id=?',
                             (player.user_id, CHAIN_ID)).fetchone()
            if old is not None and old['wallet_address'].lower() != wallet:
                raise HTTPException(409, 'Ví tài khoản không khớp.')
            db.execute('''INSERT INTO player_profile_levels(user_id,chain_id,wallet_address,level,updated_at)
                VALUES(?,?,?,?,?) ON CONFLICT(user_id,chain_id) DO UPDATE SET
                level=MAX(player_profile_levels.level,excluded.level),updated_at=excluded.updated_at''',
                (player.user_id, CHAIN_ID, wallet, data.level, bay_gio_iso()))
            level = db.execute('SELECT level FROM player_profile_levels WHERE user_id=? AND chain_id=?',
                               (player.user_id, CHAIN_ID)).fetchone()['level']
            db.commit()
        return {'level': level}
    except sqlite3.Error:
        raise HTTPException(503, 'Chưa đồng bộ được cấp Hồ sơ.') from None


def _tai_tong_the(request):
    factory = getattr(request.app.state, 'auth_session_factory', None)
    if factory is None or config.SBT_CHAIN_ID != CHAIN_ID:
        raise RuntimeError('Ranking source unavailable')
    with factory() as db:
        users = [dict(user_id=str(uid), wallet=wallet.lower(), ten=name)
                 for uid, wallet, name in db.execute(select(User.id, User.wallet_address, User.username)).all()]
    if not users:
        return []
    kho = getattr(request.app.state, 'kho_tien_trinh', None)
    if kho is None:
        raise RuntimeError('Verified account progress unavailable')
    with closing(ket_noi()) as conn:
        conn.execute('BEGIN')
        completed = doc_man_hoan_thanh(users, conn, kho.db_path, CHAIN_ID)
        owners = {u['user_id']:u['wallet'] for u in users}
        profiles = {r['wallet_address'].lower():r['level'] for r in conn.execute(
            'SELECT user_id,wallet_address,level FROM player_profile_levels WHERE chain_id=?', (CHAIN_ID,))
            if owners.get(r['user_id']) == r['wallet_address'].lower()}
    wallets = sorted(u['wallet'] for u in users)
    gold, owned = doc_so_du_va_huy_hieu(wallets, CHAIN_ID, config.HOP_DONG_CUA_HANG, config.HOP_DONG_SBT)
    return xep_hang(users, completed, gold, owned, profiles)


@router.get('/tong-the')
def xep_hang_toan_server(
    request: Request,
    response: Response,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
):
    response.headers['Cache-Control'] = 'no-store, private'
    with _cache_init:
        if not hasattr(request.app.state, 'bang_tong_the_cache'):
            request.app.state.bang_tong_the_cache = BoNhoBangTongThe()
        cache = request.app.state.bang_tong_the_cache
    try:
        with closing(ket_noi()) as db:
            # A persisted revision also invalidates snapshots in other server workers.
            revision = tuple(db.execute('SELECT COUNT(*),COALESCE(SUM(level),0) FROM player_profile_levels WHERE chain_id=?',
                                        (CHAIN_ID,)).fetchone())
        ranked, updated, stale = cache.lay(
            (CHAIN_ID, config.HOP_DONG_CUA_HANG.lower(), config.HOP_DONG_SBT.lower()),
            lambda: _tai_tong_the(request), revision=revision)
        return phan_hoi(ranked, player.wallet_address, CHAIN_ID, updated, stale)
    except Exception:
        raise HTTPException(503, 'Bảng xếp hạng chưa đồng bộ được dữ liệu server.') from None


@router.get('/tuan')
def xep_hang_tuan(
    response: Response,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
    man: int | None = Query(None, ge=1, le=20),
    thich_ung: bool = False,
    top: int = Query(100, ge=1, le=100),
):
    response.headers['Cache-Control'] = 'no-store, private'
    with closing(ket_noi()) as conn:
        conn.execute('BEGIN')  # consistent read snapshot without reserving SQLite's writer
        return bang_tuan(conn, player.wallet_address, CHAIN_ID,
                         man=man, thich_ung=thich_ung, top=top)
