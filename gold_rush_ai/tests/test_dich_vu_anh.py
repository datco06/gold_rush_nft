from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import sqlite3
from threading import Barrier

from PIL import Image
import pytest

from core.kho_anh import KhoAnh
from core.nhan_vat_ai import YeuCauTaoNhanVat
from core.providers.anh import AnhMauOffline

ASSETS = Path(__file__).resolve().parents[2] / "gold_rush/assets/images"


class KhongDuocGoi:
    generation_source = "image_model"
    def sinh(self, **kw):
        raise AssertionError("Retry đã lưu không được gọi provider")


def service(tmp_path, *, provider=None, **kw):
    from core.dich_vu_anh import DichVuAnh
    return DichVuAnh(KhoAnh(tmp_path / "images.sqlite3", **kw),
                     demo_provider=AnhMauOffline(ASSETS), provider=provider)


def tao(s, *, player="player_a", request="request_1", description="Thợ mỏ mũ vàng"):
    return s.tao(player_id=player, request_id=request,
                 yeu_cau=YeuCauTaoNhanVat(description=description))


def counts(tmp_path):
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        return tuple(conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                     for table in ("anh_nhan_vat", "yeu_cau_anh"))


def test_tao_va_retry_sau_khi_mo_lai_tra_cung_anh(tmp_path):
    anh = tao(service(tmp_path))
    cu = tao(service(tmp_path, provider=KhongDuocGoi()))
    assert anh == cu
    assert counts(tmp_path) == (1, 1)


def test_cung_key_doi_mo_ta_bi_chan_truoc_khi_goi_provider(tmp_path):
    from core.kho_anh import XungDotYeuCauAnh
    tao(service(tmp_path))
    with pytest.raises(XungDotYeuCauAnh):
        tao(service(tmp_path, provider=KhongDuocGoi()), description="Cao bồi áo nâu")
    assert counts(tmp_path) == (1, 1)


def test_mo_ta_da_trim_co_cung_dau_van_tay(tmp_path):
    s = service(tmp_path)
    a = tao(s)
    b = tao(s, description="  Thợ mỏ mũ vàng  ")
    assert a == b


def test_nguoi_khac_cung_key_duoc_anh_rieng_va_khong_doc_cheo(tmp_path):
    s = service(tmp_path)
    a = tao(s)
    b = tao(s, player="player_b")
    assert a.image_id != b.image_id
    assert s.kho.doc_cho_nguoi("player_a", a.image_id)[0] == a
    assert s.kho.doc_cho_nguoi("player_b", a.image_id) is None
    assert counts(tmp_path) == (2, 2)


def test_anh_cu_chua_co_chu_chi_doc_noi_bo(tmp_path):
    from core.ai_nhan_vat import tao_anh_nhan_vat
    s = service(tmp_path)
    kq = tao_anh_nhan_vat(YeuCauTaoNhanVat(description="Thợ mỏ"), demo_provider=AnhMauOffline(ASSETS))
    anh = s.kho.luu(kq)
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        conn.execute("DROP TABLE yeu_cau_anh")
    s = service(tmp_path)
    assert s.kho.doc(anh.image_id) is not None
    assert s.kho.doc_cho_nguoi("player_a", anh.image_id) is None


def test_het_ttl_cho_phep_tai_su_dung_key_va_don_lien_ket_cu(tmp_path):
    now = [1000.0]
    s = service(tmp_path, han_luu_giay=10, lay_thoi_gian=lambda: now[0])
    a = tao(s)
    now[0] = 1010.0
    b = tao(s, description="Cao bồi")
    assert a.image_id != b.image_id
    assert s.kho.doc_cho_nguoi("player_a", a.image_id) is None
    assert counts(tmp_path) == (1, 1)
    now[0] = 1020.0
    assert s.kho.don_het_han() == 1
    assert counts(tmp_path) == (0, 0)


def test_loi_luu_lien_ket_rollback_ca_anh_va_metadata(tmp_path):
    from core.kho_anh import LoiKhoAnh
    s = service(tmp_path)
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        conn.execute("""CREATE TRIGGER chan_request BEFORE INSERT ON yeu_cau_anh
                        BEGIN SELECT RAISE(ABORT, 'private-path'); END""")
    with pytest.raises(LoiKhoAnh) as error:
        tao(s)
    assert "private-path" not in str(error.value)
    assert counts(tmp_path) == (0, 0)


def test_cache_bi_hong_khong_duoc_sinh_lai_am_tham(tmp_path):
    from core.kho_anh import LoiKhoAnh
    tao(service(tmp_path))
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        conn.execute("UPDATE anh_nhan_vat SET checksum = 'bad'")
    with pytest.raises(LoiKhoAnh):
        tao(service(tmp_path, provider=KhongDuocGoi()))


@pytest.mark.parametrize("player,request_id", [("../a", "ok"), ("ok", "bad/key"), ("", "ok"), ("ok", "x" * 65)])
def test_id_yeu_cau_sai_bi_chan_truoc_provider(tmp_path, player, request_id):
    with pytest.raises(ValueError):
        tao(service(tmp_path, provider=KhongDuocGoi()), player=player, request=request_id)


def test_hai_service_dong_thoi_chi_luu_mot_ket_qua(tmp_path):
    barrier = Barrier(2)
    class ProviderCho:
        generation_source = "image_model"
        def sinh(self, **kw):
            barrier.wait(timeout=5)
            with Image.new("RGBA", (16, 16), "red") as image, BytesIO() as buf:
                image.save(buf, format="PNG")
                return buf.getvalue()
    cac_service = [service(tmp_path, provider=ProviderCho()) for _ in range(2)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        ket_qua = list(pool.map(tao, cac_service))
    assert ket_qua[0] == ket_qua[1]
    assert counts(tmp_path) == (1, 1)
