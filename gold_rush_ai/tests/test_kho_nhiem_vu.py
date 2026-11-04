"""Lưu trữ SQLite thật trong thư mục tạm, không ghi dữ liệu vận hành."""
import sqlite3

import pytest

from core.nhiem_vu import NhiemVu


def kho(tep):
    from core.kho_nhiem_vu import KhoNhiemVu

    return KhoNhiemVu(tep)


def nhiem_vu(so=1, **kw):
    return NhiemVu(id=f"quest_{so}", title="Thợ mỏ", description="Thu thập một đồng xu.",
                   objective="collect_coins", target=1, stage_id=2, difficulty="easy",
                   generation_source="rule_based", **kw)


def luu(k, so=1, *, player="player_a", request=None, sau=None):
    return k.luu(player, request or f"request_{so}", nhiem_vu(so), sau_nhiem_vu_id=sau)


def test_luu_va_doc_lai_sau_khi_mo_kho_moi(tmp_path):
    tep = tmp_path / "ai" / "quests.sqlite3"
    nv = luu(kho(tep))
    k = kho(tep)
    assert k.lay_theo_yeu_cau("player_a", "request_1", 2, "easy") == nv
    assert k.lich_su("player_a", 2) == [nv]
    assert nv.reward.gold == 0


def test_cung_request_khong_ghi_de_hoac_them_ban_ghi(tmp_path):
    k = kho(tmp_path / "quests.sqlite3")
    cu = luu(k)
    gui_lai = k.luu("player_a", "request_1", nhiem_vu(2), sau_nhiem_vu_id=None)
    assert gui_lai == cu
    assert k.lich_su("player_a", 2) == [cu]


@pytest.mark.parametrize("thay_doi", [{"stage_id": 3}, {"difficulty": "hard"}])
def test_cung_key_khong_duoc_dung_cho_yeu_cau_khac(tmp_path, thay_doi):
    from core.kho_nhiem_vu import XungDotYeuCauNhiemVu

    k = kho(tmp_path / "quests.sqlite3")
    cu = luu(k)
    nv = cu.model_copy(update={"id": "quest_khac", **thay_doi})
    with pytest.raises(XungDotYeuCauNhiemVu):
        k.luu("player_a", "request_1", nv, sau_nhiem_vu_id=cu.id)
    assert k.lich_su("player_a", 2) == [cu]


def test_lich_su_tach_player_va_man_gioi_han_theo_thu_tu_tao(tmp_path):
    k = kho(tmp_path / "quests.sqlite3")
    mot = luu(k, 1)
    hai = luu(k, 2, sau=mot.id)
    ba = luu(k, 3, sau=hai.id)
    luu(k, 4, player="player_b", request="request_1")
    man_khac = nhiem_vu(5).model_copy(update={"stage_id": 3})
    k.luu("player_a", "request_5", man_khac, sau_nhiem_vu_id=None)
    assert k.lich_su("player_a", 2, limit=2) == [hai, ba]
    assert k.lich_su("player_b", 2)[0].id == "quest_4"
    assert k.lich_su("player_a", 3) == [man_khac]
    assert k.lay_theo_yeu_cau("player_c", "request_1", 2, "easy") is None


def test_phat_hien_lich_su_da_doi_truoc_khi_luu(tmp_path):
    from core.kho_nhiem_vu import LichSuNhiemVuDaThayDoi

    k = kho(tmp_path / "quests.sqlite3")
    cu = luu(k)
    with pytest.raises(LichSuNhiemVuDaThayDoi):
        luu(k, 2, sau=None)
    assert k.lich_su("player_a", 2) == [cu]
    assert luu(k, 2, sau=cu.id).id == "quest_2"


@pytest.mark.parametrize("sai", ["", " ", "../../file", "x" * 65, True])
def test_khoa_khong_hop_le_bi_tu_choi(tmp_path, sai):
    k = kho(tmp_path / "quests.sqlite3")
    with pytest.raises(ValueError):
        k.luu(sai, "request_1", nhiem_vu(), sau_nhiem_vu_id=None)
    with pytest.raises(ValueError):
        k.luu("player_a", sai, nhiem_vu(), sau_nhiem_vu_id=None)
    assert k.lich_su("player_a", 2) == []


@pytest.mark.parametrize("limit", [0, -1, 101, True, 1.5])
def test_chan_limit_khong_hop_le(tmp_path, limit):
    with pytest.raises(ValueError):
        kho(tmp_path / "quests.sqlite3").lich_su("player_a", 2, limit=limit)


def test_file_database_hong_bao_loi_kho(tmp_path):
    from core.kho_nhiem_vu import LoiKhoNhiemVu

    tep = tmp_path / "quests.sqlite3"
    tep.write_bytes(b"not a SQLite database")
    with pytest.raises(LoiKhoNhiemVu):
        kho(tep)


def test_payload_luu_bi_hong_khong_bi_coi_la_lich_su_rong(tmp_path):
    from core.kho_nhiem_vu import LoiKhoNhiemVu

    tep = tmp_path / "quests.sqlite3"
    k = kho(tep)
    luu(k)
    with sqlite3.connect(tep) as conn:
        conn.execute("UPDATE nhiem_vu SET payload = ?", ("{}",))
    with pytest.raises(LoiKhoNhiemVu):
        k.lich_su("player_a", 2)


def test_loi_ghi_rollback_khong_lam_hong_ban_ghi_cu(tmp_path):
    from core.kho_nhiem_vu import LoiKhoNhiemVu

    k = kho(tmp_path / "quests.sqlite3")
    cu = luu(k)
    with pytest.raises(LoiKhoNhiemVu):
        k.luu("player_b", "request_b", cu, sau_nhiem_vu_id=None)
    assert k.lich_su("player_a", 2) == [cu]
    assert k.lich_su("player_b", 2) == []
    assert luu(k, 2, player="player_b").id == "quest_2"
