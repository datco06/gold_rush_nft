from copy import deepcopy
from pathlib import Path
from random import Random

import pytest

from core.kiem_tra_nhiem_vu import kiem_tra_nhiem_vu
from core.luoi import BanDo, doc_tmx
from core.man_choi import ManChoi, doc
from core.nhiem_vu import NhiemVu


def man_choi(**thay_doi):
    return ManChoi(**{
        "id": 2, "ten": "Màn thử", "mo_ta": "Màn kiểm thử",
        "tep": "man_2.tmx", "gioi_han_giay": 100,
        "he_so_ke_dich": 1.0, "coc": 5, "thuong": 5, "so_xu": 3, "sao": 2,
        **thay_doi,
    })


def ban_do():
    return BanDo(13, 1, [[False] * 13], [
        ("george", 0, 0), ("coin", 4, 0), ("coin", 8, 0), ("coin", 12, 0),
    ])


def tao(man=None, bd=None, **kw):
    from core.ai_nhiem_vu import tao_nhiem_vu_du_phong

    return tao_nhiem_vu_du_phong(man or man_choi(), bd or ban_do(), **kw)


def khoa(nv):
    return (nv.stage_id, nv.objective, nv.target, nv.time_limit_seconds)


def test_offline_tra_nhiem_vu_dung_contract_khong_cap_thuong():
    nv = tao(rng=Random(2))
    assert isinstance(nv, NhiemVu)
    assert NhiemVu.model_validate_json(nv.model_dump_json()) == nv
    assert nv.stage_id == 2
    assert nv.id.startswith("quest_")
    assert nv.generation_source == "rule_based"
    assert nv.reward.gold == 0
    assert nv.status == "offered"
    assert kiem_tra_nhiem_vu(nv, man_choi(), ban_do()) == nv


def test_cung_seed_lap_lai_noi_dung_nhung_id_van_rieng_biet():
    a, b = tao(rng=Random(9)), tao(rng=Random(9))
    assert a.model_dump(exclude={"id"}) == b.model_dump(exclude={"id"})
    assert a.id != b.id


def test_tranh_lap_theo_muc_tieu_du_da_doi_id_va_tieu_de():
    cu = tao(rng=Random(2))
    doi_ten = cu.model_copy(update={"id": "quest_khac", "title": "Tiêu đề mới"})
    moi = tao(lich_su=[doi_ten], rng=Random(2))
    assert khoa(moi) != khoa(cu)


def test_uu_tien_chua_dung_roi_quay_vong_muc_tieu_lau_nhat():
    lich_su = []
    for _ in range(8):
        lich_su.append(tao(lich_su=lich_su, rng=Random(4)))
    cac_khoa = [khoa(nv) for nv in lich_su]
    assert len(set(cac_khoa[:4])) == 4
    assert {nv.objective for nv in lich_su[:4]} == {
        "collect_coins", "finish_before_time", "finish_with_max_hits",
    }
    assert cac_khoa[4:] == cac_khoa[:4]
    assert all(truoc != sau for truoc, sau in zip(cac_khoa, cac_khoa[1:]))


def test_lich_su_man_khac_khong_chan_nhiem_vu_man_hien_tai():
    cu = tao(rng=Random(2))
    man_khac = cu.model_copy(update={"stage_id": 3})
    moi = tao(lich_su=[man_khac], rng=Random(2))
    assert khoa(moi) == khoa(cu)


@pytest.mark.parametrize("do_kho,target", [("easy", 1), ("medium", 2), ("hard", 3)])
def test_do_kho_thay_doi_muc_tieu_xu_khong_chi_doi_nhan(do_kho, target):
    nv = tao(do_kho=do_kho, rng=Random(2))
    assert nv.difficulty == do_kho
    assert nv.objective == "collect_coins"
    assert nv.target == target


@pytest.mark.parametrize("sai", ["impossible", "", None, True])
def test_tu_choi_do_kho_khong_ho_tro(sai):
    with pytest.raises(ValueError):
        tao(do_kho=sai)


def test_loai_muc_tieu_qua_han_nhung_van_sinh_duoc_nhat_mot_xu():
    nv = tao(man=man_choi(gioi_han_giay=7), rng=Random(2))
    assert nv.objective == "collect_coins"
    assert nv.target == 1
    assert kiem_tra_nhiem_vu(nv, man_choi(gioi_han_giay=7), ban_do()) == nv


def test_chi_con_mot_lua_chon_vua_dung_thi_bao_khong_co_nhiem_vu_moi():
    from core.ai_nhiem_vu import KhongCoNhiemVuPhuHop

    m = man_choi(gioi_han_giay=7)
    cu = tao(man=m)
    with pytest.raises(KhongCoNhiemVuPhuHop):
        tao(man=m, lich_su=[cu])


@pytest.mark.parametrize("loi", ["manifest", "unreachable", "too_short"])
def test_khong_bo_qua_validator_khi_du_lieu_man_khong_phu_hop(loi):
    from core.ai_nhiem_vu import KhongCoNhiemVuPhuHop

    m, bd = man_choi(), ban_do()
    if loi == "manifest":
        m = man_choi(so_xu=4)
    elif loi == "unreachable":
        bd.chan[0][2] = True
    else:
        m = man_choi(gioi_han_giay=1)
    with pytest.raises(KhongCoNhiemVuPhuHop):
        tao(man=m, bd=bd)


def test_khong_sua_lich_su_hoac_ban_do_cua_ben_goi():
    m, bd = man_choi(), ban_do()
    lich_su = [tao(man=m, bd=bd, rng=Random(2))]
    bd_truoc, lich_su_truoc = deepcopy(bd), deepcopy(lich_su)
    tao(man=m, bd=bd, lich_su=lich_su, rng=Random(2))
    assert bd == bd_truoc
    assert lich_su == lich_su_truoc


@pytest.mark.parametrize("stage_id", [1, 2, 3, 4, 5, 6])
def test_sinh_offline_tren_ban_do_that(stage_id):
    tiles = Path(__file__).resolve().parents[2] / "gold_rush" / "assets" / "tiles"
    m = doc(tiles / "man_choi.json")[stage_id]
    bd = doc_tmx(tiles / m.tep)
    lich_su = []
    for _ in range(6):
        nv = tao(man=m, bd=bd, lich_su=lich_su, rng=Random(7))
        assert nv.stage_id == stage_id
        assert kiem_tra_nhiem_vu(nv, m, bd) == nv
        assert not lich_su or khoa(nv) != khoa(lich_su[-1])
        lich_su.append(nv)
    assert len({khoa(nv) for nv in lich_su[:4]}) == 4
