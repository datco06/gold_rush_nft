from datetime import datetime, timezone

import pytest

from core.bang_xep_hang_tong_the import BoNhoBangTongThe, xep_hang, phan_hoi


def people(n):
    return [dict(user_id=f'{i:03}', wallet=f'0x{i:040x}', ten=f'Player{i}') for i in range(n)]


def test_priority_complete_server_before_top30_and_personal_outside():
    users = people(35)
    exp = {u['wallet']: 100 for u in users}
    exp[users[34]['wallet']] = 300
    badges = {u['wallet']: [] for u in users}
    badges[users[33]['wallet']] = [1, 3]
    gold = {u['wallet']: i for i, u in enumerate(users)}
    gold[users[32]['wallet']] = 10**35
    ranked = xep_hang(users, exp, gold, badges)
    assert [r['ten'] for r in ranked[:3]] == ['Player34', 'Player33', 'Player32']
    assert ranked[0]['level'] == 3
    data = phan_hoi(ranked, users[0]['wallet'], 31337, datetime.now(timezone.utc), False)
    assert len(data['bang']) == 30
    assert data['ban']['hang'] == 35
    assert data['bang'][2]['vang'] == str(10**35)
    assert data['viewer'] == users[0]['wallet']
    assert all('wallet' not in row and 'user_id' not in row for row in data['bang'])


def test_stable_ties_distinct_owned_badges_new_users_and_small_server():
    users = people(3)
    ranked = xep_hang(list(reversed(users)), {}, {}, {u['wallet']: [] for u in users})
    assert [r['ten'] for r in ranked] == ['Player0', 'Player1', 'Player2']
    assert all(r['level'] == 1 and r['vang'] == 0 for r in ranked)
    assert len(phan_hoi(ranked, users[0]['wallet'], 1, datetime.now(timezone.utc), False)['bang']) == 3
    with pytest.raises(ValueError):
        xep_hang(users, {}, {}, {users[0]['wallet']: [1, 1]})


def test_cache_once_ttl_failure_stale_and_configuration_isolation():
    time = [0.0]
    cache = BoNhoBangTongThe(clock=lambda: time[0])
    calls = []
    def build():
        calls.append(1)
        return xep_hang(people(2), {}, {}, {u['wallet']: [] for u in people(2)})
    first = cache.lay((1, 'contract'), build)
    assert cache.lay((1, 'contract'), build) == first
    assert len(calls) == 1
    time[0] = 61
    def fail():
        raise RuntimeError('private RPC failure')
    stale = cache.lay((1, 'contract'), fail)
    assert stale[2] is True and stale[1] == first[1]
    assert cache.lay((1, 'contract'), build)[2] is True
    time[0] = 122
    assert cache.lay((1, 'contract'), build)[2] is False
    assert len(calls) == 2
    with pytest.raises(RuntimeError):
        cache.lay((2, 'other-contract'), fail)


def test_cache_concurrent_build_is_coalesced():
    from concurrent.futures import ThreadPoolExecutor
    cache = BoNhoBangTongThe()
    calls = []
    def build():
        calls.append(1)
        return []
    with ThreadPoolExecutor(max_workers=6) as pool:
        result = list(pool.map(lambda _: cache.lay((1, 'c'), build), range(20)))
    assert len(calls) == 1
    assert all(r == result[0] for r in result)


def test_slow_build_ttl_starts_when_snapshot_finishes():
    time = [0.0]
    cache = BoNhoBangTongThe(clock=lambda: time[0])
    calls = []
    def slow():
        calls.append(1)
        time[0] += 65
        return []
    cache.lay((1, 'c'), slow)
    cache.lay((1, 'c'), slow)
    assert len(calls) == 1


def test_concurrent_refresh_serves_last_snapshot_without_waiting():
    from concurrent.futures import ThreadPoolExecutor
    from threading import Event
    time = [0.0]
    cache = BoNhoBangTongThe(clock=lambda: time[0])
    cache.lay((1, 'c'), lambda: [])
    time[0] = 61
    started, finish = Event(), Event()
    def blocked():
        started.set()
        assert finish.wait(3)
        return []
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(cache.lay, (1, 'c'), blocked)
        assert started.wait(1)
        second = pool.submit(cache.lay, (1, 'c'), lambda: [])
        try:
            assert second.result(timeout=.3)[2] is True
        finally:
            finish.set()
        first.result(timeout=1)
