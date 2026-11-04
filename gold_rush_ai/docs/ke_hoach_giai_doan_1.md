# Kế hoạch thiết lập môi trường AI

**Mục tiêu:** Python 3.12.10 chạy backend, dashboard và bộ test hiện có trong `gold_rush_ai/.venv`, có hướng dẫn tái lập trên PowerShell.

**Căn cứ:** `bao_cao_giai_doan_0.md`, phần Giai đoạn 1; người dùng đã yêu cầu tiếp tục giai đoạn này.

**Kiến trúc:** Giữ nguyên source API/core và cấu hình qua biến môi trường. Uvicorn dùng `--env-file .env`; test dùng CLI dotenv cùng venv. Model đọc bản JSON sẵn có trong assets Flutter.

**Công nghệ:** Python 3.12.10, venv, pip, FastAPI/Uvicorn, Streamlit, pytest.

**Giới hạn:** Chỉ branch `feature/ai`; giữ thay đổi Flutter ban đầu; không commit/push, không tạo model mới, không giao dịch blockchain hoặc gọi AI trả phí. Không tự sửa config/API chung hoặc lỗi map Flutter.

**Quyết định:** Thiết lập tại workspace người dùng chỉ định và branch `feature/ai`; không tạo worktree/branch khác. Dùng các phiên bản dependency từ môi trường đã chạy baseline, không nâng cấp hàng loạt. Bản khóa dependency chỉ chứa closure của requirements hiện tại.

## Các bước và kiểm chứng

- [x] Kiểm tra branch/status/diff; xác nhận chưa có venv/env để tránh ghi đè.
- [x] Tạo bản khóa phiên bản và venv độc lập (không system-site-packages).
- [x] Cài requirements bằng bản khóa; dùng 64 wheel đã cache, offline.
- [x] Chạy `pip check`, xác nhận Python/path và dependency tương thích.
- [x] Thêm `.env.example`; tạo `.env` cục bộ nếu chưa có; kiểm tra ignore. Không sửa code nạp env: dùng CLI hiện có của dotenv/Uvicorn.
- [x] Chạy toàn bộ pytest trong venv với cấu hình env, kiểm tra bản đồ.
- [x] Khởi chạy Uvicorn thật, gửi request health/model/predict; khởi chạy Streamlit và kiểm tra health, kiểm tra script dashboard bằng AppTest. Đã dừng hai tiến trình do kiểm thử tạo.
- [x] Ghi README PowerShell cho API/dashboard/Flutter, ghi hạn chế Flutter hiện có và biên bản kết quả thực tế.
- [x] Rà soát diff, ignore và bàn giao; dừng trước Giai đoạn 2.

## Điểm rà soát

Không coi health HTTP 200 là model đã nạp; kiểm tra `da_nap`. `.env` không tự nạp bởi pytest/Streamlit; hướng dẫn dùng dotenv CLI khi cần. Đường dẫn tương đối trong `.env.example` yêu cầu cwd là `gold_rush_ai`. Không cho fixture test ghi sổ phiếu vào dữ liệu vận hành. Không coi Streamlit health endpoint là bằng chứng dashboard render đúng. Lệnh Flutter có thể cần quyền mở file khóa SDK, và analyzer đang có lỗi `tileAt` ngoài phạm vi.

## Tiến độ

- Bắt đầu: Git đúng `feature/ai`; thay đổi ban đầu là `gold_rush/analysis_options.yaml`, file mới `gold_rush/pubspec.lock`, báo cáo Giai đoạn 0.
- Môi trường: 64 phiên bản khớp constraints; pip check đạt; venv độc lập.
- Kiểm thử: 72 pytest đạt (1 deprecation warning); 6/6 map OK; HTTP API và Streamlit đạt; AppTest render/chat không exception.
- Quyết định: Không sửa source nạp env hoặc UI chỉ để xử lý các deprecation warning; giữ phạm vi thiết lập và ghi rõ giới hạn trong biên bản.
- Rà soát độc lập: Không có Critical/Important; đã sửa hướng dẫn ba công cụ tùy chọn để dùng đúng Python venv thay vì Python từ PATH. Đây chỉ là chỉnh tài liệu, không chạy các công cụ ghi asset.
