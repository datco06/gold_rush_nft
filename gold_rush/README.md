# Gold Rush — game 2D trên Flame

Dựng lại trò chơi **Gold Rush** của sách *Building Games with Flutter*
(Paul Teale, Packt 2022) trên **Flame 1.38** và **Flutter 3.47**, chạy được
trên Android, Web, Windows, macOS và Linux từ cùng một mã nguồn.

Biên soạn: **Võ Thái Anh** · Trường Đại học Phenikaa · Tháng 9/2026
· Phiên bản 1.1 (10/2026) thêm thư mục `lib/ai/` — xem **mục 7**

> Sách viết trên Flame 1.0–1.1. Từ đó tới nay Flame đã thay đổi kiến trúc hai
> lần, chép nguyên mã trong sách sẽ không biên dịch được. Toàn bộ khác biệt
> được liệt kê trong **[DOI-CHIEU-2022-2026.md](DOI-CHIEU-2022-2026.md)** —
> đọc tệp đó trước nếu thầy cô đang dạy theo sách.

---

## 1. Chơi thế nào

George đi tìm vàng. Nhặt hết đồng xu trên bản đồ trước khi hết máu.

| | |
|---|---|
| **Mục tiêu** | Nhặt đủ 24 đồng xu, mỗi đồng 20 điểm |
| **Nguy hiểm** | 5 zombie và 4 bộ xương; chạm phải mất 25 máu, kẻ địch tự nổ |
| **Thua** | Máu về 0 |
| **Thắng** | Nhặt hết xu |

**Điều khiển** (dùng được cả ba cùng lúc):

* Cần gạt ở góc dưới bên trái — điện thoại
* Phím mũi tên hoặc `W A S D` — máy tính, giữ hai phím để đi chéo
* Chạm vào bản đồ — George tự đi tới chỗ đó

---

## 2. Chạy

### 2.1. Chuẩn bị môi trường phát triển

Yêu cầu tối thiểu:

* Flutter 3.47 hoặc mới hơn và Dart SDK theo `pubspec.yaml`.
* Android Studio/Android SDK nếu chạy APK hoặc thiết bị Android.
* Chrome nếu chạy bản Web.
* Node.js và npm nếu cần chạy mạng Hardhat trong `../gold_rush_chain/`.

Kiểm tra môi trường trước khi chạy:

```bash
flutter doctor
flutter devices
```

Lần đầu checkout hoặc sau khi thay đổi `pubspec.yaml`:

```bash
cd gold_rush
flutter pub get
```

Chỉ chạy `flutter create .` khi checkout bị thiếu thư mục nền tảng
(`android/`, `web/`, `windows/`...). Lệnh này **không ghi đè** `lib/`,
`assets/` và `pubspec.yaml`.

### 2.2. Chạy bản Web

```bash
flutter run -d chrome --web-port 5174 \
  --dart-define=GOLD_RUSH_API=http://127.0.0.1:8000
```

Web dùng MetaMask Extension qua EIP-1193/EIP-6963. Nếu chỉ muốn chạy giao
diện offline, có thể bỏ `GOLD_RUSH_API`.

### 2.3. Chạy bản Android

Android dùng Reown AppKit/WalletConnect để mở MetaMask Mobile. Không đưa
private key vào APK; project ID chỉ là mã nhận diện ứng dụng, không phải khóa
ví.

```bash
# Android Emulator: backend trên máy phát triển
flutter run -d emulator-5554 \
  --dart-define=GOLD_RUSH_API=http://10.0.2.2:8000 \
  --dart-define=REOWN_PROJECT_ID=<project-id>

# Android thật: thay <ip-lan> bằng địa chỉ LAN của máy chạy backend
flutter run -d <device-id> \
  --dart-define=GOLD_RUSH_API=http://<ip-lan>:8000 \
  --dart-define=REOWN_PROJECT_ID=<project-id>
```

Ứng dụng Android đã đăng ký deep link `goldrush://` để quay lại Gold Rush
sau khi xác nhận trong MetaMask. Khi phát hành thật, thay bằng redirect/app
link HTTPS của dự án qua `GOLD_RUSH_NATIVE_REDIRECT` và `GOLD_RUSH_APP_LINK`.
`GOLD_RUSH_NATIVE_ORIGIN` phải là Origin đã được cho phép trong backend; không
dùng URL RPC hoặc URL API làm Origin.

### 2.4. Backend và mạng Blockchain phát triển

Chạy backend từ thư mục `gold_rush_ai/` theo README của backend, sau đó truyền
địa chỉ backend bằng `GOLD_RUSH_API`. Các địa chỉ thường dùng:

| Môi trường | Backend nhìn từ app | Chain ID |
|---|---|---:|
| Web trên cùng máy | `http://127.0.0.1:8000` | 31337 |
| Android Emulator | `http://10.0.2.2:8000` | 31337 |
| Android thật | `http://<ip-lan>:8000` | 31337 |
| Phát hành thử nghiệm | URL HTTPS của backend | 11155111 |

Hardhat Local dùng chain ID `31337`. Sepolia dùng chain ID `11155111` và chỉ
dùng khi đã có địa chỉ hợp đồng, RPC và cấu hình backend tương ứng. Xem thêm
[`../gold_rush_chain/README.md`](../gold_rush_chain/README.md).

### Bảng xếp hạng toàn server — Top 30

Mở từ Hồ sơ → Bảng xếp hạng, ở menu bên trái ngay dưới nút Nhân vật.
Danh sách cuộn dọc hiển thị tên, Level, vàng kiếm được và từng loại huy
hiệu đã sở hữu. Các vị trí 1–10 có viền vàng, 11–20 viền bạc, 21–30 viền đồng;
có nhãn Top 10/20/30, tô sáng người chơi hiện tại và hạng cá nhân ngoài Top 30.

Thứ tự: Level giảm dần → số loại huy hiệu giảm dần → tổng vàng kiếm được giảm
dần → mã tài khoản ổn định khi ba chỉ số bằng nhau. Tổng hợp toàn bộ tài khoản
đã đăng ký trên backend trước khi lấy 30 người đầu; không tạo người chơi giả nếu
server ít hơn 30 người. Dữ liệu cùng server/mạng, không đọc lịch sử cục bộ.

Nguồn chỉ số:

- Tên từ tài khoản SIWE đã đăng ký; Level tính bằng công thức EXP hiện có ở backend.
  BXH không dùng cấp độ tính từ số màn cục bộ của Hồ sơ và không đổi công thức đó.
- Vàng kiếm được cộng `so_vang_goc` (hoặc `so_vang` ở phiếu cũ hợp lệ), mỗi mã ván
  chỉ một lần, từ sổ phiếu do server cấp và ticket khớp ví/màn/vé/chain. Đây là phần
  thưởng đã được xác minh, kể cả còn chờ nhận về ví; không gồm cọc hoàn lại, vàng
  được chuyển vào, faucet hay quà tặng. Mua trang bị không trừ chỉ số này. Phiếu
  thiếu nguồn mạng rõ ràng không tự nhập vào tổng.
- Huy hiệu chỉ đếm từng loại SBT thực sự sở hữu (ID 1–5), đọc `hasAchievement` cho
  mọi ví đăng ký tại cùng một block; không lấy trạng thái đủ điều kiện hoặc cache
  do client gửi làm bằng chứng. Cần RPC đúng mạng, `SBT_CHAIN_ID` khớp `CHAIN_ID`
  và `HOP_DONG_SBT` đã triển khai; RPC hỗ trợ JSON-RPC batch. Chỉ gọi phương thức
  đọc, không yêu cầu ký, mint hoặc gửi giao dịch để xem BXH.

`GET /api/bang-xep-hang/tong-the` dùng phiên SIWE, trả tối đa 30 vị trí cùng hạng
cá nhân; không nhận điểm/ví/level từ query để tính hạng. Backend dùng bộ nhớ đệm
chung 60 giây. App tự làm mới khi màn BXH đang mở và ở tiền cảnh, có nút làm mới,
hiển thị thời điểm cập nhật. Lỗi nguồn dữ liệu giữ bản đầy đủ trước đó và báo dữ
liệu cũ; lần đầu chưa đồng bộ được thì báo chưa sẵn sàng, không giả định 0 huy hiệu.
Chu kỳ 60 giây tính từ lúc đồng bộ xong; khi đang làm mới, yêu cầu khác nhận ngay
bản đầy đủ trước đó. Sổ vàng đã từng tồn tại bị thiếu/trống hoặc làm tổng vàng
giảm bất thường sẽ không thay thế bản tốt bằng số 0. Đổi tài khoản/mạng, đăng
xuất hoặc đóng màn BXH hủy yêu cầu cũ, không dùng chung phản hồi giữa hai phiên.
Số vàng truyền dạng chuỗi thập phân để không mất chính xác trên Web.

API BXH tuần `/api/bang-xep-hang/tuan` và API telemetry `/api/bang-xep-hang` vẫn
được giữ nguyên cho dữ liệu cũ; màn BXH trong app hiện dùng Top 30 tổng thể.

### 2.5. Kiểm tra mã nguồn

```bash
flutter analyze
flutter test
```

#### Thêm hoặc sửa ngôn ngữ

Bản dịch giao diện nằm trong `assets/i18n/`; `languages.json` khai báo mã và tên
hiển thị. Bộ `NgonNgu` nạp và lưu cache một lần khi khởi động; các màn tiếp tục
dùng `ChuGame` và `dich()` như trước, không import từng bản dịch.

Để thêm một ngôn ngữ, ví dụ tiếng Nhật:

1. Sao chép `assets/i18n/en.json` thành `assets/i18n/ja.json`.
2. Dịch các **giá trị**, giữ nguyên khóa tiếng Việt, tham số `{0}`, `{1}` và ký
   tự xuống dòng `\n`. Tên người chơi, địa chỉ ví và dữ liệu ký không phải bản dịch.
3. Thêm `"ja": "日本語"` vào đối tượng `languages` trong `languages.json`; giữ các
   ngôn ngữ cũ, `default` và `fallback`. Không cần sửa file Dart hoặc `pubspec.yaml`.
4. Chạy `flutter test --no-pub test/ngon_ngu`, khởi động lại app và kiểm tra chữ
   trên màn hình điện thoại. Build/phát hành lại để đóng gói file ngôn ngữ mới.

Ngôn ngữ hợp lệ tự xuất hiện trong ô chọn. Câu thiếu dùng bản dịch dự phòng;
file ngôn ngữ bổ sung bị lỗi, sai tham số hoặc thiếu sẽ không được đưa vào danh sách lựa chọn.
Đây là quản lý bản dịch đóng gói trong app, không gọi dịch vụ dịch tự động.

`flutter analyze` phải không có `error`. Hiện source vẫn còn một số `info`
về style và một cảnh báo phần tử chưa dùng; đây không phải lỗi biên dịch,
nhưng cần xử lý nếu yêu cầu analyzer hoàn toàn sạch.

> **Máy bị đơ khi `flutter run` cho Android?** Lệnh `flutter create .` cho
> Gradle dùng tới **8 GB RAM** (`org.gradle.jvmargs=-Xmx8G` trong
> `android/gradle.properties`). Trên máy 8 GB đang mở máy ảo, cả máy sẽ đứng.
> Chạy ngay sau `flutter create .`:
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File cong-cu\giam-ram-gradle.ps1
> ```
>
> (macOS/Linux: `bash cong-cu/giam-ram-gradle.sh`). Khi chỉ thử lối chơi,
> `flutter run -d windows` hoặc `-d chrome` nhẹ hơn nhiều. Hướng dẫn đầy đủ
> nằm trong `KHAC-PHUC-DO-MAY.md` của dự án Quán Ngon.


Chạy trên Windows:

```bash
flutter run -d windows
```

Chạy bộ kiểm thử:

```bash
flutter test
```

Số lượng test thay đổi theo từng phiên bản source. Có các nhóm test cho gameplay,
AI, giao diện, xác thực, Blockchain, cửa hàng, kho đồ và kết nối backend. Một
số test tích hợp cần backend hoặc Hardhat đang chạy; xem README của từng phần
trước khi kết luận toàn bộ hệ thống đã đạt.

> **Nếu màn hình đen hoặc hiện lỗi đỏ:** gần như luôn là do phần `assets`
> trong `pubspec.yaml` chưa khai đủ ba thư mục `images/`, `tiles/`, `audio/`,
> hoặc chưa chạy `flutter pub get` sau khi sửa `pubspec.yaml`.

---

## 3. Cấu trúc mã nguồn

```
lib/
├── cau_hinh.dart            Mọi con số cân bằng gameplay gom về một chỗ
├── tai_nguyen.dart          Nạp ảnh một lần, cắt sprite sheet thành hoạt ảnh
├── the_gioi.dart            World có bắt sự kiện chạm (tap-to-move)
├── gold_rush_game.dart      Vòng đời ván chơi, camera, điều hướng màn hình
├── main.dart                GameWidget + các lớp phủ giao diện
├── am_thanh/
│   └── am_thanh.dart        Bọc flame_audio, không bao giờ để lỗi âm thanh làm sập game
├── ai/                      (phiên bản 1.1) — xem mục 7
│   ├── tim_duong.dart       A* trên lưới ô, thuần Dart
│   ├── mo_hinh_do_kho.dart  Suy luận mô hình độ khó từ assets/models/*.json
│   ├── dieu_chinh_do_kho.dart  Độ khó thích ứng: kẹp 80–115%, đổi từ từ, tắt được
│   ├── nhat_ky_choi.dart    Ghi diễn biến ván + tính 5 đặc trưng
│   └── gui_nhat_ky.dart     Gửi nhật ký về máy chủ (tuỳ chọn, --dart-define)
├── components/
│   ├── ban_do.dart          Đọc tệp .tmx: lớp ô, lớp đối tượng, điểm xuất hiện
│   ├── luoi_va_cham.dart    Toán va chạm thuần — kiểm thử được, không cần Flame
│   ├── nhan_vat.dart        Lớp nền: hoạt ảnh theo hướng, trượt dọc tường, bóng đổ
│   ├── george.dart          Nhân vật chính, gộp ba nguồn điều khiển
│   ├── ke_dich.dart         Zombie & skeleton: tuần tra ↔ đuổi theo ↔ tìm kiếm (A*)
│   ├── dong_xu.dart         Đồng xu quay, cộng điểm
│   ├── hieu_ung.dart        Hạt và bóng đổ
│   └── hud.dart             Thanh máu, điểm, số xu còn lại
├── dieu_khien/
│   └── nut_tam_dung.dart    Nút tạm dừng vẽ bằng canvas
└── man_hinh/
    └── lop_phu.dart         Menu, Cài đặt, Tạm dừng, Kết thúc (widget Flutter)
```

Quy tắc phân tầng, đọc từ trên xuống:

```
main.dart  →  gold_rush_game.dart  →  components/  →  ban_do.dart
                                   ↘  tai_nguyen.dart
```

Một tách biệt nữa đáng chú ý: `ban_do.dart` lo việc **đọc tệp**, còn
`luoi_va_cham.dart` lo việc **tính toán**. Lớp `LuoiVaCham` chỉ nhận một mảng
hai chiều true/false, không biết gì về Flame, Tiled hay tệp trên đĩa — nên
kiểm thử được bằng `flutter test` mà không cần dựng gì cả.

Component **không** tự đi tìm game để lấy dữ liệu. Mọi thứ chúng cần đều được
truyền vào qua hàm dựng. Đây là lý do `KeDich` nhận một hàm `viTriNguoiChoi()`
chứ không nhận thẳng đối tượng `George`: tệp `ke_dich.dart` hoàn toàn không
biết George tồn tại, nên kiểm thử và tái sử dụng đều dễ hơn.

---

## 4. Tài nguyên được sinh bằng mã nguồn

Sách dùng bộ đồ hoạ tải từ OpenGameArt và kho GitHub của Packt. Dự án này
**không sao chép bất cứ thứ gì từ đó**. Toàn bộ ảnh, âm thanh và bản đồ do
một script Python sinh ra:

```bash
python3 cong-cu/sinh_tai_nguyen.py
```

Script tạo ra:

| Tệp | Nội dung |
|---|---|
| `assets/images/tileset.png` | 9 ô 16×16: cỏ, cỏ hoa, đường, nước, cây, đá, sàn kim cương, tường, ô chặn |
| `assets/images/george.png` | 4 hướng × 4 khung hình |
| `assets/images/zombie.png`, `skeleton.png` | như trên |
| `assets/images/dong_xu.png` | 8 khung xoay |
| `assets/images/joystick_*.png` | nền và núm cần gạt |
| `assets/tiles/gold_rush.tmx` | bản đồ 40×30 ô, 3 lớp ô + 1 lớp đối tượng |
| `assets/audio/*.wav` | tiếng nhặt xu, kẻ địch nổ, bước chân, nhạc nền 8 giây |

Muốn đổi phong cách đồ hoạ: sửa bảng màu `P` và các hàm `ve_*` trong script
rồi chạy lại. Muốn dùng đồ hoạ khác hẳn: thay tệp PNG cùng tên, giữ nguyên
kích thước ô 16×16 và bố cục 4 hàng × 4 cột cho nhân vật.

Muốn sửa bản đồ bằng phần mềm **Tiled** (tiled.mapeditor.org): mở thẳng
`assets/tiles/gold_rush.tmx`. Giữ nguyên tên bốn lớp `Nen`, `TrangTri`,
`VaCham`, `DoiTuong` — mã nguồn tra theo tên, đổi tên là bản đồ không nạp được.

---

## 5. Muốn sửa gì thì sửa ở đâu

| Muốn làm gì | Sửa ở đâu |
|---|---|
| Game dễ/khó hơn | `cau_hinh.dart` — tốc độ, máu, tầm nhìn kẻ địch |
| Thêm/bớt quái, đổi vị trí xu | mở `gold_rush.tmx` bằng Tiled, sửa lớp `DoiTuong` |
| Đổi bản đồ | sửa hàm `dung_ban_do()` trong script Python, hoặc vẽ trong Tiled |
| Nhìn thấy nhiều/ít hơn | `CauHinh.soONhinThayNgang` |
| Thêm loại kẻ địch mới | thêm một hàm dựng `factory` trong `ke_dich.dart` |
| Đổi giao diện menu | `man_hinh/lop_phu.dart` — là widget Flutter thuần |
| Xem vùng va chạm để gỡ lỗi | mở `gold_rush.tmx`, bật hiển thị lớp `VaCham` |

---

## 6. Gợi ý bài tập mở rộng

Xếp theo độ khó tăng dần, bám đúng mạch các chương của sách:

1. **Mức 1** — Đổi bảng màu trong script Python để có bản đồ mùa đông (cỏ
   thành tuyết, nước thành băng).
2. **Mức 1** — Thêm âm thanh khi George trúng đòn (viết thêm một hàm sinh WAV).
3. **Mức 1** — Viết thêm kiểm thử cho `LuoiVaCham` với một bản đồ hình xoắn ốc.
4. **Mức 2** — Thêm vật phẩm hồi máu: một loại component mới giống `DongXu`
   nhưng cộng máu thay vì cộng điểm.
5. **Mức 2** — Đếm ngược thời gian; hết giờ là thua. Hiển thị trên HUD.
6. **Mức 2** — Lưu điểm cao nhất bằng `shared_preferences` (Tuần 11) để
   không mất khi tắt ứng dụng.
7. **Mức 3** — (đã có lời giải trong `lib/ai/tim_duong.dart`, phiên bản 1.1)
   Cho A* đi 8 hướng có chặn cắt góc tường, đo lại số lần kẻ địch bị kẹt.
8. **Mức 3** — Thêm màn chơi thứ hai: vẽ `gold_rush_2.tmx`, nhặt hết xu ở màn
   một thì chuyển sang màn hai.
9. **Mức 3** — Đưa bảng xếp hạng lên Firebase Firestore (xem tài liệu
   *Triển khai Flutter trên Firebase*), rồi triển khai bản web lên Hosting.

---

## 7. Phần AI (phiên bản 1.1)

```
assets/models/do_kho_v1.json   ← MÔ HÌNH chạy trên máy (vài KB, huấn luyện bằng Python)
lib/ai/                        ← mã Dart dùng mô hình và thuật toán AI
test/ai/                       ← kiểm thử, gồm kiểm thử hợp đồng Python ↔ Dart
../gold_rush_ai/               ← dự án Python: huấn luyện, API FastAPI, dashboard Streamlit
```

| Tính năng | Loại AI | Ở đâu |
|---|---|---|
| Kẻ địch vòng qua tường, mất dấu thì lùng sục chỗ thấy lần cuối | Tìm đường A* + máy trạng thái | `lib/ai/tim_duong.dart`, `components/ke_dich.dart` |
| Kẻ địch nhanh/chậm theo phong độ người chơi | Học máy (hồi quy logistic) | `lib/ai/dieu_chinh_do_kho.dart` + `assets/models/` |
| Ghi nhật ký ván để huấn luyện lại bằng dữ liệu thật | Thu thập dữ liệu | `lib/ai/nhat_ky_choi.dart`, `gui_nhat_ky.dart` |
| Bản đồ mới bảo đảm thắng được | Sinh nội dung theo thủ tục + BFS | `../gold_rush_ai/core/sinh_ban_do.py` |
| Trợ lý trả lời cách chơi | RAG rút gọn | `../gold_rush_ai/core/tro_ly.py` |

Bật/tắt độ khó thích ứng trong màn **Cài đặt**. Thiếu tệp mô hình thì game tự
chơi với độ khó cố định. Gửi nhật ký về máy chủ chỉ khi chạy với
`--dart-define=GOLD_RUSH_API=http://...`.

Hướng dẫn từng bước: tài liệu *Hướng dẫn xây dựng Gold Rush và phát triển AI*.

### 7.1. Cửa hàng nhân vật trên blockchain (mạng phát triển và mạng thử nghiệm)

```
lib/blockchain/        abi.dart · vi.dart (+ vi_web.dart MetaMask) · cua_hang.dart · may_chu_phieu.dart · nhan_vat.dart
lib/man_hinh/cua_hang.dart   lớp phủ "Cửa hàng nhân vật"
assets/images/george_*.png   3 nhân vật — sinh bằng cong-cu/sinh_nhan_vat.py
../gold_rush_chain/    hợp đồng CuaHangGoldRush.sol (Hardhat 3, OpenZeppelin 5.7)
../gold_rush_ai/core/trong_tai.py   kiểm định ván + ký phiếu vàng EIP-712
```

Xu nhặt trong ván → máy chủ kiểm định nhật ký → ký **phiếu vàng** → người chơi nộp
phiếu qua MetaMask → hợp đồng đúc **vàng** → đốt vàng để mua **nhân vật** (chỉ đổi ngoại
hình). Vàng và nhân vật **không chuyển nhượng được**, chỉ chạy trên mạng thử nghiệm —
xem tài liệu *Đề xuất cửa hàng nhân vật Gold Rush trên blockchain* (pháp lý: Nghị định
147/2024/NĐ-CP Điều 57). Bản Web dùng MetaMask Extension; bản Android dùng
MetaMask Mobile qua Reown AppKit/WalletConnect và deep link.

### 7.2. Nhiều màn chơi, cọc vào màn, giao dịch chống lỗi (phiên bản 1.3)

```
assets/tiles/man_choi.json      6 màn — MỘT nguồn sự thật cho app, máy chủ, hợp đồng
assets/tiles/man_2…6.tmx        sinh bằng ../gold_rush_ai/scripts/sinh_man_choi.py
lib/man_choi.dart               đọc man_choi.json; đồng hồ đếm ngược trên HUD
lib/man_hinh/chon_man.dart      lớp phủ "Chọn màn" (hỏi xác nhận trước khi đặt cọc)
lib/blockchain/giao_dich.dart   BỘ GIAO DỊCH: 9 bước kiểm tra trước/sau mỗi giao dịch MetaMask
lib/blockchain/loi_hop_dong.dart  dịch lỗi revert / lỗi ví sang tiếng Việt
lib/blockchain/phien_vi.dart    một phiên ví dùng chung cho chọn màn, cửa hàng, màn kết thúc
```

* Màn 1 luyện tập: không giới hạn giờ, thua không mất gì. Màn 2–6: có giờ, kẻ địch nhanh dần, **cọc**.
* Vào màn có cọc = hợp đồng **đốt cọc ngay** (`vaoMan`). Hoàn thành → phiếu hoàn cọc + xu + thưởng.
  Chết / hết giờ / bỏ ván / đóng trình duyệt → không có phiếu → **mất cọc, tự động, không cần giao dịch**.
* Phiếu đang chờ được **gộp** vào giao dịch tiếp theo (`multicall`): nhận vàng + vào màn, hoặc
  nhận vàng + mua nhân vật, đều chỉ MỘT lần bấm Xác nhận.

## 8. Trạng thái hiện tại và giới hạn

* Bộ kiểm thử phủ phần va chạm (`test/luoi_va_cham_test.dart`) và phần AI
  thuần (`test/ai/`). Chưa có kiểm thử cho vòng đời ván chơi trong
  `GoldRushGame` — đó là bài tập tốt để làm tiếp.
* Mô hình độ khó trong `assets/models/` được huấn luyện trên **dữ liệu mô
  phỏng**; thay bằng dữ liệu thật trước khi kết luận gì về người chơi.
* `flutter analyze` đã được chạy trên source hiện tại: không có lỗi biên dịch,
  nhưng còn các cảnh báo/ghi chú style cần dọn nếu muốn báo cáo analyzer sạch.
* Các test tích hợp Blockchain cần đúng chain, hợp đồng và backend; không tự
  reset Blockchain trong quy trình kiểm thử.
* Trò chơi không lưu tiến trình. Đóng ứng dụng là mất điểm.
* Trên máy yếu, nếu thấy giật thì giảm `CauHinh.soONhinThayNgang` — vẽ ít ô
  hơn thì nhẹ hơn.

## 9. Triển khai

Phần cài đặt phát triển ở mục 2 chỉ dành cho chạy local. Khi triển khai thật,
cần tách riêng ba thành phần:

1. **Backend:** triển khai FastAPI và database lên máy chủ/Render hoặc nền
   tảng tương đương; cấu hình CORS, HTTPS, cookie/CSRF và biến môi trường.
2. **Blockchain:** triển khai hợp đồng lên Sepolia `11155111`, cập nhật địa
   chỉ hợp đồng vào backend và cấu hình app; không dùng private key thật trong
   Flutter hoặc Git.
3. **Flutter:**

   ```bash
   flutter build web --release \
     --dart-define=GOLD_RUSH_API=https://<backend-domain>

   flutter build apk --release \
     --dart-define=GOLD_RUSH_API=https://<backend-domain> \
     --dart-define=REOWN_PROJECT_ID=<project-id> \
     --dart-define=GOLD_RUSH_SEPOLIA_RPC_URL=<sepolia-rpc> \
     --dart-define=GOLD_RUSH_NATIVE_ORIGIN=https://<app-domain> \
     --dart-define=GOLD_RUSH_NATIVE_REDIRECT=goldrush:// \
     --dart-define=GOLD_RUSH_APP_LINK=https://<app-domain>/wc
   ```

APK phát hành phải ký bằng keystore riêng, thay cấu hình redirect bằng domain
thật và kiểm thử quay lại ứng dụng sau khi MetaMask Mobile xác nhận. Không dùng
debug signing cho bản phát hành. Trước khi phát hành Sepolia, phải cập nhật
backend và AppKit với chain `eip155:11155111`, địa chỉ hợp đồng và RPC thật;
không dùng địa chỉ hợp đồng Hardhat `31337` cho APK release.

## 10. Nguồn tham khảo

| Địa chỉ | Nội dung |
|---|---|
| docs.flame-engine.org | Tài liệu chính thức Flame |
| pub.dev/packages/flame | Phiên bản mới nhất |
| tiled.mapeditor.org | Phần mềm vẽ bản đồ Tiled |
| Paul Teale, *Building Games with Flutter*, Packt 2022 | Sách gốc của thiết kế trò chơi này |
