import 'dart:math' show Random, min;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import '../am_thanh/am_thanh.dart';
import '../cau_hinh.dart';
import '../chien_dau/ki_nang.dart';
import '../chien_dau/quan_ly_trang_bi.dart';
import '../chien_dau/sat_thuong.dart';
import '../phat_trien/cap_do.dart';
import 'boss.dart';
import 'dan_ban.dart';
import 'dong_xu.dart';
import 'ke_dich.dart';
import 'nhan_vat.dart';
import 'trang_bi_george.dart';
import 'vat_pham_roi.dart';

/// Nhân vật chính.
class George extends NhanVat with KeyboardHandler {
  /// Gọi khi điểm hoặc máu thay đổi.
  final void Function() khiChiSoDoi;

  /// Gọi khi nhân vật chết.
  final void Function() khiChet;
  Map<HuongDi, SpriteAnimation> trangBiVuKhi;
  Map<HuongDi, SpriteAnimation> trangBiGiap;
  Map<HuongDi, SpriteAnimation> trangBiGiay;
  // George có thể nhận update ngay khi component vừa được gắn vào cây Flame,
  // trước khi onLoad() hoàn tất. Vì vậy lớp trang bị phải là tuỳ chọn trong
  // giai đoạn khởi tạo; movement/animation không được làm hỏng game chỉ vì
  // lớp vẽ phụ chưa sẵn sàng.
  TrangBiGeorge? _lopTrangBi;

  int diem = 0;
  int mau = CauHinh.mauToiDa;
  int _mauToiDaTrangBi = CauHinh.mauToiDa;
  int _satThuongBan = 0;
  double _tamBan = 0;
  bool _xuyenPha = false;
  double _giamSatThuong = 0;
  double _heSoTocDoTrangBi = 1.0;

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

  final Random _rnd = Random();

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
    this.trangBiVuKhi = const {},
    this.trangBiGiap = const {},
    this.trangBiGiay = const {},
  });

  bool get conSong => mau > 0;

  bool get dangBatTu => _batTu > 0;

  int get mauToiDaHienTai => _mauToiDaTrangBi;

  void datChiSoTrangBi({
    int satThuong = 0,
    double tamBan = 0,
    int hpCongThem = 0,
    double giamSatThuong = 0,
    double tocDoCongThem = 0,
    bool xuyenPha = false,
  }) {
    final maxCu = _mauToiDaTrangBi;
    _mauToiDaTrangBi = CauHinh.mauToiDa + hpCongThem;
    _satThuongBan = satThuong;
    _tamBan = tamBan;
    _xuyenPha = xuyenPha;
    _giamSatThuong = giamSatThuong.clamp(0.0, 1.0);
    _heSoTocDoTrangBi = 1.0 + tocDoCongThem;
    mau = (mau + (_mauToiDaTrangBi - maxCu)).clamp(0, _mauToiDaTrangBi).toInt();
  }

  void capNhatTrangBiHienThi({
    Map<HuongDi, SpriteAnimation>? vuKhi,
    Map<HuongDi, SpriteAnimation>? giap,
    Map<HuongDi, SpriteAnimation>? giay,
  }) {
    if (vuKhi != null) trangBiVuKhi = vuKhi;
    if (giap != null) trangBiGiap = giap;
    if (giay != null) trangBiGiay = giay;
    _lopTrangBi?.capNhatTrangBi(
      vuKhi: vuKhi ?? trangBiVuKhi,
      giap: giap ?? trangBiGiap,
      giay: giay ?? trangBiGiay,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(hopVaCham());
    final lopTrangBi = TrangBiGeorge(
      vuKhi: trangBiVuKhi.isEmpty ? null : trangBiVuKhi,
      giap: trangBiGiap.isEmpty ? null : trangBiGiap,
      giay: trangBiGiay.isEmpty ? null : trangBiGiay,
    );
    _lopTrangBi = lopTrangBi;
    add(lopTrangBi);
  }

  @override
  void capNhatHuong(Vector2 huong) {
    super.capNhatHuong(huong);
    _lopTrangBi?.capNhatHuong(current ?? HuongDi.xuong);
  }

  @override
  void datDangDi(bool dangDi) {
    super.datDangDi(dangDi);
    _lopTrangBi?.datDangDi(dangDi);
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
      final mucTieuGan = _timMucTieuApSat(huong);
      if (mucTieuGan != null) {
        if (mucTieuGan.nhanSatThuong(sat)) {
          _khiHaMucTieu(mucTieuGan);
        }
        if (!_xuyenPha) {
          return true;
        }
      }

      parent?.add(
        DanBan(
          banDo: banDo,
          viTri: _viTriDauDan(huong),
          huong: huong,
          satThuong: sat,
          tamBay: vk.tamDanh,
          xuyenPha: _xuyenPha,
          khiHaMucTieu: _khiHaMucTieu,
          mucTieuDaTrung: mucTieuGan != null ? {mucTieuGan} : null,
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
          m.nhanSatThuong(sat)) {
        _khiHaMucTieu(m);
      }
    }

    return true;
  }

  /// Bắn một viên đạn theo đúng hướng đang nhìn.
  ///
  /// Đây là lối vào riêng cho nút BẮN: mỗi lần gọi chỉ tạo một [DanBan],
  /// không dùng hồi chiêu nên các lần chạm liên tiếp tạo các viên đạn riêng.
  bool banTheoHuongNhin() {
    if (!conSong || !dieuKhienDuoc) return false;

    // Chỉ súng đã trang bị mới được tạo đạn. Khi không có súng,
    // _tamBan được giữ ở 0 trong lúc áp dụng trang bị.
    if (_tamBan <= 0) return false;

    final cha = parent;
    if (cha == null) return false;

    final huong = huongNhin;
    _lopTrangBi?.phatBan();

    final sat =
        (_satThuongBan > 0 ? _satThuongBan : CauHinh.satThuongGoc) +
        capDo.thuongSatThuong;

    final mucTieuGan = _timMucTieuApSat(huong);
    if (mucTieuGan != null) {
      if (mucTieuGan.nhanSatThuong(sat)) {
        _khiHaMucTieu(mucTieuGan);
      }
      if (!_xuyenPha) {
        return true;
      }
    }

    cha.add(
      DanBan(
        banDo: banDo,
        viTri: _viTriDauDan(huong),
        huong: huong,
        satThuong: sat,
        tamBay: _tamBan > 0
            ? _tamBan * CauHinh.kichThuocO
            : CauHinh.kichThuocO * 4,
        xuyenPha: _xuyenPha,
        khiHaMucTieu: _khiHaMucTieu,
        mucTieuDaTrung: mucTieuGan != null ? {mucTieuGan} : null,
      ),
    );
    return true;
  }

  /// Tính vị trí đầu đạn bắn ra, giữ đạn trên cao độ vũ khí (y + 2) và không bị cấn vào mép khi đứng sát 4 cạnh.
  Vector2 _viTriDauDan(Vector2 huong) {
    final goc = Vector2(position.x, position.y + 2);
    var viTri = goc + huong * 6;

    if (banDo.luoi.biChanTaiDiem(viTri.x, viTri.y) &&
        !banDo.luoi.biChanTaiDiem(goc.x, goc.y)) {
      viTri = goc + huong * 2;
    }
    return viTri;
  }

  /// Tìm mục tiêu (quái hoặc Boss) đang áp sát phía trước và thẳng hàng với mặt nhìn của George.
  CoTheBiDanh? _timMucTieuApSat(Vector2 huong) {
    final cha = parent;
    if (cha == null) return null;

    final danhSach = cha.children.whereType<CoTheBiDanh>().toList();
    CoTheBiDanh? mucTieuGanNhat;
    double khoangCachNhoNhat = double.infinity;

    for (final m in danhSach) {
      if (m is KeDich && m.isDead) continue;
      if (m is Boss && m.daChet) continue;

      final delta = m.viTriDanh - position;
      final dDoc = delta.dot(huong);
      final dNgang = (delta - huong * dDoc).length;

      // Áp sát (dọc từ -4 đến 1.5 ô = 24px) và thẳng hàng với mặt nhìn:
      final oPhiaTruoc = dDoc >= -4 && dDoc <= CauHinh.kichThuocO * 1.5;
      final thangHang = dDoc >= 0
          ? (dNgang <= 10 && (dDoc >= 4 || dDoc >= dNgang))
          : (dNgang <= 6);

      if (oPhiaTruoc && thangHang) {
        if (dDoc < khoangCachNhoNhat) {
          khoangCachNhoNhat = dDoc;
          mucTieuGanNhat = m;
        }
      }
    }
    return mucTieuGanNhat;
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

    final coDi = thuDiChuyen(
      huong * CauHinh.tocDoGeorge * _heSoTocDoTrangBi * dt,
    );

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
  // XỬ LÝ MỤC TIÊU BỊ HẠ, VẬT PHẨM RƠI
  // --------------------------------------------------

  final Set<CoTheBiDanh> _mucTieuDaTinhHa = {};

  void _khiHaMucTieu(CoTheBiDanh m) {
    if (!_mucTieuDaTinhHa.add(m)) return;
    soKeDichDaHa++;
    _congExp(m is Boss ? CauHinh.expBoss : CauHinh.expMoiKeDich);

    // Rơi vật phẩm theo bảng quy tắc. Không phải DongXu nên không đụng tới điều kiện thắng.
    for (final p in BangRoi.chon(_rnd, laBoss: m is Boss)) {
      parent?.add(
        VatPhamRoi(
          phanThuong: p,
          viTri:
              m.viTriDanh +
              Vector2(_rnd.nextDouble() * 8 - 4, _rnd.nextDouble() * 8 - 4),
        ),
      );
    }

    khiHaMucTieu?.call(m);

    khiChiSoDoi();
  }

  void _nhanPhanThuong(PhanThuong p) {
    switch (p.loai) {
      case LoaiVatPham.binhMau:
        mau = min(CauHinh.mauToiDa, mau + p.giaTri);
      case LoaiVatPham.cucExp:
        _congExp(p.giaTri);
    }
    khiChiSoDoi();
  }

  // --------------------------------------------------
  // VA CHẠM
  // --------------------------------------------------

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);

    if (!conSong) return;

    if (other is DongXu) {
      if (other.nhat()) {
        diem += CauHinh.diemMoiDongXu;
        khiChiSoDoi();
      }
      return;
    }

    if (other is VatPhamRoi) {
      if (other.nhat()) _nhanPhanThuong(other.phanThuong);
      return;
    }

    if (other is KeDich) {
      if (!dangBatTu && !other.isDead) {
        nhanSatThuong(other.satThuongCham);
      }
      return;
    }
  }

  /// Boss hoặc quái chạm vào George: gây sát thương mỗi khi hết thời gian bất tử.
  /// Dùng onCollision (gọi mỗi khung hình khi đang chạm), không phải onCollisionStart.
  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is Boss && !other.daChet) {
      nhanSatThuong(CauHinh.satThuongBossCham);
    }
    if (other is KeDich && !other.isDead) {
      nhanSatThuong(other.satThuongCham);
    }
  }

  // --------------------------------------------------
  // NHẬN SÁT THƯƠNG
  // --------------------------------------------------

  /// Công khai để Boss và đạn của Boss gọi được.
  void nhanSatThuong([int luong = CauHinh.mauMatMoiLanTrung]) {
    if (!conSong || dangBatTu) return;

    // Khiên chặn mọi đòn trong lúc đang bật.
    if (kyNang.dangDung(LoaiKyNang.shield)) return;

    final satThuongThucTe = (luong * (1 - _giamSatThuong)).round();
    mau -= satThuongThucTe;

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
