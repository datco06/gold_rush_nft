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
            db.execute("INSERT INTO player_progress(player_id,exp,updated_at) VALUES(?,?,?)", (uid, 300 if i==34 else 100, 'now'))
    monkeypatch.setattr(api_bxh, 'ket_noi', lambda: csdl.ket_noi(game_db))
    monkeypatch.setattr(api_bxh, 'CHAIN_ID', 31337)
    monkeypatch.setattr(api_bxh.config, 'SBT_CHAIN_ID', 31337)
    monkeypatch.setattr(api_bxh.config, 'HOP_DONG_SBT', '0x'+'b'*40)
    monkeypatch.setattr(api_bxh.config, 'SO_PHIEU', tmp_path / 'vouchers')
    monkeypatch.setattr(api_bxh.config, 'SO_VE', tmp_path / 'tickets')
    monkeypatch.setattr(api_bxh, 'doc_huy_hieu', lambda wallets, *args: {w: ([1,2] if w==f'0x{33:040x}' else []) for w in wallets})
    app = FastAPI()
    app.include_router(api_bxh.router)
    app.state.auth_session_factory = factory
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


def test_source_failure_keeps_last_complete_snapshot_not_fake_zero_badges(setup, monkeypatch):
    client, app, clock = setup
    first = client.get('/api/bang-xep-hang/tong-the').json()
    def offline(*args): raise RuntimeError('private RPC details')
    monkeypatch.setattr(api_bxh, 'doc_huy_hieu', offline)
    clock[0] = 61
    later = client.get('/api/bang-xep-hang/tong-the').json()
    assert later['du_lieu_cu'] is True
    assert later['bang'] == first['bang']
    assert later['cap_nhat_luc'] == first['cap_nhat_luc']
    app.state.bang_tong_the_cache = BoNhoBangTongThe()
    response = client.get('/api/bang-xep-hang/tong-the')
    assert response.status_code == 503 and 'private' not in response.text
