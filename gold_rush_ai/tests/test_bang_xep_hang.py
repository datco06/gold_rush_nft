from datetime import datetime, timezone, timedelta
from types import SimpleNamespace

import pytest

from core import bang_xep_hang as bxh, csdl


NOW = datetime(2026, 11, 23, 2, tzinfo=timezone.utc)
ALICE = SimpleNamespace(wallet_address='0x' + 'a' * 40, username='Alice')
BOB = SimpleNamespace(wallet_address='0x' + 'b' * 40, username='Bob')


@pytest.fixture
def conn(tmp_path):
    path = tmp_path / 'ranking.db'
    csdl.khoi_tao_csdl(path)
    with csdl.lay_csdl(path) as db:
        yield db


def record(conn, run, player=ALICE, stage=1, coins=5, seconds=50,
           at=NOW, chain=31337, adaptive=False, result='thang'):
    van = dict(ma_van=run, man=stage, ket_qua=result, diem=coins * 20,
               giay=seconds, do_kho_thich_ung=adaptive,
               player_id='spoofed', ten_hien_thi='spoofed',
               su_kien=[{'loai': 'nhat_xu'} for _ in range(coins)])
    return bxh.ghi_van_da_xac_minh(conn, player, chain, van, at)


def board(conn, **kwargs):
    return bxh.bang_tuan(conn, ALICE.wallet_address, 31337, now=NOW, **kwargs)


def test_best_run_per_stage_identity_ties_and_stage_filter(conn):
    record(conn, 'a1')
    record(conn, 'a2', seconds=40)
    record(conn, 'a3', stage=2, coins=10, seconds=60)
    record(conn, 'b1', BOB, coins=15, seconds=100)
    result = board(conn)
    assert result['tong_nguoi'] == 2
    assert [(r['hang'], r['diem'], r['giay']) for r in result['bang']] == [(1, 300, 100), (1, 300, 100)]
    assert result['ban']['ten'] == 'Alice'
    assert result['ban']['so_man'] == 2
    assert result['ban']['la_ban'] is True
    assert all('spoofed' not in str(r) for r in result['bang'])
    assert board(conn, man=2)['tong_nguoi'] == 1
    assert board(conn, man=2)['ban']['diem'] == 200


def test_duplicate_is_immutable_and_does_not_move_to_new_week(conn):
    record(conn, 'same', seconds=60)
    record(conn, 'same', BOB, coins=100, seconds=1, at=NOW + timedelta(days=8))
    assert board(conn)['ban']['diem'] == 100
    assert board(conn)['ban']['giay'] == 60
    assert bxh.bang_tuan(conn, ALICE.wallet_address, 31337, now=NOW + timedelta(days=8))['bang'] == []


def test_week_boundary_is_monday_vietnam_time_and_excludes_future(conn):
    start = datetime(2026, 11, 22, 17, tzinfo=timezone.utc)
    record(conn, 'previous', BOB, at=start - timedelta(microseconds=1))
    record(conn, 'current', at=start)
    record(conn, 'next', BOB, at=start + timedelta(days=7))
    data = board(conn)
    assert data['tuan'] == '2026-11-23'
    assert datetime.fromisoformat(data['bat_dau']) == start
    assert datetime.fromisoformat(data['ket_thuc']) == start + timedelta(days=7)
    assert data['tong_nguoi'] == 1


def test_personal_rank_outside_top_and_missing_personal(conn):
    record(conn, 'a', seconds=100)
    for n in range(105):
        player = SimpleNamespace(wallet_address=f'0x{n:040x}', username=f'P{n}')
        record(conn, f'run{n}', player, seconds=10 + n / 10)
    data = board(conn)
    assert len(data['bang']) == 100
    assert data['ban']['hang'] == 106
    assert not any(r['la_ban'] for r in data['bang'])
    assert bxh.bang_tuan(conn, BOB.wallet_address, 31337, now=NOW)['ban'] is None


def test_chain_and_adaptive_mode_are_separate(conn):
    record(conn, 'standard')
    record(conn, 'adaptive', BOB, adaptive=True)
    record(conn, 'other-chain', BOB, chain=11155111)
    assert board(conn)['tong_nguoi'] == 1
    assert board(conn, thich_ung=True)['ban'] is None
    assert board(conn, thich_ung=True)['bang'][0]['ten'] == 'Bob'


@pytest.mark.parametrize('changes', [
    dict(result='thua'), dict(seconds=float('nan')), dict(seconds=-1),
    dict(seconds=0), dict(stage=21), dict(coins=0),
])
def test_invalid_or_losing_run_is_not_ranked(conn, changes):
    with pytest.raises(ValueError):
        record(conn, 'invalid', **changes)
    assert board(conn)['bang'] == []


def test_schema_is_additive_and_idempotent(tmp_path):
    path = tmp_path / 'old.db'
    csdl.khoi_tao_csdl(path)
    with csdl.lay_csdl(path) as db:
        db.execute("INSERT INTO match_results(ma_van,player_id,man,ket_qua,created_at) VALUES ('old','p',1,'thua','2026-01-01')")
    csdl.khoi_tao_csdl(path)
    with csdl.lay_csdl(path) as db:
        assert db.execute('SELECT ma_van FROM match_results').fetchone()[0] == 'old'
        assert db.execute('SELECT COUNT(*) FROM weekly_rank_runs').fetchone()[0] == 0
