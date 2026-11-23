from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from api import bang_xep_hang as api_bxh, main
from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai
from core import bang_xep_hang as bxh, csdl, nhat_ky, trong_tai


@pytest.fixture
def setup(tmp_path, monkeypatch):
    path = tmp_path / 'rank.db'
    csdl.khoi_tao_csdl(path)
    database = lambda: csdl.lay_csdl(path)
    monkeypatch.setattr(api_bxh, 'lay_csdl', database)
    monkeypatch.setattr(api_bxh, 'CHAIN_ID', 31337)
    monkeypatch.setattr(main, 'lay_csdl', database)
    monkeypatch.setattr(main, 'CHAIN_ID', 31337)
    monkeypatch.setattr(main, 'NHAT_KY_DIR', tmp_path / 'logs')
    monkeypatch.setattr(main, 'SO_PHIEU', tmp_path / 'vouchers.jsonl')
    monkeypatch.setattr(main, 'SO_VE', tmp_path / 'tickets.jsonl')
    monkeypatch.setattr(main, 'BAN_DO_DIR', tmp_path)
    monkeypatch.setattr(main, 'LOCAL_FAUCET_ENABLED', False)
    monkeypatch.setattr(trong_tai, 'VANG_TOI_DA_MOI_NGAY', 0)
    monkeypatch.setattr(main, '_khoa_trong_tai', lambda: b'')
    monkeypatch.setattr(main, '_ky', lambda *args: {'test_verified': True})
    monkeypatch.setattr(main, 'doc_tmx', lambda _: None)
    stage = SimpleNamespace(id=1, tep='stage.tmx', mien_phi=True)
    monkeypatch.setattr(main, '_cac_man', lambda: {1: stage})
    (tmp_path / 'stage.tmx').touch()
    monkeypatch.setattr(trong_tai, 'kiem_dinh', lambda *args: SimpleNamespace(hop_le=True, ly_do=[], so_vang=5))
    player = NguoiChoiXacThuc(user_id='alice', wallet_address='0x' + 'a' * 40, username='Alice')
    app = FastAPI()
    app.include_router(api_bxh.router)
    app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: player
    main.app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: player
    yield SimpleNamespace(path=path, db=database, player=player, app=app,
                          client=TestClient(app), game_client=TestClient(main.app), root=tmp_path)
    main.app.dependency_overrides.pop(lay_nguoi_choi_hien_tai, None)


def send_log(env, run='rank-run-001', result='thang'):
    nk = nhat_ky.NhatKyVan(ma_van=run, phien_ban_app='test', ket_qua=result,
                          man=1, ban_do='stage.tmx', giay=60, diem=100,
                          player_id='attacker', ten_hien_thi='attacker',
                          su_kien=[dict(loai='nhat_xu', giay=i + 1, x=i, y=1) for i in range(5)])
    nhat_ky.luu(nk, main.NHAT_KY_DIR)
    trong_tai.SoVe(main.SO_VE).bat_dau(run, env.player.wallet_address, 1, 0)


def test_api_requires_auth_and_does_not_accept_spoofed_personal_identity(setup):
    env = setup
    assert env.client.get('/api/bang-xep-hang/tuan?wallet=attacker&player_id=other').json()['ban'] is None
    env.app.dependency_overrides.clear()
    assert env.client.get('/api/bang-xep-hang/tuan?wallet=' + env.player.wallet_address).status_code == 401


@pytest.mark.parametrize('query', ['man=0', 'man=21', 'top=0', 'top=101', 'thich_ung=invalid'])
def test_query_validation(setup, query):
    assert setup.client.get('/api/bang-xep-hang/tuan?' + query).status_code == 422


def test_only_successful_referee_victory_is_counted_and_retry_is_immutable(setup):
    env = setup
    send_log(env)
    assert env.client.get('/api/bang-xep-hang/tuan').json()['bang'] == []
    result = env.game_client.post('/api/vang/phieu', json={'ma_van': 'rank-run-001'})
    assert result.status_code == 200, result.json()
    data = env.client.get('/api/bang-xep-hang/tuan').json()
    assert data['ban']['ten'] == 'Alice'
    assert data['ban']['diem'] == 100
    assert data['ban']['giay'] == 60
    assert env.game_client.post('/api/vang/phieu', json={'ma_van': 'rank-run-001'}).status_code == 200
    assert env.client.get('/api/bang-xep-hang/tuan').json() == data
    with env.db() as conn:
        assert conn.execute('SELECT COUNT(*) FROM weekly_rank_runs').fetchone()[0] == 1


def test_retry_recovers_missing_snapshot_in_original_issuance_week(setup):
    env = setup
    send_log(env)
    so = trong_tai.SoPhieu(main.SO_PHIEU)
    so.ghi('rank-run-001', env.player.wallet_address, 5, 1, 0)
    env.game_client.post('/api/vang/phieu', json={'ma_van': 'rank-run-001'})
    with env.db() as conn:
        stored = conn.execute('SELECT verified_at FROM weekly_rank_runs').fetchone()
    assert stored is not None
    assert int(datetime.fromisoformat(stored[0]).timestamp()) == so.lay('rank-run-001')['luc']


def test_losing_or_invalid_referee_result_never_scores(setup, monkeypatch):
    env = setup
    send_log(env, result='thua')
    env.game_client.post('/api/vang/phieu', json={'ma_van': 'rank-run-001'})
    assert env.client.get('/api/bang-xep-hang/tuan').json()['bang'] == []
    send_log(env, run='rank-run-002')
    monkeypatch.setattr(trong_tai, 'kiem_dinh', lambda *args: SimpleNamespace(hop_le=False, ly_do=['invalid'], so_vang=0))
    assert env.game_client.post('/api/vang/phieu', json={'ma_van': 'rank-run-002'}).status_code == 422
    assert env.client.get('/api/bang-xep-hang/tuan').json()['bang'] == []


def test_other_owner_cannot_score_and_storage_failure_does_not_block_rewards(setup, monkeypatch):
    env = setup
    send_log(env)
    other = NguoiChoiXacThuc(user_id='bob', wallet_address='0x' + 'b' * 40)
    main.app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: other
    assert env.game_client.post('/api/vang/phieu', json={'ma_van': 'rank-run-001'}).status_code == 403
    main.app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: env.player
    def unavailable(*args, **kwargs):
        raise RuntimeError('test storage unavailable')
    monkeypatch.setattr(bxh, 'ghi_van_da_xac_minh', unavailable)
    assert env.game_client.post('/api/vang/phieu', json={'ma_van': 'rank-run-001'}).status_code == 200
    assert env.client.get('/api/bang-xep-hang/tuan').json()['bang'] == []
