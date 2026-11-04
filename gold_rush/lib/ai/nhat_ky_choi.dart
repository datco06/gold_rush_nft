import 'dart:math';

/// Ghi lại diễn biến một ván chơi (telemetry) và tính đặc trưng cho mô hình.
///
/// Hai việc, cùng một nguồn số liệu:
///   1. `dacTrung(...)` — vector 5 số đưa vào `DieuChinhDoKho` mỗi 10 giây.
///   2. `thanhJson(...)` — nhật ký cả ván gửi về máy chủ (`POST /api/nhat-ky`)
///      để sau này huấn luyện lại mô hình bằng dữ liệu THẬT.
///
/// HỢP ĐỒNG ĐẶC TRƯNG phải khớp từng chữ với `gold_rush_ai/core/do_kho.py`.
/// Đổi tên, đổi thứ tự hay đổi cách tính một đặc trưng = phải huấn luyện lại
/// và tăng phiên bản mô hình.
///
/// Dữ liệu cá nhân: KHÔNG ghi tên thật, email, vị trí GPS hay mã thiết bị.
/// `maVan` là chuỗi ngẫu nhiên mới cho từng ván.
class NhatKyChoi {
  static const double chuKyAnhChup = 10; // giây
  static const double phutToiThieu = 0.25;
  static const int toiDaSuKien = 500; // khớp giới hạn phía máy chủ

  final Random _rnd;

  NhatKyChoi({Random? rnd}) : _rnd = rnd ?? Random.secure();

  late String maVan;
  int tongXu = 0;
  int soXu = 0;
  int soLanTrung = 0;
  double giay = 0;
  double _demAnhChup = 0;

  final List<Map<String, Object>> anhChup = [];
  final List<Map<String, Object>> suKien = [];

  /// Sinh trước một mã ván — màn có cọc cần mã ván để đăng ký với máy chủ TRƯỚC khi chơi.
  String sinhMaVan() => _sinhMaVan();

  /// Bắt đầu ván mới. [maVanCoSan]: mã đã đăng ký với máy chủ (màn có cọc).
  void batDau(int tongSoXu, {String? maVanCoSan}) {
    maVan = maVanCoSan ?? _sinhMaVan();
    tongXu = tongSoXu;
    soXu = 0;
    soLanTrung = 0;
    giay = 0;
    _demAnhChup = 0;
    anhChup.clear();
    suKien.clear();
  }

  /// Gọi mỗi khung hình khi đang chơi. Trả về true khi tới lúc chụp đặc trưng.
  bool troiThoiGian(double dt) {
    giay += dt;
    _demAnhChup += dt;
    if (_demAnhChup >= chuKyAnhChup) {
      _demAnhChup -= chuKyAnhChup;
      return true;
    }
    return false;
  }

  void ghiNhatXu(double x, double y) {
    soXu++;
    _ghi('nhat_xu', x, y);
  }

  void ghiTrungDon(double x, double y) {
    soLanTrung++;
    _ghi('trung_don', x, y);
  }

  void _ghi(String loai, double x, double y) {
    if (suKien.length >= toiDaSuKien) return;
    suKien.add({
      'loai': loai,
      'giay': _tron(giay),
      'x': _tron(max(0, x)),
      'y': _tron(max(0, y)),
    });
  }

  /// Vector đặc trưng theo đúng thứ tự `MoHinhDoKho.dacTrungHoTro`.
  List<double> dacTrung(int mau, int mauToiDa) {
    final phut = max(giay / 60, phutToiThieu);
    return [
      mau / mauToiDa,
      soLanTrung / phut,
      soXu / phut,
      tongXu == 0 ? 0.0 : soXu / tongXu,
      giay / 60,
    ];
  }

  /// Chụp đặc trưng hiện tại vào nhật ký và trả về để đưa cho bộ điều chỉnh.
  List<double> chup(int mau, int mauToiDa) {
    final x = dacTrung(mau, mauToiDa);
    if (anhChup.length < 400) {
      anhChup.add({
        'giay': _tron(giay),
        'ti_le_mau': _tron(x[0]),
        'trung_don_moi_phut': _tron(x[1]),
        'xu_moi_phut': _tron(x[2]),
        'ti_le_xu': _tron(x[3]),
        'phut_da_choi': _tron(x[4]),
      });
    }
    return x;
  }

  /// Nhật ký cả ván, đúng lược đồ `NhatKyVan` ở `gold_rush_ai/core/nhat_ky.py`.
  Map<String, Object> thanhJson({
    required String ketQua, // 'thang' | 'thua' | 'bo'
    required int diem,
    required String phienBanApp,
    required bool doKhoThichUng,
    String banDo = 'gold_rush.tmx',
    int man = 1,
    String tenHienThi = '',
  }) {
    final ten = tenHienThi.trim();
    return {
      'ma_van': maVan,
      'phien_ban_app': phienBanApp,
      'ban_do': banDo,
      'man': man,
      'ket_qua': ketQua,
      'giay': _tron(giay),
      'diem': diem,
      'do_kho_thich_ung': doKhoThichUng,
      'ten_hien_thi': ten.length > 20 ? ten.substring(0, 20) : ten,
      'anh_chup': List.of(anhChup),
      'su_kien': List.of(suKien),
    };
  }

  String _sinhMaVan() {
    const kyTu = '0123456789abcdef';
    final b = StringBuffer();
    for (var i = 0; i < 32; i++) {
      if (i == 8 || i == 12 || i == 16 || i == 20) b.write('-');
      b.write(kyTu[_rnd.nextInt(16)]);
    }
    return b.toString();
  }

  static double _tron(num v) => (v * 10000).round() / 10000;
}
