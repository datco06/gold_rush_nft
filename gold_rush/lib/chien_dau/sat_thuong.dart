import 'dart:math';

import 'package:flame/components.dart';

/// Mục tiêu người chơi đánh được (KeDich, Boss).
abstract interface class CoTheBiDanh {
  Vector2 get viTriDanh;

  /// true nếu đòn này hạ gục mục tiêu.
  bool nhanSatThuong(int luong);
}

/// Máu dùng chung. Không bao giờ nhỏ hơn 0 hay lớn hơn tối đa.
class SucKhoe {
  final int toiDa;
  int _hien;

  SucKhoe(this.toiDa, [int? hien])
    : _hien = (hien ?? toiDa).clamp(0, toiDa).toInt();

  int get hien => _hien;
  bool get conSong => _hien > 0;
  double get tiLe => toiDa == 0 ? 0.0 : _hien / toiDa;

  /// Trả về lượng máu thật sự mất.
  int nhan(int satThuong) {
    if (satThuong <= 0) return 0;
    final mat = min(satThuong, _hien);
    _hien -= mat;
    return mat;
  }

  int hoi(int luong) {
    if (luong <= 0) return 0;
    final them = min(luong, toiDa - _hien);
    _hien += them;
    return them;
  }
}

/// Thời gian hồi chiêu.
class HoiChieu {
  final double thoiGian;
  double _con = 0;
  double _tong;

  HoiChieu(this.thoiGian) : _tong = thoiGian;

  bool get san => _con <= 0;
  double get conLai => _con;
  double get tiLeConLai =>
      _tong <= 0 ? 0.0 : (_con / _tong).clamp(0.0, 1.0).toDouble();

  /// Dùng chiêu. false nếu đang hồi.
  bool thu([double? thoiGianRieng]) {
    if (!san) return false;
    _tong = thoiGianRieng ?? thoiGian;
    _con = _tong;
    return true;
  }

  void troiQua(double dt) {
    if (_con > 0) _con = max(0.0, _con - dt);
  }
}

/// Điểm [muc] có nằm trong hình quạt phía trước [tu] không?
bool trongTamDanh({
  required Vector2 tu,
  required Vector2 huong,
  required Vector2 muc,
  required double tam,
  double gocNua = pi / 3,
}) {
  final den = muc - tu;
  final kc = den.length;
  if (kc > tam) return false;
  if (kc < 0.001) return true;
  final cosGoc = den.dot(huong) / (kc * huong.length);
  return cosGoc >= cos(gocNua);
}
