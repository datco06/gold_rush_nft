# TÀI LIỆU KẾT NỐI API & TÍCH HỢP (NGƯỜI 5 – MAP GENERATOR & BACKEND)

Tài liệu này quy chuẩn hóa toàn bộ các API mới được xây dựng bởi Người 5 (Backend & Map Generator), phục vụ cho việc tích hợp đồng bộ giữa **Người 1 (UI)**, **Người 2 (Gameplay)**, **Người 3 (Generative AI)** và **Người 4 (Blockchain)**.

---

## 1. Dành cho Người 1 (UI: World Map, Cửa hàng & Kho đồ)

### 1.1. Lấy tiến trình người chơi (World Map & Cấp độ)
* **Phương thức**: `GET`
* **Endpoint**: `/api/progress`
* **Query Params**:
  * `player_id` (string, bắt buộc): Mã người chơi (ví dụ: `player_001`).
  * `wallet` (string, tùy chọn): Địa chỉ ví nếu người chơi đã kết nối ví (ví dụ: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC`).
  * `ten_hien_thi` (string, tùy chọn): Tên biệt danh hiển thị.
* **Mô tả**: Nếu người chơi chưa có trên hệ thống, Backend sẽ tự động khởi tạo tiến trình ban đầu: Cấp 1, EXP 0, mở sẵn Màn 1 (`unlocked_stage_ids: [1]`), trang bị kiếm gỗ (`kiem_go`) và nhân vật George (`george`).
* **Phản hồi mẫu**:
```json
{
  "player_id": "player_001",
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
  "updated_at": "2026-11-07T00:35:00Z"
}
```
* **UI World Map**: Dựa vào `unlocked_stage_ids` để hiển thị các điểm màn chơi mở/khóa, dựa vào `completed_stage_ids` để hiển thị cờ chiến thắng hoặc số sao.

---

### 1.2. Lấy danh sách kho đồ người chơi
* **Phương thức**: `GET`
* **Endpoint**: `/api/inventory`
* **Query Params**:
  * `player_id` (string, bắt buộc): Mã người chơi.
  * `loai` (string, tùy chọn): Lọc theo loại `weapon`, `character`, `potion`, `material`.
* **Phản hồi mẫu**:
```json
{
  "player_id": "player_001",
  "so_luong_vat_pham": 2,
  "kho_do": [
    {
      "id": 1,
      "player_id": "player_001",
      "item_id": "kiem_go",
      "item_type": "weapon",
      "quantity": 1,
      "metadata": { "ten": "Kiếm gỗ", "sat_thuong": 5 },
      "acquired_at": "2026-11-07T00:35:00Z"
    },
    {
      "id": 2,
      "player_id": "player_001",
      "item_id": "george",
      "item_type": "character",
      "quantity": 1,
      "metadata": { "ten": "George", "toc_do": 74 },
      "acquired_at": "2026-11-07T00:35:00Z"
    }
  ]
}
```

---

### 1.3. Yêu cầu đổi trang bị
* **Phương thức**: `POST`
* **Endpoint**: `/api/equipment/select`
* **Headers**: `Content-Type: application/json`
* **Body**:
```json
{
  "player_id": "player_001",
  "loai": "weapon",
  "item_id": "kiem_go"
}
```
* **Phản hồi thành công (200)**:
```json
{
  "thanh_cong": true,
  "thong_bao": "Đã trang bị weapon 'kiem_go' thành công",
  "equipped_weapon_id": "kiem_go",
  "equipped_character_id": "george"
}
```
* **Lỗi (400)**: Khi người chơi chưa sở hữu `item_id` đó trong kho đồ.

---

## 2. Dành cho Người 2 (Gameplay: Ván chơi & Telemetry)

### 2.1. Gửi nhật ký ván chơi & Tự động mở màn
* **Phương thức**: `POST`
* **Endpoint**: `/api/nhat-ky`
* **Body** (đã bổ sung trường `player_id`):
```json
{
  "ma_van": "van-test-123456",
  "player_id": "player_001",
  "phien_ban_app": "1.3.0",
  "ban_do": "gold_rush.tmx",
  "man": 1,
  "ket_qua": "thang",
  "giay": 45.2,
  "diem": 480,
  "su_kien": [
    { "loai": "nhat_xu", "giay": 10.5, "x": 120.0, "y": 80.0 },
    { "loai": "ket_thuc", "giay": 45.2, "x": 300.0, "y": 200.0 }
  ]
}
```
* **Cơ chế hoạt động**:
  1. Backend chạy bộ kiểm định trọng tài (`trong_tai.kiem_dinh`) trên bản đồ `.tmx`.
  2. Nếu ván hợp lệ và `ket_qua == "thang"`:
     * Tự động ghi nhận `completed_stage_ids` cho màn đó.
     * Tự động mở khóa màn kế tiếp vào `unlocked_stage_ids`.
     * Tự động cộng EXP cho người chơi.
     * Cập nhật tiến độ các nhiệm vụ liên quan (nhặt xu, hoàn thành màn).
  3. Client **không cần và không được phép** gọi API cộng EXP hay mở màn trực tiếp.

---

## 3. Dành cho Người 3 (Generative AI: AI Quests)

### 3.1. Lấy ngữ cảnh người chơi để đưa vào prompt sinh nhiệm vụ
* **Phương thức**: `GET`
* **Endpoint**: `/api/quests/ai-context`
* **Query Params**: `player_id`
* **Phản hồi mẫu**:
```json
{
  "player_id": "player_001",
  "level": 2,
  "unlocked_stage_ids": [1, 2],
  "completed_stage_ids": [1],
  "equipped_weapon": "kiem_go",
  "muc_tieu_hop_le": [
    "hoan_thanh_man",
    "nhat_xu",
    "choi_khong_trung_don",
    "toc_do"
  ],
  "nhiem_vu_gan_day": []
}
```

### 3.2. Gán nhiệm vụ do AI sinh cho người chơi
* **Phương thức**: `POST`
* **Endpoint**: `/api/quests/ai-assign`
* **Body**:
```json
{
  "player_id": "player_001",
  "title": "Thử thách Rừng thưa",
  "description": "Nhặt 15 đồng xu tại Màn 2 mà không được bỏ cuộc",
  "target_type": "nhat_xu",
  "target_count": 15,
  "reward_exp": 80,
  "reward_gold": 5,
  "reward_items": [
    { "item_id": "binh_mau", "item_type": "potion", "quantity": 1 }
  ]
}
```

### 3.3. Lấy danh sách nhiệm vụ đang làm
* **Phương thức**: `GET`
* **Endpoint**: `/api/quests/active`
* **Query Params**: `player_id`

### 3.4. Nhận thưởng nhiệm vụ khi hoàn thành
* **Phương thức**: `POST`
* **Endpoint**: `/api/quests/claim`
* **Body**: `{ "player_id": "player_001", "quest_id": "q_abc123" }`
* **Tác vụ Backend**: Tự động chuyển trạng thái `da_nhan`, cộng EXP vào tiến trình và chuyển vật phẩm vào kho đồ.

---

## 4. Dành cho Người 4 (Blockchain: Đặt cọc & Phiếu vàng)

* Toàn bộ cơ chế EIP-712 và các endpoint gốc **được giữ nguyên vẹn 100%**:
  * `POST /api/man/bat-dau`: Đăng ký ván có cọc `(ma_van, vi, man, ve)`.
  * `POST /api/vang/phieu`: Trọng tài kiểm định và ký phiếu vàng EIP-712.
  * `GET /api/vang/cho-nhan`: Lấy các phiếu vàng đang chờ nhận của ví.
  * `GET /api/vang/cau-hinh`: Lấy chainId, địa chỉ hợp đồng và địa chỉ trọng tài.
* Khi người chơi đăng nhập bằng ví, gọi `GET /api/progress?player_id=...&wallet=0x...` để liên kết danh tính ví với tiến trình trong database.

---

## 5. Map Generator (Sinh bản đồ & Level Maps)

* **`GET /api/maps/config`**: Trả về phiên bản thuật toán (`v1.3`), kích thước chuẩn (40x30 ô, 16px/ô) và thư mục assets.
* **`GET /api/maps/pool`**: Trả về danh sách và trạng thái kiểm định của toàn bộ file `.tmx` đóng gói sẵn trong `assets/tiles/`.
* **`GET /api/maps/generate?seed=7&mat_do=0.36&dinh_dang=json`**: Sinh bản đồ theo seed và trả về JSON chỉ số (đường đi trung bình, kẻ địch gần nhất) hoặc XML TMX (`dinh_dang=tmx`).

