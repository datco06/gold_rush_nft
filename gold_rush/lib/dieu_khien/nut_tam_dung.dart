import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

/// Nút tạm dừng vẽ bằng canvas, đặt trong viewport nên luôn nằm yên trên màn hình.
///
/// Một `PositionComponent` chỉ nhận được cú chạm khi nó có `size`, vì
/// `containsLocalPoint` mặc định dựa vào kích thước. Quên đặt size là lý do
/// phổ biến nhất khiến nút "bấm không ăn".
class NutTamDung extends PositionComponent with TapCallbacks {
  final VoidCallback khiBam;

  bool _dangBam = false;

  NutTamDung({required this.khiBam})
      : super(size: Vector2.all(38), priority: 101);

  /// Tự bám vào góc trên bên phải mỗi khi kích thước màn hình đổi.
  ///
  /// Đặt logic vị trí ngay trong component thay vì để game tính hộ: component
  /// nào tự lo được chỗ đứng của nó thì phần còn lại của mã nguồn đỡ rối.
  @override
  void onGameResize(Vector2 kichThuoc) {
    super.onGameResize(kichThuoc);
    position = Vector2(kichThuoc.x - size.x - 14, 14);
  }

  @override
  void onTapDown(TapDownEvent event) {
    _dangBam = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    _dangBam = false;
    khiBam();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _dangBam = false;
  }

  @override
  void render(Canvas canvas) {
    final khung = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRRect(
      RRect.fromRectAndRadius(khung, const Radius.circular(10)),
      Paint()..color = _dangBam ? const Color(0xAA000000) : const Color(0x66000000),
    );

    final son = Paint()..color = const Color(0xFFF2F4F7);
    canvas.drawRect(Rect.fromLTWH(size.x * 0.32, size.y * 0.27, 4, size.y * 0.46), son);
    canvas.drawRect(Rect.fromLTWH(size.x * 0.56, size.y * 0.27, 4, size.y * 0.46), son);
  }
}
