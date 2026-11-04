"""LLM chỉ sinh nội dung; mục tiêu hợp lệ và fallback thuộc backend."""
import json
from random import Random

import pytest

from core.ai_nhiem_vu import tao_nhiem_vu_du_phong
from core.luoi import BanDo
from core.man_choi import ManChoi


class ProviderGia:
    def __init__(self, content):
        self.content = content

    def sinh(self, *, system_prompt, user_prompt):
        return self.content


def context():
    m = ManChoi(2, "Màn thử", "Màn kiểm thử", "man_2.tmx", 100, 1.0, 5, 5, 3, 2)
    bd = BanDo(13, 1, [[False] * 13], [("george", 0, 0), ("coin", 4, 0), ("coin", 8, 0), ("coin", 12, 0)])
    return m, bd


def noi_dung(**thay_doi):
    return json.dumps({
        "title": "Ánh vàng đầu tiên", "description": "Thu thập 1 đồng xu để mở đầu chuyến tìm vàng.",
        "objective": "collect_coins", "target": 1, "time_limit_seconds": None, "difficulty": "easy",
        **thay_doi,
    }, ensure_ascii=False)


def tao(provider=None, **kw):
    from core.nhiem_vu_llm import tao_nhiem_vu_voi_llm

    return tao_nhiem_vu_voi_llm(*context(), provider=provider, rng=Random(2), **kw)


def test_llm_hop_le_chi_doi_noi_dung_giu_muc_tieu_va_thuong_server():
    nv = tao(ProviderGia(noi_dung()))
    assert nv.generation_source == "llm"
    assert nv.title == "Ánh vàng đầu tiên"
    assert nv.target == 1
    assert nv.objective == "collect_coins"
    assert nv.stage_id == 2
    assert nv.reward.gold == 0


def test_khong_co_provider_van_hoat_dong_offline():
    assert tao().generation_source == "rule_based"


@pytest.mark.parametrize("raw", ["not json", "```json\n{}\n```", "[]", "{}", "x" * 16385, None],
                         ids=["invalid-json", "markdown", "array", "missing-fields", "oversized", "not-text"])
def test_json_sai_thieu_qua_lon_tra_fallback_hop_le(raw):
    nv = tao(ProviderGia(raw))
    assert nv.generation_source == "rule_based"
    assert nv.target == 1
    assert nv.reward.gold == 0


@pytest.mark.parametrize("thay_doi", [
    {"target": 4}, {"target": 2}, {"target": True}, {"objective": "defeat_boss"},
    {"difficulty": "hard"}, {"time_limit_seconds": 1}, {"reward": {"gold": 50}},
    {"stage_id": 6}, {"status": "completed"}, {"title": "  "},
])
def test_llm_khong_duoc_doi_muc_tieu_hoac_them_quyen_server(thay_doi):
    assert tao(ProviderGia(noi_dung(**thay_doi))).generation_source == "rule_based"


def test_provider_loi_tra_fallback_khong_lo_chi_tiet_nhay_cam(caplog):
    from core.providers.llm import LoiProviderLLM

    class ProviderLoi:
        def sinh(self, **kw):
            raise LoiProviderLLM("secret-api-key")

    assert tao(ProviderLoi()).generation_source == "rule_based"
    assert "secret-api-key" not in caplog.text


def test_prompt_co_schema_va_muc_tieu_nhung_khong_gui_player_history_hoac_thuong():
    captured = []
    class ProviderPrompt:
        def sinh(self, *, system_prompt, user_prompt):
            captured.append((system_prompt, json.loads(user_prompt)))
            return noi_dung()

    nv = tao(ProviderPrompt())
    system, data = captured[0]
    assert nv.generation_source == "llm"
    assert data["quest"]["target"] == 1
    assert data["response_schema"]["additionalProperties"] is False
    assert "reward" not in data["quest"]
    assert "id" not in data["quest"]
    assert "JSON" in system


def test_loi_llm_van_giu_chong_lap_cua_fallback():
    cu = tao()
    moi = tao(ProviderGia("broken"), lich_su=[cu])
    assert moi.generation_source == "rule_based"
    assert (moi.objective, moi.target, moi.time_limit_seconds) != (cu.objective, cu.target, cu.time_limit_seconds)


def test_khong_goi_provider_khi_context_khong_the_tao_nhiem_vu():
    from core.ai_nhiem_vu import KhongCoNhiemVuPhuHop
    from core.nhiem_vu_llm import tao_nhiem_vu_voi_llm

    class KhongDuocGoi:
        def sinh(self, **kw):
            raise AssertionError("Không được gọi LLM với dữ liệu màn sai")

    m, bd = context()
    bd.chan[0][2] = True
    with pytest.raises(KhongCoNhiemVuPhuHop):
        tao_nhiem_vu_voi_llm(m, bd, provider=KhongDuocGoi())


@pytest.mark.parametrize("loai", ["timeout", "nested-json"])
def test_loi_qua_adapter_duoc_chuyen_sang_fallback(loai):
    import httpx
    from core.providers.llm import ChatCompletionsLLM

    def timeout(request):
        if loai == "timeout":
            raise httpx.ReadTimeout("simulated", request=request)
        return httpx.Response(200, content=b"[" * 10000 + b"0" + b"]" * 10000)

    with httpx.Client(transport=httpx.MockTransport(timeout)) as client:
        p = ChatCompletionsLLM(url="https://llm.example/chat", model="demo", client=client)
        assert tao(p).generation_source == "rule_based"
