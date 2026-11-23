"""Read-only authenticated weekly leaderboard, independent of raw telemetry ranking."""
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai
from config import CHAIN_ID
from core.bang_xep_hang import bang_tuan
from core.csdl import lay_csdl

router = APIRouter(prefix='/api/bang-xep-hang', tags=['bang-xep-hang'])


@router.get('/tuan')
def xep_hang_tuan(
    response: Response,
    player: Annotated[NguoiChoiXacThuc, Depends(lay_nguoi_choi_hien_tai)],
    man: int | None = Query(None, ge=1, le=20),
    thich_ung: bool = False,
    top: int = Query(100, ge=1, le=100),
):
    response.headers['Cache-Control'] = 'no-store, private'
    with lay_csdl() as conn:
        return bang_tuan(conn, player.wallet_address, CHAIN_ID,
                         man=man, thich_ung=thich_ung, top=top)
