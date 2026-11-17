from concurrent.futures import ThreadPoolExecutor
import sqlite3
from threading import Barrier

import pytest


def kho(tmp_path, **kw):
    from core.quota_ai import KhoQuotaAI
    return KhoQuotaAI(tmp_path / "quota.sqlite3", **kw)


def test_quota_luu_qua_khoi_dong_lai_va_tach_nguoi_loai(tmp_path):
    from core.quota_ai import VuotQuotaAI
    kho(tmp_path).tieu_thu("player_a", "image", 1)
    with pytest.raises(VuotQuotaAI):
        kho(tmp_path).tieu_thu("player_a", "image", 1)
    kho(tmp_path).tieu_thu("player_b", "image", 1)
    kho(tmp_path).tieu_thu("player_a", "quest", 1)


def test_quota_doi_ngay_utc_va_retry_after_lam_tron_len(tmp_path):
    from core.quota_ai import VuotQuotaAI
    now = [86399.75]
    store = kho(tmp_path, lay_thoi_gian=lambda: now[0])
    store.tieu_thu("player_a", "image", 1)
    with pytest.raises(VuotQuotaAI) as error:
        store.tieu_thu("player_a", "image", 1)
    assert error.value.cho_lai_sau == 1
    now[0] = 86400.0
    store.tieu_thu("player_a", "image", 1)
    with pytest.raises(VuotQuotaAI) as error:
        store.tieu_thu("player_a", "image", 1)
    assert error.value.cho_lai_sau == 86400


def test_hai_kho_dong_thoi_khong_vuot_quota(tmp_path):
    from core.quota_ai import VuotQuotaAI
    stores = [kho(tmp_path) for _ in range(8)]
    barrier = Barrier(8)
    def goi(store):
        barrier.wait(timeout=5)
        try:
            store.tieu_thu("player_a", "image", 3)
            return True
        except VuotQuotaAI:
            return False
    with ThreadPoolExecutor(max_workers=8) as pool:
        assert sum(pool.map(goi, stores)) == 3


def test_gioi_han_khong_cho_phep_goi_va_co_the_tang_cau_hinh(tmp_path):
    from core.quota_ai import VuotQuotaAI
    store = kho(tmp_path)
    with pytest.raises(VuotQuotaAI):
        store.tieu_thu("player_a", "image", 0)
    store.tieu_thu("player_a", "image", 1)
    with pytest.raises(VuotQuotaAI):
        store.tieu_thu("player_a", "image", 1)
    store.tieu_thu("player_a", "image", 2)


@pytest.mark.parametrize("limit", [True, -1, 1.5, "1", 10001, None])
def test_gioi_han_sai_khong_tieu_thu_quota(tmp_path, limit):
    store = kho(tmp_path)
    with pytest.raises(ValueError):
        store.tieu_thu("player_a", "image", limit)
    store.tieu_thu("player_a", "image", 1)


@pytest.mark.parametrize("player,loai", [("", "image"), ("../a", "image"),
    ("a" * 65, "image"), (True, "image"), ("player_a", "unknown")])
def test_dinh_danh_sai_khong_tieu_thu_quota(tmp_path, player, loai):
    store = kho(tmp_path)
    with pytest.raises(ValueError):
        store.tieu_thu(player, loai, 1)
    store.tieu_thu("player_a", "image", 1)


@pytest.mark.parametrize("now", [True, -1, float("nan"), float("inf"), "now", 1e100])
def test_dong_ho_sai_bao_loi_co_kiem_soat(tmp_path, now):
    from core.quota_ai import LoiQuotaAI
    with pytest.raises(LoiQuotaAI):
        kho(tmp_path, lay_thoi_gian=lambda: now).tieu_thu("player_a", "image", 1)


def test_db_hong_khong_lo_duong_dan(tmp_path):
    from core.quota_ai import LoiQuotaAI
    (tmp_path / "quota.sqlite3").write_bytes(b"broken quota")
    with pytest.raises(LoiQuotaAI) as error:
        kho(tmp_path)
    assert str(tmp_path) not in str(error.value)


def test_khong_dung_database_memory():
    from core.quota_ai import KhoQuotaAI
    with pytest.raises(ValueError):
        KhoQuotaAI(":memory:")


def test_bo_dem_hong_khong_duoc_am_tham_dat_lai(tmp_path):
    from core.quota_ai import LoiQuotaAI
    store = kho(tmp_path)
    store.tieu_thu("player_a", "image", 2)
    with sqlite3.connect(tmp_path / "quota.sqlite3") as conn:
        conn.execute("UPDATE quota_ai SET so_luot = -1")
    with pytest.raises(LoiQuotaAI):
        store.tieu_thu("player_a", "image", 2)
