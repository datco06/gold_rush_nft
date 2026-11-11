import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import '../am_thanh/am_thanh.dart';
import '../cau_hinh.dart';
import 'dong_xu.dart';
import 'ke_dich.dart';
import 'nhan_vat.dart';

/// Nhân vật chính.
///
/// George nhận lệnh di chuyển từ BA nguồn, xét theo thứ tự ưu tiên:
///   1. Bàn phím  – máy tính (Chương 5 và 8 của sách)
///   2. Joystick  – điện thoại
///   3. Chạm màn hình – chạm vào đâu thì đi tới đó
///
/// Nguồn nào đang có tín hiệu thì nguồn đó thắng, và thao tác bàn phím hay
/// joystick sẽ huỷ đích đến do chạm màn hình. Không làm vậy thì người chơi
/// chạm một phát rồi cầm joystick, nhân vật sẽ giằng co giữa hai lệnh.
class George extends NhanVat with KeyboardHandler {
  /// Gọi khi số điểm hoặc lượng máu đổi, để HUD vẽ lại.
  final void Function() khiChiSoDoi;

  /// Gọi khi máu về 0.
  final void Function() khiChet;

  int diem = 0;
  int mau = CauHinh.mauToiDa;

  /// Còn bao nhiêu giây bất tử sau khi trúng đòn.
  double _batTu = 0;

  /// Hướng do bàn phím quy định, cập nhật trong onKeyEvent.
  final Vector2 _huongBanPhim = Vector2.zero();

  /// Hướng do joystick quy định, game gán vào mỗi khung hình.
  final Vector2 huongJoystick = Vector2.zero();

  /// Đích đến do người chơi chạm vào màn hình. null nghĩa là không có.
  Vector2? viTriDich;

  double _dongHoBuocChan = 0;

  /// Khoá điều khiển khi đang mở menu hoặc ván đã kết thúc.
  ///
  /// Cần cờ này vì bàn phím đi thẳng vào component, không qua vòng kiểm tra
  /// trạng thái của game: thiếu nó thì bấm phím mũi tên lúc đang mở menu là
  /// George vẫn chạy phía sau lớp phủ.
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
    add(hopVaCham());
  }

  // ------------------------------------------------------------------
  // Bàn phím
  // ------------------------------------------------------------------
  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (!dieuKhienDuoc) {
      _huongBanPhim.setZero();
      return false;
    }

    // Đọc từ keysPressed (tập phím ĐANG được giữ) chứ không đọc từ event.
    // Đọc từ event thì giữ phím sẽ chỉ chạy một lần, và bấm hai phím cùng lúc
    // để đi chéo sẽ không hoạt động.
    final trai = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    final phai = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);
    final len = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW);
    final xuong = keysPressed.contains(LogicalKeyboardKey.arrowDown) ||
        keysPressed.contains(LogicalKeyboardKey.keyS);

    // Chú ý viết 1.0 / 0.0 chứ không phải 1 / 0: Vector2.x là double, và Dart
    // KHÔNG tự đổi kiểu cho biểu thức điều kiện (chỉ tự đổi cho hằng số).
    _huongBanPhim
      ..x = (phai ? 1.0 : 0.0) - (trai ? 1.0 : 0.0)
      ..y = (xuong ? 1.0 : 0.0) - (len ? 1.0 : 0.0);

    if (_huongBanPhim.x != 0 || _huongBanPhim.y != 0) {
      viTriDich = null; // bàn phím huỷ đích chạm màn hình
    }

    // Trả về false để các component khác vẫn nhận được sự kiện phím
    // (ví dụ phím Esc mở menu tạm dừng do game xử lý).
    return false;
  }

  // ------------------------------------------------------------------
  // Vòng lặp
  // ------------------------------------------------------------------
  @override
  void update(double dt) {
    super.update(dt);
    if (!conSong || !dieuKhienDuoc) {
      datDangDi(false);
      return;
    }

    if (_batTu > 0) {
      _batTu -= dt;
      // Nhấp nháy để người chơi biết mình đang trong thời gian miễn thương.
      opacity = ((_batTu * 12).floor() % 2 == 0) ? 0.35 : 1.0;
      if (_batTu <= 0) opacity = 1.0;
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
      // Đâm vào tường trên đường tới đích thì bỏ đích, tránh đứng ịn vào tường.
      viTriDich = null;
    }
  }

  /// Gộp ba nguồn điều khiển thành một vector hướng duy nhất.
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
      // Tới đủ gần thì coi như đã đến, nếu không nhân vật sẽ rung quanh đích.
      if (den.length < 3) {
        viTriDich = null;
        return Vector2.zero();
      }
      return den;
    }

    return Vector2.zero();
  }

  // ------------------------------------------------------------------
  // Va chạm
  // ------------------------------------------------------------------
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
      khac.noTung(); // kẻ địch tự nổ và biến mất
      _nhanSatThuong();
    }
  }

  void _nhanSatThuong() {
    mau -= CauHinh.mauMatMoiLanTrung;
    if (mau < 0) mau = 0;
    _batTu = CauHinh.thoiGianBatTu;
    khiChiSoDoi();

    if (mau == 0) {
      opacity = 1.0;
      datDangDi(false);
      khiChet();
    }
  }
}
