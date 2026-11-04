import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../cau_hinh.dart';
import 'ban_do.dart';
import 'hieu_ung.dart';

/// Lớp nền cho mọi nhân vật đi bộ trên bản đồ: George, zombie và skeleton.
///
/// Gom vào đây ba việc mà cả ba loại đều cần:
///   1. Chọn đúng hoạt ảnh theo hướng đang đi.
///   2. Trượt dọc theo tường thay vì dính cứng khi đâm vào vật cản.
///   3. Dừng hoạt ảnh lại khi đứng yên.
abstract class NhanVat extends SpriteAnimationGroupComponent<HuongDi>
    with CollisionCallbacks {
  final BanDo banDo;

  /// Hộp dùng để kiểm tra va chạm với ĐỊA HÌNH (khác với hitbox va chạm giữa
  /// các nhân vật do Flame quản lý).
  static final Vector2 hopChan =
      Vector2(CauHinh.rongHopChan, CauHinh.caoHopChan);

  NhanVat({
    required this.banDo,
    required Map<HuongDi, SpriteAnimation> hoatAnh,
    required Vector2 viTri,
    super.priority = 2,
  }) : super(
          animations: hoatAnh,
          current: HuongDi.xuong,
          position: viTri,
          size: Vector2.all(CauHinh.kichThuocO),
          anchor: Anchor.center,
        );

  /// Vẽ bóng TRƯỚC khi vẽ sprite.
  ///
  /// Đây là lý do phải ghi đè render ở lớp nền thay vì gắn một component con:
  /// Flame vẽ cha trước rồi mới vẽ con, nên một component bóng làm con sẽ nằm
  /// đè lên chính nhân vật.
  @override
  void render(Canvas canvas) {
    Bong.ve(canvas);
    super.render(canvas);
  }

  /// Tâm của hộp chân, lệch xuống dưới so với tâm sprite.
  ///
  /// Nhân vật cao 16 pixel nhưng chỉ "đứng" bằng phần chân, nên vùng va chạm
  /// với địa hình phải nằm ở dưới. Nhờ vậy nhân vật đi lấn được vào tán cây
  /// phía trên mà nhìn vẫn tự nhiên.
  Vector2 get tamChan => Vector2(position.x, position.y + 4);

  /// Thử dời nhân vật đi `delta`. Tách riêng hai trục để nhân vật trượt dọc
  /// theo tường thay vì đứng chết một chỗ khi đi chéo vào góc.
  ///
  /// Trả về true nếu có dịch chuyển thật sự (dùng để biết nên chạy hoạt ảnh
  /// hay đứng yên).
  bool thuDiChuyen(Vector2 delta) {
    var coDi = false;

    if (delta.x != 0) {
      final thu = Vector2(position.x + delta.x, position.y + 4);
      if (banDo.diDuoc(thu, hopChan)) {
        position.x += delta.x;
        coDi = true;
      }
    }

    if (delta.y != 0) {
      final thu = Vector2(position.x, position.y + delta.y + 4);
      if (banDo.diDuoc(thu, hopChan)) {
        position.y += delta.y;
        coDi = true;
      }
    }

    return coDi;
  }

  /// Chọn hoạt ảnh theo vector hướng. Trục nào lớn hơn thì thắng, để nhân vật
  /// đi chéo vẫn quay mặt về một hướng dứt khoát chứ không rung qua lại.
  void capNhatHuong(Vector2 huong) {
    if (huong.x == 0 && huong.y == 0) return;
    if (huong.x.abs() > huong.y.abs()) {
      current = huong.x > 0 ? HuongDi.phai : HuongDi.trai;
    } else {
      current = huong.y > 0 ? HuongDi.xuong : HuongDi.len;
    }
  }

  /// Bật/tắt chạy hoạt ảnh. Đứng yên mà chân vẫn bước trông rất kỳ.
  void datDangDi(bool dangDi) {
    if (playing != dangDi) playing = dangDi;
  }

  /// Hitbox dùng cho va chạm GIỮA CÁC NHÂN VẬT (George ↔ quái, George ↔ xu).
  /// Nhỏ hơn sprite một chút để chạm nhau mới tính là trúng.
  RectangleHitbox hopVaCham() => RectangleHitbox(
        size: Vector2(10, 12),
        position: Vector2(3, 3),
      );
}
