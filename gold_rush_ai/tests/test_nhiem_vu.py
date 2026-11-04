"""Contract và giới hạn nhiệm vụ; không gọi mạng hoặc sửa tài nguyên game."""
import json

import pytest
from pydantic import ValidationError

from core.luoi import BanDo
from core.man_choi import ManChoi


def de_xuat(**thay_doi):
    from core.nhiem_vu import DeXuatNhiemVu

    return DeXuatNhiemVu.model_validate({
        "title": "Thợ mỏ chăm chỉ",
        "description": "Thu thập 2 đồng xu trong màn này.",
        "objective": "collect_coins",
        "target": 2,
        "difficulty": "easy",
        **thay_doi,
    })


def man_choi(**thay_doi):
    return ManChoi(**{
        "id": 2, "ten": "Màn thử", "mo_ta": "Màn kiểm thử",
        "tep": "man_2.tmx", "gioi_han_giay": 100,
        "he_so_ke_dich": 1.0, "coc": 5, "thuong": 5, "so_xu": 3, "sao": 2,
        **thay_doi,
    })


def ban_do():
    # Đường thẳng: George tại 0, ba xu ở 4/8/12; một ô = 16px.
    return BanDo(13, 1, [[False] * 13], [
        ("george", 0, 0), ("coin", 4, 0), ("coin", 8, 0), ("coin", 12, 0),
    ])


def kiem_tra(yc, man=None, bd=None):
    from core.kiem_tra_nhiem_vu import kiem_tra_nhiem_vu

    return kiem_tra_nhiem_vu(yc, man or man_choi(), bd or ban_do())


def test_request_chi_can_man_khong_bat_buoc_level_chua_co():
    from core.nhiem_vu import YeuCauTaoNhiemVu

    yc = YeuCauTaoNhiemVu.model_validate({"stage_id": 2})
    assert yc.stage_id == 2
    assert yc.player_id is None
    with pytest.raises(ValidationError):
        YeuCauTaoNhiemVu.model_validate({})


@pytest.mark.parametrize("sai", [0, -1, 1001, True, "2", 2.5])
def test_request_tu_choi_id_man_sai(sai):
    from core.nhiem_vu import YeuCauTaoNhiemVu

    with pytest.raises(ValidationError):
        YeuCauTaoNhiemVu.model_validate({"stage_id": sai})


@pytest.mark.parametrize("sai", ["", "   ", "../../player", "x" * 65])
def test_request_tu_choi_player_id_khong_hop_le(sai):
    from core.nhiem_vu import YeuCauTaoNhiemVu

    with pytest.raises(ValidationError):
        YeuCauTaoNhiemVu.model_validate({"stage_id": 2, "player_id": sai})


def test_schema_json_phan_biet_de_xuat_ai_va_nhiem_vu_server():
    from core.nhiem_vu import NhiemVu

    dx = de_xuat(title="  Thợ mỏ  ")
    nv = NhiemVu(**dx.model_dump(), id="quest_demo_001", stage_id=2, generation_source="rule_based")
    j = json.loads(nv.model_dump_json())
    assert j["title"] == "Thợ mỏ"
    assert j["objective"] == "collect_coins"
    assert j["target"] == 2
    assert j["time_limit_seconds"] is None
    assert j["reward"] == {"gold": 0}
    assert j["status"] == "offered"
    assert j["schema_version"] == 1


@pytest.mark.parametrize("sai", [
    {"objective": "defeat_boss"}, {"objective": "defeat_enemies"},
    {"objective": "escape_map"}, {"target": True}, {"target": "2"},
    {"target": 2.5}, {"target": 0}, {"target": -1},
    {"title": "  "}, {"description": "\n"}, {"title": "x" * 81},
    {"description": "x" * 501}, {"difficulty": "impossible"},
    {"reward": {"gold": 50}}, {"stage_id": 6}, {"status": "completed"},
    {"time_limit_seconds": 0}, {"time_limit_seconds": True},
    {"time_limit_seconds": 3601}, {"time_limit_seconds": float("inf")},
])
def test_de_xuat_tu_choi_du_lieu_sai_va_truong_server_so_huu(sai):
    with pytest.raises(ValidationError):
        de_xuat(**sai)


@pytest.mark.parametrize("objective,target,time_limit", [
    ("finish_before_time", 1, 20),
    ("finish_with_max_hits", 0, None),
    ("finish_with_max_hits", 3, None),
])
def test_schema_cho_phep_cac_muc_tieu_gameplay_ho_tro(objective, target, time_limit):
    yc = de_xuat(objective=objective, target=target, time_limit_seconds=time_limit)
    assert kiem_tra(yc) == yc


@pytest.mark.parametrize("sai", [
    {"objective": "finish_before_time", "target": 1},
    {"objective": "finish_before_time", "target": 2, "time_limit_seconds": 20},
    {"objective": "finish_with_max_hits", "target": 4},
])
def test_schema_chan_muc_tieu_mo_ho_hoac_so_lan_trung_gay_chet(sai):
    with pytest.raises(ValidationError):
        de_xuat(**sai)


@pytest.mark.parametrize("reward", [{"gold": 1}, {"gold": -1}, {"gold": True}, {"gold": 0, "nft": 1}])
def test_schema_chua_cho_phep_cap_thuong_that(reward):
    from core.nhiem_vu import NhiemVu

    with pytest.raises(ValidationError):
        NhiemVu(**de_xuat().model_dump(), id="quest_001", stage_id=2,
                generation_source="llm", reward=reward)


def test_target_nhat_xu_khong_vuot_kha_nang_ban_do():
    assert kiem_tra(de_xuat(target=3)).target == 3
    with pytest.raises(ValueError, match="xu"):
        kiem_tra(de_xuat(target=4))


def test_manifest_lech_so_xu_bi_tu_choi():
    with pytest.raises(ValueError, match="xu"):
        kiem_tra(de_xuat(), man=man_choi(so_xu=4))


def test_ban_do_xu_khong_toi_duoc_bi_tu_choi():
    bd = ban_do()
    bd.chan[0][2] = True
    with pytest.raises(ValueError, match="bản đồ"):
        kiem_tra(de_xuat(), bd=bd)


def test_thoi_han_khong_vuot_gioi_han_man():
    assert kiem_tra(de_xuat(time_limit_seconds=100)).time_limit_seconds == 100
    with pytest.raises(ValueError, match="(?i)thời"):
        kiem_tra(de_xuat(time_limit_seconds=101))


def test_thoi_gian_xet_dung_so_xu_can_nhat():
    # 4 ô = 64/74 giây; biên demo 1.5 lần + 5s, làm tròn lên = 7s.
    assert kiem_tra(de_xuat(target=1, time_limit_seconds=7)).target == 1
    with pytest.raises(ValueError, match="(?i)thời"):
        kiem_tra(de_xuat(target=1, time_limit_seconds=6))


def test_nhiem_vu_hoan_thanh_can_thoi_gian_cho_toan_bo_xu():
    # 12 ô = 192/74 giây; biên demo 1.5 lần + 5s, làm tròn lên = 9s.
    assert kiem_tra(de_xuat(objective="finish_before_time", target=1, time_limit_seconds=9))
    with pytest.raises(ValueError, match="(?i)thời"):
        kiem_tra(de_xuat(objective="finish_before_time", target=1, time_limit_seconds=8))


def test_man_qua_ngan_van_bi_chan_khi_quest_khong_co_han_rieng():
    with pytest.raises(ValueError, match="(?i)thời"):
        kiem_tra(de_xuat(objective="finish_with_max_hits", target=0),
                 man=man_choi(gioi_han_giay=8))


def test_man_khong_gioi_han_van_cho_phep_quest_co_han():
    assert kiem_tra(de_xuat(time_limit_seconds=20), man=man_choi(gioi_han_giay=0))
