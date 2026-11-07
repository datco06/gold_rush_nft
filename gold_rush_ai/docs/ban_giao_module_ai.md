# Bàn giao module AI – người 3

Ngày kiểm tra: 07/11/2026. Nhánh: `feature/ai`.
Nền mã chức năng: `770bc83`, kèm bộ kiểm thử contract Flutter–backend trong lần cập nhật này.

Module AI đã hoàn thiện các task bổ sung 1–7 trong phạm vi MVP đã thống nhất.
Kết quả này chưa phải nghiệm thu toàn bộ game hoặc toàn bộ chức năng nhân vật chơi được trong hướng dẫn nhóm.

## Những phần đã có

| Task | Kết quả |
|---|---|
| 1 | README, mẫu cấu hình, demo offline ba API, ví dụ request và contract bàn giao |
| 2 | Khóa SQLite chống sinh ảnh trùng đồng thời; kiểm tra sức chứa trước provider |
| 3 | Quota bền vững theo người/ngày UTC: mặc định 5 ảnh, 20 lượt LLM; HTTP 429/Retry-After |
| 4 | Nhiệm vụ theo cấp độ và hiệu suất đã xác minh, giữ kiểm tra khả thi và kết quả retry |
| 5 | Snapshot chung, hook nguồn dữ liệu backend; tạo ảnh verified đòi hoàn thành đủ màn 1–6 |
| 6 | Menu AI chụp màn đang/vừa chơi lúc mở route, không cố định màn 1 |
| 7 | Kiểm thử client Flutter gọi backend HTTP thật và tổng hợp bằng chứng/giới hạn bàn giao |

Ba API và model/client Flutter đã có loading, lỗi, retry, giới hạn JSON/ảnh và kiểm tra quyền.
Nhiệm vụ vẫn là đề xuất `offered`, thưởng bằng 0; ảnh là preview PNG tĩnh 128×128 có TTL.
Provider LLM/ảnh tách khỏi business logic, mặc định tắt và có fallback được ghi nhãn.
Đề xuất độ khó mới là rule-based; không tuyên bố là mô hình học máy mới.

## Kết quả kiểm tra thực tế

| Kiểm tra | Kết quả |
|---|---|
| Toàn bộ pytest backend | 711 đạt, 1 cảnh báo deprecation Starlette/HTTPX đã có |
| Toàn bộ Flutter test mặc định | 269 đạt, 3 test HTTP tích hợp được bỏ qua theo cấu hình |
| Bật riêng test Flutter–backend qua HTTP thật | 3/3 đạt: nhiệm vụ, độ khó, tạo/tải PNG và ownership |
| Thử run ID sai | Bị chặn trong setup, không tạo bản ghi nhiệm vụ/ảnh |
| Analyzer 21 file AI liên quan, gồm menu và test tích hợp | Không có lỗi/cảnh báo |
| Analyzer toàn game | Còn 1 lỗi `tileAt`, 2 warning và 7 info đã có |
| Python `pip check` | Không có dependency bị lỗi |
| Git diff check | Đạt |
| Dữ liệu vận hành | `.env`, `.venv` và SQLite nhiệm vụ/ảnh/quota được Git bỏ qua |
| Cleanup kiểm thử tích hợp | Server đã dừng, kết nối SQLite đóng, dữ liệu tạm đã xóa |

Các tổng test bao gồm cả test nền có sẵn của repository, không phải toàn bộ đều do người 3 viết mới.
Test HTTP dùng backend FastAPI thật và client/decoder Flutter thật, với ngữ cảnh demo và ảnh mẫu offline.
Test backend cho snapshot verified, quota, điều kiện sáu màn và provider HTTP dùng fixture/mock; không gọi dịch vụ tính phí.
Không cần sửa bản đồ chính để chạy bộ kiểm thử contract này.

## Cách chạy và dữ liệu bàn giao

Làm theo [README](../README.md): chuẩn bị môi trường, chạy demo, các request mẫu,
kiểm thử Flutter–backend và cấu hình môi trường/provider đều đã được ghi rõ.

- API nhiệm vụ: `POST /api/ai/nhiem-vu/tao`.
- API độ khó: `POST /api/ai/do-kho/de-xuat`.
- API ảnh: `POST /api/ai/nhan-vat/tao`, `GET /api/ai/nhan-vat/anh/{image_id}`.
- Hook cho người 5: `api.ngu_canh_ai.gan_nguon_du_lieu_ai` nhận hàm async trả `core.ngu_canh_ai.BanChupNguoiChoiAI`.
- Contract phản hồi giữ nguyên để các client trong `gold_rush/lib/ai/` đọc được.
- Bộ kiểm thử HTTP: `gold_rush/test/tich_hop/backend_ai_test.dart`, bật bằng hai dart-define trong README.

## Những phần còn cần phối hợp hoặc nghiệm thu thêm

1. **Bản đồ/gameplay:** `gold_rush/lib/components/ban_do.dart:101` gọi `TileLayer.tileAt` không có trong Tiled đang cài. Cần chủ module sửa chính thức để toàn game build sạch. Các lần dùng bản sao tạm không sửa được lỗi trong checkout chính.
2. **Backend người 5:** triển khai adapter xác thực/session, liên kết đúng người với cấp độ, màn đã hoàn thành, lịch sử và hệ số trước; đăng ký vào hook chung. Checkout hiện chưa có nguồn này. Typed snapshot không tự chứng minh tiến trình nếu adapter tin dữ liệu client.
3. **Gameplay/giao diện:** người 2 nối theo dõi/hoàn thành nhiệm vụ và áp dụng tham số đề xuất; người 1 nối trải nghiệm chọn nhân vật. Module hiện hiển thị đề xuất/preview, chưa tạo khác biệt tương ứng trong chiến đấu.
4. **Provider thật:** chọn dịch vụ/model và ngân sách, cấu hình môi trường rồi kiểm chứng chất lượng/nội dung, latency và fallback. Chưa gọi LLM/sinh ảnh tính phí để nghiệm thu. Quota chỉ giới hạn số lượt theo người, không phải ngân sách tiền tệ toàn hệ thống.
5. **Nếu mở rộng theo hướng dẫn đầy đủ:** cần chuẩn sprite 4 hướng × 4 frame, kiểm tra bố cục/animation, metadata nhân vật và lưu trữ lâu dài. MVP ảnh tĩnh đã duyệt chưa bao gồm việc này; AI skin không tự trở thành NFT.
6. **Demo cuối:** chưa kiểm thử Android Emulator và chưa có video demo mới cho luồng tích hợp dữ liệu thật. Không dùng kết quả test contract để tuyên bố đã chạy thành công toàn game trên Android.

Có thể bàn giao/push nhánh AI như một mốc MVP có kiểm thử và công bố các giới hạn trên.
Chưa nên coi đây là bản hoàn tất toàn bộ hướng dẫn nhóm để nghiệm thu cuối hoặc phát hành.
