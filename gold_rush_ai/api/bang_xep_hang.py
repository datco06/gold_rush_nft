"""Read-only authenticated weekly leaderboard, independent of raw telemetry ranking."""
from typing import Annotated
from contextlib import closing
from threading import Lock

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy import select

import config
from auth.models import User
from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai
from config import CHAIN_ID
from core.bang_xep_hang import bang_tuan
from core.csdl import ket_noi
from core.bang_xep_hang_tong_the import BoNhoBangTongThe, xep_hang, phan_hoi
from core.nguon_bang_tong_the import doc_man_hoan_thanh, doc_so_du_va_huy_hieu

router = APIRouter(prefix='/api/bang-xep-hang', tags=['bang-xep-hang'])
_cache_init = Lock()


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
    wallets = sorted(u['wallet'] for u in users)
    gold, owned = doc_so_du_va_huy_hieu(wallets, CHAIN_ID, config.HOP_DONG_CUA_HANG, config.HOP_DONG_SBT)
    return xep_hang(users, completed, gold, owned)


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
        ranked, updated, stale = cache.lay((CHAIN_ID, config.HOP_DONG_CUA_HANG.lower(), config.HOP_DONG_SBT.lower()), lambda: _tai_tong_the(request))
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
