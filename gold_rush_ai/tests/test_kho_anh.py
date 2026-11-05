"""Kho ảnh SQLite thật, thời gian giả lập, rollback và giới hạn đồng thời."""
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import re
import sqlite3
from threading import Barrier

from PIL import Image
import pytest

from core.ai_nhan_vat import KetQuaTaoAnh


class DongHo:
    def __init__(self):
        self.giay = 1000.0

    def __call__(self):
        return self.giay


@pytest.fixture
def dong_ho():
    return DongHo()


def ket_qua(*, source="demo", color=(20, 30, 40, 128)):
    with Image.new("RGBA", (16, 32), color) as image, BytesIO() as output:
        image.save(output, format="PNG")
        return KetQuaTaoAnh(png=output.getvalue(), generation_source=source)


def kho(tmp_path, dong_ho, **kw):
    from core.kho_anh import KhoAnh
    return KhoAnh(tmp_path / "images.sqlite3", lay_thoi_gian=dong_ho, **kw)


def so_anh(tmp_path):
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        return conn.execute("SELECT COUNT(*) FROM anh_nhan_vat").fetchone()[0]


def test_luu_mo_lai_doc_png_va_metadata_dung_contract(tmp_path, dong_ho):
    from core.nhan_vat_ai import AnhNhanVat
    anh = kho(tmp_path, dong_ho).luu(ket_qua())
    assert re.fullmatch(r"img_[0-9a-f]{32}", anh.image_id)
    assert anh.image_url == f"/api/ai/nhan-vat/anh/{anh.image_id}"
    assert anh.generation_source == "demo"
    assert AnhNhanVat.model_validate_json(anh.model_dump_json()) == anh
    metadata, raw = kho(tmp_path, dong_ho).doc(anh.image_id)
    assert metadata == anh
    with Image.open(BytesIO(raw)) as image:
        assert image.format == "PNG"
        assert image.mode == "RGBA"
        assert image.size == (128, 128)
        assert image.getpixel((64, 64)) == (20, 30, 40, 128)
    assert so_anh(tmp_path) == 1


def test_id_do_server_tao_moi_va_nguon_model_duoc_giu(tmp_path, dong_ho):
    store = kho(tmp_path, dong_ho)
    a = store.luu(ket_qua())
    b = store.luu(ket_qua(source="image_model"))
    assert a.image_id != b.image_id
    assert store.doc(b.image_id)[0].generation_source == "image_model"


@pytest.mark.parametrize("image_id", ["../secret", "C:/private.png", "img_bad", "img_" + "g" * 32,
    "img_" + "a" * 33, "img_" + "a" * 32 + "\n", None, True],
    ids=["traversal", "path", "short", "hex", "long", "newline", "none", "bool"])
def test_id_sai_bi_chan_truoc_khi_doc(tmp_path, dong_ho, image_id):
    with pytest.raises(ValueError):
        kho(tmp_path, dong_ho).doc(image_id)


def test_id_hop_le_khong_ton_tai_tra_none(tmp_path, dong_ho):
    assert kho(tmp_path, dong_ho).doc("img_" + "0" * 32) is None


def test_anh_het_han_dung_moc_va_doc_khong_gia_han(tmp_path, dong_ho):
    store = kho(tmp_path, dong_ho, han_luu_giay=10)
    anh = store.luu(ket_qua())
    dong_ho.giay = 1009.999
    assert store.doc(anh.image_id) is not None
    dong_ho.giay = 1010.0
    assert store.doc(anh.image_id) is None


def test_don_chi_xoa_anh_het_han_va_tra_dung_so_luong(tmp_path, dong_ho):
    store = kho(tmp_path, dong_ho, han_luu_giay=10)
    a = store.luu(ket_qua())
    dong_ho.giay = 1005.0
    b = store.luu(ket_qua())
    dong_ho.giay = 1010.0
    assert store.don_het_han() == 1
    assert store.don_het_han() == 0
    assert store.doc(a.image_id) is None
    assert store.doc(b.image_id) is not None
    assert so_anh(tmp_path) == 1


def test_luu_moi_tu_don_het_han_truoc_khi_kiem_tra_suc_chua(tmp_path, dong_ho):
    store = kho(tmp_path, dong_ho, han_luu_giay=10, so_anh_toi_da=1)
    a = store.luu(ket_qua())
    dong_ho.giay = 1010.0
    b = store.luu(ket_qua())
    assert store.doc(a.image_id) is None
    assert store.doc(b.image_id) is not None
    assert so_anh(tmp_path) == 1


def test_kho_day_khong_xoa_anh_con_han(tmp_path, dong_ho):
    from core.kho_anh import KhoAnhDay
    store = kho(tmp_path, dong_ho, so_anh_toi_da=1)
    a = store.luu(ket_qua())
    with pytest.raises(KhoAnhDay):
        store.luu(ket_qua())
    assert store.doc(a.image_id) is not None
    assert so_anh(tmp_path) == 1


def test_loi_ghi_rollback_khong_lam_mat_anh_cu_hoac_de_lai_ban_do(tmp_path, dong_ho):
    from core.kho_anh import LoiKhoAnh
    store = kho(tmp_path, dong_ho)
    anh = store.luu(ket_qua())
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        conn.execute("""CREATE TRIGGER chan_anh BEFORE INSERT ON anh_nhan_vat
                        BEGIN SELECT RAISE(ABORT, 'private-database-path'); END""")
    with pytest.raises(LoiKhoAnh) as error:
        store.luu(ket_qua())
    assert "private-database-path" not in str(error.value)
    assert str(tmp_path) not in str(error.value)
    assert so_anh(tmp_path) == 1
    assert store.doc(anh.image_id) is not None


@pytest.mark.parametrize("cot,value", [("payload", "{}"), ("png", b"corrupt"),
    ("checksum", "bad"), ("expires_at", "invalid")], ids=["metadata", "image", "checksum", "expiry"])
def test_du_lieu_luu_hong_bao_loi_kho(tmp_path, dong_ho, cot, value):
    from core.kho_anh import LoiKhoAnh
    store = kho(tmp_path, dong_ho)
    anh = store.luu(ket_qua())
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        conn.execute(f"UPDATE anh_nhan_vat SET {cot} = ? WHERE image_id = ?", (value, anh.image_id))
    with pytest.raises(LoiKhoAnh):
        store.doc(anh.image_id)


def test_metadata_thuoc_id_khac_khong_duoc_tra_ve(tmp_path, dong_ho):
    from core.kho_anh import LoiKhoAnh
    store = kho(tmp_path, dong_ho)
    a = store.luu(ket_qua())
    b = store.luu(ket_qua())
    with sqlite3.connect(tmp_path / "images.sqlite3") as conn:
        conn.execute("UPDATE anh_nhan_vat SET payload = ? WHERE image_id = ?", (b.model_dump_json(), a.image_id))
    with pytest.raises(LoiKhoAnh):
        store.doc(a.image_id)


def test_database_hong_hoac_parent_la_file_bao_loi_co_kiem_soat(tmp_path):
    from core.kho_anh import KhoAnh, LoiKhoAnh
    tep = tmp_path / "broken.sqlite3"
    tep.write_bytes(b"not sqlite")
    with pytest.raises(LoiKhoAnh):
        KhoAnh(tep)
    parent = tmp_path / "file"
    parent.write_bytes(b"data")
    with pytest.raises(LoiKhoAnh):
        KhoAnh(parent / "images.sqlite3")


@pytest.mark.parametrize("doi", [
    {"han_luu_giay": 0}, {"han_luu_giay": True}, {"han_luu_giay": 1.5},
    {"han_luu_giay": 31536001}, {"so_anh_toi_da": 0}, {"so_anh_toi_da": True},
    {"so_anh_toi_da": 10001}, {"lay_thoi_gian": None},
])
def test_tu_choi_cau_hinh_sai(tmp_path, doi):
    from core.kho_anh import KhoAnh
    with pytest.raises(ValueError):
        KhoAnh(tmp_path / "images.sqlite3", **doi)


def test_khong_dung_memory_vi_moi_thao_tac_mo_connection_rieng():
    from core.kho_anh import KhoAnh
    with pytest.raises(ValueError):
        KhoAnh(":memory:")


@pytest.mark.parametrize("bay_gio", [True, float("nan"), float("inf"), -1, "now"],
                         ids=["bool", "nan", "inf", "negative", "string"])
def test_thoi_gian_khong_hop_le_khong_ghi_anh(tmp_path, dong_ho, bay_gio):
    store = kho(tmp_path, dong_ho)
    dong_ho.giay = bay_gio
    with pytest.raises(ValueError):
        store.luu(ket_qua())
    assert so_anh(tmp_path) == 0


@pytest.mark.parametrize("kq", [KetQuaTaoAnh(png=b"bad", generation_source="demo"),
    ket_qua(source="unknown")], ids=["bad-image", "bad-source"])
def test_ket_qua_khong_hop_le_khong_duoc_luu(tmp_path, dong_ho, kq):
    with pytest.raises(ValueError):
        kho(tmp_path, dong_ho).luu(kq)
    assert so_anh(tmp_path) == 0


def test_hai_kho_ghi_dong_thoi_khong_vuot_gioi_han(tmp_path, dong_ho):
    from core.kho_anh import KhoAnhDay
    cac_kho = [kho(tmp_path, dong_ho, so_anh_toi_da=1) for _ in range(2)]
    barrier = Barrier(2)
    def ghi(store):
        barrier.wait(timeout=5)
        try:
            return store.luu(ket_qua()).image_id
        except KhoAnhDay:
            return None
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(ghi, cac_kho))
    assert sum(result is not None for result in results) == 1
    assert so_anh(tmp_path) == 1


def test_luu_duoc_anh_tu_pipeline_demo_thuc(tmp_path, dong_ho):
    from core.ai_nhan_vat import tao_anh_nhan_vat
    from core.nhan_vat_ai import YeuCauTaoNhanVat
    from core.providers.anh import AnhMauOffline
    assets = Path(__file__).resolve().parents[2] / "gold_rush/assets/images"
    kq = tao_anh_nhan_vat(YeuCauTaoNhanVat(description="Thợ mỏ mũ vàng"), demo_provider=AnhMauOffline(assets))
    store = kho(tmp_path, dong_ho)
    anh = store.luu(kq)
    assert store.doc(anh.image_id)[1] == kq.png

def test_doc_bi_cho_van_kiem_tra_thoi_han_sau_khi_doc_xong(tmp_path, dong_ho, monkeypatch):
    import core.kho_anh as module
    store = kho(tmp_path, dong_ho, han_luu_giay=10)
    anh = store.luu(ket_qua())
    connect = sqlite3.connect
    def ket_noi_cham(*args, **kw):
        dong_ho.giay = 1011.0
        return connect(*args, **kw)
    monkeypatch.setattr(module.sqlite3, "connect", ket_noi_cham)
    assert store.doc(anh.image_id) is None