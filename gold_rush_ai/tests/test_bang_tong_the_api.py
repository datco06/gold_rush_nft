from datetime import datetime, timezone
import json
from uuid import UUID

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from api import bang_xep_hang as api_bxh
from api.auth_guard import NguoiChoiXacThuc, lay_nguoi_choi_hien_tai
from auth.models import Base, User
from core import csdl
from core.bang_xep_hang_tong_the import BoNhoBangTongThe
from core.tien_trinh_storage import KhoTienTrinh


@pytest.fixture
def setup(tmp_path, monkeypatch):
    engine = create_engine(f'sqlite:///{tmp_path / "auth.db"}')
    Base.metadata.create_all(engine)
    factory = sessionmaker(engine)
    with factory() as db:
        for i in range(35):
            db.add(User(id=UUID(int=i+1), wallet_address=f'0x{i:040x}', username=f'User{i}', username_key=f'user{i}'))
        db.commit()
    game_db = tmp_path / 'game.db'
    csdl.khoi_tao_csdl(game_db)
    with csdl.lay_csdl(game_db) as db:
        for i in range(35):
            uid = str(UUID(int=i+1))
            db.execute("INSERT INTO players(player_id,wallet_address,created_at,last_login) VALUES(?,?,?,?)", (uid, f'0x{i:040x}', 'now', 'now'))
            db.execute("INSERT INTO player_progress(player_id,exp,completed_stage_ids,updated_at) VALUES(?,?,?,?)", (uid, 300 if i==34 else 100, '[1,2]' if i==34 else '[1]', 'now'))
    monkeypatch.setattr(api_bxh, 'ket_noi', lambda: csdl.ket_noi(game_db))
    monkeypatch.setattr(api_bxh, 'CHAIN_ID', 31337)
    monkeypatch.setattr(api_bxh.config, 'SBT_CHAIN_ID', 31337)
    monkeypatch.setattr(api_bxh.config, 'HOP_DONG_SBT', '0x'+'b'*40)
    monkeypatch.setattr(api_bxh.config, 'SO_PHIEU', tmp_path / 'vouchers')
    monkeypatch.setattr(api_bxh.config, 'SO_VE', tmp_path / 'tickets')
    monkeypatch.setattr(api_bxh.config, 'HOP_DONG_CUA_HANG', '0x'+'c'*40)
    monkeypatch.setattr(api_bxh, 'doc_so_du_va_huy_hieu', lambda wallets, *args: (
        {w: 1000+int(w,16) for w in wallets},
        {w: ([1,2] if w==f'0x{33:040x}' else []) for w in wallets}))
    app = FastAPI()
    app.include_router(api_bxh.router)
    app.state.auth_session_factory = factory
    app.state.kho_tien_trinh = KhoTienTrinh(tmp_path / 'verified-progress.db')
    clock = [0.0]
    app.state.bang_tong_the_cache = BoNhoBangTongThe(clock=lambda: clock[0])
    player = NguoiChoiXacThuc(user_id=str(UUID(int=1)), wallet_address='0x'+'0'*40, username='Spoofed session label')
    app.dependency_overrides[lay_nguoi_choi_hien_tai] = lambda: player
    yield TestClient(app), app, clock
    engine.dispose()


def test_full_registered_server_top30_names_levels_and_personal_not_client_metrics(setup):
    client, app, _ = setup
    response = client.get('/api/bang-xep-hang/tong-the?level=999&top=999')
    assert response.status_code == 200
    data = response.json()
    assert response.headers['cache-control'] == 'no-store, private'
    assert data['tong_nguoi'] == 35 and len(data['bang']) == 30
    assert data['bang'][0]['ten'] == 'User34' and data['bang'][0]['level'] == 3
    assert data['bang'][1]['ten'] == 'User33' and data['bang'][1]['huy_hieu'] == [1,2]
    assert data['ban']['ten'] == 'User0'
    assert data['viewer'] == '0x'+'0'*40
    app.dependency_overrides.clear()
    assert client.get('/api/bang-xep-hang/tong-the').status_code == 401


def test_source_failure_keeps_last_complete_snapshot_not_fake_zero_badges(setup, monkeypatch, caplog):
    client, app, clock = setup
    first = client.get('/api/bang-xep-hang/tong-the').json()
    def offline(*args): raise RuntimeError('private RPC details')
    monkeypatch.setattr(api_bxh, 'doc_so_du_va_huy_hieu', offline)
    clock[0] = 61
    later = client.get('/api/bang-xep-hang/tong-the').json()
    assert later['du_lieu_cu'] is True
    assert later['bang'] == first['bang']
    assert later['cap_nhat_luc'] == first['cap_nhat_luc']
    app.state.bang_tong_the_cache = BoNhoBangTongThe()
    response = client.get('/api/bang-xep-hang/tong-the')
    assert response.status_code == 503 and 'private' not in response.text
    assert 'RuntimeError' in caplog.text and 'bang_xep_hang.py:' in caplog.text
    assert 'private RPC details' not in caplog.text


def test_verified_progress_and_real_balances_work_without_exp_or_reward_ledgers(setup):
    client, app, clock = setup
    with api_bxh.ket_noi() as db:
        db.execute("UPDATE player_progress SET exp=0,completed_stage_ids='[]'")
        db.commit()
    for stage in (1, 2, 7):
        app.state.kho_tien_trinh.ghi_nhan_hoan_thanh(
            owner_user_id=str(UUID(int=1)), verified_wallet_address='0x'+'0'*40,
            stage_id=stage, verification_source='referee_validation',
            completion_evidence={'ma_van': f'real-{stage}'}, replay_key=f'referee:real-{stage}')
    data = client.get('/api/bang-xep-hang/tong-the').json()
    assert data['ban']['level'] == 4 and data['ban']['vang'] == '1000'
    assert data['bang'][0]['ten'] == 'User0'
    assert not api_bxh.config.SO_PHIEU.exists() and not api_bxh.config.SO_VE.exists()


def test_missing_progress_source_does_not_fake_new_account_levels(setup):
    client, app, clock = setup
    first = client.get('/api/bang-xep-hang/tong-the').json()
    app.state.kho_tien_trinh.db_path.unlink()
    clock[0] = 61
    later = client.get('/api/bang-xep-hang/tong-the').json()
    assert later['du_lieu_cu'] is True and later['bang'] == first['bang']
    app.state.bang_tong_the_cache = BoNhoBangTongThe()
    assert client.get('/api/bang-xep-hang/tong-the').status_code == 503


def test_live_balance_can_decrease_after_spending_without_stale_earned_gold_guard(setup, monkeypatch):
    client, app, clock = setup
    source = api_bxh.doc_so_du_va_huy_hieu
    balances, badges = source([f'0x{i:040x}' for i in range(35)])
    monkeypatch.setattr(api_bxh, 'doc_so_du_va_huy_hieu', lambda *args: (dict(balances), badges))
    assert client.get('/api/bang-xep-hang/tong-the').json()['ban']['vang'] == '1000'
    balances['0x'+'0'*40] = 7
    clock[0] = 61
    later = client.get('/api/bang-xep-hang/tong-the').json()
    assert later['ban']['vang'] == '7' and later['du_lieu_cu'] is False


def test_account_and_wallet_must_match_and_dev_fixtures_do_not_raise_level(setup):
    client, app, _ = setup
    for stage, owner, wallet, source in [
        (2, str(UUID(int=1)), '0x'+'f'*40, 'referee_validation'),
        (3, str(UUID(int=1)), '0x'+'0'*40, 'dev_test_fixture'),
        (4, str(UUID(int=2)), '0x'+'0'*40, 'referee_validation'),
    ]:
        app.state.kho_tien_trinh.ghi_nhan_hoan_thanh(
            owner_user_id=owner, verified_wallet_address=wallet, stage_id=stage,
            verification_source=source, completion_evidence={}, replay_key=f'test:{stage}')
    assert client.get('/api/bang-xep-hang/tong-the').json()['ban']['level'] == 2


def test_verified_sources_union_distinct_stages_not_replays_or_other_chain(setup):
    client, app, _ = setup
    wallet = '0x'+'0'*40
    for stage in (1, 7):
        app.state.kho_tien_trinh.ghi_nhan_hoan_thanh(
            owner_user_id=str(UUID(int=1)), verified_wallet_address=wallet, stage_id=stage,
            verification_source='referee_validation', completion_evidence={}, replay_key=f'verified:{stage}')
    with api_bxh.ket_noi() as db:
        for chain, run, stage in [(31337,'first',7),(31337,'replay',7),(31337,'later',8),(1,'wrong-chain',9)]:
            db.execute('''INSERT INTO weekly_rank_runs
                (chain_id,ma_van,wallet,ten,man,diem,duration_ms,thich_ung,verified_at)
                VALUES(?,?,?,?,?,20,1000,0,?)''', (chain,run,wallet,'untrusted label',stage,'now'))
        db.commit()
    # Stage1 overlaps all three stores; Stage7 repeats; only {1,7,8} count.
    data = client.get('/api/bang-xep-hang/tong-the').json()
    assert data['ban']['level'] == 4 and data['ban']['ten'] == 'User0'


def test_changing_shop_contract_invalidates_cached_balances(setup, monkeypatch):
    client, app, _ = setup
    source = api_bxh.doc_so_du_va_huy_hieu
    calls = []
    def read(wallets, chain, shop, sbt):
        calls.append(shop)
        balances, badges = source(wallets)
        return {w:v+len(calls) for w,v in balances.items()},badges
    monkeypatch.setattr(api_bxh, 'doc_so_du_va_huy_hieu', read)
    assert client.get('/api/bang-xep-hang/tong-the').json()['ban']['vang'] == '1001'
    monkeypatch.setattr(api_bxh.config,'HOP_DONG_CUA_HANG','0x'+'d'*40)
    data = client.get('/api/bang-xep-hang/tong-the').json()
    assert data['ban']['vang'] == '1002' and len(calls) == 2


def test_legacy_verified_matches_restore_level7_without_new_progress_rows(setup):
    client, _, _ = setup
    with api_bxh.ket_noi() as db:
        db.execute("UPDATE player_progress SET completed_stage_ids='[]',exp=0")
        for run, stage in enumerate([1, 2, 3, 4, 5, 6, 1]):
            db.execute('''INSERT INTO match_results
                (ma_van,player_id,man,ket_qua,hop_le,is_verified,verified_by,verified_wallet,created_at)
                VALUES(?,?,?,'thang',1,1,'referee_voucher',?,'now')''',
                (f'old-win-{run}', 'client-reported-name', stage, '0x'+'0'*40))
        db.commit()
    data = client.get('/api/bang-xep-hang/tong-the').json()
    assert data['ban']['level'] == 7
    assert data['bang'][0]['ten'] == 'User0'
    assert data['ban']['vang'] == '1000'


@pytest.mark.parametrize('result,valid,verified,source,wallet', [
    ('thang',1,0,'telemetry_unverified','0x'+'0'*40),
    ('thang',1,1,'telemetry_unverified','0x'+'0'*40),
    ('thang',1,1,'referee_voucher',''),
    ('thang',1,1,'referee_voucher','0x'+'1'*40),
    ('thua',1,1,'referee_voucher','0x'+'0'*40),
    ('thang',0,1,'referee_voucher','0x'+'0'*40),
])
def test_legacy_matches_do_not_grant_levels_from_spoofed_or_unverified_results(
        setup, result, valid, verified, source, wallet):
    client, _, _ = setup
    with api_bxh.ket_noi() as db:
        db.execute("UPDATE player_progress SET completed_stage_ids='[]',exp=0")
        db.execute('''INSERT INTO match_results
            (ma_van,player_id,man,ket_qua,hop_le,is_verified,verified_by,verified_wallet,created_at)
            VALUES('spoof',?,6,?,?,?,?,?,'now')''',
            (str(UUID(int=1)), result, valid, verified, source, wallet))
        db.commit()
    assert client.get('/api/bang-xep-hang/tong-the').json()['ban']['level'] == 1


def test_schema_failure_logs_exact_source_without_sql_or_paths(setup, caplog):
    client, _, _ = setup
    with api_bxh.ket_noi() as db:
        db.execute('ALTER TABLE match_results RENAME COLUMN verified_wallet TO legacy_wallet')
        db.commit()
    response = client.get('/api/bang-xep-hang/tong-the')
    assert response.status_code == 503
    assert 'type=OperationalError source=nguon_bang_tong_the.py:' in caplog.text
    assert 'no such column' not in caplog.text and 'SELECT' not in caplog.text
    assert str(api_bxh.config.SO_PHIEU.parent) not in caplog.text
