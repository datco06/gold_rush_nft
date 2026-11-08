import 'dart:math';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../cau_hinh.dart';

enum LoaiVatPham { binhMau, cucExp }

class PhanThuong {
  final LoaiVatPham loai;
  final int giaTri;
  const PhanThuong(this.loai, this.giaTri);
}

/// Bảng quy tắc rơi. Hàm thuần, truyền Random để kiểm thử.
class BangRoi {
  static List<PhanThuong> chon(
    Random rnd, {
    bool laBoss = false,
    double tiLeExp = CauHinh.tiLeRoiExp,
    double tiLeMau = CauHinh.tiLeRoiBinhMau,
  }) {
    if (laBoss) {
      return const [
        PhanThuong(LoaiVatPham.cucExp, 50),
        PhanThuong(LoaiVatPham.binhMau, 50),
      ];
    }
    return [
      if (rnd.nextDouble() < tiLeExp)
        const PhanThuong(LoaiVatPham.cucExp, 15),
      if (rnd.nextDouble() < tiLeMau)
        const PhanThuong(LoaiVatPham.binhMau, 20),
    ];
  }
}

class VatPhamRoi extends PositionComponent with CollisionCallbacks {
  final PhanThuong phanThuong;
  double _song = CauHinh.thoiGianTonTaiVatPham;
  bool _daNhat = false;

  VatPhamRoi({required this.phanThuong, required Vector2 viTri})
      : super(
          position: viTri,
          size: Vector2.all(8),
          anchor: Anchor.center,
          priority: 1,
        );

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(radius: 4));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _song -= dt;
    if (_song <= 0) removeFromParent();
  }

  /// Nhặt. true nếu lần gọi này là lần nhặt thật sự (giống DongXu.nhat).
  bool nhat() {
    if (_daNhat) return false;
    _daNhat = true;
    removeFromParent();
    return true;
  }

  @override
  void render(Canvas canvas) {
    // Nhấp nháy trong 3 giây cuối để báo sắp biến mất.
    if (_song < 3 && (_song * 8).floor() % 2 == 0) return;
    final mau = phanThuong.loai == LoaiVatPham.binhMau
        ? const Color(0xFFE0453A)
        : const Color(0xFF6EC1FF);
    canvas.drawCircle(const Offset(4, 4), 3.5, Paint()..color = mau);
  }
}