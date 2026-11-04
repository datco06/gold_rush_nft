import 'mo_hinh_do_kho.dart';

/// Điều chỉnh độ khó động (Dynamic Difficulty Adjustment — DDA).
///
/// Mỗi lần nhận một ảnh chụp đặc trưng (10 giây/lần), lớp này hỏi mô hình
/// "khả năng người chơi sắp thua là bao nhiêu" rồi chỉnh tốc độ kẻ địch:
///
///   * sắp thua (p cao)  → kẻ địch chậm lại, thấp nhất 80%;
///   * chơi quá dễ (p thấp) → kẻ địch nhanh lên, cao nhất 115%.
///
/// Ba nguyên tắc thiết kế (quan trọng hơn chính mô hình):
///   1. **Có giới hạn.** Hệ số kẹp trong [0,8; 1,15] — AI không bao giờ biến
///      game thành dễ tuyệt đối hay khó vô lý.
///   2. **Thay đổi từ từ.** Mỗi lần chỉ dịch 30% quãng đường tới mục tiêu,
///      người chơi không thấy kẻ địch "giật" tốc độ.
///   3. **Minh bạch, tắt được.** Người chơi bật/tắt trong màn Cài đặt. Không có
///      mô hình (thiếu tệp, tệp hỏng) thì game chạy với độ khó cố định.
class DieuChinhDoKho {
  static const double heSoThap = 0.8;
  static const double heSoCao = 1.15;
  static const double doNhay = 0.4;
  static const double tocDoBamTheo = 0.3;

  /// Chưa đủ dữ liệu để đánh giá thì không chỉnh (đầu ván ai cũng "chưa nhặt xu").
  static const double phutToiThieu = 0.5;

  MoHinhDoKho? moHinh;
  bool batThichUng;

  double _heSo = 1.0;
  double? _pGanNhat;

  DieuChinhDoKho({this.moHinh, this.batThichUng = true});

  /// Hệ số nhân vào tốc độ kẻ địch. Luôn là 1.0 khi tắt hoặc không có mô hình.
  double get heSoTocDo => (batThichUng && moHinh != null) ? _heSo : 1.0;

  /// Xác suất thua lần dự đoán gần nhất — để hiện lên màn gỡ lỗi hoặc gửi nhật ký.
  double? get pGanNhat => _pGanNhat;

  /// Quy xác suất thua thành hệ số mục tiêu — trùng `he_so_toc_do()` bên Python.
  static double mucTieu(double pThua) =>
      (1.0 - doNhay * (pThua - 0.5)).clamp(heSoThap, heSoCao).toDouble();

  /// Gọi mỗi khi có ảnh chụp đặc trưng mới. [dacTrung] theo đúng thứ tự
  /// `MoHinhDoKho.dacTrungHoTro`; phần tử cuối là số phút đã chơi.
  void capNhat(List<double> dacTrung) {
    final mh = moHinh;
    if (mh == null || !batThichUng) return;
    if (dacTrung.last < phutToiThieu) return;

    final p = mh.duDoan(dacTrung);
    _pGanNhat = p;
    _heSo += (mucTieu(p) - _heSo) * tocDoBamTheo;
  }

  /// Đầu mỗi ván: trả về độ khó gốc.
  void datLai() {
    _heSo = 1.0;
    _pGanNhat = null;
  }
}
