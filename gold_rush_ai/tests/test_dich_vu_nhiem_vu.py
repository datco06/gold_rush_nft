"""Service dùng generator/validator và SQLite thật; LLM được giả lập tại biên."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
import json
from random import Random
from threading import Barrier, Event

import pytest

from core.luoi import BanDo
from core.man_choi import ManChoi


def context():
    m = ManChoi(2, "Màn thử", "Màn kiểm thử", "man_2.tmx", 100, 1.0, 5, 5, 3, 2)
    bd = BanDo(13, 1, [[False] * 13], [("george", 0, 0), ("coin", 4, 0), ("coin", 8, 0), ("coin", 12, 0)])
    return m, bd


def service(tep, provider=None):
    from core.kho_nhiem_vu import KhoNhiemVu
    from core.dich_vu_nhiem_vu import DichVuNhiemVu

    return DichVuNhiemVu(KhoNhiemVu(tep), provider=provider)


def tao(s, request="request_1", player="player_a", **kw):
    m, bd = context()
    return s.tao(player_id=player, request_id=request, man=m, ban_do=bd, rng=Random(2), **kw)


def muc_tieu(nv):
    return nv.objective, nv.target, nv.time_limit_seconds


def test_service_luu_offline_va_su_dung_lich_su_sau_khi_khoi_tao_lai(tmp_path):
    tep = tmp_path / "quests.sqlite3"
    cu = tao(service(tep))
    moi = tao(service(tep), "request_2")
    assert cu.generation_source == moi.generation_source == "rule_based"
    assert cu.reward.gold == moi.reward.gold == 0
    assert cu.id != moi.id
    assert muc_tieu(cu) != muc_tieu(moi)


def test_retry_tra_dung_ban_cu_khong_goi_provider_lan_nua(tmp_path):
    tep = tmp_path / "quests.sqlite3"
    cu = tao(service(tep))
    class KhongDuocGoi:
        def sinh(self, **kw):
            raise AssertionError("Retry đã lưu không được gọi LLM")
    gui_lai = tao(service(tep, KhongDuocGoi()))
    assert gui_lai == cu


def test_tach_nguoi_choi_du_dung_cung_request_id(tmp_path):
    s = service(tmp_path / "quests.sqlite3")
    a, b = tao(s), tao(s, player="player_b")
    assert a.id != b.id
    assert muc_tieu(a) == muc_tieu(b)


def test_yeu_cau_cung_key_doi_do_kho_bi_chan_truoc_khi_goi_llm(tmp_path):
    from core.kho_nhiem_vu import XungDotYeuCauNhiemVu

    tep = tmp_path / "quests.sqlite3"
    tao(service(tep))
    class KhongDuocGoi:
        def sinh(self, **kw):
            raise AssertionError("Request xung đột không được gọi LLM")
    with pytest.raises(XungDotYeuCauNhiemVu):
        tao(service(tep, KhongDuocGoi()), do_kho="hard")


def test_loi_llm_van_luu_duoc_fallback(tmp_path):
    from core.providers.llm import LoiProviderLLM

    class ProviderLoi:
        def sinh(self, **kw):
            raise LoiProviderLLM("Mất kết nối")
    tep = tmp_path / "quests.sqlite3"
    cu = tao(service(tep, ProviderLoi()))
    assert cu.generation_source == "rule_based"
    assert tao(service(tep)) == cu


def test_du_lieu_man_sai_khong_luu_quest(tmp_path):
    from core.ai_nhiem_vu import KhongCoNhiemVuPhuHop
    from core.kho_nhiem_vu import KhoNhiemVu

    tep = tmp_path / "quests.sqlite3"
    m, bd = context()
    bd.chan[0][2] = True
    with pytest.raises(KhongCoNhiemVuPhuHop):
        service(tep).tao(player_id="player_a", request_id="request_1", man=m, ban_do=bd)
    assert KhoNhiemVu(tep).lich_su("player_a", 2) == []


@pytest.mark.parametrize("trung_key", [True, False], ids=["same-request", "different-requests"])
def test_hai_service_dong_thoi_khong_luu_trung_hoac_lap_muc_tieu(tmp_path, trung_key):
    from core.kho_nhiem_vu import KhoNhiemVu

    tep = tmp_path / "quests.sqlite3"
    barrier = Barrier(2)
    class ProviderDongThoi:
        def sinh(self, *, system_prompt, user_prompt):
            barrier.wait(timeout=5)
            return json.dumps(json.loads(user_prompt)["quest"], ensure_ascii=False)
    mot, hai = service(tep, ProviderDongThoi()), service(tep, ProviderDongThoi())
    with ThreadPoolExecutor(max_workers=2) as pool:
        a = pool.submit(tao, mot, "request_1")
        b = pool.submit(tao, hai, "request_1" if trung_key else "request_2")
        nv_a, nv_b = a.result(timeout=15), b.result(timeout=15)
    lich_su = KhoNhiemVu(tep).lich_su("player_a", 2)
    if trung_key:
        assert nv_a == nv_b
        assert lich_su == [nv_a]
    else:
        assert len(lich_su) == 2
        assert nv_a.id != nv_b.id
        assert muc_tieu(nv_a) != muc_tieu(nv_b)


def test_same_key_da_luu_giua_lan_doc_cache_va_doc_lich_su(tmp_path):
    from core.dich_vu_nhiem_vu import DichVuNhiemVu
    from core.kho_nhiem_vu import KhoNhiemVu

    tep = tmp_path / "quests.sqlite3"
    da_doc_cache, da_luu = Event(), Event()
    class KhoChoLichSu(KhoNhiemVu):
        def lich_su(self, *args, **kw):
            da_doc_cache.set()
            assert da_luu.wait(timeout=5)
            return super().lich_su(*args, **kw)

    nguoi_thang = service(tep)
    nguoi_gui_lai = DichVuNhiemVu(KhoChoLichSu(tep))
    m, bd = context()
    # Màn chỉ có một lựa chọn: nếu đọc history mới rồi sinh lại sẽ báo hết quest.
    m = replace(m, gioi_han_giay=7)
    args = {"player_id": "player_a", "request_id": "request_1", "man": m, "ban_do": bd}
    with ThreadPoolExecutor(max_workers=1) as pool:
        gui_lai = pool.submit(nguoi_gui_lai.tao, **args)
        try:
            assert da_doc_cache.wait(timeout=5)
            da_tao = nguoi_thang.tao(**args)
        finally:
            da_luu.set()
        assert gui_lai.result(timeout=10) == da_tao
    assert KhoNhiemVu(tep).lich_su("player_a", 2) == [da_tao]
