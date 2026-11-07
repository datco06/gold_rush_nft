from __future__ import annotations

from random import Random
from typing import Literal

from .kho_nhiem_vu import KhoNhiemVu, LichSuNhiemVuDaThayDoi, LoiKhoNhiemVu
from .luoi import BanDo
from .man_choi import ManChoi
from .nhiem_vu import NhiemVu
from .nhiem_vu_llm import tao_nhiem_vu_voi_llm
from .providers.llm import NhaCungCapLLM
from .providers.quota import LLMCoQuota
from .quota_ai import KhoQuotaAI, kiem_tra_gioi_han


class DichVuNhiemVu:
    def __init__(self, kho: KhoNhiemVu, *, provider: NhaCungCapLLM | None = None,
                 quota: KhoQuotaAI | None = None, gioi_han_ngay: int = 20):
        self.kho = kho
        self.provider = provider
        self.quota = quota
        self.gioi_han_ngay = kiem_tra_gioi_han(gioi_han_ngay)
        if quota is not None and quota.duong_dan.resolve() == kho.duong_dan.resolve():
            raise ValueError("Quota cần database riêng với kho nhiệm vụ")

    def tao(self, *, player_id: str, request_id: str, man: ManChoi, ban_do: BanDo,
            do_kho: Literal["easy", "medium", "hard"] = "easy", rng: Random | None = None) -> NhiemVu:
        provider = self.provider
        if provider is not None and self.quota is not None:
            provider = LLMCoQuota(provider, self.quota, player_id, self.gioi_han_ngay)
        for lan in range(3):
            cu = self.kho.lay_theo_yeu_cau(player_id, request_id, man.id, do_kho)
            if cu is not None:
                return cu
            lich_su = self.kho.lich_su(player_id, man.id)
            cu = self.kho.lay_theo_yeu_cau(player_id, request_id, man.id, do_kho)
            if cu is not None:
                return cu
            nv = tao_nhiem_vu_voi_llm(man, ban_do, provider=provider if lan == 0 else None,
                                     lich_su=lich_su, do_kho=do_kho, rng=rng)
            try:
                return self.kho.luu(player_id, request_id, nv,
                                    sau_nhiem_vu_id=lich_su[-1].id if lich_su else None)
            except LichSuNhiemVuDaThayDoi:
                continue
        raise LoiKhoNhiemVu("Có nhiều yêu cầu đồng thời, chưa lưu được nhiệm vụ; hãy thử lại")
