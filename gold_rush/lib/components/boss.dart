import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../cau_hinh.dart';
import '../chien_dau/sat_thuong.dart';
import 'dan_ban.dart';
import 'hieu_ung.dart';
import 'nhan_vat.dart';

enum PhaseBoss { mot, hai, ba }

/// Hàm thuần, chỉ nhìn HP. Dùng số nguyên để không dính sai số ở đúng ngưỡng 50% và 20%.
PhaseBoss xacDinhPhase(int hp, int hpToiDa) {
  if (hpToiDa <= 0 || hp <= 0) return PhaseBoss.ba;
  if (hp * 100 > hpToiDa * 50) return PhaseBoss.mot;
  if (hp * 100 > hpToiDa * 20) return PhaseBoss.hai;
  return PhaseBoss.ba;
}

class Boss extends NhanVat implements CoTheBiDanh {
  final Vector2 Function() viTriNguoiChoi;

  /// Gây sát thương lên người chơi (gắn vào George.nhanSatThuong).
  final void Function(int) gayDame;
  void Function(Boss)? khiChet;
  void Function(PhaseBoss)? khiDoiPhase;

  final SucKhoe sucKhoe = SucKhoe(CauHinh.mauBoss);
  PhaseBoss _phase = PhaseBoss.mot;
  double _hoiBan = CauHinh.hoiBanBoss;
  double _hoiDienRong = CauHinh.hoiChieuDienRong;
  double _gongChieu = 0;
  bool _daChet = false;

  Boss({
    required super.banDo,
    required super.hoatAnh,
    required super.viTri,
    required this.viTriNguoiChoi,
    required this.gayDame,
    this.khiChet,
  });

  PhaseBoss get phase => _phase;

  @override
  Vector2 get viTriDanh => position;

  double get _heSoTocDo => switch (_phase) {
        PhaseBoss.mot => 1.0,
        PhaseBoss.hai => 1.5,
        PhaseBoss.ba => 1.2,
      };

  @override
  Future<void> onLoad() async {
    size = Vector2.all(24);
    add(RectangleHitbox(size: Vector2(18, 20), position: Vector2(3, 3)));
  }

  @override
  bool nhanSatThuong(int luong) {
    if (_daChet) return false;
    sucKhoe.nhan(luong);
    if (sucKhoe.conSong) return false;
    _daChet = true;
    parent?.add(HieuUngNoKeDich(position.clone(), const Color(0xFFFFD84D)));
    khiChet?.call(this);
    removeFromParent();
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_daChet) return;

    final phaseMoi = xacDinhPhase(sucKhoe.hien, sucKhoe.toiDa);
    if (phaseMoi != _phase) _vaoPhase(phaseMoi);

    // Đang gồng chiêu: đứng yên, hết gồng thì đánh.
    if (_gongChieu > 0) {
      datDangDi(false);
      _gongChieu -= dt;
      if (_gongChieu <= 0) _tungChieuDienRong();
      return;
    }

    final den = viTriNguoiChoi() - position;
    if (den.length > 14) {
      final huong = den.normalized();
      capNhatHuong(huong);
      datDangDi(
        thuDiChuyen(huong * CauHinh.tocDoBoss * _heSoTocDo * dt),
      );
    } else {
      datDangDi(false);
    }

    if (_phase != PhaseBoss.mot) {
      _hoiBan -= dt;
      if (_hoiBan <= 0) {
        _hoiBan = CauHinh.hoiBanBoss;
        _ban(den);
      }
    }

    if (_phase == PhaseBoss.ba) {
      _hoiDienRong -= dt;
      if (_hoiDienRong <= 0) {
        _hoiDienRong = CauHinh.hoiChieuDienRong;
        _gongChieu = 1.0;
      }
    }
  }

  void _vaoPhase(PhaseBoss p) {
    _phase = p;
    _hoiBan = 0.5;
    if (p == PhaseBoss.ba) _hoiDienRong = 1.5;
    parent?.add(HieuUngNoKeDich(position.clone(), const Color(0xFFFF5A3C)));
    khiDoiPhase?.call(p);
  }

  void _ban(Vector2 huong) {
    parent?.add(DanBan(
      banDo: banDo,
      viTri: position.clone(),
      huong: huong,
      satThuong: CauHinh.satThuongDanBoss,
      tamBay: 140,
      tuKeDich: true,
      gayDameNguoiChoi: gayDame,
    ));
  }

  void _tungChieuDienRong() {
    parent?.add(HieuUngNoKeDich(position.clone(), const Color(0xFFFF5A3C)));
    if (position.distanceTo(viTriNguoiChoi()) <= CauHinh.banKinhDienRong) {
      gayDame(CauHinh.satThuongDienRong);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Thanh máu nhỏ trên đầu Boss (không đụng vào HUD của Người 1).
    canvas.drawRect(
      Rect.fromLTWH(0, -5, size.x, 3),
      Paint()..color = const Color(0x88000000),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, -5, size.x * sucKhoe.tiLe, 3),
      Paint()..color = const Color(0xFFDC4A3D),
    );
    // Vòng báo trước chiêu diện rộng.
    if (_gongChieu > 0) {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        CauHinh.banKinhDienRong,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xAAFF5A3C),
      );
    }
  }
}