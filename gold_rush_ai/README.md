# gold_rush_ai — máy chủ AI cho game Gold Rush

Đặt thư mục này **cạnh** thư mục `gold_rush/` (app Flutter):

```
du-an/
├── gold_rush/        ← app Flutter + Flame (chạy trên máy người chơi)
└── gold_rush_ai/     ← thư mục này (Python: huấn luyện, API, dashboard)
```

Cấu trúc theo đúng khuôn notebook *AI Web Apps — Streamlit & React*:

| Thư mục / tệp | Vai trò | Có biết gì về web? |
|---|---|---|
| `config.py` | mọi cấu hình, ghi đè bằng biến môi trường | không |
| `core/luoi.py` | đọc `.tmx`, A* tham chiếu, kiểm tra bản đồ chơi được | không |
| `core/sinh_ban_do.py` | sinh bản đồ theo thủ tục (automat tế bào + BFS) | không |
| `core/do_kho.py` | dữ liệu mô phỏng, huấn luyện, xuất mô hình độ khó | không |
| `core/nhat_ky.py` | lược đồ nhật ký ván chơi, lưu JSONL, bảng xếp hạng | không |
| `core/tro_ly.py` | trợ lý gợi ý cách chơi (RAG rút gọn, TF-IDF) | không |
| `core/ve.py` | vẽ bản đồ / bản đồ nhiệt | không |
| `core/man_choi.py` | đọc `man_choi.json`, ước lượng thời gian tối thiểu mỗi màn | không |
| `core/trong_tai.py` | kiểm định ván, ký phiếu EIP-712, sổ phiếu, sổ vé, đồng hồ máy chủ | không |
| `core/eth_ky.py` | keccak256 · secp256k1 · EIP-712 thuần Python | không |
| `api/main.py` | FastAPI bọc `core/` thành HTTP | có |
| `streamlit_app.py` | dashboard cho giảng viên / nhóm thiết kế | có |
| `scripts/` | lệnh dòng lệnh: huấn luyện, sinh bản đồ, kiểm định bản đồ | không |
| `data/kb/` | kho tri thức của trợ lý (Markdown, mỗi mục `## `) | — |
| `data/nhat_ky/` | nhật ký ván chơi nhận từ app (KHÔNG đưa lên Git) | — |
| `artifacts/do_kho/` | **mô hình** `do_kho_v1.json` + `metrics.json` | — |
| `tests/` | kiểm thử tự động | — |

## Chạy nhanh

```bash
pip install -r requirements.txt
python -m pytest -q                                  # 72 test (API cần fastapi, httpx)
python scripts/sinh_man_choi.py --xem                # sinh màn 2–6 + man_choi.json vào ../gold_rush/assets/tiles/
python scripts/thu_dau_cuoi.py                       # thử đầu–cuối với Hardhat node (cần pip install eth-account)

python scripts/huan_luyen_do_kho.py                  # huấn luyện, chép mô hình sang ../gold_rush/assets/models/
python scripts/sinh_ban_do.py --seed 7               # sinh bản đồ mới → artifacts/ban_do/
python scripts/kiem_tra_ban_do.py ../gold_rush/assets/tiles   # mọi màn chơi có thắng được không

uvicorn api.main:app --reload --port 8000            # API, tài liệu ở http://localhost:8000/docs
API_URL=http://localhost:8000 streamlit run streamlit_app.py
```

Cho app gửi nhật ký về máy chủ:

```bash
cd ../gold_rush
flutter run -d chrome --web-port 5000 --dart-define=GOLD_RUSH_API=http://localhost:8000
```

## Mô hình nằm ở đâu

| Mô hình | Huấn luyện ở | Tệp | App dùng ở |
|---|---|---|---|
| Độ khó thích ứng (hồi quy logistic) | `core/do_kho.py` | `artifacts/do_kho/do_kho_v1.json` | `gold_rush/assets/models/do_kho_v1.json` → `lib/ai/mo_hinh_do_kho.dart` |
| Tìm đường A* | (thuật toán, không huấn luyện) | — | `gold_rush/lib/ai/tim_duong.dart` (bản Python: `core/luoi.py`) |
| Sinh bản đồ | (thuật toán, không huấn luyện) | `.tmx` sinh ra | `gold_rush/assets/tiles/` |
| Trợ lý gợi ý | chỉ mục TF-IDF dựng lúc khởi động | `data/kb/*.md` | gọi qua `POST /api/tro-ly` |

**Lưu ý:** mô hình độ khó hiện được huấn luyện trên **dữ liệu mô phỏng** để chạy được ngay.
Khi đã có ≥ 200 ván thật trong `data/nhat_ky/`, chạy lại với `--nguon nhat_ky`.
