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

## Chuẩn bị môi trường trên Windows PowerShell

Chạy từ `D:\Projects\gold_rush_nft\gold_rush_ai`, dùng Python 3.12.10:

```powershell
Set-Location D:\Projects\gold_rush_nft\gold_rush_ai
python --version
python -m venv .venv
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt -c requirements-lock.txt
& .\.venv\Scripts\python.exe -m pip check
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
```

Nếu `.venv` đã tồn tại, dùng lại môi trường đó; không cần chạy lại lệnh tạo.
Không cần kích hoạt `Activate.ps1`, nên không phải thay execution policy.
`requirements-lock.txt` ghim 64 dependency của baseline **Windows x64/Python 3.12.10**.
Đây là bản constraints cho `requirements.txt`, không phải bản khóa mọi nền tảng.
Không nâng cấp package tự động; sau khi đổi dependency cần kiểm thử và cập nhật bản khóa.

Trong lần thiết lập Giai đoạn 1, toàn bộ wheel có sẵn trong cache đã được dùng để cài offline.
Máy hiện tại có thể cài lại bằng:

```powershell
& .\.venv\Scripts\python.exe -m pip install --no-index --find-links .venv/wheelhouse -r requirements.txt -c requirements-lock.txt
```

Wheelhouse là dữ liệu local trong `.venv`, không được đưa lên Git; máy mới dùng lệnh cài đầu tiên.

`.env` và `.venv/` được `.gitignore` gốc bỏ qua; `.env.example` được chia sẻ.
`config.py` chỉ đọc biến môi trường, **không tự nạp `.env`**.
API dùng `--env-file`; lệnh test/dashboard dùng CLI `python-dotenv` để nạp file.
Biến môi trường có sẵn được ưu tiên qua `--no-override` ở các lệnh dưới.
Luôn chạy tại thư mục `gold_rush_ai` vì đường dẫn model trong `.env.example` là tương đối.

## Chạy API

```powershell
Set-Location D:\Projects\gold_rush_nft\gold_rush_ai
& .\.venv\Scripts\python.exe -m uvicorn api.main:app --env-file .env --host 127.0.0.1 --port 8000
```

Tài liệu tương tác: <http://127.0.0.1:8000/docs>. Kiểm tra:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health
```

Phải thấy `da_nap.do_kho = true` và `da_nap.tro_ly = true`; chỉ `status=ok` chưa đủ.
`.env.example` trỏ model tới `../gold_rush/assets/models/do_kho_v1.json` đang có sẵn,
không cần train hoặc chép đè asset. Nếu bỏ cấu hình này, backend mặc định tìm
`artifacts/do_kho/do_kho_v1.json`; checkout mới chưa có file đó nên API độ khó trả 503.

Chưa cần khóa trọng tài hay địa chỉ hợp đồng để thử AI. Các route `/api/vang/*`
cần khóa/hợp đồng vẫn trả 503 khi chưa cấu hình. `ENABLED` giữ `vang` vì API danh sách
màn `/api/man` hiện dùng chung feature flag đó; bật flag không tự gửi giao dịch blockchain.

## Chạy dashboard Streamlit

Mở terminal thứ hai trong `gold_rush_ai`, giữ API đang chạy ở terminal đầu:

```powershell
& .\.venv\Scripts\python.exe -m dotenv -f .env run --no-override -- .\.venv\Scripts\python.exe -m streamlit run streamlit_app.py --server.address 127.0.0.1 --server.port 8501 --server.headless true --browser.gatherUsageStats false
```

Dashboard: <http://127.0.0.1:8501>. `API_URL` được đọc từ `.env`.
Dừng từng server bằng `Ctrl+C` tại terminal tương ứng.

## Kiểm thử baseline

```powershell
& .\.venv\Scripts\python.exe -m dotenv -f .env run --no-override -- .\.venv\Scripts\python.exe -m pytest -q
& .\.venv\Scripts\python.exe scripts/kiem_tra_ban_do.py ../gold_rush/assets/tiles
```

Baseline gồm 72 test Python; test API dùng dữ liệu tạm, không gửi giao dịch.
TestClient hiện có cảnh báo deprecation về HTTPX; ghi nhận trong biên bản Giai đoạn 1,
chưa thay hàng loạt dependency chỉ để tắt cảnh báo.

## Kết nối Flutter

```powershell
Set-Location D:\Projects\gold_rush_nft\gold_rush
flutter run -d chrome --web-port 5000 --dart-define=GOLD_RUSH_API=http://127.0.0.1:8000
```

Đây là lệnh khởi chạy sau khi chuẩn bị nền tảng Flutter và giải quyết lỗi build hiện có.
Checkout đang thiếu các thư mục nền tảng; Giai đoạn 1 AI không tự chạy `flutter create .`.
Giai đoạn 0 đã xác nhận 24 test AI đạt nhưng `flutter analyze` còn lỗi
`components/ban_do.dart:101`: `TileLayer.tileAt` không tồn tại trong dependency local.
Cần phối hợp chủ gameplay/map trước khi xác nhận game chạy hoàn chỉnh.

Địa chỉ backend theo môi trường:

| Client | `GOLD_RUSH_API` |
|---|---|
| Chrome cùng máy | `http://127.0.0.1:8000` |
| Android Emulator | `http://10.0.2.2:8000` |
| Android thật | `http://<IP-LAN-của-máy-chủ>:8000` |

Thiết bị khác cần Uvicorn bind `--host 0.0.0.0`, cùng mạng và firewall cho phép.
CORS phải khớp origin/port web; `.env.example` cho phép localhost/127.0.0.1 port 5000,
8501 và localhost port 5173. HTTP trên Android còn cần cấu hình nền tảng phù hợp.
Chưa kiểm thử kết nối từ Android thật/emulator trong Giai đoạn 1.

## Công cụ có ghi dữ liệu

Các lệnh sau có thể ghi model, bản đồ hoặc asset; không cần chạy để khởi động API/dashboard:

```powershell
& .\.venv\Scripts\python.exe scripts/huan_luyen_do_kho.py --khong-chep-sang-app
& .\.venv\Scripts\python.exe scripts/sinh_ban_do.py --seed 7
& .\.venv\Scripts\python.exe scripts/sinh_man_choi.py --xem
```

`huan_luyen_do_kho.py` khi bỏ `--khong-chep-sang-app` có thể ghi đè model Flutter.
Script `sinh_man_choi.py` ghi tài nguyên màn dùng chung với nhóm.
`scripts/thu_dau_cuoi.py` cần `eth-account`, Hardhat và có gửi giao dịch;
không cài/chạy nó trong phạm vi chuẩn bị môi trường AI.

## Mô hình nằm ở đâu

| Mô hình | Huấn luyện ở | Tệp | App dùng ở |
|---|---|---|---|
| Độ khó thích ứng (hồi quy logistic) | `core/do_kho.py` | `artifacts/do_kho/do_kho_v1.json` | `gold_rush/assets/models/do_kho_v1.json` → `lib/ai/mo_hinh_do_kho.dart` |
| Tìm đường A* | (thuật toán, không huấn luyện) | — | `gold_rush/lib/ai/tim_duong.dart` (bản Python: `core/luoi.py`) |
| Sinh bản đồ | (thuật toán, không huấn luyện) | `.tmx` sinh ra | `gold_rush/assets/tiles/` |
| Trợ lý gợi ý | chỉ mục TF-IDF dựng lúc khởi động | `data/kb/*.md` | gọi qua `POST /api/tro-ly` |

**Lưu ý:** mô hình độ khó hiện được huấn luyện trên **dữ liệu mô phỏng** để chạy được ngay.
Khi đã có ≥ 200 ván thật trong `data/nhat_ky/`, chạy lại với `--nguon nhat_ky`.
