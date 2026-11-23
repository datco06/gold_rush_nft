"""Overall server ranking; no gameplay mutations or client-reported metrics."""
from datetime import datetime, timezone
from threading import Lock
from time import monotonic

from core.tien_trinh import tinh_cap_va_exp


def xep_hang(users, exp, gold, badges):
    result = []
    seen = set()
    for user in users:
        wallet = user['wallet'].lower()
        earned = gold.get(wallet, 0)
        xp = exp.get(wallet, 0)
        owned = badges.get(wallet)
        if (wallet in seen or type(xp) is not int or xp < 0
                or type(earned) is not int or earned < 0 or not isinstance(owned, list)
                or len(set(owned)) != len(owned)
                or any(type(i) is not int or not 1 <= i <= 5 for i in owned)):
            raise ValueError('Incomplete or invalid ranking source')
        seen.add(wallet)
        result.append(dict(user_id=user['user_id'], wallet=wallet, ten=user['ten'],
                           level=tinh_cap_va_exp(xp)['level'], vang=earned,
                           huy_hieu=sorted(owned)))
    result.sort(key=lambda r: (-r['level'], -len(r['huy_hieu']), -r['vang'], r['user_id']))
    for position, row in enumerate(result, 1):
        row['hang'] = position
    return result


def phan_hoi(ranked, viewer, chain_id, updated_at, stale):
    def public(row):
        return dict(hang=row['hang'], ten=row['ten'], level=row['level'],
                    vang=str(row['vang']), huy_hieu=list(row['huy_hieu']),
                    la_ban=row['wallet'] == viewer.lower())
    mine = next((r for r in ranked if r['wallet'] == viewer.lower()), None)
    return dict(chain_id=chain_id, viewer=viewer.lower(), cap_nhat_luc=updated_at.isoformat(),
                du_lieu_cu=stale, tong_nguoi=len(ranked),
                bang=[public(r) for r in ranked[:30]], ban=public(mine) if mine else None)


class BoNhoBangTongThe:
    """One shared complete snapshot, coalesced refresh and safe stale fallback."""
    def __init__(self, *, clock=monotonic):
        self._clock = clock
        self._lock = Lock()
        self._key = None
        self._value = None
        self._updated = None
        self._attempt = None
        self._stale = False

    def lay(self, key, build):
        with self._lock:
            now = self._clock()
            if key != self._key:
                self._key, self._value, self._updated, self._attempt = key, None, None, None
            if self._attempt is not None and now - self._attempt < 60:
                if self._value is None:
                    raise RuntimeError('Ranking synchronization unavailable')
                return self._value, self._updated, self._stale
            self._attempt = now
            try:
                value = build()
                self._value = value
                self._updated = datetime.now(timezone.utc)
                self._stale = False
            except Exception:
                if self._value is None:
                    raise RuntimeError('Ranking synchronization unavailable') from None
                self._stale = True
            return self._value, self._updated, self._stale
