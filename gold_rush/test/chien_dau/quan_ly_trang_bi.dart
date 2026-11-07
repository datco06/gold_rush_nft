import 'vu_khi.dart';

/// Một ô chính, một ô phụ, đúng một vũ khí hoạt động.
class QuanLyTrangBi {
  VuKhi chinh;
  VuKhi? phu;
  bool _dungPhu = false;

  /// UI (Người 1) gắn vào đây để cập nhật biểu tượng.
  void Function(VuKhi)? khiDoi;

  QuanLyTrangBi({this.chinh = VuKhi.kiem, this.phu = VuKhi.cung});

  VuKhi get hienTai => (_dungPhu && phu != null) ? phu! : chinh;

  bool doi() {
    if (phu == null) return false;
    _dungPhu = !_dungPhu;
    khiDoi?.call(hienTai);
    return true;
  }

  /// Dùng cho trường equipment_ids trong kết quả ván.
  List<String> get idDangTrang => [chinh.id, if (phu != null) phu!.id];
}
