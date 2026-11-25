import 'package:flutter/widgets.dart';

/// Bố cục chung cho joystick Flame và nút Bắn Flutter.
class BoCucDieuKhien {
  const BoCucDieuKhien(this.khung, this.leAnToan);

  final Size khung;
  final EdgeInsets leAnToan;

  bool get gon => khung.width < 600 || khung.height < 420;
  double get kichThuoc => gon ? 78 : 92;

  double get _leNgang =>
      (khung.width * .085 - kichThuoc / 2).clamp(24.0, 120.0);

  double get trai => leAnToan.left + _leNgang;
  double get phai => leAnToan.right + _leNgang;
  double get duoi =>
      leAnToan.bottom + (khung.height * .23 - kichThuoc / 2).clamp(32.0, 150.0);
}
