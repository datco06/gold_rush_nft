class NhiemVu {
  final String id;
  final int manChoi;
  final String tieuDe;
  final String moTa;
  final String mucTieu;
  final int soLuong;
  final int? gioiHanGiay;
  final String doKho;
  final int vangThuong;
  final String nguonSinh;
  final String nguonNguCanh;

  const NhiemVu._({
    required this.id,
    required this.manChoi,
    required this.tieuDe,
    required this.moTa,
    required this.mucTieu,
    required this.soLuong,
    required this.gioiHanGiay,
    required this.doKho,
    required this.vangThuong,
    required this.nguonSinh,
    required this.nguonNguCanh,
  });

  factory NhiemVu.tuJson(Map<String, dynamic> json) {
    final id = _chuoi(json, 'id', 64);
    if (!RegExp(r'^quest_[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('ID nhiệm vụ không hợp lệ');
    }
    _soNguyen(json, 'schema_version', 1, 1);
    _luaChon(json, 'status', const {'offered'});
    final mucTieu = _luaChon(json, 'objective', const {
      'collect_coins',
      'finish_before_time',
      'finish_with_max_hits',
    });
    final soLuong = _soNguyen(json, 'target', 0, 100000);
    final gioiHan = json['time_limit_seconds'] == null
        ? null
        : _soNguyen(json, 'time_limit_seconds', 1, 3600);
    if ((mucTieu == 'collect_coins' && soLuong < 1) ||
        (mucTieu == 'finish_before_time' &&
            (soLuong != 1 || gioiHan == null)) ||
        (mucTieu == 'finish_with_max_hits' && soLuong > 3)) {
      throw const FormatException('Mục tiêu nhiệm vụ không hợp lệ');
    }
    final thuong = json['reward'];
    if (thuong is! Map<String, dynamic>) {
      throw const FormatException('Thiếu thông tin thưởng');
    }
    return NhiemVu._(
      id: id,
      manChoi: _soNguyen(json, 'stage_id', 1, 1000),
      tieuDe: _chuoi(json, 'title', 80),
      moTa: _chuoi(json, 'description', 500),
      mucTieu: mucTieu,
      soLuong: soLuong,
      gioiHanGiay: gioiHan,
      doKho: _luaChon(json, 'difficulty', const {'easy', 'medium', 'hard'}),
      vangThuong: _soNguyen(thuong, 'gold', 0, 0),
      nguonSinh: _luaChon(json, 'generation_source', const {
        'llm',
        'rule_based',
        'demo',
      }),
      nguonNguCanh: _luaChon(json, 'context_source', const {
        'verified',
        'demo',
      }),
    );
  }
}

String _chuoi(Map<String, dynamic> json, String truong, int toiDa) {
  final giaTri = json[truong];
  if (giaTri is! String ||
      giaTri.trim().isEmpty ||
      giaTri.runes.length > toiDa) {
    throw FormatException('Trường $truong không hợp lệ');
  }
  return giaTri;
}

int _soNguyen(
  Map<String, dynamic> json,
  String truong,
  int toiThieu,
  int toiDa,
) {
  final giaTri = json[truong];
  if (giaTri is! int || giaTri < toiThieu || giaTri > toiDa) {
    throw FormatException('Trường $truong không hợp lệ');
  }
  return giaTri;
}

String _luaChon(Map<String, dynamic> json, String truong, Set<String> choPhep) {
  final giaTri = json[truong];
  if (giaTri is! String || !choPhep.contains(giaTri)) {
    throw FormatException('Trường $truong không được hỗ trợ');
  }
  return giaTri;
}
