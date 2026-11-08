import 'dart:math' show min;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import '../am_thanh/am_thanh.dart';
import '../cau_hinh.dart';
import '../chien_dau/ky_nang.dart';
import '../chien_dau/quan_ly_trang_bi.dart';
import '../chien_dau/sat_thuong.dart';
import '../phat_trien/cap_do.dart';
import 'ban_do.dart';
import 'boss.dart';
import 'dan_ban.dart';
import 'dong_xu.dart';
import 'ke_dich.dart';
import 'nhan_vat.dart';

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
  final BoKyNang kyNang = BoKyNang();
  final Vector2 _huongDash = Vector2.zero();

  /// EXP và cấp độ. Tách riêng khỏi [diem] (điểm chỉ tăng khi nhặt xu).
  final HoSoCapDo capDo = HoSoCapDo();

  /// UI (Người 1) gắn vào đây để hiện thông báo lên cấp.
  void Function(int capMoi)? khiLenCap;

  int soKeDichDaHa = 0;

  /// Người khác (nhật ký, UI) gắn vào đây để biết khi có mục tiêu bị hạ.
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

      // Tấn công: Space hoặc J
      if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyJ) {
        dungKyNang(LoaiKyNang.attack);
      }

      // Đổi vũ khí: Q
      if (k == LogicalKeyboardKey.keyQ) trangBi.doi();

      // Dash: Shift hoặc K
      if (k == LogicalKeyboardKey.shiftLeft ||
          k == LogicalKeyboardKey.shiftRight ||
          k == LogicalKeyboardKey.keyK) {
        dungKyNang(LoaiKyNang.dash);
      }

      // Shield: L
      if (k == LogicalKeyboardKey.keyL) dungKyNang(LoaiKyNang.shield);

      // Magnet: M
      if (k == LogicalKeyboardKey.keyM) dungKyNang(LoaiKyNang.magnet);

      // Nâng cấp Dash bằng điểm kỹ năng: U (để demo)
      if (k == LogicalKeyboardKey.keyU) nangKyNang(LoaiKyNang.dash);
    }

    final trai = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);

    final phai = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);

    final len = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW);

    final xuong = keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
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
  // KỸ NĂNG
  // --------------------------------------------------

  /// Cổng duy nhất cho phím và nút UI (Người 1).
  bool dungKyNang(LoaiKyNang l) {
    if (!conSong || !dieuKhienDuoc) return false;
    switch (l) {
      case LoaiKyNang.attack:
        return tanCong();
      case LoaiKyNang.dash:
        return _dungDash();
      default:
        return kyNang.kich(l);
    }
  }

  bool _dungDash() {
    if (!kyNang.kich(LoaiKyNang.dash)) return false;
    final h = _huongHienTai();
    _huongDash.setFrom((h.x == 0 && h.y == 0) ? huongNhin : h.normalized());
    return true;
  }

  /// Tiêu 1 điểm kỹ năng để nâng cấp một kỹ năng.
  bool nangKyNang(LoaiKyNang l) {
    if (capDo.skillPoints <= 0 || !kyNang.nangCap(l)) return false;
    capDo.skillPoints--;
    return true;
  }

  // --------------------------------------------------
  // EXP
  // --------------------------------------------------

  void _congExp(int exp) {
    final len = capDo.congExp(exp);
    if (len > 0) {
      // Lên cấp thì hồi máu, không tăng máu tối đa (HUD tính tỉ lệ theo mauToiDa).
      mau = min(CauHinh.mauToiDa, mau + 20 * len);
      khiLenCap?.call(capDo.level);
    }
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
    final sat = vk.satThuong + capDo.thuongSatThuong;

    // Tấn công tầm xa
    if (vk.tamXa) {
      parent?.add(
        DanBan(
          banDo: banDo,
          viTri: position + huong * 8,
          huong: huong,
          satThuong: sat,
          tamBay: vk.tamDanh,
          khiHaMucTieu: _khiHaMucTieu,
        ),
      );

      return true;
    }

    // Tấn công cận chiến
    final mucTieu = parent?.children.whereType<CoTheBiDanh>().toList() ??
        const <CoTheBiDanh>[];

    for (final m in mucTieu) {
      if (trongTamDanh(
            tu: position,
            huong: huong,
            muc: m.viTriDanh,
            tam: vk.tamDanh,
          ) &&
          m.nhanSatThuong(sat)) {
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
    kyNang.troiQua(dt);

    if (!conSong || !dieuKhienDuoc) {
      datDangDi(false);
      return;
    }

    // Magnet: kéo xu trong bán kính về phía George.
    if (kyNang.dangDung(LoaiKyNang.magnet)) {
      final xu =
          parent?.children.whereType<DongXu>().toList() ?? const <DongXu>[];
      for (final x in xu) {
        if (x.position.distanceTo(position) <= CauHinh.banKinhNamCham) {
          x.keVe(position, dt);
        }
      }
    }

    if (_batTu > 0) {
      _batTu -= dt;

      opacity = ((_batTu * 12).floor() % 2 == 0) ? 0.35 : 1.0;

      if (_batTu <= 0) {
        opacity = 1.0;
      }
    }

    // Dash: lướt theo hướng đã chốt, thuDiChuyen tự kiểm tra va chạm tường.
    if (kyNang.dangDung(LoaiKyNang.dash)) {
      datDangDi(thuDiChuyen(_huongDash * CauHinh.tocDoDash * dt));
      return;
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
  // VẼ (vòng khiên)
  // --------------------------------------------------

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (kyNang.dangDung(LoaiKyNang.shield)) {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xCC6EC1FF),
      );
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
    _congExp(m is Boss ? CauHinh.expBoss : CauHinh.expMoiKeDich);

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

      nhanSatThuong();
    }
  }

  /// Boss chạm vào George: gây sát thương mỗi khi hết thời gian bất tử.
  /// Dùng onCollision (gọi mỗi khung hình khi đang chạm), không phải onCollisionStart.
  @override
  void onCollision(Set<Vector2> diemGiaoNhau, PositionComponent khac) {
    super.onCollision(diemGiaoNhau, khac);
    if (khac is Boss) nhanSatThuong(CauHinh.satThuongBossCham);
  }

  // --------------------------------------------------
  // NHẬN SÁT THƯƠNG
  // --------------------------------------------------

  /// Công khai để Boss và đạn của Boss gọi được.
  void nhanSatThuong([int luong = CauHinh.mauMatMoiLanTrung]) {
    if (!conSong || dangBatTu) return;

    // Khiên chặn mọi đòn trong lúc đang bật.
    if (kyNang.dangDung(LoaiKyNang.shield)) return;

    mau -= luong;

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