import 'dart:convert';

/// Một màn chơi — đọc từ `assets/tiles/man_choi.json`.
///
/// Tệp JSON đó là MỘT nguồn sự thật dùng chung cho ba bên:
///   * app (tệp này) dựng màn hình chọn màn, nạp đúng bản đồ, đặt đồng hồ và tốc độ kẻ địch;
///   * máy chủ trọng tài (`gold_rush_ai/core/man_choi.py`) biết giới hạn thời gian, cọc, thưởng;
///   * Ignition (`gold_rush_chain`) gọi `datMan(id, coc, soXu + thuong)` lúc triển khai hợp đồng.
/// Sinh lại bằng `python gold_rush_ai/scripts/sinh_man_choi.py`.
class ManChoi {
  final int id;
  final String ten;
  final String moTa;

  /// Tên tệp .tmx trong `assets/tiles/`.
  final String tep;

  /// 0 = không giới hạn thời gian.
  final int gioiHanGiay;

  /// Nhân vào tốc độ zombie/skeleton (sau hệ số của AI độ khó).
  final double heSoKeDich;

  /// Vàng đặt cọc khi vào màn. 0 = màn luyện tập.
  final int coc;

  /// Vàng thưởng thêm khi hoàn thành (ngoài số xu).
  final int thuong;
  final int soXu;
  final int sao;

  const ManChoi({
    required this.id,
    required this.ten,
    required this.moTa,
    required this.tep,
    required this.gioiHanGiay,
    required this.heSoKeDich,
    required this.coc,
    required this.thuong,
    required this.soXu,
    required this.sao,
  });

  bool get mienPhi => coc == 0;

  /// Máy chủ chỉ nhận nhật ký màn có cọc tới trong ngần này giờ THẬT kể từ lúc bắt đầu (kể cả tạm dừng).
  /// PHẢI khớp `HE_SO_TAM_DUNG * gioi_han_giay + 60` trong gold_rush_ai/core/trong_tai.py.
  Duration get hanNopNhatKy => Duration(seconds: 2 * gioiHanGiay + 60);

  /// Hoàn thành màn có cọc thì nhận về bấy nhiêu vàng (cọc + xu + thưởng).
  int get nhanVeKhiHoanThanh => coc + soXu + thuong;

  factory ManChoi.tuJson(Map<String, dynamic> j) => ManChoi(
        id: j['id'] as int,
        ten: j['ten'] as String,
        moTa: j['mo_ta'] as String,
        tep: j['tep'] as String,
        gioiHanGiay: j['gioi_han_giay'] as int,
        heSoKeDich: (j['he_so_ke_dich'] as num).toDouble(),
        coc: j['coc'] as int,
        thuong: j['thuong'] as int,
        soXu: j['so_xu'] as int,
        sao: j['sao'] as int,
      );

  /// Màn mặc định khi chưa nạp được tệp JSON: bản đồ gốc, luyện tập — game vẫn chơi được.
  static const ManChoi macDinh = ManChoi(
    id: 1,
    ten: 'Đồng cỏ',
    moTa: 'Màn luyện tập.',
    tep: 'gold_rush.tmx',
    gioiHanGiay: 0,
    heSoKeDich: 1,
    coc: 0,
    thuong: 0,
    soXu: 24,
    sao: 1,
  );

  /// Đọc nội dung tệp `man_choi.json`, sắp theo id.
  static List<ManChoi> docDanhSach(String noiDung) {
    final j = jsonDecode(noiDung) as Map<String, dynamic>;
    final ds = [
      for (final m in j['man'] as List<dynamic>) ManChoi.tuJson(m as Map<String, dynamic>),
    ]..sort((a, b) => a.id.compareTo(b.id));
    if (ds.isEmpty) throw const FormatException('man_choi.json không có màn nào');
    return ds;
  }
}

/// "1:05" — đồng hồ trên HUD và màn hình chọn màn.
String dinhDangGiay(num giay) {
  final s = giay.ceil().clamp(0, 99 * 60);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
