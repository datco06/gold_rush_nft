from __future__ import annotations

from .ai_nhan_vat import tao_anh_nhan_vat
from .kho_anh import KhoAnh
from .nhan_vat_ai import AnhNhanVat, YeuCauTaoNhanVat
from .providers.anh import NhaCungCapAnh
from .providers.quota import AnhCoQuota
from .quota_ai import KhoQuotaAI, kiem_tra_gioi_han


class DichVuAnh:
    def __init__(
        self,
        kho: KhoAnh,
        *,
        demo_provider: NhaCungCapAnh,
        provider: NhaCungCapAnh | None = None,
        quota: KhoQuotaAI | None = None,
        gioi_han_ngay: int = 5,
        cho_phep_fallback: bool = True,
    ):
        self.kho = kho
        self.demo_provider = demo_provider
        self.provider = provider
        self.quota = quota
        self.gioi_han_ngay = kiem_tra_gioi_han(gioi_han_ngay)
        self.cho_phep_fallback = cho_phep_fallback
        if quota is not None and quota.duong_dan.resolve() == kho.duong_dan.resolve():
            raise ValueError("Quota cần database riêng với kho ảnh")

    def tao(self, *, player_id: str, request_id: str, yeu_cau: YeuCauTaoNhanVat) -> AnhNhanVat:
        cu = self.kho.lay_theo_yeu_cau(player_id, request_id, yeu_cau)
        if cu is not None:
            return cu
        provider = self.provider
        if provider is not None and self.quota is not None:
            provider = AnhCoQuota(provider, self.quota, player_id, self.gioi_han_ngay)
        return self.kho.tao_theo_yeu_cau(
            player_id,
            request_id,
            yeu_cau,
            lambda: tao_anh_nhan_vat(
                yeu_cau,
                demo_provider=self.demo_provider,
                provider=provider,
                cho_phep_fallback=self.cho_phep_fallback,
            ),
        )
