import pytest
from pydantic import ValidationError

from core.man_choi import ManChoi
from core.nhat_ky import NhatKyVan


def man():
    return ManChoi(1, "Màn thử", "Luyện tập", "gold_rush.tmx", 0, 1.0, 0, 0, 24, 1)


def van(i, ket_qua="thang", xu=24, **kw):
    return NhatKyVan(ma_van=f"game-{i:04d}", phien_ban_app="1.3.0", ket_qua=ket_qua,
                     diem=xu * 20, giay=120, **kw)


def chon(level, recent_history=()):
    from core.ca_nhan_hoa_nhiem_vu import HoSoNhiemVu, chon_do_kho_nhiem_vu
    return chon_do_kho_nhiem_vu(man(), HoSoNhiemVu(level=level, recent_history=tuple(recent_history)))


@pytest.mark.parametrize("level,want", [(1, "easy"), (2, "easy"), (3, "medium"),
    (4, "medium"), (5, "hard"), (1000, "hard")])
def test_cap_do_gioi_han_do_kho_du_lich_su_tot(level, want):
    assert chon(level, [van(i) for i in range(3)]) == want


def test_hieu_suat_yeu_va_trung_binh_khong_bi_ep_nhiem_vu_kho():
    assert chon(8, [van(i, "thua", 0) for i in range(3)]) == "easy"
    assert chon(8, [van(0), van(1), van(2, "thua", 12), van(3, "thua", 12)]) == "medium"


@pytest.mark.parametrize("level,want", [(1, "easy"), (3, "medium"), (8, "medium")])
def test_thieu_lich_su_dung_muc_than_trong(level, want):
    assert chon(level) == want
    assert chon(level, [van(0), van(1)]) == want


def test_bo_van_khac_man_ban_do_va_lap_khong_du_so_mau():
    ds = [van(0), van(0), van(1, man=2), van(2, ban_do="other.tmx"), van(3, "bo", 0)]
    assert chon(8, ds) == "medium"


def test_chi_dung_muoi_van_gan_nhat():
    assert chon(8, [van(i) for i in range(5)] +
                [van(i, "thua", 0) for i in range(5, 15)]) == "easy"


def test_lich_su_mau_thuan_bao_loi_khong_am_tham_bo_qua():
    from core.ca_nhan_hoa_nhiem_vu import LoiHoSoNhiemVu
    with pytest.raises(LoiHoSoNhiemVu):
        chon(8, [van(0), van(0, "thua", 0)])
    with pytest.raises(LoiHoSoNhiemVu):
        chon(8, [van(0, xu=25)])


@pytest.mark.parametrize("level", [True, 0, -1, 1.5, "5", 1001, None])
def test_cap_do_sai_kieu_hoac_gioi_han_bi_tu_choi(level):
    from core.ca_nhan_hoa_nhiem_vu import HoSoNhiemVu
    with pytest.raises(ValidationError):
        HoSoNhiemVu(level=level)


def test_ho_so_khong_nhan_du_lieu_thua_va_lich_su_qua_lon():
    from core.ca_nhan_hoa_nhiem_vu import HoSoNhiemVu
    with pytest.raises(ValidationError):
        HoSoNhiemVu(level=5, reward=100)
    with pytest.raises(ValidationError):
        HoSoNhiemVu(level=5, recent_history=(van(0),) * 1001)
