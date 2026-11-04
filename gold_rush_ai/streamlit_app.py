"""Bảng điều khiển Gold Rush — client mỏng gọi FastAPI (giống streamlit_app.py của notebook).

Chạy:  API_URL=http://localhost:8000 streamlit run streamlit_app.py
"""
import json
import os
import tempfile

import requests
import streamlit as st

from config import APP_FLUTTER
from core.luoi import doc_tmx
from core.ve import ve_ban_do

API = os.environ.get("API_URL", "http://localhost:8000")
st.set_page_config(page_title="Gold Rush · AI", page_icon="🪙", layout="wide")


def goi(method: str, duong_dan: str, **kw):
    """Mọi lời gọi API ở một chỗ; lỗi mạng hiện thành thông báo thay vì làm sập trang."""
    try:
        r = requests.request(method, f"{API}{duong_dan}", timeout=30, **kw)
        r.raise_for_status()
        return r
    except requests.RequestException as e:
        st.error(f"Không gọi được {duong_dan}: {e}")
        st.stop()


st.title("🪙 Gold Rush — bảng điều khiển AI")
suc_khoe = goi("GET", "/api/health").json()
st.caption(f"API: {API} · mô hình độ khó: {suc_khoe.get('phien_ban_mo_hinh') or 'chưa nạp'}")

tab_tq, tab_nhiet, tab_ban_do, tab_do_kho, tab_tro_ly = st.tabs(
    ["Tổng quan", "Bản đồ nhiệt", "Sinh bản đồ", "Mô hình độ khó", "Trợ lý"])

# ---------------------------------------------------------------- Tổng quan
with tab_tq:
    tk = goi("GET", "/api/thong-ke").json()
    c1, c2, c3, c4 = st.columns(4)
    tat_ca = tk["tat_ca"]
    c1.metric("Số ván", tat_ca.get("so_van", 0))
    c2.metric("Tỉ lệ thắng", f"{(tat_ca.get('ti_le_thang') or 0) * 100:.0f}%")
    c3.metric("Bỏ giữa chừng", f"{(tat_ca.get('ti_le_bo_giua_chung') or 0) * 100:.0f}%")
    c4.metric("Thời gian TB", f"{tat_ca.get('giay_trung_binh', 0):.0f} s")
    st.subheader("Có / không bật độ khó thích ứng")
    st.caption("Muốn kết luận độ khó thích ứng có hiệu quả, hai nhóm phải được chia NGẪU NHIÊN (thử nghiệm A/B), "
               "không để người chơi tự chọn.")
    st.dataframe({k: tk[k] for k in ("co_thich_ung", "khong_thich_ung")})
    st.subheader("Bảng xếp hạng")
    st.dataframe(goi("GET", "/api/bang-xep-hang", params={"top": 20}).json()["bang"], use_container_width=True)

# ---------------------------------------------------------------- Bản đồ nhiệt
with tab_nhiet:
    st.write("Nơi George hay trúng đòn — chỗ đỏ đậm là chỗ thiết kế màn chơi cần xem lại "
             "(kẻ địch đặt quá gần đường đi, góc khuất không có lối thoát…).")
    tep_mac_dinh = APP_FLUTTER / "assets" / "tiles" / "gold_rush.tmx"
    tep_tai = st.file_uploader("Tệp .tmx khác (bỏ trống = bản đồ gốc trong app)", type=["tmx"])
    if tep_tai is not None:
        with tempfile.NamedTemporaryFile(suffix=".tmx", delete=False) as f:
            f.write(tep_tai.getvalue())
        duong_dan, ten = f.name, tep_tai.name
    else:
        duong_dan, ten = tep_mac_dinh, tep_mac_dinh.name
    if not os.path.exists(duong_dan):
        st.warning(f"Không thấy {duong_dan} — tải tệp .tmx lên hoặc đặt biến APP_FLUTTER.")
    else:
        sk = goi("GET", "/api/su-kien", params={"loai": "trung_don", "ban_do": ten}).json()["su_kien"]
        st.caption(f"{len(sk)} lần trúng đòn được ghi nhận trên {ten}")
        st.pyplot(ve_ban_do(doc_tmx(duong_dan), su_kien=sk, tieu_de=ten))

# ---------------------------------------------------------------- Sinh bản đồ
with tab_ban_do:
    c1, c2 = st.columns([1, 3])
    seed = c1.number_input("seed", 0, 10**9, 7)
    mat_do = c1.slider("Độ rậm vật cản", 0.30, 0.48, 0.42, 0.01)
    r = goi("GET", "/api/ban-do/sinh", params={"seed": seed, "mat_do": mat_do})
    chi_so = json.loads(r.headers.get("X-Chi-So", "{}"))
    c1.json(chi_so)
    c1.download_button("Tải .tmx", r.content, file_name=f"gold_rush_{seed}.tmx", mime="application/xml")
    with tempfile.NamedTemporaryFile(suffix=".tmx", delete=False) as f:
        f.write(r.content)
    c2.pyplot(ve_ban_do(doc_tmx(f.name), tieu_de=f"seed={seed} · độ rậm={mat_do}"))

# ---------------------------------------------------------------- Mô hình độ khó
with tab_do_kho:
    st.write("Thử nhập trạng thái một ván để xem mô hình dự đoán gì — đúng 5 đặc trưng app gửi lên.")
    c1, c2 = st.columns(2)
    mau = c1.slider("Máu còn lại", 0, 100, 50, 25)
    trung = c1.number_input("Số lần trúng đòn", 0, 10, 2)
    xu = c1.number_input("Số xu đã nhặt", 0, 24, 4)
    giay = c1.slider("Đã chơi (giây)", 10, 360, 60, 10)
    phut = max(giay / 60, 0.25)
    dt = [mau / 100, trung / phut, xu / phut, xu / 24, giay / 60]
    kq = goi("POST", "/api/do-kho/du-doan", json={"dac_trung": dt}).json()
    c2.metric("Xác suất sắp thua", f"{kq['p_thua'] * 100:.0f}%")
    c2.metric("Hệ số tốc độ kẻ địch", f"× {kq['he_so_toc_do']:.2f}")
    c2.caption(f"Phiên bản: {kq['phien_ban']} · đặc trưng: {', '.join(kq['dac_trung'])}")

# ---------------------------------------------------------------- Trợ lý
with tab_tro_ly:
    if "hoi_thoai" not in st.session_state:
        st.session_state.hoi_thoai = []
    for vai, noi_dung in st.session_state.hoi_thoai:
        st.chat_message(vai).write(noi_dung)
    if cau := st.chat_input("Hỏi về cách chơi Gold Rush…"):
        st.session_state.hoi_thoai.append(("user", cau))
        st.chat_message("user").write(cau)
        tl = goi("POST", "/api/tro-ly", json={"cau_hoi": cau}).json()
        st.session_state.hoi_thoai.append(("assistant", tl["tra_loi"]))
        st.chat_message("assistant").write(tl["tra_loi"])
