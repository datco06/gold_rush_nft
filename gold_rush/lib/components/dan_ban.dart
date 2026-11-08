import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../chien_dau/sat_thuong.dart';
import 'ban_do.dart';
import 'boss.dart';
import 'george.dart';
import 'ke_dich.dart';

class DanBan extends PositionComponent with CollisionCallbacks {
  static const double tocDo = 150;

  final BanDo banDo;
  final Vector2 huong;
  final int satThuong;
  final double tamBay;

  /// true = đạn của Boss (trúng George); false = mũi tên của người chơi.
  final bool tuKeDich;

  /// Đạn của Boss gọi hàm này khi trúng George (gắn vào George.nhanSatThuong).
  final void Function(int)? gayDameNguoiChoi;

  /// Mũi tên của người chơi gọi hàm này khi hạ được mục tiêu.
  final void Function(CoTheBiDanh)? khiHaMucTieu;

  double _daBay = 0;
  bool _xong = false;

  DanBan({
    required this.banDo,
    required Vector2 viTri,
    required Vector2 huong,
    required this.satThuong,
    required this.tamBay,
    this.khiHaMucTieu,
    this.tuKeDich = false,
    this.gayDameNguoiChoi,
  }) : huong = huong.normalized(),
       super(
         position: viTri,
         size: Vector2.all(4),
         anchor: Anchor.center,
         priority: 3,
       );

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(radius: 2));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_xong) return;
    final buoc = huong * tocDo * dt;
    position.add(buoc);
    _daBay += buoc.length;
    if (_daBay >= tamBay || !banDo.diDuoc(position, Vector2.all(2))) _huy();
  }

  @override
  void onCollisionStart(Set<Vector2> diem, PositionComponent khac) {
    super.onCollisionStart(diem, khac);
    if (_xong) return;

    // Đạn của Boss: chỉ quan tâm George, bỏ qua mọi thứ khác (kể cả Boss).
    if (tuKeDich) {
      if (khac is George) {
        _huy();
        gayDameNguoiChoi?.call(satThuong);
      }
      return;
    }

    // Mũi tên của người chơi: trúng quái hoặc Boss.
    if (khac is KeDich || khac is Boss) {
      _huy();
      final m = khac as CoTheBiDanh;
      if (m.nhanSatThuong(satThuong)) khiHaMucTieu?.call(m);
    }
  }

  void _huy() {
    if (_xong) return;
    _xong = true;
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(
      const Offset(2, 2),
      2,
      Paint()
        ..color = tuKeDich ? const Color(0xFFFF5A3C) : const Color(0xFFFFE9A8),
    );
  }
}