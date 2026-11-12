from dataclasses import replace

import pytest
from pydantic import ValidationError

from core.man_choi import ManChoi
from core.nhat_ky import NhatKyVan


def man():
    return ManChoi(1, "Màn thử", "Luyện tập", "gold_rush.tmx", 0, 1.0, 0, 0, 24, 1)


def van(i, ket_qua="thang", xu=24, **kw):
    return NhatKyVan(ma_van=f"game-{i:04d}", phien_ban_app="1.3.0", ket_qua=ket_qua,
                     diem=xu * 20, giay=120, **kw)


def de_xuat(lich_su=(), **kw):
    from core.ca_nhan_hoa_do_kho import de_xuat_do_kho
    return de_xuat_do_kho(man(), lich_su, **kw)


def test_nguoi_moi_co_fallback_trung_tinh():
    kq = de_xuat()
    assert kq.difficulty == "medium"
    assert kq.performance_score is None
    assert kq.adjustments.enemy_speed_multiplier == 1.0
    assert kq.source == "fallback"
    assert kq.sample_count == 0
    assert kq.schema_version == 1
    assert "3 ván" in kq.reason


@pytest.mark.parametrize("so_van", [1, 2])
def test_chua_du_du_lieu_khong_suy_dien_tay_nghe(so_van):
    kq = de_xuat([van(i) for i in range(so_van)])
    assert kq.source == "fallback"
    assert kq.performance_score is None
    assert kq.sample_count == so_van


@pytest.mark.parametrize("cac_van,score,do_kho,he_so,ti_le", [
    ([van(i, "thua", 6) for i in range(4)], 0.075, "easy", 0.95, "0%"),
    ([van(0), van(1), van(2, "thua", 12), van(3, "thua", 12)], 0.575, "medium", 1.03, "50%"),
    ([van(i) for i in range(4)], 1.0, "hard", 1.05, "100%"),
], ids=["yeu", "trung-binh", "gioi"])
def test_phan_loai_nguoi_choi_co_diem_va_ly_do(cac_van, score, do_kho, he_so, ti_le):
    kq = de_xuat(cac_van)
    assert kq.source == "rule_based"
    assert kq.performance_score == pytest.approx(score)
    assert kq.difficulty == do_kho
    assert kq.adjustments.enemy_speed_multiplier == pytest.approx(he_so)
    assert kq.sample_count == 4
    assert "4 ván" in kq.reason
    assert f"tỷ lệ thắng {ti_le}" in kq.reason


@pytest.mark.parametrize("thang,thua,do_kho,score", [
    (2, 3, "medium", 0.4), (3, 1, "hard", 0.75),
])
def test_nguong_phan_loai_khong_bi_sai_do_lam_tron(thang, thua, do_kho, score):
    kq = de_xuat([van(i) for i in range(thang)] +
                 [van(i + thang, "thua", 0) for i in range(thua)])
    assert kq.performance_score == score
    assert kq.difficulty == do_kho


def test_bo_giua_chung_va_man_khac_khong_anh_huong_de_xuat():
    ds = [van(i, "thua", 0) for i in range(3)]
    truoc = de_xuat(ds)
    sau = de_xuat(ds + [van(10, "bo", 0), van(11, man=2), van(12, ban_do="other.tmx")])
    assert sau == truoc


def test_chi_dung_muoi_van_hoan_tat_gan_nhat():
    kq = de_xuat([van(0)] + [van(i, "thua", 0) for i in range(1, 11)])
    assert kq.sample_count == 10
    assert kq.performance_score == 0.0
    assert kq.difficulty == "easy"


def test_retry_nhat_ky_khong_lam_tang_so_mau():
    nk = van(0)
    ds = [nk, nk.model_copy(update={"nhan_luc": "khac"}), van(1)]
    kq = de_xuat(ds)
    assert kq.sample_count == 2
    assert kq.source == "fallback"


def test_cung_ma_van_co_ket_qua_khac_phai_bao_loi():
    with pytest.raises(ValueError):
        de_xuat([van(0), van(0, "thua", 0)])


@pytest.mark.parametrize("truoc", [0.8, 0.95, 1.0, 1.1, 1.15])
@pytest.mark.parametrize("ket_qua,xu", [("thang", 24), ("thua", 0)])
def test_he_so_co_gioi_han_va_dich_chuyen_toi_da_nam_phan_tram(truoc, ket_qua, xu):
    kq = de_xuat([van(i, ket_qua, xu) for i in range(3)], he_so_truoc=truoc)
    he_so = kq.adjustments.enemy_speed_multiplier
    assert 0.8 <= he_so <= 1.15
    assert abs(he_so - truoc) <= 0.050000001
    assert he_so >= truoc if ket_qua == "thang" else he_so <= truoc


def test_fallback_tro_ve_trung_tinh_tu_tu_khi_co_he_so_cu():
    assert de_xuat(he_so_truoc=1.15).adjustments.enemy_speed_multiplier == 1.1
    assert de_xuat(he_so_truoc=0.8).adjustments.enemy_speed_multiplier == 0.85


def test_lap_nhieu_lan_khong_vuot_gioi_han():
    he_so = 1.0
    for _ in range(20):
        he_so = de_xuat([van(i) for i in range(3)], he_so_truoc=he_so).adjustments.enemy_speed_multiplier
    assert he_so == 1.15


@pytest.mark.parametrize("truoc", [True, "1.0", 0.79, 1.16, float("nan"), float("inf")],
                         ids=["bool", "string", "thap", "cao", "nan", "inf"])
def test_tu_choi_he_so_truoc_khong_hop_le(truoc):
    with pytest.raises(ValueError):
        de_xuat(he_so_truoc=truoc)


@pytest.mark.parametrize("nk", [van(0, "thua", 25), van(0, "thang", 23),
    van(0, "thua", 0).model_copy(update={"diem": 21}),
    van(0).model_copy(update={"diem": "480"})], ids=["vuot-xu", "thang-thieu-xu", "diem-le", "sai-kieu"])
def test_nhat_ky_mau_thuan_khong_duoc_dung_de_ca_nhan_hoa(nk):
    with pytest.raises(ValueError):
        de_xuat([nk])


@pytest.mark.parametrize("doi", [{"id": True}, {"so_xu": 0}, {"so_xu": 24.0}, {"tep": ""}])
def test_tu_choi_du_lieu_man_sai(doi):
    from core.ca_nhan_hoa_do_kho import de_xuat_do_kho
    with pytest.raises(ValueError):
        de_xuat_do_kho(replace(man(), **doi), [])


def test_nhat_ky_cu_khong_co_anh_chup_va_su_kien_van_dung_duoc():
    ds = [van(i) for i in range(3)]
    assert all(not nk.anh_chup and not nk.su_kien for nk in ds)
    assert de_xuat(ds).performance_score == 1.0
    assert all(nk.diem == 480 for nk in ds)


def test_json_co_the_doc_lai_va_khong_chap_nhan_tham_so_chua_ho_tro():
    from core.ca_nhan_hoa_do_kho import DeXuatDoKho, DieuChinhTocDo
    kq = de_xuat([van(i) for i in range(3)])
    assert DeXuatDoKho.model_validate_json(kq.model_dump_json()) == kq
    assert kq.adjustments.model_dump() == {"enemy_speed_multiplier": 1.05}
    with pytest.raises(ValidationError):
        DieuChinhTocDo(enemy_speed_multiplier=1.0, enemy_count_multiplier=2)
    with pytest.raises(ValidationError):
        kq.adjustments.enemy_speed_multiplier = 2.0


@pytest.mark.parametrize("truoc,ket_qua,xu", [
    (1.0249996, "thang", 24), (0.9750004, "thua", 0),
])
def test_he_so_cu_nhieu_chu_so_khong_lam_tron_vuot_buoc(truoc, ket_qua, xu):
    kq = de_xuat([van(i, ket_qua, xu) for i in range(3)], he_so_truoc=truoc)
    assert abs(kq.adjustments.enemy_speed_multiplier - truoc) <= 0.050000001

@pytest.mark.parametrize("phien_ban", [True, 1.0, "1"], ids=["bool", "float", "string"])
def test_schema_version_chi_nhan_so_nguyen_dung_kieu(phien_ban):
    from core.ca_nhan_hoa_do_kho import DeXuatDoKho
    payload = de_xuat().model_dump() | {"schema_version": phien_ban}
    with pytest.raises(ValidationError):
        DeXuatDoKho.model_validate(payload)
