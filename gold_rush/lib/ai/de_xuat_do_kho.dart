/// Đề xuất schema v1 từ API, để tầng tích hợp duyệt hệ số tốc độ kẻ địch.
class DeXuatDoKho {
  final int manChoi;
  final String doKho;
  final double? diemHieuSuat;
  final String lyDo;
  final double heSoTocDo;
  final String nguon;
  final int soVan;
  final String nguonNguCanh;

  const DeXuatDoKho._({
    required this.manChoi,
    required this.doKho,
    required this.diemHieuSuat,
    required this.lyDo,
    required this.heSoTocDo,
    required this.nguon,
    required this.soVan,
    required this.nguonNguCanh,
  });

  factory DeXuatDoKho.tuJson(Map<String, dynamic> json) {
    _soNguyen(json, 'schema_version', 1, 1);
    final lyDo = json['reason'];
    if (lyDo is! String || lyDo.trim().isEmpty || lyDo.runes.length > 500) {
      throw const FormatException('Lý do đề xuất không hợp lệ');
    }
    if (!json.containsKey('performance_score')) {
      throw const FormatException('Thiếu điểm hiệu suất');
    }
    final diem = json['performance_score'] == null
        ? null
        : _soThuc(json, 'performance_score', 0, 1);
    final dieuChinh = json['adjustments'];
    if (dieuChinh is! Map<String, dynamic>) {
      throw const FormatException('Thiếu tham số điều chỉnh');
    }
    return DeXuatDoKho._(
      manChoi: _soNguyen(json, 'stage_id', 1, 1000),
      doKho: _luaChon(json, 'difficulty', const {'easy', 'medium', 'hard'}),
      diemHieuSuat: diem,
      lyDo: lyDo,
      heSoTocDo: _soThuc(dieuChinh, 'enemy_speed_multiplier', 0.8, 1.15),
      nguon: _luaChon(json, 'source', const {'rule_based', 'fallback'}),
      soVan: _soNguyen(json, 'sample_count', 0, 10),
      nguonNguCanh: _luaChon(json, 'context_source', const {
        'verified',
        'demo',
      }),
    );
  }
}

int _soNguyen(
  Map<String, dynamic> json,
  String truong,
  int toiThieu,
  int toiDa,
) {
  final value = json[truong];
  if (value is! int || value < toiThieu || value > toiDa) {
    throw FormatException('Trường $truong không hợp lệ');
  }
  return value;
}

double _soThuc(
  Map<String, dynamic> json,
  String truong,
  double toiThieu,
  double toiDa,
) {
  final value = json[truong];
  if (value is! num || !value.isFinite || value < toiThieu || value > toiDa) {
    throw FormatException('Trường $truong không hợp lệ');
  }
  return value.toDouble();
}

String _luaChon(Map<String, dynamic> json, String truong, Set<String> choPhep) {
  final value = json[truong];
  if (value is! String || !choPhep.contains(value)) {
    throw FormatException('Trường $truong không được hỗ trợ');
  }
  return value;
}
