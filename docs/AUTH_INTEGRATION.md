# Gold Rush — thiết kế tích hợp tài khoản MetaMask

Ngày khảo sát: **06/11/2026**, nhánh **`feature/auth`**.

**Trạng thái: tài liệu thiết kế cho lượt đầu, chưa triển khai Auth.** Các API, bảng dữ liệu và file ghi “đề xuất” dưới đây chưa tồn tại. Chỉ tạo tài liệu này; không commit, push, đổi nhánh, merge hoặc cherry-pick. Không đọc mã từ nhánh `feature/blockchain` để đưa vào nhánh hiện tại; không sửa SBT/NFT.

## 1. Kết quả kiểm tra dự án hiện tại

### Flutter và điều hướng

| File đã đọc | Cơ chế thực tế và tác động tới Auth |
| --- | --- |
| `gold_rush/lib/main.dart` | `MaterialApp.home` là `ManHinhGame`; State giữ một `GoldRushGame`, dựng `GameWidget` ngay khi mở ứng dụng. Chưa có Auth Gate hay route đăng nhập. |
| `gold_rush/lib/gold_rush_game.dart` | `onLoad()` nạp bản đồ, dựng ván làm nền, bật `LopPhu.menu`; `onMount()` dừng engine. Menu gọi `moChonMan()`, overlay chọn màn gọi `choiMan()`, rồi `batDauVanMoi()`. Chưa kiểm tra tài khoản. |
| `gold_rush/lib/man_hinh/lop_phu.dart` | Widget Flutter cho menu, cài đặt, tạm dừng, kết thúc. `_Khung`/`_Nut` là private; khung cuộn tối đa 380 px, nút chính cao 50 px. |
| `gold_rush/lib/man_hinh/chon_man.dart` | Overlay chọn 6 màn, tối đa 520 px. Màn luyện tập hiện chơi được khi chưa kết nối ví; màn có cọc yêu cầu `PhienVi`. |
| `gold_rush/lib/man_hinh/cua_hang.dart` | Overlay cửa hàng, tối đa 440 px; có nút kết nối và địa chỉ rút gọn, chưa phải hồ sơ tài khoản. |
| `gold_rush/lib/the_gioi.dart` | Flame World của màn chơi, không phải màn hình World Map chọn vùng. |
| `gold_rush/lib/ai/gui_nhat_ky.dart` | Đọc `GOLD_RUSH_API` bằng dart-define. HTTP hiện chưa cấu hình cookie/CSRF; khi thiếu API game vẫn chơi offline. |

**Chưa có World Map riêng trong mã hiện tại.** Điểm vào tương ứng để tích hợp là menu → overlay `chonMan`. Sau xác thực, nút “BẮT ĐẦU PHIÊU LƯU” sẽ mở game và đưa tới overlay chọn màn bằng cơ chế này, không tạo World Map giả. Nếu World Map được bổ sung về sau, đặt nó dưới cùng Auth Gate.

### Ví hiện có

| File đã đọc | Có thể tái sử dụng | Phần còn thiếu |
| --- | --- | --- |
| `lib/blockchain/vi.dart` | Interface `Vi`, `LoiVi`, `DoiTaiKhoan`, `DoiMang`; conditional import cho web/native. | Chưa có phương thức ký thông điệp; chưa có lifecycle giải phóng provider. |
| `lib/blockchain/vi_web.dart` | EIP-6963 ưu tiên MetaMask; EIP-1193 `eth_requestAccounts`, `eth_accounts`, `eth_chainId`; phát sự kiện đổi ví/mạng. Constructor chỉ discovery, không xin tài khoản. | Có fallback sang ví EIP-6963 đầu tiên hoặc `window.ethereum`, nên chưa bảo đảm ví được chọn là MetaMask. Chưa có `personal_sign`; listener chưa có cơ chế gỡ. |
| `lib/blockchain/vi_khong_ho_tro.dart` | Native trả thông báo chỉ hỗ trợ ví trên web. | Chưa triển khai SDK/deep link Android/iOS/desktop. |
| `lib/blockchain/phien_vi.dart` | `ChangeNotifier` dùng chung cho chọn màn/cửa hàng/kết quả; nghe đổi tài khoản, xóa số dư/phiếu/quyền sở hữu khi đổi ví. | Đây là phiên giao dịch, không phải phiên đăng nhập. `ketNoi()` lấy cấu hình backend, kiểm tra mạng và hợp đồng, tải dữ liệu cửa hàng; không dùng nó làm điều kiện đăng nhập. Đổi mạng hiện chỉ cảnh báo/kiểm tra ở giao dịch sau. |

`GoldRushGame.phienVi` hiện tự tạo một `Vi` khi có `GOLD_RUSH_API`. Auth cần một `Vi` cấp ứng dụng, sau đó truyền cùng instance vào phiên giao dịch để không có hai lựa chọn provider/tài khoản khác nhau. Không dùng `PhienVi.daKetNoi` làm bằng chứng xác thực.

Trong checkout khảo sát không có file được Git theo dõi mang tên SBT/NFT; không giả định `vat_pham/nft_model.dart` đang tồn tại chỉ vì IDE còn mở tab đó. Bộ cửa hàng/ví hiện tại vẫn giữ nguyên chức năng. Có thư mục untracked `gold_rush_chain/ignition/deployments/` trước khi khảo sát; không tác động.

### Assets và giao diện thật

`pubspec.yaml`: Dart `^3.13.3`, Flame `^1.38.2`, flame_tiled `^3.1.2`, flame_audio `^2.12.2`, http `^1.6.0`; dev dùng `flutter_test`, `flutter_lints`. Đây là ràng buộc đang khai báo, không phải kết luận phiên bản mới nhất hay phiên bản đã resolve. Chưa khai báo font riêng hoặc thư viện quản lý Auth.

| Asset hiện có | Kích thước / cách dùng đề xuất |
| --- | --- |
| `assets/images/tileset.png` | 144×16, 9 ô 16×16: cỏ, hoa, đường, nước, cây, đá, sàn, tường, ô chặn. Dựng nền tĩnh rừng/đường/đá bằng các ô đã có. |
| `assets/images/george.png` | 64×64, 4×4 frame 16×16. Cắt frame đầu làm avatar mặc định; không thu nhỏ toàn sprite sheet thành avatar. |
| `assets/images/george_tho_mo.png`, `george_cao_boi.png`, `george_hiep_si.png` | Mỗi ảnh 64×64. Chỉ dùng George gốc cho đăng ký, không cấp quyền sở hữu nhân vật cửa hàng qua Auth. |
| `assets/images/dong_xu.png` | 128×16, 8 frame; dùng một frame làm chi tiết vàng. |
| `assets/images/zombie.png`, `skeleton.png`, `joystick_*.png` | Đang phục vụ gameplay; không cần đưa vào form Auth. |
| `assets/tiles/gold_rush.tmx`, `man_2.tmx` … `man_6.tmx`, `man_choi.json` | Có bản đồ thật và danh sách màn; bản gốc 40×30 ô. Không sửa bản đồ để làm Auth. |
| `assets/audio/nhac_nen.wav`, `dong_xu.wav`, `buoc_chan.wav`, `va_cham.wav` | Không autoplay âm thanh trước tương tác. |

Đã xem trực tiếp `tileset.png` và `george.png`, kiểm tra kích thước PNG của toàn bộ ảnh. Không có logo ảnh GOLD RUSH, ảnh nền Auth, ảnh nút/khung gỗ hay file font trong `assets/`. Logo dùng chữ; khung gỗ/đá vẽ bằng Flutter. Không dùng ảnh URL bên ngoài, không cần sinh asset mới ở bước đầu.

Màu hiện có ở `cau_hinh.dart`: vàng `#E3A008`, nền `#1B2430`, nền phủ `#CC121820`, chữ `#F2F4F7`, đỏ `#DC4A3D`. Theme đang Material 3 tối, chưa có font pixel. Giữ vàng/nền/chữ hiện tại; thêm màu Auth cục bộ như nâu gỗ `#4A3022`, xanh rừng `#183A2A`, viền vàng nhạt `#F1CF7A` (màu đề xuất, chưa có trong cấu hình).

### FastAPI, dữ liệu và test

| Thành phần đã đọc | Kết quả |
| --- | --- |
| `gold_rush_ai/api/main.py` | Một FastAPI app, lifespan nạp mô hình/danh sách màn/trợ lý vào `STATE`. API cho nhật ký, thống kê, bản đồ, AI, vé và phiếu; chưa có Auth router, cookie hay dependency người dùng. |
| `gold_rush_ai/config.py` | Cấu hình qua env; `CHAIN_ID` mặc định 31337, có chú thích Sepolia 11155111. `CORS_ORIGINS` mặc định localhost cổng 8501/5173/5000. |
| CORS trong `api/main.py` | Đã giới hạn origins nhưng chưa bật credentials; methods/headers dùng wildcard. Cần cấu hình cookie rõ ràng khi tích hợp. |
| `core/nhat_ky.py` | Telemetry JSONL theo ngày, `ma_van` và tên hiển thị tùy chọn; không có `users.id`. Bình luận hiện chủ đích không liên kết các ván với một người. |
| `core/trong_tai.py` và API vé/phiếu | Sổ phiếu/vé JSONL, liên kết địa chỉ ví và mã ván. Đó không phải DB tài khoản hay tiến trình nhân vật. |
| `core/eth_ky.py` | Mật mã thuần Python phục vụ phiếu EIP-712. Không mở rộng mã này thành bộ xác minh đăng nhập; Auth dùng thư viện Ethereum riêng. |
| Dependencies | `requirements.txt` có FastAPI, Pydantic, uvicorn, numpy, scikit-learn, matplotlib, streamlit, requests, httpx, pytest. Chưa có SQLAlchemy/Alembic/eth-account trong requirements. Không thấy cấu hình ORM, migration hay file DB trong cây dự án được khảo sát. |
| Tiến trình | `GoldRushGame.diemCaoNhat` chỉ ở bộ nhớ; chưa có tài khoản, EXP/inventory/quest được lưu theo người dùng. Phiếu/vé trên server và dữ liệu hợp đồng không thay thế tiến trình RPG. |
| Flutter tests | 11 file `*_test.dart`, 87 lời gọi khai báo test trong source; unit test dùng `flutter_test`, `ViGia`, `MockClient`. Chưa có test Auth/UI Auth. |
| Backend tests | 6 file `test_*.py`, 72 method `test_*` trong source; `unittest.TestCase` chạy qua pytest, API dùng `TestClient` và thư mục tạm. Một số test sửa env/reload module nên phải chú ý cách ly trạng thái. |

Các endpoint hiện nhận `vi` do client gửi (`/api/man/bat-dau`, `/api/man/ve`, `/api/vang/phieu`, `/api/vang/cho-nhan`) **chưa chứng minh người gọi sở hữu ví đó**. `/api/nhat-ky` chưa ràng buộc chủ ván; kiểm tra trùng mã ván không phải kiểm tra quyền. Auth Gate ở Flutter không tự bảo vệ các endpoint này.

## 2. Kiến trúc đề xuất

```text
MaterialApp
  └─ CongXacThuc (Auth Gate, giữ Vi + BoXacThuc ở cấp ứng dụng)
      ├─ kiểm tra /api/me + eth_accounts/eth_chainId, không popup
      ├─ ManHinhDangNhap: chào mừng → kết nối → ký → đăng ký/thành công
      └─ phiên hợp lệ + ví/mạng khớp + bấm bắt đầu
          └─ ManHinhGame theo user.id/session generation
              └─ GoldRushGame → menu / overlay chonMan → gameplay

Flutter MayChuXacThuc ── cookie HttpOnly + CSRF ── FastAPI Auth router
                                                    ├─ SIWE + eth-account
                                                    ├─ SQLAlchemy + SQLite
                                                    └─ dependency phiên + adapter quyền chủ ván
```

Một controller `BoXacThuc extends ChangeNotifier` quản lý state machine; không thêm thư viện state management nếu chưa cần. Model JSON thuần Dart, client HTTP inject được, đồng hồ/timer inject được để test hết hạn.

Trạng thái: `khoiPhuc`, `chaoMung`, `dangKetNoi`, `choKy`, `dangXacMinh`, `canDangKy`, `dangDangKy`, `sanSang`, `trongGame`, `dangDangXuat`, `loi`. Lỗi lưu cả mã ổn định và thông báo tiếng Việt; không suy ra thành công từ địa chỉ ví.

Quy tắc cấp quyền: chỉ phiên `authenticated` còn hạn, chưa thu hồi, có `user_id`, đã khớp ví hiện tại mới mở game. Quyền `registration` chỉ cho tạo tên, không được `/api/me` hay dữ liệu người chơi. Chỉ `GET /api/me`/kết quả verify hoặc register từ backend xác nhận trạng thái tài khoản.

## 3. Giao diện đề xuất

Dùng một màn đăng nhập nhiều trạng thái, một form tạo nhân vật trong cùng bố cục, một panel hồ sơ. Tái sử dụng chọn màn/cửa hàng/cài đặt, không tạo bản sao. `_Khung`/`_Nut` hiện private nên tạo bộ widget Auth nhỏ riêng trước; chưa tách/sửa toàn bộ menu.

| Trạng thái | Nội dung và hành động |
| --- | --- |
| Chào mừng | Chữ **GOLD RUSH**, **AI ADVENTURE & BLOCKCHAIN**, nền cây/đường/đá tĩnh, nút **KẾT NỐI METAMASK**, dòng “Đăng nhập bằng ví, không cần mật khẩu”. |
| Đang kết nối | Chờ MetaMask, hướng dẫn xem popup tiện ích, nút Hủy. Hủy chỉ bỏ luồng ứng dụng; không hứa đóng popup provider đang chờ. Kết quả trả muộn không được tự chuyển bước. |
| Xác thực ví | Địa chỉ rút gọn, mạng, thông điệp có thể mở xem, nút **KÝ XÁC THỰC**. Giải thích: ký thông điệp đăng nhập này không chuyển NFT, token hoặc tiền, không tốn gas. |
| Tạo nhân vật | Chỉ sau verify trả `registration_required`; tên bắt buộc, ví đã xác minh chỉ đọc, frame George gốc, nút **TẠO TÀI KHOẢN**. Không có email/mật khẩu/private key. |
| Thành công | Tên nhân vật, ví rút gọn, nút **BẮT ĐẦU PHIÊU LƯU**. Nút dựng game sau Gate, mở overlay `chonMan`; không đặt thêm route World Map chưa tồn tại. |
| Hồ sơ | Panel được mở từ menu/tạm dừng sau khi tích hợp: tên, avatar, ví đầy đủ có copy, trạng thái phiên, nút **ĐĂNG XUẤT**. |

Khung tối đa 480 px, `SafeArea`, cuộn được khi bàn phím mở, padding 16 px màn nhỏ/24–32 px desktop, nút tối thiểu 52 px. Ở màn hẹp dùng một cột; chữ tiếng Việt dùng font hệ thống và không cố định chiều cao form. Viền bậc thang, bóng cứng, màu gỗ/đá; ảnh phóng theo pixel với `FilterQuality.none`. Animation fade/slide ngắn khoảng 180–220 ms, tôn trọng giảm chuyển động. Nền static cache, không dựng Flame/game trước xác thực chỉ để làm nền đăng nhập.

Phân biệt chưa cài MetaMask, provider khác, người dùng từ chối (4001), đang có popup (-32002), sai mạng, lỗi RPC, backend không sẵn sàng, challenge hết hạn, tên trùng. Không hiển thị stack trace/response có dữ liệu nhạy cảm. Mobile native hiện hướng dẫn dùng bản web desktop có tiện ích MetaMask; không tuyên bố đã có mở app tự động. Web mobile chỉ tiếp tục nếu thực sự có provider phù hợp, không tự giả định có extension.

## 4. Chính sách tài khoản và database đề xuất

Một địa chỉ EOA chuẩn hóa lowercase = một tài khoản trên các chain được phép; lưu chain vào challenge/session, không đưa chain vào khóa duy nhất của `users`. Địa chỉ SIWE hiển thị checksum; chuẩn hóa ở backend sau validate 20 byte hex, không dùng username để xác thực. Trước mắt mặc định cho phép **31337**, thêm **11155111** bằng cấu hình; không cho mainnet mặc định. Auth không phụ thuộc hợp đồng cửa hàng hay khóa trọng tài.

Tên: trim, chuẩn hóa Unicode NFC, 3–20 Unicode code point; cho chữ Unicode, dấu kết hợp, chữ số, space ASCII, `_`, `-`; ít nhất một chữ hoặc số; cấm control/zero-width/emoji và ký tự khác. Gộp các space liên tiếp. `username_key = NFC(username.casefold())`, UNIQUE, giữ dấu tiếng Việt: “An” trùng “an”, “Đạt” khác “Dat”. Backend là nguồn quy tắc cuối cùng; frontend kiểm tra sớm và hiển thị lỗi field. Độ dài request thô cũng bị giới hạn để không normalize dữ liệu quá lớn. Avatar ban đầu chỉ nhận giá trị server `george`, không nhận URL/tên file tùy ý.

SQLite local + SQLAlchemy + Alembic là đề xuất vì dự án chưa có DB/ORM. Dùng engine/session factory inject được, một DB session mỗi request, bật foreign keys và busy timeout; cấu hình transaction SQLite rõ ràng và test cạnh tranh bằng DB file thật. Không tạo bảng bằng hai cơ chế `create_all` và migration song song ở production. Migration là nguồn schema; DB test tạm có thể apply cùng migration.

| Bảng mới | Trường / ràng buộc chính |
| --- | --- |
| `users` | `id` UUID PK, `wallet_address` UNIQUE NOT NULL, `username`, `username_key` UNIQUE, `avatar`, `created_at`. |
| `auth_challenges` | `id` UUID, `nonce` UNIQUE, `wallet_address`, `chain_id`, `domain`, `uri`, `message` chính xác, `browser_binding_hash`, `issued_at`, `expires_at`, `consumed_at`. |
| `auth_sessions` | `id`, `token_hash` UNIQUE, `purpose` (`registration`/`authenticated`), `wallet_address`, `chain_id`, `user_id` nullable FK, `created_at`, `expires_at`, `revoked_at`. CHECK: phiên authenticated bắt buộc có user; registration không có user. |
| `game_run_owners` | Adapter bảo vệ API cũ: `ma_van` PK/UNIQUE, `user_id` FK, `created_at`; nhận quyền sở hữu từ phiên, không từ JSON client. Chưa phải bảng tiến trình. |

Không lưu chữ ký vào DB/log. Session/grant/browser binding là giá trị ngẫu nhiên 32 byte trở lên, gửi cookie; DB chỉ lưu SHA-256 của token. Không cần JWT hoặc khóa ký JWT. `AUTH_CSRF_SECRET` là secret độc lập qua env để tạo CSRF HMAC gắn với session; không dùng khóa trọng tài.

Nonce `secrets.token_hex(16)` (32 ký tự hex, phù hợp chữ/số SIWE); challenge 5 phút, quyền đăng ký 10 phút, phiên đăng nhập 8 giờ thời hạn tuyệt đối là mặc định đề xuất. Tất cả thời gian UTC, đồng hồ server quyết định hết hạn; dọn bản ghi cũ theo retention cấu hình. Rate limit challenge/verify/register theo IP và ví; không chỉ dùng dict trong RAM khi có nhiều worker.

Đăng ký trong một transaction: kiểm tra grant còn hạn/chưa thu hồi → INSERT user → thu hồi grant bằng conditional UPDATE → tạo session mới → COMMIT. Unique constraints chặn hai request tạo trùng ví/tên; rollback nếu bất kỳ bước thất bại. Tên trùng trả 409 và còn được thử lại với grant hợp lệ. Grant đã dùng không thể tạo session lần hai. Không tự gộp tài khoản theo tên.

Cho Người 5: `player_progress.user_id` FK UNIQUE, EXP, inventory/quest liên kết cùng `users.id`. Không tạo các bảng đó ở lượt Auth đầu; mọi API tương lai lấy `user_id` từ dependency phiên, không từ địa chỉ hay ID client đưa. Không ghi đè hoặc tự gán JSONL cũ cho user mới. Nếu cần nhập dữ liệu cũ phải có thiết kế migration riêng.

## 5. SIWE và chống replay

Thông điệp theo [EIP-4361](https://eips.ethereum.org/EIPS/eip-4361), ký EIP-191 `personal_sign`; server tạo toàn bộ domain/URI/timestamp/nonce từ cấu hình tin cậy và challenge đã lưu. Client không gửi domain/URI để server dùng trực tiếp. Không suy domain từ Host/X-Forwarded-Host chưa được cấu hình tin cậy.

Ví dụ local (địa chỉ chỉ là mẫu; thông điệp thực tế phải có EIP-55 checksum):

```text
localhost:5000 wants you to sign in with your Ethereum account:
0x0000000000000000000000000000000000000001

Sign in to Gold Rush. This request does not transfer assets.

URI: http://localhost:5000
Version: 1
Chain ID: 31337
Nonce: 7d82b0539c4a6f219b08a175e6d24310
Issued At: 2026-11-06T03:00:00Z
Expiration Time: 2026-11-06T03:05:00Z
```

1. Bấm kết nối mới gọi `eth_requestAccounts`. Kiểm tra provider MetaMask và chain được phép. Sai chain hiển thị nút đổi mạng riêng; không mở popup chuyển mạng khi chỉ restore.
2. Bấm ký mới lấy challenge rồi gọi `personal_sign` với `[hex(UTF8(message)), address]` qua cùng provider đã chọn, theo [tài liệu MetaMask](https://docs.metamask.io/metamask-connect/evm/guides/sign-data/). Ký nguyên message, không tự thêm prefix hoặc double-hash.
3. `/verify` đọc challenge và cookie browser binding, so khớp message byte-for-byte, parse/validate các trường SIWE, version 1, domain, URI, chain allowlist, nonce, issuedAt/expirationTime, wallet. Giới hạn sai lệch đồng hồ ở issuedAt (đề xuất 30 giây); không gia hạn expiry theo client.
4. Dùng `eth-account` recover signer trên EIP-191 (`encode_defunct(text=message)`), so địa chỉ recover với địa chỉ challenge. Thư viện SIWE/parser được lựa chọn và kiểm tra tương thích khi viết `siwe.py`; không thay parser bằng một regex lỏng, không dùng mật mã tự viết của trọng tài.
5. Sau chữ ký hợp lệ, trong một transaction thực hiện `UPDATE auth_challenges SET consumed_at=:now WHERE id=:id AND consumed_at IS NULL AND expires_at > :now AND browser_binding_hash=:binding`; bắt buộc đúng **1 row**. Cùng transaction tạo grant/session và thu hồi phiên cũ nếu có; commit xong mới set cookie. Hai request đồng thời chỉ một request thành công. Không dùng “đọc chưa dùng rồi set” ngoài transaction.
6. Challenge sai chữ ký không được cấp quyền. Challenge đã dùng/hết hạn không cấp lại session dù chữ ký đúng. Hỏng response sau commit yêu cầu challenge mới, không phát lại session token từ DB.

Chỉ hỗ trợ chữ ký recover được về EOA trong giai đoạn đầu. Không quảng cáo hỗ trợ smart contract wallet. [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271) cần backend RPC tin cậy cho đúng chain, kiểm tra `isValidSignature`, timeout/giới hạn tài nguyên và test riêng; delegated account/EIP-7702, counterfactual wallet cũng cần chính sách riêng. Không dựa vào việc frontend tự báo “EOA”.

## 6. Hợp đồng JSON API đề xuất

Mọi response Auth và dữ liệu cá nhân có `Cache-Control: no-store`. POST dùng JSON, giới hạn body nhỏ (đề xuất 8 KiB); verify giới hạn message 4 KiB, chữ ký EOA 65 byte hex. Wallet validate ở backend; model reject field ngoài hợp đồng. Không trả session token trong JSON.

### `POST /api/auth/challenge` → 201

```json
{"wallet_address":"0x0000000000000000000000000000000000000001","chain_id":31337}
```

```json
{"challenge_id":"c21ad4be-b54e-4ecb-9c99-62dbdcedc677","message":"<toàn bộ SIWE message nguyên văn>","expires_at":"2026-11-06T03:05:00Z"}
```

Set cookie HttpOnly `gr_auth_flow` nếu chưa có binding hợp lệ, lưu hash binding vào challenge. Một browser có thể có nhiều challenge riêng; không thay binding trên mỗi request làm hỏng tab khác. Chỉ nhận Origin trong allowlist, `Content-Type: application/json`, header `X-Gold-Rush-Auth: 1` để bootstrap qua CORS preflight. Origin thiếu/null bị từ chối ở Auth browser endpoints; test/API client phải gửi Origin hợp lệ. Sai chain 422, quá hạn mức 429. Response không tiết lộ ví đã đăng ký hay chưa.

### `POST /api/auth/verify` → 200

```json
{"challenge_id":"c21ad4be-b54e-4ecb-9c99-62dbdcedc677","message":"<message đã nhận>","signature":"0x<130 ký tự hex>"}
```

Kiểm tra Origin/header bootstrap như challenge và browser binding bắt buộc. Ví đã đăng ký:

```json
{"status":"authenticated","user":{"id":"80574202-05bd-4577-8edf-d480b37cf9a2","wallet_address":"0x0000000000000000000000000000000000000001","username":"Nhà Thám Hiểm","avatar":"george","created_at":"2026-11-06T03:01:00Z"},"expires_at":"2026-11-06T11:01:00Z","csrf_token":"<CSRF gắn với session>"}
```

Ví mới:

```json
{"status":"registration_required","wallet_address":"0x0000000000000000000000000000000000000001","expires_at":"2026-11-06T03:11:00Z","csrf_token":"<CSRF gắn với grant>"}
```

Cả hai set cookie `gr_session` mới, nhưng lưu `purpose` khác nhau trong DB. Cookie của quyền đăng ký không dùng để truy cập game. Thu hồi session/grant cũ nhận được trong request khi thay phiên. Chữ ký sai 401; message/binding không khớp 401; challenge dùng lại 409; hết hạn 410. Lỗi không chứa chữ ký/token/message gốc.

### `POST /api/auth/register` → 201

```json
{"username":"Nhà Thám Hiểm"}
```

Cookie grant + `X-CSRF-Token` bắt buộc. Không nhận wallet từ request đăng ký; lấy từ grant đã chứng minh. Server đặt avatar mặc định. Thành công trả cùng cấu trúc `status: authenticated` như verify, xoay cookie/CSRF và thu hồi grant. Thiếu grant/hết hạn 401, CSRF sai 403, tên sai 422, tên/ví trùng 409. Nếu ví đã được tạo bởi một luồng khác, yêu cầu xác thực mới để đăng nhập, không tạo user thứ hai.

### `GET /api/me` → 200

```json
{"user":{"id":"80574202-05bd-4577-8edf-d480b37cf9a2","wallet_address":"0x0000000000000000000000000000000000000001","username":"Nhà Thám Hiểm","avatar":"george","created_at":"2026-11-06T03:01:00Z"},"chain_id":31337,"expires_at":"2026-11-06T11:01:00Z","csrf_token":"<CSRF gắn với session>"}
```

Chỉ lookup từ cookie authenticated hợp lệ, join user tương ứng. Không nhận `user_id`/wallet để đổi hồ sơ trả về. Không có phiên, chỉ có grant, đã thu hồi hoặc hết hạn → 401. Với grant chưa hoàn tất, reload quay lại đăng nhập/ký mới; chưa bổ sung endpoint resume đăng ký trong phiên bản đầu.

### `POST /api/auth/logout` → 204

Body `{}`, cookie + CSRF cho phiên/grant hiện tại. Thu hồi DB, xóa cookie đúng Path/SameSite/Secure, không chỉ xóa phía Flutter. Đã logout thì idempotent 204; request có phiên đang hợp lệ nhưng CSRF sai vẫn 403. Không gọi RPC “ngắt MetaMask” để giả lập logout. Nếu cookie hết hạn được browser tự xóa thì server vẫn từ chối phiên theo `expires_at`.

Lỗi Auth chung:

```json
{"detail":{"code":"USERNAME_TAKEN","message":"Tên nhà thám hiểm đã được sử dụng.","field":"username"}}
```

Pydantic validation có thể trả `detail` dạng list chuẩn FastAPI; client phải xử lý cả list và object. Chuẩn hóa lỗi chỉ trong router Auth, không đổi hợp đồng lỗi của API cũ.

## 7. Cookie, CORS, CSRF và cấu hình

Local: Flutter `http://localhost:5000`, API `http://localhost:8000`. Hai origin khác nhau nhưng cùng site; dùng cố định hostname `localhost`, không trộn `127.0.0.1`. Cookie host-only, `HttpOnly`, `SameSite=Lax`, `Path=/api`, `Secure=false` **chỉ ở local HTTP**. Production ưu tiên reverse proxy cùng origin cho game và `/api`, HTTPS bắt buộc, `Secure=true`. Max-Age không vượt hạn DB. Không dùng cấu hình cookie thiếu Secure trong môi trường HTTPS production.

Client web tạo `BrowserClient()..withCredentials = true` bằng conditional import để native vẫn biên dịch; [http mặc định không bật withCredentials](https://pub.dev/documentation/http/latest/browser_client/BrowserClient/withCredentials.html). Dùng cùng cấu hình credential cho Auth và API người chơi; browser tự quản cookie, không cố đọc HttpOnly. Không lưu auth token/chữ ký trong localStorage, sessionStorage, SharedPreferences hay URL. CSRF chỉ giữ trong bộ nhớ controller, khôi phục từ `/api/me`.

CORS bổ sung `allow_credentials=True`, allow origins cụ thể, methods cụ thể (`GET`, `POST`, `OPTIONS`) và headers cụ thể (`Content-Type`, `X-CSRF-Token`, `X-Gold-Rush-Auth`). Giữ origins cần thiết của dashboard; không dùng `*` với credentials, theo [tài liệu FastAPI](https://fastapi.tiangolo.com/tutorial/cors/). CORS không thay thế kiểm tra Origin/CSRF phía server. Preflight không yêu cầu session.

Mọi POST thay đổi dữ liệu sau verify kiểm tra Origin và CSRF HMAC gắn với token cookie (so constant-time); challenge/verify bootstrap dùng Origin + JSON + custom header + browser binding. Không chấp nhận form POST hay “chỉ có cookie” cho mutation. API cá nhân GET không làm thay đổi phiên và không cho cache. Site production khác site API chưa thuộc cấu hình đầu: nếu cần, phải thiết kế lại cookie `SameSite=None; Secure` và kiểm thử trình duyệt chặn third-party cookies; ưu tiên reverse proxy.

Env mới đề xuất cho backend:

```dotenv
AUTH_DATABASE_URL=sqlite:///./data/auth/gold_rush_auth.db
AUTH_SIWE_DOMAIN=localhost:5000
AUTH_SIWE_URI=http://localhost:5000
AUTH_ALLOWED_CHAIN_IDS=31337
AUTH_CHALLENGE_TTL_SECONDS=300
AUTH_REGISTRATION_TTL_SECONDS=600
AUTH_SESSION_TTL_SECONDS=28800
AUTH_COOKIE_SECURE=false
AUTH_CSRF_SECRET=<secret ngẫu nhiên ít nhất 32 byte, không commit>
CORS_ORIGINS=http://localhost:5000,http://localhost:8501
```

Đường dẫn SQLite tương đối lấy theo thư mục chạy `gold_rush_ai`; implementation nên resolve path rõ ràng. Dùng env hiện tại, `.env.example` chỉ là mẫu; server hiện chưa tự nạp `.env`, cần export env hoặc cơ chế nạp được bổ sung có chủ đích. Không tái sử dụng `TRONG_TAI_KHOA`. Thêm ignore DB/`-wal`/`-shm`, không ignore migration. Pin phiên bản dependency được kiểm tra khi triển khai, không chọn số phiên bản từ trí nhớ.

Frontend tiếp tục `GOLD_RUSH_API`; thêm `GOLD_RUSH_AUTH_CHAIN_ID=31337` làm gợi ý UI, backend là nguồn quyết định. Khi thiếu API, Gate báo chưa cấu hình và chặn game, không fallback vào chơi offline trong bản Auth.

## 8. Khôi phục phiên, đổi ví, đăng xuất và bảo vệ API cũ

Restore chỉ gọi `/api/me`, `eth_accounts`, `eth_chainId`; không `eth_requestAccounts`/ký/chuyển mạng tự động. Phiên còn hạn nhưng provider vắng, accounts rỗng, địa chỉ không khớp hoặc mạng khác `session.chain_id` thì không mở game; thu hồi phiên rồi yêu cầu thao tác lại. Khi tab focus/app resume kiểm tra lại, và timer tối đa khoảng 60 giây khi game hoạt động gọi `/api/me`. Timer tới `expires_at` đóng Gate; backend vẫn kiểm tra mọi request. Lỗi mạng khóa truy cập và cho thử lại, không khẳng định phiên đã hết hạn nếu chưa nhận 401.

Nghe `accountsChanged` ngay từ cấp ứng dụng; đổi sang ví khác/rỗng thì khóa Gate đồng bộ, xóa profile/avatar/grant/CSRF khỏi UI, pause/dispose game, bỏ kết quả async cũ rồi logout backend. `chainChanged` thay chain so với phiên cũng đóng Gate và yêu cầu xác thực mới. Không tự chuyển ví/người dùng chỉ bằng event. Không mở popup đến khi người dùng bấm.

Mỗi thao tác gắn generation; kết quả request/MetaMask trả muộn sau Hủy/đổi ví/logout không được phục hồi state cũ. Kiểm tra lại account/chain trước và sau ký/verify/register. Serialize các mutation Auth: bỏ kết quả HTTP ở Dart không hủy tác dụng `Set-Cookie` trong browser; nếu mutation cũ hoàn tất sau hủy, phải hoàn tất thu hồi/đối chiếu `/me` trước khi cho luồng mới mở game. Đồng bộ thông báo logout/đổi ví giữa tab qua BroadcastChannel hoặc tương đương, chỉ truyền tín hiệu, không truyền token.

Không gắn phiên cũ sang game mới: tạo `ManHinhGame` theo `user.id` và generation, dùng lại đúng `Vi` nhưng tạo mới trạng thái `PhienVi`, dọn subscription/timer/notifier khi rời game. Các request/retry nhật ký/phiếu phải gắn generation lúc tạo và ngừng trước khi gửi dưới cookie người dùng mới. Không cho nhật ký A còn nằm trong hàng đợi gửi bằng phiên B. Việc dispose Flame cần dừng audio và hủy tài nguyên do game sở hữu, không dispose `Vi` cấp ứng dụng theo mỗi game.

Đăng xuất đóng Gate ngay và chờ server xác nhận thu hồi. Nếu mất mạng, hiển thị chưa hoàn tất đăng xuất, khóa restore; có thể giữ cờ `logout_pending` không chứa dữ liệu tài khoản trong sessionStorage và hoàn tất revoke trước khi restore, kể cả reload. `/me` chỉ được gọi lại để mở game khi không còn pending. Xóa cookie phía client không đủ để tuyên bố đã thu hồi DB. Backend không tự biết MetaMask đổi ví khi thiết bị offline; không hứa thu hồi server tức thì trong trường hợp đó. Khi kết nối trở lại phải hoàn tất revoke hoặc xác thực lại và thay phiên.

### Adapter API cũ cần thiết để tránh chỉ bảo vệ giao diện

Đây là thay đổi bảo mật tối thiểu dự kiến ở các lượt sau, **chưa sửa trong lượt khảo sát**. Thêm dependency/middleware riêng có phạm vi endpoint cụ thể; giữ nguyên thuật toán Map Generator, AI, kiểm định và ký phiếu.

| Endpoint hiện có | Kiểm tra bổ sung đề xuất |
| --- | --- |
| `POST /api/nhat-ky` | Phiên + Origin/CSRF; ràng buộc `ma_van` UNIQUE với `current_user.id` bằng transaction. Ván đã có owner khác phải từ chối trước handler; owner đúng được retry idempotent. |
| `POST /api/man/bat-dau` | Phiên + CSRF; `vi` phải trùng wallet phiên; chiếm quyền mã ván cho user hiện tại bằng unique constraint trước khi gọi logic cũ. |
| `GET /api/man/ve`, `GET /api/vang/cho-nhan` | Phiên; `vi` query phải khớp ví phiên, không cho đọc dữ liệu ví khác. |
| `POST /api/vang/phieu` | Phiên + CSRF; `vi` khớp ví phiên và `ma_van` thuộc user. Không tự nhận quyền sở hữu chỉ vì biết mã ván. |
| `GET /api/me`, API tiến trình tương lai | Chỉ truy vấn theo user trong phiên. ID client gửi không có quyền đổi owner. |

Adapter có thể đặt trong `api/bao_ve_nguoi_choi.py` và gắn tại `api/main.py`; giới hạn body trước khi đọc/parse, không log body, không chặn CORS OPTIONS. Trường `vi` được giữ để tương thích payload cũ, nhưng backend phải so khớp. Bản ghi owner dạng reservation có thể tồn tại khi handler cũ thất bại: owner đúng được retry; không giải phóng mã ván cho tài khoản khác. Transaction DB ownership không làm thao tác ghi JSONL thành transaction; test lỗi/retry riêng và không tuyên bố atomic toàn bộ pipeline cũ.

Nhật ký cũ chưa có owner không được tự gán bởi người biết mã ván. Chỉ cấp owner khi tạo ván mới trong luồng đã xác thực; đối chiếu cả mã tồn tại trong JSONL trước khi cho nhận owner. Cần khóa/đồng bộ phù hợp quanh đường vào adapter để tránh cuộc đua với handler cũ. Dữ liệu legacy giữ cho thống kê, muốn nhận lại phiếu cũ cần kế hoạch đối soát riêng. Không bật chế độ “bỏ qua Auth” cho API cá nhân để làm test cũ chạy xanh.

Health, cấu hình công khai, danh sách màn có thể public. API sinh bản đồ/AI/thống kê không biến thành API tiến trình; quyền quản trị dashboard cần chính sách riêng nếu đưa lên Internet. Khi gắn ownership vào telemetry, cập nhật mô tả dữ liệu: nhật ký được liên kết tài khoản ở bảng adapter, bình luận “không nối được các ván” hiện tại sẽ không còn mô tả đầy đủ hệ thống. Không âm thầm đổi schema telemetry/AI.

## 9. Phân chia file và thứ tự triển khai cụ thể

**Không thực hiện danh sách này trong lượt đầu.** Mỗi lượt tiếp theo chỉ viết/sửa file được yêu cầu và kiểm tra phù hợp; không chuyển bước tự động. File chưa đủ dependency chỉ kiểm tra cú pháp/định dạng, không báo đã qua test tích hợp. Khuyến nghị thứ tự:

| Bước | File mới hoặc thay đổi | Trách nhiệm / kiểm tra đi kèm |
| --- | --- | --- |
| 1 | `gold_rush_ai/auth/__init__.py`, `auth/config.py` | Cấu hình Auth độc lập, validate domain/URI/origin/TTL/secret. Tiếp theo thêm `tests/test_auth_config.py`. |
| 2 | `gold_rush_ai/requirements.txt` | Thêm/pin SQLAlchemy, Alembic, eth-account và parser SIWE sau kiểm tra tương thích; cài trong venv riêng. |
| 3 | `gold_rush_ai/auth/database.py` | Engine/session factory inject được, SQLite FK/transaction; không mở DB lúc import module. |
| 4 | `gold_rush_ai/auth/models.py` | Bốn bảng, unique/FK/check constraints; sau đó `tests/test_auth_database.py`. |
| 5 | `gold_rush_ai/alembic.ini`, `migrations/env.py`, `migrations/script.py.mako`, `migrations/versions/0001_auth.py` | Lần lượt tạo cấu hình và migration, kiểm tra upgrade trên DB tạm. |
| 6 | `gold_rush_ai/auth/schemas.py` | Request/response, quy tắc tên/ví và lỗi; `tests/test_auth_schemas.py`. |
| 7 | `gold_rush_ai/auth/siwe.py` | Dựng/parse thông điệp, recover EIP-191, đối chiếu dữ liệu; `tests/test_auth_siwe.py`. |
| 8 | `gold_rush_ai/auth/service.py` | Challenge một lần, cấp/thu hồi session/grant, đăng ký atomic; `tests/test_auth_service.py` gồm concurrency. |
| 9 | `gold_rush_ai/auth/dependencies.py` | Current user, cookie, Origin, CSRF, rate limiter interface; test quyền truy cập. |
| 10 | `gold_rush_ai/auth/router.py` | Năm endpoint mới; `tests/test_auth_api.py` dùng app Auth tối thiểu/DB tạm. |
| 11 | `gold_rush_ai/.env.example`, `.gitignore` | Mẫu env không có secret, ignore DB và sidecar. |
| 12 | `gold_rush_ai/api/bao_ve_nguoi_choi.py` | Adapter phiên/ownership cho API cũ; test truy cập chéo và legacy. |
| 13 | `gold_rush_ai/api/main.py` | Chỉ mount Auth router, lifecycle tài nguyên Auth, CORS credential, adapter có phạm vi. Giải thích diff trước khi sửa. Cập nhật tests API cũ với phiên thật/fixtures, không đổi assertion nghiệp vụ để lách bảo vệ. |
| 14 | `gold_rush/lib/xac_thuc/mo_hinh_xac_thuc.dart` | DTO, state/lỗi Auth; test JSON. |
| 15 | `gold_rush/lib/blockchain/vi.dart` | Bổ sung capability riêng `ViKyThongDiep` và lifecycle riêng nếu cần, giữ interface `Vi` cũ cho fake hiện có. Chưa đổi giao dịch/SBT/NFT. |
| 16 | `gold_rush/lib/blockchain/vi_web.dart` | Implement capability ký; nhận diện MetaMask rõ, discovery chờ có giới hạn khi người dùng bấm, gỡ listener khi đóng ứng dụng. Native không implement capability thì UI báo chưa hỗ trợ. |
| 17 | `gold_rush/lib/xac_thuc/http_client.dart`, `http_client_web.dart`, `http_client_native.dart` | Lần lượt tạo factory conditional và credential HTTP. Native chưa hỗ trợ Auth ví; không âm thầm thay cookie bằng localStorage token. |
| 18 | `gold_rush/lib/xac_thuc/may_chu_xac_thuc.dart` | Năm API, timeout, phân loại lỗi, CSRF in-memory; `test/xac_thuc/may_chu_xac_thuc_test.dart`. |
| 19 | `gold_rush/lib/xac_thuc/bo_xac_thuc.dart` | State machine, restore, generation, provider events, expiry/logout; `test/xac_thuc/bo_xac_thuc_test.dart` + fake ký/sự kiện riêng. |
| 20 | `gold_rush/lib/man_hinh/xac_thuc/thanh_phan.dart` | Nền pixel tĩnh, khung, nút, avatar crop, theme cục bộ; kiểm tra widget kích thước nhỏ. |
| 21 | `gold_rush/lib/man_hinh/xac_thuc/tao_nhan_vat.dart` | Form tên + ví chỉ đọc; test validate và lỗi backend. |
| 22 | `gold_rush/lib/man_hinh/xac_thuc/dang_nhap.dart` | Welcome/connect/sign/register/success trong một màn; test từng trạng thái. |
| 23 | `gold_rush/lib/man_hinh/xac_thuc/ho_so.dart` | Panel hồ sơ/logout, không thay cửa hàng. |
| 24 | `gold_rush/lib/xac_thuc/cong_xac_thuc.dart` | Gate nhận game builder để test chưa auth không dựng game/Flame. |
| 25 | `gold_rush/lib/main.dart` | Đổi home sang Gate, composition root sở hữu provider/controller; chỉ dựng game sau auth. Giải thích diff trước khi sửa. |
| 26 | `gold_rush/lib/gold_rush_game.dart`, `lib/blockchain/phien_vi.dart` | Từng file riêng: inject Vi/phiên thay vì tự chọn provider, dọn trạng thái và vòng đời. Thêm hook mở chọn màn sau nút bắt đầu; không sửa logic tính thắng/thua. |
| 27 | `gold_rush/lib/man_hinh/lop_phu.dart` | Thêm điểm mở panel hồ sơ vào menu/tạm dừng, giữ menu hiện có. |
| 28 | `gold_rush/lib/ai/gui_nhat_ky.dart`, `lib/blockchain/may_chu_phieu.dart` | Từng file riêng: inject client credential/CSRF và generation cho request cá nhân; ngừng retry cũ khi đổi phiên. Không sửa thuật toán AI hoặc dữ liệu phiếu. |
| 29 | `gold_rush/test/xac_thuc/cong_xac_thuc_test.dart`, `man_hinh_xac_thuc_test.dart`; `gold_rush_ai/tests/test_auth_access.py` | Kiểm tra Gate, responsive, API ownership/replay và tích hợp thật. |
| 30 | `docs/AUTH_INTEGRATION.md` | Cập nhật trạng thái, lệnh chạy, phiên bản thực tế và số test thực chạy sau mỗi mốc. |

Các file nhóm trong một ô là danh sách thứ tự của một mốc, **không phải yêu cầu viết tất cả trong một lượt**. Có thể điều chỉnh tên file khi phát hiện ràng buộc thực tế, phải cập nhật tài liệu trước khi mở rộng phạm vi. Không cần sửa `pubspec.yaml` chỉ để thêm UI Auth; nếu triển khai HTTP/capability bằng package hiện có thì giữ dependencies Flutter.

Thay đổi dùng chung tối thiểu cần trình bày trước khi thực hiện: `main.dart` (Gate), `gold_rush_game.dart` (inject ví/lifecycle/điểm mở chọn màn), `vi.dart`/`vi_web.dart` (ký và lifecycle), `phien_vi.dart` (dọn phiên), hai HTTP client cũ (credentials/generation), `lop_phu.dart` (lối mở hồ sơ), `api/main.py` (mount/CORS/adapter). Không có thay đổi nào trong số này đã được thực hiện ở lượt khảo sát.

## 10. Kế hoạch kiểm thử và trạng thái kiểm chứng

Backend: challenge đúng định dạng; chữ ký EOA đúng/sai; ví recover khác; message/domain/URI/chain bị thay; nonce hết hạn/dùng lại; browser binding sai; hai verify đồng thời chỉ một cấp quyền; grant hết hạn/dùng lại; hai register cùng ví/tên chỉ một user; tên Unicode; session rotation/expiry/revoke; CSRF/Origin sai; CORS credential; chỉ grant không được vào `/me`; đọc/ghi ván của user khác bị chặn; không chiếm telemetry legacy; rollback/retry và DB tồn tại qua restart.

Flutter unit/widget: có/không provider, provider khác MetaMask, từ chối, popup bận, sai chain; ký và verify riêng biệt; đăng ký lần đầu/đăng nhập ví cũ; đổi ví trong lúc ký/verify/register/game; kết quả trả muộn sau Hủy; logout lỗi mạng; restore không popup; expiry/401; thiếu API chặn game; Gate không gọi game builder khi chưa auth; profile cũ không lóe khi đổi ví; retry telemetry cũ không gửi bằng phiên mới; màn 320×568, 568×320, desktop và bàn phím/tăng cỡ chữ.

Thử thủ công Flutter Web + FastAPI + MetaMask thật: popup kết nối/ký, deny/cancel, đổi chain/account, reload, hết hạn, multi-tab, logout; xác nhận DB user/session/nonce và không có giao dịch on-chain từ bước đăng nhập. Mock provider không chứng minh popup MetaMask thật hoạt động. Native chỉ test thông báo chưa hỗ trợ, không đánh dấu mobile login đã xong.

Lệnh dự kiến khi đã có dependency và triển khai tới mốc tương ứng:

```bash
# Từ gold_rush_ai, trong venv đã cài requirements
python -m pytest tests/test_auth_config.py -q
python -m pytest tests -q
alembic upgrade head
uvicorn api.main:app --reload --port 8000

# Từ gold_rush
flutter analyze
flutter test
flutter run -d chrome --web-port 5000 --dart-define=GOLD_RUSH_API=http://localhost:8000 --dart-define=GOLD_RUSH_AUTH_CHAIN_ID=31337
```

**Kết quả lượt khảo sát:** chỉ đọc source/assets, đếm khai báo test, kiểm tra công cụ và kiểm tra tài liệu mới. Flutter/Dart có trên PATH; Python mặc định chưa có pytest, FastAPI, httpx, numpy hoặc scikit-learn. Chưa cài dependencies, chưa chạy bộ test Flutter/backend, chưa có test Auth để chạy. **Số test đã chạy: 0; đạt/thất bại: chưa có kết quả.** Các số 87/72 phía trên là khai báo trong source, không phải kết quả chạy. Không báo Auth hoạt động trước khi triển khai và kiểm thử.

## 11. Tài liệu kỹ thuật đối chiếu

- [EIP-4361 — Sign-In with Ethereum](https://eips.ethereum.org/EIPS/eip-4361): định dạng message và yêu cầu xác minh.
- [EIP-191 — Signed Data Standard](https://eips.ethereum.org/EIPS/eip-191): envelope chữ ký cho `personal_sign`.
- [MetaMask — Sign data](https://docs.metamask.io/metamask-connect/evm/guides/sign-data/): thứ tự params và UTF-8 hex của `personal_sign`.
- [eth-account API](https://eth-account.readthedocs.io/en/stable/eth_account.html): recover/encode thông điệp, không cần khóa người dùng trên server.
- [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271): giới hạn hiện tại và hướng xác minh contract wallet.
- [FastAPI CORS](https://fastapi.tiangolo.com/tutorial/cors/): cấu hình origins/credentials tường minh.
- [Dart http BrowserClient.withCredentials](https://pub.dev/documentation/http/latest/browser_client/BrowserClient/withCredentials.html): cookie request phía web.
- [SQLAlchemy SQLite](https://docs.sqlalchemy.org/en/20/dialects/sqlite.html): kiểm soát transaction/foreign keys, cần kiểm tra theo phiên bản đã pin khi triển khai.

## Điểm dừng của lượt đầu

Tài liệu này là kết quả để chủ dự án kiểm tra kiến trúc, UI, API và thứ tự file. Dừng sau khảo sát và tạo tài liệu; chờ yêu cầu file cụ thể ở lượt tiếp theo. Chưa nối Gate, chưa tạo user/database, chưa thay đổi chức năng game/backend hiện tại.
