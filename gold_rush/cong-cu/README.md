# Công cụ sinh tài nguyên

`sinh_tai_nguyen.py` sinh toàn bộ ảnh, âm thanh và bản đồ của game bằng mã
nguồn — không sao chép từ bất kỳ kho tài nguyên nào, nên dùng lại tự do trong
tài liệu và bài giảng của học phần.

## Chạy

```bash
pip install pillow
python3 cong-cu/sinh_tai_nguyen.py
```

Script ghi đè thẳng vào `assets/`. Chạy lại bao nhiêu lần cũng ra kết quả
giống hệt nhau vì đã cố định `random.seed`.

## Sửa gì ở đâu

| Muốn đổi | Sửa hàm / biến |
|---|---|
| Bảng màu toàn bộ đồ hoạ | `P` ở đầu tệp |
| Hình dáng ô địa hình | `ve_tileset()` |
| Dáng nhân vật, kiểu đi | `ve_nhan_vat()` |
| Số khung xoay của đồng xu | `ve_dong_xu()` |
| Bố cục bản đồ, số quái, số xu | `dung_ban_do()` |
| Giai điệu nhạc nền | `nhac_nen()` — mảng `giai_dieu` là các nửa cung |
| Kích thước bản đồ | `COT`, `HANG` ở đầu tệp |

## Vì sao sinh bằng mã nguồn thay vì vẽ tay

1. **Bản quyền sạch.** Không phụ thuộc tài nguyên của bên thứ ba.
2. **Tái lập được.** Xoá nhầm thư mục `assets/` thì chạy một lệnh là có lại.
3. **Dễ thử nghiệm.** Đổi một dòng trong `dung_ban_do()` là có bản đồ khác
   ngay, nhanh hơn ngồi vẽ lại trong Tiled.
4. **Dạy được.** Sinh viên thấy rõ sprite sheet chỉ là một lưới ô 16×16, và
   bản đồ .tmx chỉ là XML chứa ba mảng số.

Sau khi hiểu cấu trúc rồi thì mở `assets/tiles/gold_rush.tmx` bằng phần mềm
**Tiled** để vẽ bằng chuột cho nhanh — hai cách dùng lẫn nhau được.
