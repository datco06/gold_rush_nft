import 'sat_thuong.dart';

enum LoaiKyNang { dash, shield, attack, magnet }

enum TrangThaiKyNang { san, dangDung, hoi }

class KyNang {
  final String ma;
  final LoaiKyNang loai;
  final double thoiGianHoi;
  final double thoiGianHieuLuc;

  const KyNang(this.ma, this.loai, this.thoiGianHoi, this.thoiGianHieuLuc);

  static const dash = KyNang('skill_dash', LoaiKyNang.dash, 2.0, 0.15);
  static const shield = KyNang('skill_shield', LoaiKyNang.shield, 6.0, 1.5);
  static const attack = KyNang('skill_attack', LoaiKyNang.attack, 0.0, 0.0);
  static const magnet = KyNang('skill_magnet', LoaiKyNang.magnet, 12.0, 5.0);
  static const tatCa = [dash, shield, attack, magnet];
}

class BoKyNang {
  static const int capToiDa = 3;

  final Map<LoaiKyNang, int> cap = {
    for (final k in KyNang.tatCa) k.loai: 1,
  };
  final Map<LoaiKyNang, HoiChieu> _hoi = {
    for (final k in KyNang.tatCa) k.loai: HoiChieu(k.thoiGianHoi),
  };
  final Map<LoaiKyNang, double> _hieuLuc = {};

  KyNang _lay(LoaiKyNang l) => KyNang.tatCa.firstWhere((k) => k.loai == l);

  bool dangDung(LoaiKyNang l) => (_hieuLuc[l] ?? 0) > 0;

  /// Phần trăm thời gian hồi còn lại (1 = vừa dùng, 0 = sẵn sàng) — cho UI.
  double tiLeHoi(LoaiKyNang l) => _hoi[l]!.tiLeConLai;

  TrangThaiKyNang trangThai(LoaiKyNang l) {
    if (dangDung(l)) return TrangThaiKyNang.dangDung;
    return _hoi[l]!.san ? TrangThaiKyNang.san : TrangThaiKyNang.hoi;
  }

  /// Thử kích hoạt. false nếu đang hồi.
  bool kich(LoaiKyNang l) {
    if (!_hoi[l]!.thu()) return false;
    final k = _lay(l);
    if (k.thoiGianHieuLuc > 0) {
      _hieuLuc[l] = k.thoiGianHieuLuc * (1 + 0.25 * (cap[l]! - 1));
    }
    return true;
  }

  bool nangCap(LoaiKyNang l) {
    if (cap[l]! >= capToiDa) return false;
    cap[l] = cap[l]! + 1;
    return true;
  }

  void troiQua(double dt) {
    for (final h in _hoi.values) {
      h.troiQua(dt);
    }
    for (final l in _hieuLuc.keys.toList()) {
      final con = _hieuLuc[l]! - dt;
      if (con <= 0) {
        _hieuLuc.remove(l);
      } else {
        _hieuLuc[l] = con;
      }
    }
  }
}