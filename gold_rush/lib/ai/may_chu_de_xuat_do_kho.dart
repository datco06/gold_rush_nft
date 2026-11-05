import 'package:http/http.dart' as http;

import 'de_xuat_do_kho.dart';
import 'may_chu_ai.dart';

typedef LoiDeXuatDoKho = LoiApiAi;

class KetQuaDeXuatDoKho {
  final DeXuatDoKho? deXuat;
  final LoiDeXuatDoKho? loi;
  final int? maHttp;

  const KetQuaDeXuatDoKho._({this.deXuat, this.loi, this.maHttp});

  bool get coTheThuLai =>
      loi == LoiDeXuatDoKho.hetThoiGian ||
      loi == LoiDeXuatDoKho.ketNoi ||
      loi == LoiDeXuatDoKho.mayChu ||
      maHttp == 429;
}

/// Chỉ gửi ID màn. Backend cung cấp lịch sử, quyền truy cập và hệ số trước.
/// Demo dùng X-Demo-Player khi backend đã bật AI_DIFFICULTY_DEMO.
class MayChuDeXuatDoKho {
  final MayChuAi _api;

  MayChuDeXuatDoKho({
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

  Future<KetQuaDeXuatDoKho> deXuat({required int manChoi}) async {
    if (manChoi < 1 || manChoi > 1000) {
      return const KetQuaDeXuatDoKho._(loi: LoiDeXuatDoKho.yeuCauKhongHopLe);
    }
    final kq = await _api.postJson(
      '/api/ai/do-kho/de-xuat',
      body: {'stage_id': manChoi},
    );
    if (kq.loi != null) {
      return KetQuaDeXuatDoKho._(loi: kq.loi, maHttp: kq.maHttp);
    }
    try {
      final dx = DeXuatDoKho.tuJson(kq.duLieu!);
      if (dx.manChoi != manChoi) {
        throw const FormatException('Đề xuất không khớp màn đã yêu cầu');
      }
      return KetQuaDeXuatDoKho._(deXuat: dx, maHttp: kq.maHttp);
    } on FormatException {
      return const KetQuaDeXuatDoKho._(loi: LoiDeXuatDoKho.phanHoiKhongHopLe);
    }
  }
}
