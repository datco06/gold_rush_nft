class AnhNhanVat {
  final String maAnh;
  final String duongDanAnh;
  final int chieuRong;
  final int chieuCao;
  final String nguonSinh;
  final String nguonNguCanh;

  const AnhNhanVat._({
    required this.maAnh,
    required this.duongDanAnh,
    required this.chieuRong,
    required this.chieuCao,
    required this.nguonSinh,
    required this.nguonNguCanh,
  });

  factory AnhNhanVat.tuJson(Map<String, dynamic> json) {
    final ma = json['image_id'];
    if (ma is! String ||
        ma.length != 36 ||
        !RegExp(r'^img_[0-9a-f]{32}$').hasMatch(ma)) {
      throw const FormatException('ID ảnh không hợp lệ');
    }
    final url = json['image_url'];
    if (url is! String || url != '/api/ai/nhan-vat/anh/$ma') {
      throw const FormatException('Đường dẫn ảnh không khớp ID/endpoint');
    }
    _soNguyen(json, 'schema_version', 1);
    _luaChon(json, 'status', const {'ready'});
    return AnhNhanVat._(
      maAnh: ma,
      duongDanAnh: url,
      chieuRong: _soNguyen(json, 'width', 128),
      chieuCao: _soNguyen(json, 'height', 128),
      nguonSinh: _luaChon(json, 'generation_source', const {
        'demo',
        'image_model',
      }),
      nguonNguCanh: _luaChon(json, 'context_source', const {
        'verified',
        'demo',
      }),
    );
  }
}

int _soNguyen(Map<String, dynamic> json, String truong, int mongDoi) {
  final value = json[truong];
  if (value is! int || value != mongDoi) {
    throw FormatException('Trường $truong không hợp lệ');
  }
  return value;
}

String _luaChon(Map<String, dynamic> json, String truong, Set<String> choPhep) {
  final value = json[truong];
  if (value is! String || !choPhep.contains(value)) {
    throw FormatException('Trường $truong không được hỗ trợ');
  }
  return value;
}
