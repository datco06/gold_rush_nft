# TÀI LIỆU KẾT NỐI API & TÍCH HỢP (NGƯỜI 5 – MAP GENERATOR & BACKEND v1.3 - ROUND 2)

Tài liệu này quy chuẩn hóa toàn bộ các API Backend sau đợt rà soát bảo mật P0/P1, bao gồm hệ thống bảo mật Fail-Closed, tiến trình server-authoritative, kho đồ, nhiệm vụ và Map Generator phục vụ tích hợp giữa **Người 1 (UI/World Map)**, **Người 2 (Gameplay)**, **Người 3 (Generative AI)** và **Người 4 (Blockchain)**.

---

## 1. NGUYÊN TẮC BẢO MẬT & KIẾN TRÚC (BẮT BUỘC)

### 1.1. Cơ chế xác thực (Authentication - Fail Closed)
* Tất cả API quản lý dữ liệu cá nhân (`/api/progress`, `/api/inventory`, `/api/equipment/*`, `/api/quests/*`) **bắt buộc phải qua xác thực**.
* **Tuyệt đối KHÔNG tin cậy `player_id` hoặc `wallet` gửi từ query parameter hay request body**.
* Danh tính người chơi (`user_id`, `wallet_address`) được trích xuất an toàn từ:
  1. Cookie phiên đăng nhập SIWE (`gr_session`) thẩm định qua `auth_service` từ nhánh `feature/ai`.
  2. Adapter `ai_auth_source` gắn vào `app.state`.
* **Lưu ý hiện trạng**: Hiện tại backend chưa tích hợp bộ giải mã Bearer JWT riêng. Do đó, tất cả phiên đăng nhập web và client đều hoạt động qua cơ chế SIWE Cookie (`gr_session`).
* Nếu người dùng chưa đăng nhập, máy chủ trả về `HTTP 401 Unauthorized` (`SESSION_REQUIRED`).

### 1.2. Chống CSRF & Phân lập Origin
* Các request thay đổi trạng thái (`POST`) sử dụng cookie bắt buộc phải gửi kèm header `Origin` hợp lệ (thuộc `CORS_ORIGINS`) và header `X-CSRF-Token`.
* `CORS_ORIGINS = '*'` bị cấm áp dụng cho các thao tác mutation.
* Nếu chưa có `auth_service` để kiểm chứng CSRF token, máy chủ tuân thủ nguyên tắc **Fail-Closed** và từ chối request với mã lỗi `HTTP 403 Forbidden` (`CSRF_VERIFIER_UNAVAILABLE`).

### 1.3. Server-Authoritative Progress & Chống gian lận
* Client không được phép tự gửi lệnh "mở khóa màn X" hay "cộng Y EXP".
* Telemetry (`POST /api/nhat-ky`) chỉ ghi nhận dữ liệu trận đấu thô (`is_verified = 0`), **tuyệt đối không được coi là bằng chứng xác minh để mở màn hay cộng EXP**.
* Mọi tiến trình mở khóa màn và cộng EXP phải thông qua API hoàn thành màn có bằng chứng hợp lệ (`POST /api/progress/complete-stage`):
  - Phải có chứng chỉ ký từ trọng tài (`SoPhieu`) gắn liền với địa chỉ ví SIWE của người chơi.
  - Hoặc bản ghi trận đấu đã được trọng tài xác minh (`is_verified = 1`) và có `verified_wallet` khớp chính xác với ví SIWE. **Tuyệt đối không tin cậy `player_id` tự khai trong telemetry để xác minh quyền sở hữu**.
  - Hoặc qua dịch vụ `DichVuXacMinhTienTrinh` (`tien_trinh_verifier`) từ `feature/ai`.
  - Mọi trường hợp thiếu bằng chứng hoặc bằng chứng giả mạo đều bị từ chối (**Fail-Closed**).
* Hệ thống áp dụng bảng `stage_rewards` với khóa chính `evidence_id` và transaction `BEGIN IMMEDIATE` trong SQLite để chống replay và chống lost updates khi có nhiều request đồng thời.

---

## 2. API TIẾN TRÌNH & WORLD MAP (DÀNH CHO NGƯỜI 1 & NGƯỜI 2)

### 2.1. Lấy tiến trình người chơi
* **Phương thức**: `GET`
* **Endpoint**: `/api/progress`
* **Xác thực**: Bắt buộc (Cookie `gr_session`). Không truyền `player_id` qua query.
* **Mô tả**: Lấy tiến trình hiện tại của tài khoản đã đăng nhập. Nếu là tài khoản mới, hệ thống tự động khởi tạo: Cấp 1, 0 EXP, mở sẵn Màn 1 (`unlocked_stage_ids: [1]`), trang bị kiếm gỗ (`kiem_go`) và nhân vật George (`george`).
* **Phản hồi mẫu (200 OK)**:
```json
{
  "player_id": "usr_9f8a1c",
  "wallet_address": "0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc",
  "ten_hien_thi": "Dũng",
  "level": 2,
  "exp": 120,
  "exp_hien_tai": 20,
  "exp_can_len_cap": 200,
  "unlocked_stage_ids": [1, 2],
  "completed_stage_ids": [1],
  "equipped_weapon_id": "kiem_go",
  "equipped_character_id": "george",
  "unlocked_characters": ["george"],
  "updated_at": "2026-11-11T20:30:00Z"
}
```

### 2.2. Báo cáo hoàn thành màn chơi (Server-Authoritative)
* **Phương thức**: `POST`
* **Endpoint**: `/api/progress/complete-stage`
* **Xác thực**: Bắt buộc (Cookie + Origin + CSRF token).
* **Body**:
```json
{
  "stage_id": 1,
  "evidence_id": "van_abc123xyz"
}
```
* **Quy tắc xử lý nghiêm ngặt**:
  1. `stage_id` phải nằm trong khoảng 1 đến 6.
  2. Màn chơi phải nằm trong danh sách đã mở khóa (`unlocked_stage_ids`).
  3. `evidence_id` (`ma_van`) phải được xác thực từ trọng tài hoặc `SoPhieu` gắn liền với ví của người chơi. Telemetry thô bị từ chối `HTTP 422`.
  4. Chống replay: Mỗi `evidence_id` chỉ được nhận thưởng duy nhất 1 lần trên toàn hệ thống (`HTTP 409` nếu gửi lại).
  5. Chính sách EXP Server:
     - Hoàn thành lần đầu: **50 EXP**, tự mở khóa màn kế tiếp (`stage_id + 1`).
     - Chơi lại (Replay): **10 EXP**, áp trần tối đa 3 lần chơi lại có EXP trên mỗi màn để chống cày cuốc vô hạn.
* **Phản hồi mẫu (200 OK)**:
```json
{
  "thanh_cong": true,
  "thong_bao": "Đã ghi nhận hoàn thành màn 1",
  "tien_trinh": {
    "player_id": "usr_9f8a1c",
    "level": 1,
    "exp": 50,
    "unlocked_stage_ids": [1, 2],
    "completed_stage_ids": [1]
  }
}
```

---

## 3. API KHO ĐỒ & TRANG BỊ (DÀNH CHO NGƯỜI 1 & NGƯỜI 2)

### 3.1. Lấy danh sách kho đồ
* **Phương thức**: `GET`
* **Endpoint**: `/api/inventory`
* **Query Params**: `loai` (tùy chọn: `weapon`, `character`, `potion`, `material`).
* **Xác thực**: Bắt buộc.

### 3.2. Yêu cầu đổi trang bị
* **Phương thức**: `POST`
* **Endpoint**: `/api/equipment/select`
* **Xác thực**: Bắt buộc (Cookie + Origin + CSRF token).
* **Body**:
```json
{
  "loai": "weapon",
  "item_id": "kiem_go"
}
```
* **Quy tắc**: Người chơi chỉ có thể trang bị vật phẩm mình thực sự sở hữu trong kho đồ với số lượng > 0. Nếu vi phạm trả về `HTTP 400 Bad Request`.

---

## 4. API NHIỆM VỤ AI (DÀNH CHO NGƯỜI 3 - GENERATIVE AI)

### 4.1. Lấy ngữ cảnh người chơi để đưa vào prompt sinh nhiệm vụ
* **Phương thức**: `GET`
* **Endpoint**: `/api/quests/ai-context`
* **Xác thực**: Bắt buộc.

### 4.2. Gán nhiệm vụ do AI sinh cho người chơi
* **Phương thức**: `POST`
* **Endpoint**: `/api/quests/ai-assign`
* **Quyền hạn**: **BỊ KHÓA HOÀN TOÀN ĐỐI VỚI HTTP CLIENT (FAIL-CLOSED)**.
* **Bảo vệ**: Mọi external client (kể cả đã đăng nhập SIWE hoặc cố gán cờ toàn cục) đều bị từ chối `HTTP 403 Forbidden` (`AI_ASSIGN_RESTRICTED`).
* **Cơ chế hoạt động**: Nhiệm vụ AI chỉ được tạo thông qua hàm Python nghiệp vụ server nội bộ `tao_nhiem_vu_ai_noi_bo(conn, player_id, ...)`.
* **Chính sách an toàn của hàm nội bộ**:
  - `target_type` phải nằm trong allowlist: `hoan_thanh_man`, `nhat_xu`, `choi_khong_trung_don`, `toc_do`.
  - Giới hạn tối đa 3 nhiệm vụ active (`status = 'dang_lam'`) cho mỗi người chơi.
  - EXP thưởng do server policy kẹp trần tối đa 50 EXP; `reward_gold` bắt buộc bằng 0; `reward_items` bắt buộc rỗng.

### 4.3. Lấy danh sách nhiệm vụ đang làm
* **Phương thức**: `GET`
* **Endpoint**: `/api/quests/active`
* **Xác thực**: Bắt buộc.

### 4.4. Nhận thưởng nhiệm vụ khi hoàn thành
* **Phương thức**: `POST`
* **Endpoint**: `/api/quests/claim`
* **Xác thực**: Bắt buộc (Cookie + Origin + CSRF token).
* **Body**:
```json
{
  "quest_id": "q_abc123"
}
```
* **Xử lý đồng thời (Race Condition)**: Thao tác nhận thưởng sử dụng cập nhật điều kiện nguyên tử:
  `UPDATE quests SET status = 'da_nhan' WHERE quest_id = ? AND player_id = ? AND status = 'hoan_thanh'`.
  Loại bỏ hoàn toàn khả năng nhận trùng (double-claim).

---

## 5. API TELEMETRY & TRỌNG TÀI BLOCKCHAIN (NGƯỜI 2 & NGƯỜI 4)

### 5.1. Nhật ký ván chơi (Telemetry)
* **Phương thức**: `POST`
* **Endpoint**: `/api/nhat-ky`
* **Xác thực**: Công khai (dùng cho telemetry từ client).
* **Mô tả**: Lưu nhận nhật ký ván đấu, đối soát trọng tài và ghi nhận vào bảng `match_results` với cờ `is_verified = 0`.
* **Lưu ý**: Bản ghi telemetry thô **không thể dùng làm bằng chứng mở màn**.

### 5.2. Blockchain & Phiếu Vàng EIP-712 (Chống Voucher Hijacking & Bảo vệ quyền sở hữu)
* `GET /api/vang/cau-hinh`: Lấy `chain_id`, `hop_dong`, `trong_tai`.
* `POST /api/man/bat-dau`: Đăng ký bắt đầu ván `(ma_van, vi, man, ve)`.
  - **Bảo mật & Xác thực**: Bắt buộc phiên SIWE (Fail-Closed, 401 nếu chưa đăng nhập).
  - **Ràng buộc ví**: Lấy địa chỉ ví từ phiên SIWE; nếu client truyền kèm `vi` trong body, bắt buộc phải khớp (403 nếu sai khác).
  - **Bảo vệ Mutation**: Kiểm tra Origin và X-CSRF-Token khi gửi cookie phiên `gr_session` (403 nếu thiếu hoặc sai).
  - **Màn có cọc (Màn 2–6)**: Bắt buộc `ve >= 1` tương ứng với số vé từ giao dịch `vaoMan` on-chain.
  - **Màn miễn phí (Màn 1)**: Bắt buộc đăng ký với `ve = 0` đóng vai trò **server-issued match ticket** ràng buộc `ma_van` với ví SIWE người chơi trước khi thả George vào ván. Truyền `ve > 0` vào màn 1 bị từ chối `HTTP 422`.
  - **Chống chiếm đoạt mã ván**: Không cho phép đăng ký lại mã ván đã tồn tại trong `SoVe` (`HTTP 409 Conflict`).
  - **Server-generated `ma_van`**: Nếu client không truyền `ma_van`, server tự động sinh ngẫu nhiên UUID v4 an toàn (`van-{hex32}`) và trả về cho client.
* `GET /api/man/ve`: Kiểm tra vé đã dùng chưa.
* `POST /api/vang/phieu`: Trọng tài kiểm định ván và ký EIP-712.
  - **Bảo mật & Xác thực**: Bắt buộc phiên SIWE (Fail-Closed, 401 nếu chưa đăng nhập).
  - **Ràng buộc ví**: Body `vi` phải khớp với ví phiên SIWE (403 nếu sai khác).
  - **Bắt buộc Match Ticket trước khi cấp Voucher (Fail-Closed cho cả 6 màn)**: Bắt buộc tồn tại ticket trong `SoVe` đối với TẤT CẢ các màn chơi (kể cả Màn 1 miễn phí với `ve = 0`). Nếu thiếu ticket (`bd is None`), request bị từ chối `HTTP 403 Forbidden` (hoặc `422` nếu là màn có cọc). Tuyệt đối không phát hành voucher mới và không ghi nhận `verified_wallet` nếu ván chưa được đăng ký bắt đầu qua `POST /api/man/bat-dau`.
  - **Chống Voucher Hijacking**: Nếu ván đã đăng ký trong `SoVe`, ví xin phiếu BẮT BUỘC phải khớp chính xác với ví đã đăng ký trong `SoVe`. Bất kỳ ai cố tình xin phiếu cho mã ván thuộc về ví khác đều bị từ chối `HTTP 403 Forbidden`.
  - **Ký lại phiếu cũ**: Chỉ cho phép đúng ví chủ sở hữu ban đầu của phiếu (`HTTP 409 Conflict` nếu ví khác xin lại phiếu cũ). Không tạo bản ghi mới, không cấp thưởng trùng.
  - **Phòng chống giả mạo verified_wallet**: Chỉ cập nhật `match_results.verified_wallet` và `is_verified = 1` khi danh tính ví đã được xác minh tin cậy qua cả phiên SIWE và ticket `SoVe`. Request trôi nổi chưa xác thực tuyệt đối không được ghi nhận `verified_wallet` vào CSDL.
* `GET /api/vang/cho-nhan`: Lấy các phiếu đã ký trong 7 ngày của ví.

### 5.3. Hợp đồng thay đổi với Gameplay Client (`GoldRushGame` sau khi Merge)
Sau khi hợp nhất `feature/map-backend` với `feature/gameplay`:
1. **Bắt buộc gọi `/api/man/bat-dau` cho cả Màn 1**: `GoldRushGame` trước khi bắt đầu màn 1 (luyện tập) cũng phải gửi request tới `POST /api/man/bat-dau` với `man: 1, ve: 0` để nhận hoặc đăng ký `ma_van` được bảo vệ bởi phiên SIWE.
2. **Khởi tạo mã ván an toàn**: Client có thể bỏ trống trường `ma_van` trong payload để server tự sinh mã UUID ngẫu nhiên duy nhất, ngăn ngừa va chạm mã hoặc rò rỉ mã ván trước khi chơi.
3. **Truyền Session & CSRF Token**: Các request mutation (`bat-dau`, `phieu`) từ Game client chạy trên nền Web/Hybrid cần đính kèm cookie `gr_session`, Origin header và header `X-CSRF-Token`.
4. **Nhận phiếu EIP-712**: Sau khi thắng màn và gửi nhật ký telemetry `/api/nhat-ky`, game gọi `POST /api/vang/phieu` với `ma_van` đã đăng ký để nhận phiếu ký EIP-712 sẵn sàng gọi `nhanVang` on-chain.

---

## 6. MAP GENERATOR & LEVEL POOL (NGƯỜI 5)

* **`GET /api/maps/config`**: Thông số cấu hình thuật toán (`v1.3`, 40x30 ô).
* **`GET /api/maps/pool`**: Danh mục toàn bộ file `.tmx` trong pool bản đồ.
* **`GET /api/maps/pool/{ten_tep}`**: Đọc nội dung tệp bản đồ trong pool. Có cơ chế kiểm soát path traversal (nghiêm cấm `..`, `/`, `\`).
* **`GET /api/maps/generate?seed=123&mat_do=0.36&dinh_dang=json`**: Sinh bản đồ theo seed có kiểm định BFS chơi được.

---

## 7. HỢP ĐỒNG TÍCH HỢP VỚI FEATURE/AI
* Nguồn có thẩm quyền cao nhất đối với tiến trình 6 màn chơi và mở khóa nhân vật AI là `DichVuXacMinhTienTrinh` và `KhoTienTrinh` của `feature/ai`.
* Khi hợp nhất hai nhánh:
  1. `api/auth_guard.py` tự động sử dụng `auth_service` của SIWE (xác thực session và CSRF token).
  2. `POST /api/progress/complete-stage` gọi trực tiếp `tien_trinh_verifier.xac_minh_referee_log(player, stage_id, evidence_id)`.
  3. Phân lập thẩm quyền: Map-backend chỉ quản lý mở khóa màn và EXP trong bảng `progress`; `feature/ai` quản lý nhân vật AI (`KhoNhanVat`). Hai bên chia sẻ CSDL chung thống nhất `player_id` với `owner_user_id` và không để hai nguồn cùng tự quyết định mở khóa nhân vật.
  4. Nếu chưa gắn `tien_trinh_verifier`, backend áp dụng Zero-Trust Fail-Closed: chỉ chấp nhận bằng chứng đã được ký phiếu trọng tài (`SoPhieu`) hoặc trận đấu đã xác minh (`is_verified = 1`) có `verified_wallet` khớp ví SIWE. Tuyệt đối không chấp nhận telemetry thô hoặc `player_id` tự khai.
