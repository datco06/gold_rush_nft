import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../chien_dau/sat_thuong.dart';
import 'ban_do.dart';
import 'ke_dich.dart';

class DanBan extends PositionComponent with CollisionCallbacks {
  static const double tocDo = 150;

  final BanDo banDo;
  final Vector2 huong;
  final int satThuong;
  final double tamBay;
  final void Function(CoTheBiDanh) khiHaMucTieu;
  double _daBay = 0;
  bool _xong = false;

  DanBan({
    required this.banDo,
    required Vector2 viTri,
    required Vector2 huong,
    required this.satThuong,
    required this.tamBay,
    required this.khiHaMucTieu,
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
    if (khac is KeDich) {
      _huy();
      if (khac.nhanSatThuong(satThuong)) khiHaMucTieu(khac);
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
      Paint()..color = const Color(0xFFFFE9A8),
    );
  }
}
