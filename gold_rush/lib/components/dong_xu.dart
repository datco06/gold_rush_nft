
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../am_thanh/am_thanh.dart';
import '../cau_hinh.dart';
import 'hieu_ung.dart';

/// Đồng xu quay tại chỗ, cộng điểm khi George chạm vào.
class DongXu extends SpriteAnimationComponent
    with CollisionCallbacks {
  bool _daNhat = false;

  /// Nam châm kéo xu về phía George.
  void keVe(Vector2 dich, double dt) {
    if (_daNhat) return;

    final den = dich - position;
    final kc = den.length;

    if (kc < 0.5) return;

    position.add(
      den / kc * min(kc, CauHinh.tocDoNamCham * dt),
    );
  }

  DongXu({
    required SpriteAnimation hoatAnh,
    required Vector2 viTri,
  }) : super(
          animation: hoatAnh,
          position: viTri,
          size: Vector2.all(CauHinh.kichThuocO),
          anchor: Anchor.center,
          priority: 1,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Hitbox nhỏ hơn sprite để tăng độ chính xác khi nhặt xu.
    add(
      CircleHitbox(
        radius: 5,
        position: Vector2(3, 3),
      ),
    );
  }

  /// Nhặt đồng xu.
  void nhat() {
    if (_daNhat) return;

    // Đánh dấu trước để tránh nhặt nhiều lần.
    _daNhat = true;

    // Phát âm thanh.
    AmThanh.nhatDongXu();

    // Tạo hiệu ứng nhặt xu.
    parent?.add(
      HieuUngNhatXu(position.clone()),
    );

    // Yêu cầu Flame loại bỏ component khỏi cây.
    removeFromParent();
  }
}
