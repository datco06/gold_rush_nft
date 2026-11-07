from __future__ import annotations

from .ai_nhan_vat import tao_anh_nhan_vat
from .kho_anh import KhoAnh
from .nhan_vat_ai import AnhNhanVat, YeuCauTaoNhanVat
from .providers.anh import NhaCungCapAnh


class DichVuAnh:
    def __init__(self, kho: KhoAnh, *, demo_provider: NhaCungCapAnh,
                 provider: NhaCungCapAnh | None = None):
        self.kho = kho
        self.demo_provider = demo_provider
        self.provider = provider

    def tao(self, *, player_id: str, request_id: str, yeu_cau: YeuCauTaoNhanVat) -> AnhNhanVat:
        cu = self.kho.lay_theo_yeu_cau(player_id, request_id, yeu_cau)
        if cu is not None:
            return cu
        return self.kho.tao_theo_yeu_cau(player_id, request_id, yeu_cau,
            lambda: tao_anh_nhan_vat(yeu_cau, demo_provider=self.demo_provider, provider=self.provider))
