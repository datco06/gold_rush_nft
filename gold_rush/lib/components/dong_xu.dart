import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../am_thanh/am_thanh.dart';
import '../cau_hinh.dart';
import 'hieu_ung.dart';

/// Đồng xu quay tại chỗ, cộng điểm khi George chạm vào.
///
/// Chú ý cách xử lý lúc bị nhặt: component KHÔNG tự xoá mình ngay trong hàm
/// xử lý va chạm mà đặt cờ `_daNhat` rồi mới gọi `removeFromParent()`.
/// Sửa đổi cây component ngay giữa lúc Flame đang duyệt danh sách va chạm là
/// nguồn gốc của những lỗi rất khó tái hiện.
class DongXu extends SpriteAnimationComponent with CollisionCallbacks {
  bool _daNhat = false;

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
    // Hitbox tròn nhỏ hơn sprite: phải tới gần mới ăn được xu.
    add(CircleHitbox(radius: 5, position: Vector2(3, 3)));
  }

  void nhat() {
    if (_daNhat) return;
    _daNhat = true;

    AmThanh.nhatDongXu();
    parent?.add(HieuUngNhatXu(position.clone()));
    removeFromParent();
  }
}
