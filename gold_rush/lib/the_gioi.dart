import 'package:flame/components.dart';
import 'package:flame/events.dart';

/// Thế giới trò chơi: nơi chứa bản đồ, George, đồng xu và kẻ địch.
///
/// Vì sao phải tạo lớp riêng thay vì dùng `World` mặc định: để bắt được sự
/// kiện chạm màn hình NGAY TRONG hệ toạ độ của thế giới.
///
/// `World` của Flame trả về true cho mọi điểm trong `containsLocalPoint`, nên
/// khi trộn thêm `TapCallbacks`, mọi cú chạm đều rơi vào đây và
/// `event.localPosition` chính là toạ độ thế giới — đã được camera quy đổi sẵn.
/// Không cần tự nhân ma trận biến đổi nào cả.
///
/// Đây là điểm khác lớn so với sách năm 2022: hồi đó dùng `HasTappables` trên
/// game rồi tự cộng trừ theo vị trí camera. Cách mới vừa ngắn vừa không sai số.
class TheGioi extends World with TapCallbacks {
  /// Gọi khi người chơi chạm vào bản đồ, kèm toạ độ thế giới.
  void Function(Vector2 viTri)? khiChamVaoBanDo;

  /// Tạm khoá chạm khi đang mở menu hoặc game đã kết thúc.
  bool nhanCham = false;

  @override
  void onTapDown(TapDownEvent event) {
    if (!nhanCham) return;
    khiChamVaoBanDo?.call(event.localPosition.clone());
  }
}
