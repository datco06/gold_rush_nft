import 'package:flame/components.dart';

import '../cau_hinh.dart';

/// Toàn bộ phép tính va chạm với địa hình, tách hẳn khỏi việc đọc tệp .tmx.
///
/// Vì sao tách: lớp này **không phụ thuộc gì** vào Flame Tiled, vào tệp trên
/// đĩa, hay vào cây component. Nó chỉ nhận một mảng hai chiều true/false và
/// trả lời các câu hỏi hình học. Nhờ vậy:
///
///   * Kiểm thử được bằng `flutter test` mà không cần dựng giao diện hay nạp
///     tài nguyên — xem `test/luoi_va_cham_test.dart`.
///   * Muốn đổi nguồn bản đồ (từ .tmx sang JSON, hoặc sinh ngẫu nhiên) thì
///     chỉ sửa `BanDo`, phần logic ở đây giữ nguyên.
///
/// Đây chính là bài học phân tầng đã dùng suốt học phần, áp vào game: **tách
/// phần tính toán thuần ra khỏi phần đọc ghi dữ liệu.**
class LuoiVaCham {
  /// `_chan[y][x] == true` nghĩa là ô đó không đi qua được.
  final List<List<bool>> _chan;

  final int soCot;
  final int soHang;

  LuoiVaCham(this._chan)
      : soHang = _chan.length,
        soCot = _chan.isEmpty ? 0 : _chan.first.length;

  /// Lưới trống hoàn toàn, dùng khi tệp .tmx thiếu lớp va chạm.
  factory LuoiVaCham.trong(int cot, int hang) => LuoiVaCham(
        List.generate(hang, (_) => List<bool>.filled(cot, false)),
      );

  /// Ô (cột, hàng) có chặn không. Ngoài bản đồ coi như chặn.
  ///
  /// Đây là "cổng" duy nhất mà bộ tìm đường A* (`lib/ai/tim_duong.dart`) cần
  /// từ bản đồ — nó không cần biết gì về pixel hay tệp .tmx.
  bool biChanO(int cot, int hang) {
    if (cot < 0 || hang < 0 || cot >= soCot || hang >= soHang) return true;
    return _chan[hang][cot];
  }

  /// Kích thước bản đồ tính bằng pixel thế giới.
  Vector2 get kichThuoc =>
      Vector2(soCot * CauHinh.kichThuocO, soHang * CauHinh.kichThuocO);

  /// Ô ở toạ độ thế giới (x, y) có chặn không. Ngoài bản đồ coi như chặn.
  bool biChanTaiDiem(double x, double y) {
    // Dùng floor() chứ không dùng ~/ : với toạ độ âm thì ~/ cắt về 0
    // (-1 ~/ 16 == 0) nên ô ngoài bản đồ bị hiểu nhầm thành ô 0.
    final cx = (x / CauHinh.kichThuocO).floor();
    final cy = (y / CauHinh.kichThuocO).floor();
    if (cx < 0 || cy < 0 || cx >= soCot || cy >= soHang) return true;
    return _chan[cy][cx];
  }

  /// Hình chữ nhật tâm `tam`, kích thước `kichThuocHop`, có nằm hoàn toàn
  /// trên nền đi được không.
  ///
  /// Chỉ kiểm tra bốn góc là đủ vì hộp của nhân vật (10×7) nhỏ hơn một ô (16),
  /// không thể "nhảy qua" một ô chặn nằm lọt giữa hộp.
  bool diDuoc(Vector2 tam, Vector2 kichThuocHop) {
    final nuaX = kichThuocHop.x / 2;
    final nuaY = kichThuocHop.y / 2;

    final trai = tam.x - nuaX;
    final phai = tam.x + nuaX - 0.01; // trừ epsilon: mép phải thuộc ô bên trái
    final tren = tam.y - nuaY;
    final duoi = tam.y + nuaY - 0.01;

    return !biChanTaiDiem(trai, tren) &&
        !biChanTaiDiem(phai, tren) &&
        !biChanTaiDiem(trai, duoi) &&
        !biChanTaiDiem(phai, duoi);
  }

  /// Từ điểm `tu` có "nhìn thấy" điểm `den` không, hay bị vật cản che.
  ///
  /// Phép chiếu tia đơn giản nhất: đi dọc đoạn thẳng nối hai điểm, mỗi bước
  /// nửa ô, gặp ô chặn thì coi như bị che. Kẻ địch dùng hàm này để không đuổi
  /// theo George xuyên qua tường — phần AI của Chương 10.
  bool nhinThay(Vector2 tu, Vector2 den) {
    final doDai = tu.distanceTo(den);
    if (doDai < 0.001) return true;

    final soBuoc = (doDai / (CauHinh.kichThuocO / 2)).ceil();
    final buoc = (den - tu) / soBuoc.toDouble();
    final diem = tu.clone();

    for (var i = 0; i < soBuoc; i++) {
      diem.add(buoc);
      if (biChanTaiDiem(diem.x, diem.y)) return false;
    }
    return true;
  }
}
