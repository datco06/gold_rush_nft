import pytest
from pydantic import ValidationError


IMAGE_ID = "img_" + "a" * 32


def phan_hoi(**kw):
    from core.nhan_vat_ai import AnhNhanVat
    return AnhNhanVat.model_validate({
        "image_id": IMAGE_ID, "image_url": f"/api/ai/nhan-vat/anh/{IMAGE_ID}",
        "width": 128, "height": 128, "generation_source": "demo", **kw,
    })


def test_mo_ta_tieng_viet_duoc_chuan_hoa_va_giu_noi_dung():
    from core.nhan_vat_ai import YeuCauTaoNhanVat
    yc = YeuCauTaoNhanVat(description="  Thợ mỏ tóc đỏ, mũ vàng.\nÁo xanh.  ")
    assert yc.description == "Thợ mỏ tóc đỏ, mũ vàng.\nÁo xanh."
    assert YeuCauTaoNhanVat(description="a" * 500).description == "a" * 500


@pytest.mark.parametrize("value", ["", " \n\t ", "a" * 501, None, 12, True, b"miner", [],
    "thợ\x00mỏ", "thợ\x1bmỏ", "thợ\x7fmỏ"],
    ids=["empty", "spaces", "long", "none", "int", "bool", "bytes", "list", "nul", "escape", "delete"])
def test_mo_ta_thieu_sai_kieu_hoac_co_ky_tu_dieu_khien_bi_chan(value):
    from core.nhan_vat_ai import YeuCauTaoNhanVat
    with pytest.raises(ValidationError):
        YeuCauTaoNhanVat(description=value)


def test_request_khong_nhan_url_duong_dan_hoac_key_tu_client():
    from core.nhan_vat_ai import YeuCauTaoNhanVat
    for truong in ("image_url", "output_path", "api_key", "generation_source"):
        with pytest.raises(ValidationError):
            YeuCauTaoNhanVat.model_validate({"description": "Thợ mỏ", truong: "untrusted"})
    with pytest.raises(ValidationError):
        YeuCauTaoNhanVat.model_validate({})


def test_phan_hoi_anh_demo_va_model_co_schema_nhat_quan():
    from core.nhan_vat_ai import AnhNhanVat
    for nguon in ("demo", "image_model"):
        anh = phan_hoi(generation_source=nguon)
        assert anh.status == "ready"
        assert anh.schema_version == 1
        assert AnhNhanVat.model_validate_json(anh.model_dump_json()) == anh
        assert anh.generation_source == nguon


@pytest.mark.parametrize("doi", [
    {"image_id": "../bad"}, {"image_id": "img_" + "a" * 33},
    {"image_id": "img_" + "G" * 32}, {"image_url": "https://example.test/image.png"},
    {"image_url": "/api/ai/nhan-vat/anh/other"}, {"image_url": "C:/private/image.png"},
    {"image_url": f"/api/ai/nhan-vat/anh/{IMAGE_ID}?path=private"},
    {"width": 128.0}, {"width": True}, {"height": 64},
    {"status": "completed"}, {"generation_source": "unknown"},
    {"schema_version": True}, {"schema_version": 1.0}, {"schema_version": 2},
    {"file_path": "C:/private"},
], ids=["path-id", "long-id", "hex-id", "external-url", "wrong-id", "local-path", "query-url",
        "float-width", "bool-width", "height", "status", "source", "bool-version", "float-version", "version", "extra"])
def test_phan_hoi_tu_choi_metadata_khong_hop_le(doi):
    with pytest.raises(ValidationError):
        phan_hoi(**doi)


def test_metadata_bat_bien():
    anh = phan_hoi()
    with pytest.raises(ValidationError):
        anh.width = 64
