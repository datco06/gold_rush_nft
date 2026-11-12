import 'package:http/http.dart' as http;

import 'may_chu_ai.dart';
import 'nhiem_vu.dart';

typedef LoiNhiemVu = LoiApiAi;

class KetQuaNhiemVu {
  final NhiemVu? nhiemVu;
  final LoiNhiemVu? loi;
  final int? maHttp;

  const KetQuaNhiemVu._({this.nhiemVu, this.loi, this.maHttp});

  bool get coTheThuLai =>
      loi == LoiNhiemVu.hetThoiGian ||
      loi == LoiNhiemVu.ketNoi ||
      loi == LoiNhiemVu.mayChu ||
      maHttp == 429;
}

class MayChuNhiemVu {
  final MayChuAi _api;

  http.Client? get client => _api.client;
  Duration get thoiGianCho => _api.thoiGianCho;

  MayChuNhiemVu({
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

  Future<KetQuaNhiemVu> tao({
    required int manChoi,
    required String maYeuCau,
  }) async {
    if (manChoi < 1 ||
        manChoi > 1000 ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(maYeuCau)) {
      return const KetQuaNhiemVu._(loi: LoiNhiemVu.yeuCauKhongHopLe);
    }
    final kq = await _api.postJson(
      '/api/ai/nhiem-vu/tao',
      body: {'stage_id': manChoi},
      headers: {'Idempotency-Key': maYeuCau},
    );
    if (kq.loi != null) return KetQuaNhiemVu._(loi: kq.loi, maHttp: kq.maHttp);
    try {
      final nv = NhiemVu.tuJson(kq.duLieu!);
      if (nv.manChoi != manChoi) {
        throw const FormatException('Nhiệm vụ không khớp màn đã yêu cầu');
      }
      return KetQuaNhiemVu._(nhiemVu: nv, maHttp: kq.maHttp);
    } on FormatException {
      return const KetQuaNhiemVu._(loi: LoiNhiemVu.phanHoiKhongHopLe);
    }
  }
}
