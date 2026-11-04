"""Mô hình dự đoán "người chơi sắp thua" để điều chỉnh độ khó động (Dynamic Difficulty Adjustment).

Quy trình y hệt Ứng dụng 1 của notebook AI Web Apps, chỉ khác dữ liệu:
  dữ liệu → chia tập THEO VÁN CHƠI → huấn luyện → chọn theo val → báo cáo MỘT LẦN trên test
  → lưu mô hình + metrics.json → xuất sang app.

Điểm khác quan trọng: mô hình chạy TRÊN MÁY người chơi, mỗi 10 giây một lần, nên ta chọn
hồi quy logistic — xuất ra vài con số JSON, Dart tính lại bằng 10 dòng mã, không cần
TFLite hay ONNX. Mô hình lớn hơn (mạng nơ-ron) mới cần tới các runtime đó.

HỢP ĐỒNG ĐẶC TRƯNG (feature contract) — PHẢI khớp `lib/ai/nhat_ky_choi.dart`:
  ti_le_mau            máu hiện tại / máu tối đa                  (0..1)
  trung_don_moi_phut   số lần trúng đòn / số phút đã chơi
  xu_moi_phut          số xu đã nhặt / số phút đã chơi
  ti_le_xu             số xu đã nhặt / tổng số xu                 (0..1)
  phut_da_choi         số phút đã chơi
  (số phút lấy tối thiểu 0,25 để tránh chia cho số rất nhỏ ở đầu ván)
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np

DAC_TRUNG = ["ti_le_mau", "trung_don_moi_phut", "xu_moi_phut", "ti_le_xu", "phut_da_choi"]
PHUT_TOI_THIEU = 0.25
PHIEN_BAN = "do_kho_v1"


def dac_trung(mau: int, mau_toi_da: int, so_lan_trung: int,
              so_xu: int, tong_xu: int, giay: float) -> list[float]:
    """Tính vector đặc trưng từ các con số thô — bản Python của `NhatKyChoi.dacTrung()`."""
    phut = max(giay / 60.0, PHUT_TOI_THIEU)
    return [mau / mau_toi_da, so_lan_trung / phut, so_xu / phut,
            (so_xu / tong_xu) if tong_xu else 0.0, giay / 60.0]


# ---------------------------------------------------------------------------
# 1. Dữ liệu MÔ PHỎNG — thay bằng nhật ký thật thu qua POST /api/nhat-ky khi có
# ---------------------------------------------------------------------------
def mo_phong(so_van: int = 3000, seed: int = 42, tong_xu: int = 24, mau_toi_da: int = 100,
             mat_moi_lan: int = 25) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Mô phỏng các ván chơi với "tay nghề" ẩn của người chơi.

    Mỗi giây: bị trúng đòn với xác suất phụ thuộc tay nghề; nhặt xu với xác suất tăng theo tay nghề.
    Cứ 10 giây ghi một ảnh chụp đặc trưng. Nhãn của MỌI ảnh chụp trong ván = kết cục cuối ván
    (1 = thua). Trả về X, y và mã ván (để chia tập theo ván, tránh rò rỉ dữ liệu).
    """
    rnd = np.random.default_rng(seed)
    X, y, nhom = [], [], []
    for van in range(so_van):
        tay_nghe = rnd.beta(2.2, 2.0)                       # 0 = mới chơi, 1 = cao thủ
        p_trung = 0.012 + 0.045 * (1 - tay_nghe) ** 1.5     # xác suất trúng đòn mỗi giây
        p_xu = 0.06 + 0.20 * tay_nghe                       # xác suất nhặt được xu mỗi giây
        mau, trung, xu, giay, anh = mau_toi_da, 0, 0, 0, []
        while mau > 0 and xu < tong_xu and giay < 360:
            giay += 1
            if rnd.random() < p_trung:
                trung += 1
                mau -= mat_moi_lan
            if rnd.random() < p_xu:
                xu += 1
            if giay % 10 == 0 and mau > 0:
                anh.append(dac_trung(mau, mau_toi_da, trung, xu, tong_xu, giay))
        thua = 1 if mau <= 0 else 0
        for a in anh:
            X.append(a); y.append(thua); nhom.append(van)
    return np.array(X, dtype=np.float64), np.array(y), np.array(nhom)


# ---------------------------------------------------------------------------
# 2. Huấn luyện + đánh giá
# ---------------------------------------------------------------------------
def huan_luyen(X: np.ndarray, y: np.ndarray, nhom: np.ndarray, seed: int = 42) -> tuple[dict, dict]:
    """Chia 70/15/15 THEO VÁN, chọn C theo val, báo cáo trên test. Trả về (mô hình JSON, chỉ số)."""
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import accuracy_score, brier_score_loss, roc_auc_score
    from sklearn.model_selection import GroupShuffleSplit

    gss = GroupShuffleSplit(n_splits=1, test_size=0.30, random_state=seed)
    tr, tam = next(gss.split(X, y, nhom))
    gss2 = GroupShuffleSplit(n_splits=1, test_size=0.50, random_state=seed)
    va_rel, te_rel = next(gss2.split(X[tam], y[tam], nhom[tam]))
    va, te = tam[va_rel], tam[te_rel]
    assert not set(nhom[tr]) & set(nhom[te]), "rò rỉ: cùng một ván ở cả train và test"

    # Chuẩn hoá theo TRAIN, không nhìn val/test
    tb, dl = X[tr].mean(axis=0), X[tr].std(axis=0) + 1e-9
    chuan = lambda A: (A - tb) / dl

    tot, tot_auc = None, -1.0
    for C in (0.01, 0.1, 1.0, 10.0):
        m = LogisticRegression(C=C, max_iter=2000).fit(chuan(X[tr]), y[tr])
        auc = roc_auc_score(y[va], m.predict_proba(chuan(X[va]))[:, 1])
        if auc > tot_auc:
            tot, tot_auc, tot_C = m, auc, C

    p = tot.predict_proba(chuan(X[te]))[:, 1]
    # Mốc so sánh đơn giản: "máu dưới một nửa thì sắp thua" — mô hình phải hơn mốc này mới đáng dùng
    moc = (X[te][:, 0] < 0.5).astype(float)
    chi_so = {
        "phien_ban": PHIEN_BAN,
        "du_lieu": "mo_phong",                               # đổi thành "nhat_ky_that" khi có dữ liệu thật
        "so_mau": {"train": int(len(tr)), "val": int(len(va)), "test": int(len(te))},
        "so_van": int(len(set(nhom))),
        "C_chon_theo_val": tot_C,
        "val_auc": round(float(tot_auc), 4),
        "test_auc": round(float(roc_auc_score(y[te], p)), 4),
        "test_brier": round(float(brier_score_loss(y[te], p)), 4),
        "test_accuracy@0.5": round(float(accuracy_score(y[te], p >= 0.5)), 4),
        "moc_so_sanh_auc(mau<0.5)": round(float(roc_auc_score(y[te], moc)), 4),
        "ti_le_thua": round(float(y.mean()), 4),
    }
    mo_hinh = {
        "phien_ban": PHIEN_BAN,
        "loai": "hoi_quy_logistic",
        "dac_trung": DAC_TRUNG,
        "phut_toi_thieu": PHUT_TOI_THIEU,
        "trung_binh": [round(float(v), 8) for v in tb],
        "do_lech": [round(float(v), 8) for v in dl],
        "he_so": [round(float(v), 8) for v in tot.coef_[0]],
        "chan": round(float(tot.intercept_[0]), 8),
    }
    # Ca kiểm thử nhúng sẵn: app Dart nạp tệp này và phải ra ĐÚNG các xác suất dưới đây (sai số 1e-6)
    mau_thu = [dac_trung(100, 100, 0, 3, 24, 30), dac_trung(50, 100, 2, 4, 24, 60),
               dac_trung(25, 100, 3, 6, 24, 120), dac_trung(75, 100, 1, 18, 24, 150),
               dac_trung(100, 100, 0, 0, 24, 0)]
    mau_thu = [[round(v, 8) for v in x] for x in mau_thu]
    mo_hinh["kiem_tra"] = [{"x": x, "p": round(du_doan(mo_hinh, x), 8)} for x in mau_thu]
    return mo_hinh, chi_so


def du_doan(mo_hinh: dict, x: list[float]) -> float:
    """Suy luận THUẦN (không cần sklearn) — đúng công thức Dart dùng."""
    z = mo_hinh["chan"]
    for xi, tb, dl, w in zip(x, mo_hinh["trung_binh"], mo_hinh["do_lech"], mo_hinh["he_so"]):
        z += w * (xi - tb) / dl
    return 1.0 / (1.0 + math.exp(-z))


def he_so_toc_do(p_thua: float, thap: float = 0.8, cao: float = 1.15) -> float:
    """Quy xác suất thua thành hệ số tốc độ kẻ địch — bản Python của `DieuChinhDoKho.mucTieu()`."""
    return min(cao, max(thap, 1.0 - 0.4 * (p_thua - 0.5)))


def luu(mo_hinh: dict, chi_so: dict, thu_muc: Path) -> Path:
    thu_muc.mkdir(parents=True, exist_ok=True)
    tep = thu_muc / f"{mo_hinh['phien_ban']}.json"
    tep.write_text(json.dumps(mo_hinh, ensure_ascii=False, indent=2), encoding="utf-8")
    (thu_muc / "metrics.json").write_text(json.dumps(chi_so, ensure_ascii=False, indent=2), encoding="utf-8")
    return tep
