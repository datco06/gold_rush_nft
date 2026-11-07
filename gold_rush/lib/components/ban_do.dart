import 'package:flame/components.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:flutter/foundation.dart';

import '../cau_hinh.dart';
import 'luoi_va_cham.dart';

/// Một điểm xuất hiện đọc được từ lớp đối tượng của tệp .tmx.
class DiemXuatHien {
  final String ten; // 'george' | 'coin' | 'zombie' | 'skeleton'
  final Vector2 viTri; // toạ độ thế giới, tính bằng pixel

  const DiemXuatHien(this.ten, this.viTri);

  @override
  String toString() => 'DiemXuatHien($ten @ ${viTri.x},${viTri.y})';
}

/// Bản đồ trò chơi: vừa là phần hiển thị, vừa là nguồn dữ liệu va chạm.
///
/// Bản đồ được vẽ trong Tiled và lưu ở `assets/tiles/*.tmx` (màn 1 vẽ tay `gold_rush.tmx`,
/// màn 2–6 do `gold_rush_ai/scripts/sinh_man_choi.py` sinh — cùng định dạng, cùng tên lớp).
/// Tệp .tmx có ba lớp ô và một lớp đối tượng:
///
///   Nen        – cỏ, đường, nước, sàn kim cương
///   TrangTri   – cây, đá, tường
///   VaCham     – ô nào khác 0 là ô KHÔNG đi qua được (lớp này tắt hiển thị)
///   DoiTuong   – điểm xuất hiện của George, đồng xu và kẻ địch
///
/// Tách riêng lớp VaCham thay vì suy ra từ loại ô là cách làm chuẩn: người
/// thiết kế màn chơi đổi đồ hoạ thoải mái mà không phá logic, và ngược lại có
/// thể đặt tường vô hình ở nơi không có vật cản nào nhìn thấy được.
class BanDo {
  /// Component để gắn vào thế giới. Khai báo kiểu `Component` chứ không phải
  /// `TiledComponent<...>` để khỏi dính vào tham số kiểu của flame_tiled —
  /// phần này chỉ cần thêm nó vào cây component là xong.
  late final Component thanhPhan;

  /// Dữ liệu bản đồ đã phân tích: lớp ô, lớp đối tượng, kích thước.
  late final RenderableTiledMap _duLieuBanDo;

  /// Phần tính toán va chạm, tách riêng để kiểm thử được mà không cần nạp tệp.
  late final LuoiVaCham luoi;

  int get soCot => luoi.soCot;
  int get soHang => luoi.soHang;

  /// Kích thước bản đồ tính bằng pixel thế giới.
  Vector2 get kichThuoc => luoi.kichThuoc;

  final List<DiemXuatHien> diemXuatHien = [];

  /// Tên tệp .tmx đã nạp — ghi vào nhật ký để máy chủ kiểm định đúng bản đồ.
  final String tep;

  /// Nạp tệp .tmx rồi dựng lưới va chạm và danh sách điểm xuất hiện.
  static Future<BanDo> nap([String tep = 'gold_rush.tmx']) async {
    final b = BanDo._(tep);
    await b._nap();
    return b;
  }

  BanDo._(this.tep);

  Future<void> _nap() async {
    // Tham số thứ hai là kích thước MỖI Ô KHI VẼ RA MÀN HÌNH. Để đúng bằng
    // kích thước ô trong tệp .tmx thì bản đồ hiển thị đúng tỉ lệ gốc; việc
    // phóng to thu nhỏ đã có camera lo.
    //
    // Đường dẫn mặc định của flame_tiled là 'assets/tiles/' nên chỉ cần
    // truyền tên tệp.
    final tiled = await TiledComponent.load(
      tep,
      Vector2.all(CauHinh.kichThuocO),
    );
    tiled.priority = 0;

    thanhPhan = tiled;
    _duLieuBanDo = tiled.tileMap;

    final map = _duLieuBanDo.map;
    luoi = _dungLuoiChan(map.width, map.height);
    _docDiemXuatHien();

    debugPrint(
      'Bản đồ $tep: ${soCot}x$soHang ô, '
      '${diemXuatHien.length} điểm xuất hiện',
    );
  }

  LuoiVaCham _dungLuoiChan(int cot, int hang) {
    final lop = _duLieuBanDo.getLayer<TileLayer>(CauHinh.lopVaCham);
    if (lop == null) {
      debugPrint(
        'CẢNH BÁO: không tìm thấy lớp "${CauHinh.lopVaCham}" '
        'trong tệp .tmx — nhân vật sẽ đi xuyên mọi thứ.',
      );
      return LuoiVaCham.trong(cot, hang);
    }

    final chan = List.generate(
      hang,
      (y) => List<bool>.generate(cot, (x) {
        // tileAt trả về null khi ra ngoài phạm vi; Gid.tile == 0 là ô trống.
        final gid = lop.tileAt(x, y);
        return gid != null && gid.tile != 0;
      }),
    );
    return LuoiVaCham(chan);
  }

  void _docDiemXuatHien() {
    final lop = _duLieuBanDo.getLayer<ObjectGroup>(CauHinh.lopDoiTuong);
    if (lop == null) {
      debugPrint('CẢNH BÁO: không tìm thấy lớp "${CauHinh.lopDoiTuong}".');
      return;
    }
    for (final o in lop.objects) {
      diemXuatHien.add(DiemXuatHien(o.name, Vector2(o.x, o.y)));
    }
  }

  // ------------------------------------------------------------------
  // Truy vấn va chạm — uỷ quyền hết cho LuoiVaCham
  // ------------------------------------------------------------------

  bool biChanTaiDiem(double x, double y) => luoi.biChanTaiDiem(x, y);

  bool diDuoc(Vector2 tam, Vector2 kichThuocHop) =>
      luoi.diDuoc(tam, kichThuocHop);

  bool nhinThay(Vector2 tu, Vector2 den) => luoi.nhinThay(tu, den);
}
