"""Weekly rankings from immutable referee-approved snapshots, never telemetry alone."""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone

VIET_NAM = timezone(timedelta(hours=7))


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError('Ranking timestamps must have a timezone')
    return value.astimezone(timezone.utc)


def ghi_van_da_xac_minh(conn, player, chain_id: int, van: dict, verified_at: datetime) -> None:
    """Called only AFTER SIWE ownership, ticket and referee checks have succeeded.

    Identity/name come from SIWE; score is collected coins *20, excluding rewards.
    First insertion wins, including its original server issuance timestamp.
    """
    stage, seconds = van.get('man'), van.get('giay')
    coins = sum(e.get('loai') == 'nhat_xu' for e in van.get('su_kien', []))
    if (van.get('ket_qua') != 'thang' or type(stage) is not int or not 1 <= stage <= 20
            or type(seconds) not in (int, float) or not math.isfinite(seconds)
            or not 0 < seconds <= 3600 or not 0 < coins <= 500
            or van.get('diem') != coins * 20):
        raise ValueError('Invalid verified ranking result')
    wallet = player.wallet_address.lower()
    name = player.username or f'{wallet[:6]}…{wallet[-4:]}'
    conn.execute(
        '''INSERT OR IGNORE INTO weekly_rank_runs
           (chain_id,ma_van,wallet,ten,man,diem,duration_ms,thich_ung,verified_at)
           VALUES (?,?,?,?,?,?,?,?,?)''',
        (chain_id, van['ma_van'], wallet, name, stage, coins * 20,
         max(1, round(seconds * 1000)), int(bool(van.get('do_kho_thich_ung', False))),
         _utc(verified_at).isoformat(timespec='microseconds')),
    )


_RANKING = '''
WITH candidates AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY wallet,man ORDER BY diem DESC,duration_ms,verified_at,ma_van
    ) AS best
    FROM weekly_rank_runs
    WHERE chain_id=? AND thich_ung=? AND verified_at>=? AND verified_at<?
      AND verified_at<=? AND (? IS NULL OR man=?)
), totals AS (
    SELECT wallet,MAX(ten) AS ten,SUM(diem) AS diem,
           SUM(duration_ms) AS duration_ms,COUNT(*) AS so_man
    FROM candidates WHERE best=1 GROUP BY wallet
), ranked AS (
    SELECT *,RANK() OVER (ORDER BY diem DESC,duration_ms) AS hang,
           COUNT(*) OVER () AS tong_nguoi FROM totals
)
'''


def bang_tuan(conn, wallet: str, chain_id: int, *, man: int | None = None,
              thich_ung: bool = False, top: int = 100, now: datetime | None = None) -> dict:
    now = _utc(now or datetime.now(timezone.utc))
    local = now.astimezone(VIET_NAM)
    start = (local - timedelta(days=local.weekday())).replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=7)
    params = (chain_id, int(thich_ung), _utc(start).isoformat(timespec='microseconds'),
              _utc(end).isoformat(timespec='microseconds'), now.isoformat(timespec='microseconds'), man, man)
    rows = conn.execute(_RANKING + 'SELECT * FROM ranked ORDER BY hang,wallet LIMIT ?', (*params, top)).fetchall()
    mine = conn.execute(_RANKING + 'SELECT * FROM ranked WHERE wallet=?', (*params, wallet.lower())).fetchone()

    def entry(row):
        if row is None:
            return None
        return dict(hang=row['hang'], ten=row['ten'], diem=row['diem'],
                    giay=row['duration_ms'] / 1000, so_man=row['so_man'],
                    la_ban=row['wallet'] == wallet.lower())

    return dict(tuan=start.date().isoformat(), bat_dau=_utc(start).isoformat(),
                ket_thuc=_utc(end).isoformat(), chain_id=chain_id, man=man,
                thich_ung=thich_ung, tong_nguoi=rows[0]['tong_nguoi'] if rows else 0,
                bang=[entry(row) for row in rows], ban=entry(mine))
