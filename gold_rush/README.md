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

```bash
cd gold_rush
flutter create .        # sinh android/ ios/ web/ windows/ cho máy của bạn
flutter pub get
flutter run
```

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


Lệnh `flutter create .` **không ghi đè** `lib/`, `assets/` và `pubspec.yaml`.

Chạy trên trình duyệt:

```bash
flutter run -d chrome
```

Chạy trên Windows:

```bash
flutter run -d windows
```

Chạy bộ kiểm thử:

```bash
flutter test
```

87 phép kiểm tra: 19 cho va chạm và đường ngắm (`test/luoi_va_cham_test.dart`),
24 cho phần AI (`test/ai/`), 3 cho danh sách màn (`test/man_choi_test.dart`), 41 cho phần
blockchain (`test/blockchain/` — ABI, dịch lỗi revert, bộ giao dịch MetaMask, cửa hàng, máy chủ). Chúng chạy trong vài giây vì không cần dựng giao
diện — xem mục 3 để hiểu vì sao làm được như vậy.

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

### 7.1. Cửa hàng nhân vật trên blockchain (phiên bản 1.2 — đề xuất, mạng thử nghiệm)

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
147/2024/NĐ-CP Điều 57). Chỉ bản web (`flutter run -d chrome`) kết nối được MetaMask.

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

## 8. Điều cần biết trước khi dùng làm bài mẫu

* Bộ kiểm thử phủ phần va chạm (`test/luoi_va_cham_test.dart`) và phần AI
  thuần (`test/ai/`). Chưa có kiểm thử cho vòng đời ván chơi trong
  `GoldRushGame` — đó là bài tập tốt để làm tiếp.
* Mô hình độ khó trong `assets/models/` được huấn luyện trên **dữ liệu mô
  phỏng**; thay bằng dữ liệu thật trước khi kết luận gì về người chơi.
* **Chưa chạy `flutter analyze` trên máy biên soạn** vì môi trường dựng tài
  liệu không cài được Dart SDK. Mã nguồn được viết theo tài liệu API chính
  thức của Flame 1.38 và đã rà soát thủ công, nhưng hãy chạy
  `flutter pub get && flutter analyze` trước khi phát cho sinh viên.
* Trò chơi không lưu tiến trình. Đóng ứng dụng là mất điểm.
* Bản đồ chỉ có một màn.
* Trên máy yếu, nếu thấy giật thì giảm `CauHinh.soONhinThayNgang` — vẽ ít ô
  hơn thì nhẹ hơn.

## 9. Nguồn tham khảo

| Địa chỉ | Nội dung |
|---|---|
| docs.flame-engine.org | Tài liệu chính thức Flame |
| pub.dev/packages/flame | Phiên bản mới nhất |
| tiled.mapeditor.org | Phần mềm vẽ bản đồ Tiled |
| Paul Teale, *Building Games with Flutter*, Packt 2022 | Sách gốc của thiết kế trò chơi này |
