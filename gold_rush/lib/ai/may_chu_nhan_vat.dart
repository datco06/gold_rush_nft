import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'anh_nhan_vat.dart';
import 'may_chu_ai.dart';

typedef LoiAnhNhanVat = LoiApiAi;

class KetQuaAnhNhanVat {
  final AnhNhanVat? anh;
  final Uint8List? png;
  final LoiAnhNhanVat? loi;
  final int? maHttp;

  const KetQuaAnhNhanVat._({this.anh, this.png, this.loi, this.maHttp});

  bool get coTheThuLai =>
      loi == LoiAnhNhanVat.hetThoiGian ||
      loi == LoiAnhNhanVat.ketNoi ||
      loi == LoiAnhNhanVat.mayChu ||
      maHttp == 429;
}

class MayChuNhanVat {
  final MayChuAi _api;

  MayChuNhanVat({
    String mayChu = const String.fromEnvironment('GOLD_RUSH_API'),
    String? maNguoiChoiDemo,
    http.Client? client,
    Duration thoiGianCho = const Duration(seconds: 15),
  }) : _api = MayChuAi(
         mayChu: mayChu,
         maNguoiChoiDemo: maNguoiChoiDemo,
         client: client,
         thoiGianCho: thoiGianCho,
       );

  Future<KetQuaAnhNhanVat> tao({
    required String moTa,
    required String maYeuCau,
  }) async {
    final noiDung = moTa.trim();
    if (!_moTaHopLe(noiDung) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(maYeuCau)) {
      return const KetQuaAnhNhanVat._(loi: LoiAnhNhanVat.yeuCauKhongHopLe);
    }
    final kq = await _api.postJson(
      '/api/ai/nhan-vat/tao',
      body: {'description': noiDung},
      headers: {'Idempotency-Key': maYeuCau},
    );
    if (kq.loi != null) {
      return KetQuaAnhNhanVat._(loi: kq.loi, maHttp: kq.maHttp);
    }
    try {
      return KetQuaAnhNhanVat._(
        anh: AnhNhanVat.tuJson(kq.duLieu!),
        maHttp: kq.maHttp,
      );
    } on FormatException {
      return const KetQuaAnhNhanVat._(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  Future<KetQuaAnhNhanVat> tai(AnhNhanVat anh) async {
    final kq = await _api.getBytes(
      anh.duongDanAnh,
      headers: const {'Accept': 'image/png'},
    );
    if (kq.loi != null) {
      return KetQuaAnhNhanVat._(loi: kq.loi, maHttp: kq.maHttp);
    }
    try {
      if (kq.contentType?.split(';').first.trim().toLowerCase() !=
          'image/png') {
        throw const FormatException('Phản hồi ảnh cần image/png');
      }
      final png = kq.bytes!;
      _kiemTraHeader(png, anh);
      final codec = await ui.instantiateImageCodec(png);
      try {
        if (codec.frameCount != 1) {
          throw const FormatException('Preview cần ảnh tĩnh');
        }
        final frame = await codec.getNextFrame();
        try {
          if (frame.image.width != anh.chieuRong ||
              frame.image.height != anh.chieuCao) {
            throw const FormatException('Kích thước ảnh không khớp metadata');
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      return KetQuaAnhNhanVat._(anh: anh, png: png, maHttp: kq.maHttp);
    } on Exception {
      return const KetQuaAnhNhanVat._(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }
}

bool _moTaHopLe(String value) {
  if (value.isEmpty || value.runes.length > 500) return false;
  return !value.runes.any(
    (rune) =>
        (rune < 32 && rune != 9 && rune != 10 && rune != 13) ||
        (rune >= 127 && rune <= 159) ||
        (rune >= 0xd800 && rune <= 0xdfff),
  );
}

void _kiemTraHeader(Uint8List png, AnhNhanVat anh) {
  if (png.length < 33) throw const FormatException('Thiếu header PNG');
  final header = ByteData.sublistView(png);
  if (header.getUint32(0) != 0x89504e47 ||
      header.getUint32(4) != 0x0d0a1a0a ||
      header.getUint32(8) != 13 ||
      header.getUint32(12) != 0x49484452 ||
      header.getUint32(16) != anh.chieuRong ||
      header.getUint32(20) != anh.chieuCao) {
    throw const FormatException('Header PNG không khớp ảnh xem trước');
  }
}
