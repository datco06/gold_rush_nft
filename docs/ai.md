# Sử dụng AI trong dự án Gold Rush

Nhóm dùng AI để phát triển tính năng, đọc mã nguồn, phân tích lỗi và hỗ trợ kiểm thử. Theo cách phân công trong [README](../README.md#ai-hỗ-trợ-phát-triển), **Google Gemini** hỗ trợ các việc có phạm vi rõ như API CRUD, schema, dữ liệu mẫu và tài liệu endpoint. **OpenAI GPT/Codex** hỗ trợ các việc cần đối chiếu nhiều phần của dự án như gameplay Flutter, phiên đăng nhập MetaMask và hiệu năng Android. Các đoạn chat dưới đây trích từ phiên làm việc với Codex.

## Cách nhóm dùng AI

1. **Mô tả việc cần làm và giới hạn thay đổi.** Nêu màn hình, nền tảng và phần cần giữ. Ví dụ, khi sửa lỗi Android, chỉ rõ có cần giữ nguyên hành vi trên web hay không.
2. **Gửi bằng chứng khi báo lỗi.** Cung cấp bản APK đang dùng, cấu hình máy, ảnh màn hình hoặc log. Ghi rõ lỗi xảy ra giữa ván hay sau khi ký MetaMask, vì hai tình huống đi qua các đoạn mã khác nhau.
3. **Yêu cầu phân tích trước nếu chưa rõ nguyên nhân.** Nhờ AI chỉ ra file, dòng mã, điều đã xác nhận và điều cần đo thêm. Với vấn đề RAM, đối chiếu dung lượng APK, dữ liệu ảnh sau giải mã và số đo trên điện thoại.
4. **Duyệt từng thay đổi và yêu cầu kiểm thử.** Kiểm tra các luồng liên quan trước khi build APK. Với MetaMask và lỗi đứng hình, thử lại trên máy đã gặp lỗi để kiểm chứng những gì kiểm thử tự động chưa bao phủ.
5. **Đóng gói và đưa mã lên Git.** Xác minh kiến trúc APK, số build và chữ ký trước khi gửi tester. Tách commit theo chức năng. Giữ `key.properties`, keystore, mật khẩu và cụm từ khôi phục ví ngoài Git và ngoài đoạn chat.

## Trích đoạn chat thực tế



### 1. Tìm nguyên nhân đứng hình giữa ván



>Tình trạng hiện tại khi đang trong ván  Game bị giật rồi đứng hình giữa ván. Hãy đọc file  log theo thời điểm này và kiểm tra những phần đang chạy trong ván có thể gây đứng hình. Đưa ra hướng sửa tối thiểu.

**Codex**

> Nếu game **đứng hình ngay giữa ván**, mình sẽ ưu tiên kiểm tra **vòng lặp gameplay**. Các dòng bỏ khung hình trong log bạn gửi thuộc MetaMask và launcher Vivo. Log còn thiếu dữ liệu khung hình, CPU và RAM của Gold Rush đúng lúc đứng, nên chưa đủ để kết luận thiếu RAM hay Android đã đóng game.

Nhóm tiếp tục đối chiếu code tìm đường, cách vẽ tilemap và vòng đời tài nguyên. Lượt kiểm tra phát hiện đường tạo player âm thanh lặp trong ván và tính được chi phí pixel của ảnh trang bị. Kết quả đọc mã giúp chọn thứ tự sửa. Nguyên nhân của lần đứng hình cụ thể vẫn cần đo lại trên máy.

### 2. Sửa phần quản lý player âm thanh



> Đồng ý triển khai phần tối ưu âm thanh trên Android. Hãy tái sử dụng player cho từng hiệu ứng và giải phóng chúng khi người chơi rời ván.Sửa tối thiểu , không thêm sửa xóa chức năng khác , không thêm packgae.

**Codex**

> Đã sửa phần âm thanh trên Android. Mỗi ván dùng **tối đa 3 player hiệu ứng** cho bước chân, nhặt xu và va chạm. Game dùng lại player, bỏ qua yêu cầu trùng khi âm đang phát và giải phóng player khi kết thúc hoặc rời ván.

Commit `1a56229` triển khai [vòng đời player theo ván](../gold_rush/lib/am_thanh/hieu_ung_am_thanh_van.dart) và thêm [kiểm thử tái sử dụng, thoát ván và lỗi nạp](../gold_rush/test/am_thanh/hieu_ung_am_thanh_van_test.dart).
