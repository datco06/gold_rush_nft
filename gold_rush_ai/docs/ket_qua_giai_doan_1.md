# Kết quả chuẩn bị môi trường AI

Ngày thực hiện: 05/11/2026. Branch: `feature/ai`. Căn cứ: kế hoạch Giai đoạn 1 trong báo cáo khảo sát và yêu cầu tiếp tục của người dùng.

**Kết quả:** môi trường Python độc lập đã sẵn sàng cho phát triển AI. Bộ 72 test hiện có đạt, API thật nạp được model, dashboard render đủ năm tab và hỏi trợ lý thành công trong AppTest. Không phát triển nhiệm vụ, độ khó mới hoặc sinh ảnh trong giai đoạn này.

## Môi trường đã thiết lập

- `.venv` dùng Python **3.12.10**; `include-system-site-packages=false`, user site bị tắt. Không dùng chung package global.
- Cài đúng **64 dependency** của requirements bằng wheel có sẵn trong cache, hoàn toàn offline; không nâng cấp Python/Flutter hoặc tải model.
- Thêm `requirements-lock.txt` chứa constraints của baseline Windows x64/Python 3.12.10. Đã đối chiếu toàn bộ 64 phiên bản với các package thực cài trong venv.
- Khai báo trực tiếp `python-dotenv[cli]` vì hướng dẫn test/dashboard sử dụng CLI đó. Phiên bản vẫn là 1.0.1 có trong baseline, không nâng cấp.
- Tạo `.env` cục bộ từ `.env.example`, giữ khóa trọng tài và địa chỉ hợp đồng chưa cấu hình.
- `MO_HINH_DO_KHO` trỏ tới `../gold_rush/assets/models/do_kho_v1.json` có sẵn. Không train, không chép hoặc thay đổi asset, không sửa `config.py`.
- `.env` được Uvicorn nạp qua `--env-file`; pytest/dashboard nạp qua `python -m dotenv ... run --no-override`. `config.py` vẫn chỉ đọc `os.environ`.

## Kiểm chứng thực tế

Tất cả lệnh Python bên dưới dùng `.venv\Scripts\python.exe`, cwd là `gold_rush_ai`.

| Kiểm tra | Kết quả |
|---|---|
| `python -m pip check` | `No broken requirements found` |
| Đối chiếu constraints với package đã cài | 64/64 phiên bản khớp |
| Python isolation | Python 3.12.10, `sys.prefix != sys.base_prefix`, `site.ENABLE_USER_SITE=False` |
| `python -m dotenv -f .env run --no-override -- <python-venv> -B -m pytest -q -p no:cacheprovider` | **72 passed, 1 warning, 18.67 giây** |
| `python -B scripts/kiem_tra_ban_do.py ../gold_rush/assets/tiles` | **6/6 bản đồ OK** |
| Uvicorn khởi chạy bằng `--env-file .env` trên loopback | Khởi động thành công |
| `GET /api/health` qua HTTP thật | 200; `do_kho=true`, `tro_ly=true`, phiên bản `do_kho_v1` |
| `GET /docs` | 200 |
| `GET /api/man` | 200, sáu màn |
| `GET /api/mo-hinh/do-kho` | 200 |
| `POST /api/do-kho/du-doan` | 200; input `[0.25,1.5,3,0.25,2]`, `p_thua=0.978033`, `he_so_toc_do=0.8088` |
| Streamlit server HTTP | Trang gốc và `/_stcore/health` trả 200 |
| Streamlit AppTest chạy script dashboard, gọi Uvicorn thật | Năm tab; không exception, không `st.error` |
| AppTest gửi “zombie đi nhanh không” | Hai chat message (người dùng + trợ lý); không exception hoặc `st.error` |
| Cleanup smoke test | Đã dừng cả hai tiến trình Uvicorn/Streamlit do kiểm thử tạo |
| Ignore | `.env`, `.venv/pyvenv.cfg`, wheelhouse và script smoke local bị Git bỏ qua; `.env.example` có thể theo dõi |

Smoke test chọn cổng loopback trống để tránh chiếm cổng server khác của người dùng; truyền `API_URL` tương ứng cho dashboard. Nhật ký/sổ vé/phiếu và file tạm của smoke test nằm trong thư mục tạm riêng, không ghi vào dữ liệu vận hành. Script kiểm thử local nằm trong `.venv/phase1_smoke.py`, không thuộc source được đưa lên Git.

AppTest kiểm tra script và cây UI, không phải kiểm tra hình thức bằng trình duyệt thật. Chưa chơi game hoặc thử Android trong giai đoạn này.

Rà soát độc lập không phát hiện vấn đề Critical/Important trong phạm vi Giai đoạn 1. Đã chỉnh thêm ba lệnh công cụ tùy chọn trong README để gọi Python venv rõ ràng, phù hợp cách thiết lập không activate venv; không chạy các công cụ ghi asset đó.

## File tạo mới và chỉnh sửa

| File | Thay đổi |
|---|---|
| `.env.example` | Cấu hình mẫu cho model, API URL, CORS và feature flags; không có bí mật |
| `requirements-lock.txt` | Constraints cho 64 dependency đã kiểm thử trên Windows/Python 3.12.10 |
| `requirements.txt` | Khai báo trực tiếp `python-dotenv[cli]>=1.0` |
| `.gitignore` | Sửa chú thích về model để phù hợp quy tắc ignore `artifacts/` từ gốc; không thay quy tắc backend trọng tài |
| `README.md` | Hướng dẫn venv, cài package, nạp `.env`, chạy API/dashboard/test bằng PowerShell; phân biệt lệnh ghi asset và giới hạn Flutter |
| `docs/ke_hoach_giai_doan_1.md` | Kế hoạch và tiến độ thực hiện |
| `docs/ket_qua_giai_doan_1.md` | Biên bản kết quả này |

Các file runtime `.venv/` và `.env` chỉ có ở máy local. Wheelhouse trong `.venv` hỗ trợ cài lại offline trên máy hiện tại; máy mới dùng lệnh pip từ README với bản constraints.

Không thay đổi `api/main.py`, `config.py`, `core/`, `streamlit_app.py`, gameplay, bản đồ, model hoặc `gold_rush_chain/`. `gold_rush/analysis_options.yaml` và `gold_rush/pubspec.lock` là thay đổi đã tồn tại trước công việc này và được giữ nguyên. Không commit/push/merge/rebase hoặc gửi giao dịch.

## Cách chạy

Mở terminal PowerShell trong `D:\Projects\gold_rush_nft\gold_rush_ai`:

```powershell
# Terminal 1 — API
& .\.venv\Scripts\python.exe -m uvicorn api.main:app --env-file .env --host 127.0.0.1 --port 8000
```

Mở terminal thứ hai cùng thư mục:

```powershell
# Terminal 2 — dashboard
& .\.venv\Scripts\python.exe -m dotenv -f .env run --no-override -- .\.venv\Scripts\python.exe -m streamlit run streamlit_app.py --server.address 127.0.0.1 --server.port 8501 --server.headless true --browser.gatherUsageStats false
```

API docs: `http://127.0.0.1:8000/docs`. Dashboard: `http://127.0.0.1:8501`. Dừng bằng `Ctrl+C` tại từng terminal. Các server kiểm thử đã dừng, không có server được để chạy nền khi bàn giao.

## Cảnh báo và giới hạn còn tồn tại

1. TestClient phát cảnh báo deprecation về HTTPX từ Starlette. Toàn bộ test đạt; chưa đổi framework/dependency chỉ để bỏ cảnh báo.
2. Dashboard phát cảnh báo `use_container_width` nên chuyển sang `width`; hiện render và chat vẫn hoạt động. Đây là việc sửa UI nhỏ về sau, không được coi là lỗi đã khắc phục trong Giai đoạn 1.
3. AppTest có cảnh báo thiếu ScriptRunContext ở main thread của harness; không có exception hoặc lỗi trong cây UI dashboard.
4. Nếu chạy API/test mà không nạp `.env`, model mặc định vẫn thiếu và API độ khó có thể trả 503. Đây là giải pháp cấu hình local cho Giai đoạn 1; quy tắc đóng gói model dùng chung vẫn cần chủ backend quyết định.
5. Lỗi Flutter `TileLayer.tileAt` tại `components/ban_do.dart:101` đã được xác định ở Giai đoạn 0; chưa sửa và chưa chạy lại Flutter analyzer/test ở giai đoạn này vì source/dependency Flutter không thay đổi.
6. Checkout vẫn chưa có thư mục nền tảng Flutter. Chưa chạy `flutter create .`, chưa cấu hình Android/emulator hoặc thử game end-to-end.
7. Chưa có Player ID/progress/history contract đáng tin cậy cho tính năng nhiệm vụ/cá nhân hóa; cần chốt ở Giai đoạn 2. Không gọi provider LLM hoặc ảnh, chưa có API key nào được yêu cầu/cài vào Flutter.

## Bước tiếp theo

Giai đoạn 2 ưu tiên MVP nhiệm vụ với schema, validator, fallback offline, API và tests. Sau khi bạn cho phép tiếp tục, sẽ chốt objective phù hợp gameplay và phạm vi phối hợp backend trước khi sửa phần liên quan. Chưa triển khai Giai đoạn 2 trong lượt này.
