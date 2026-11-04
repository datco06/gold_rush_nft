import 'dart:math' as math;

/// Mô hình dự đoán "người chơi sắp thua" — hồi quy logistic.
///
/// Mô hình được HUẤN LUYỆN bằng Python (`gold_rush_ai/core/do_kho.py`) rồi xuất
/// ra `assets/models/do_kho_v1.json`. App chỉ làm phần SUY LUẬN:
///
///     z = chặn + Σ hệSố[i] × (x[i] − trungBình[i]) / độLệch[i]
///     p = 1 / (1 + e^(−z))
///
/// Vì sao không dùng TFLite/ONNX: mô hình chỉ có 5 hệ số. Thêm một runtime
/// vài MB vào app để nhân 5 con số là lãng phí. Khi đổi sang mạng nơ-ron thì
/// mới cần runtime — lúc đó chỉ thay lớp này, phần còn lại của game giữ nguyên
/// vì mọi nơi khác chỉ gọi `duDoan(...)`.
class MoHinhDoKho {
  final String phienBan;
  final List<String> dacTrung;
  final List<double> trungBinh;
  final List<double> doLech;
  final List<double> heSo;
  final double chan;

  MoHinhDoKho({
    required this.phienBan,
    required this.dacTrung,
    required this.trungBinh,
    required this.doLech,
    required this.heSo,
    required this.chan,
  }) {
    final n = dacTrung.length;
    if (trungBinh.length != n || doLech.length != n || heSo.length != n) {
      throw FormatException('Mô hình $phienBan: số phần tử các mảng không khớp');
    }
  }

  /// Danh sách đặc trưng app tính được — xem `NhatKyChoi.dacTrung`.
  /// Mô hình đòi đặc trưng khác danh sách này là mô hình của phiên bản app khác.
  static const List<String> dacTrungHoTro = [
    'ti_le_mau',
    'trung_don_moi_phut',
    'xu_moi_phut',
    'ti_le_xu',
    'phut_da_choi',
  ];

  factory MoHinhDoKho.tuJson(Map<String, dynamic> j) {
    List<double> soThuc(String k) =>
        (j[k] as List).map((v) => (v as num).toDouble()).toList();

    final dt = (j['dac_trung'] as List).cast<String>();
    if (dt.length != dacTrungHoTro.length ||
        !List.generate(dt.length, (i) => dt[i] == dacTrungHoTro[i])
            .every((dung) => dung)) {
      throw FormatException(
          'Mô hình cần đặc trưng $dt, app này chỉ tính được $dacTrungHoTro');
    }
    return MoHinhDoKho(
      phienBan: j['phien_ban'] as String,
      dacTrung: dt,
      trungBinh: soThuc('trung_binh'),
      doLech: soThuc('do_lech'),
      heSo: soThuc('he_so'),
      chan: (j['chan'] as num).toDouble(),
    );
  }

  /// Xác suất (0..1) ván này kết thúc bằng thua, tính từ vector đặc trưng [x].
  double duDoan(List<double> x) {
    if (x.length != heSo.length) {
      throw ArgumentError('Cần ${heSo.length} đặc trưng, nhận ${x.length}');
    }
    var z = chan;
    for (var i = 0; i < x.length; i++) {
      z += heSo[i] * (x[i] - trungBinh[i]) / doLech[i];
    }
    return 1 / (1 + math.exp(-z));
  }
}
