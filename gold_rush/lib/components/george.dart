import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import '../am_thanh/am_thanh.dart';
import '../chien_dau/sat_thuong.dart';
import '../chien_dau/quan_ly_trang_bi.dart';
import '../cau_hinh.dart';
import 'ban_do.dart';
import 'dong_xu.dart';
import 'ke_dich.dart';
import 'nhan_vat.dart';
import 'dan_ban.dart';

/// Nhân vật chính.
class George extends NhanVat with KeyboardHandler {
  /// Gọi khi điểm hoặc máu thay đổi.
  final void Function() khiChiSoDoi;

  /// Gọi khi nhân vật chết.
  final void Function() khiChet;

  int diem = 0;
  int mau = CauHinh.mauToiDa;

  final HoiChieu _hoiDanh = HoiChieu(CauHinh.thoiGianHoiDanh);

  final QuanLyTrangBi trangBi = QuanLyTrangBi();

  int soKeDichDaHa = 0;

  void Function(CoTheBiDanh)? khiHaMucTieu;

  double _batTu = 0;

  final Vector2 _huongBanPhim = Vector2.zero();

  final Vector2 huongJoystick = Vector2.zero();

  Vector2? viTriDich;

  double _dongHoBuocChan = 0;

  bool dieuKhienDuoc = false;

  George({
    required super.banDo,
    required super.hoatAnh,
    required super.viTri,
    required this.khiChiSoDoi,
    required this.khiChet,
  });

  bool get conSong => mau > 0;

  bool get dangBatTu => _batTu > 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(hopVaCham());
  }

  // --------------------------------------------------
  // BÀN PHÍM
  // --------------------------------------------------

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (!dieuKhienDuoc) {
      _huongBanPhim.setZero();
      return false;
    }

    if (event is KeyDownEvent) {
      final k = event.logicalKey;

      // Đổi vũ khí bằng Q
      if (k == LogicalKeyboardKey.keyQ) {
        trangBi.doi();
      }

      // Tấn công bằng Space hoặc J
      if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyJ) {
        tanCong();
      }
    }

    final trai =
        keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);

    final phai =
        keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);

    final len =
        keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW);

    final xuong =
        keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS);

    _huongBanPhim
      ..x = (phai ? 1.0 : 0.0) - (trai ? 1.0 : 0.0)
      ..y = (xuong ? 1.0 : 0.0) - (len ? 1.0 : 0.0);

    if (_huongBanPhim.x != 0 || _huongBanPhim.y != 0) {
      viTriDich = null;
    }

    return false;
  }

  // --------------------------------------------------
  // TẤN CÔNG
  // --------------------------------------------------

  bool tanCong() {
    if (!conSong || !dieuKhienDuoc) {
      return false;
    }

    final vk = trangBi.hienTai;

    if (!_hoiDanh.thu(vk.thoiGianHoi)) {
      return false;
    }

    final huong = huongNhin;

    // Tấn công tầm xa
    if (vk.tamXa) {
      parent?.add(
        DanBan(
          banDo: banDo,
          viTri: position + huong * 8,
          huong: huong,
          satThuong: vk.satThuong,
          tamBay: vk.tamDanh,
          khiHaMucTieu: _khiHaMucTieu,
        ),
      );

      return true;
    }

    // Tấn công cận chiến
    final mucTieu =
        parent?.children.whereType<CoTheBiDanh>().toList() ??
        const <CoTheBiDanh>[];

    for (final m in mucTieu) {
      if (trongTamDanh(
            tu: position,
            huong: huong,
            muc: m.viTriDanh,
            tam: vk.tamDanh,
          ) &&
          m.nhanSatThuong(vk.satThuong)) {
        _khiHaMucTieu(m);
      }
    }

    return true;
  }

  // --------------------------------------------------
  // VÒNG LẶP GAME
  // --------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);

    _hoiDanh.troiQua(dt);

    if (!conSong || !dieuKhienDuoc) {
      datDangDi(false);
      return;
    }

    if (_batTu > 0) {
      _batTu -= dt;

      opacity = ((_batTu * 12).floor() % 2 == 0) ? 0.35 : 1.0;

      if (_batTu <= 0) {
        opacity = 1.0;
      }
    }

    final huong = _huongHienTai();

    if (huong.x == 0 && huong.y == 0) {
      datDangDi(false);
      return;
    }

    huong.normalize();

    capNhatHuong(huong);

    final coDi = thuDiChuyen(huong * CauHinh.tocDoGeorge * dt);

    datDangDi(coDi);

    if (coDi) {
      _dongHoBuocChan += dt;

      if (_dongHoBuocChan >= 0.32) {
        _dongHoBuocChan = 0;
        AmThanh.buocChan();
      }
    } else {
      viTriDich = null;
    }
  }

  // --------------------------------------------------
  // ĐIỀU KHIỂN DI CHUYỂN
  // --------------------------------------------------

  Vector2 _huongHienTai() {
    if (_huongBanPhim.x != 0 || _huongBanPhim.y != 0) {
      return _huongBanPhim.clone();
    }

    if (huongJoystick.x != 0 || huongJoystick.y != 0) {
      viTriDich = null;
      return huongJoystick.clone();
    }

    final dich = viTriDich;

    if (dich != null) {
      final den = dich - position;

      if (den.length < 3) {
        viTriDich = null;
        return Vector2.zero();
      }

      return den;
    }

    return Vector2.zero();
  }

  // --------------------------------------------------
  // HƯỚNG NHÌN
  // --------------------------------------------------

  Vector2 get huongNhin => switch (current) {
    HuongDi.trai => Vector2(-1, 0),
    HuongDi.phai => Vector2(1, 0),
    HuongDi.len => Vector2(0, -1),
    _ => Vector2(0, 1),
  };

  // --------------------------------------------------
  // XỬ LÝ MỤC TIÊU BỊ HẠ
  // --------------------------------------------------

  void _khiHaMucTieu(CoTheBiDanh m) {
    soKeDichDaHa++;

    khiHaMucTieu?.call(m);

    khiChiSoDoi();
  }

  // --------------------------------------------------
  // VA CHẠM
  // --------------------------------------------------

  @override
  void onCollisionStart(Set<Vector2> diemGiaoNhau, PositionComponent khac) {
    super.onCollisionStart(diemGiaoNhau, khac);

    if (!conSong) return;

    if (khac is DongXu) {
      khac.nhat();

      diem += CauHinh.diemMoiDongXu;

      khiChiSoDoi();

      return;
    }

    if (khac is KeDich) {
      if (dangBatTu) return;

      khac.noTung();

      _nhanSatThuong();
    }
  }

  // --------------------------------------------------
  // NHẬN SÁT THƯƠNG
  // --------------------------------------------------

  void _nhanSatThuong() {
    mau -= CauHinh.mauMatMoiLanTrung;

    if (mau < 0) {
      mau = 0;
    }

    _batTu = CauHinh.thoiGianBatTu;

    khiChiSoDoi();

    if (mau == 0) {
      opacity = 1.0;

      datDangDi(false);

      khiChet();
    }
  }
}
