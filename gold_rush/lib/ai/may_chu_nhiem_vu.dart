import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'nhiem_vu.dart';

enum LoiNhiemVu {
  chuaCauHinh,
  yeuCauKhongHopLe,
  hetThoiGian,
  ketNoi,
  biTuChoi,
  mayChu,
  phanHoiKhongHopLe,
}

/// Giao diện có thể hiển thị lỗi và cho thử lại qua kết quả này.
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

/// Client gọi API nhiệm vụ. Chưa cấu hình GOLD_RUSH_API thì trả offline.
///
/// Caller giữ cùng maYeuCau cho các lần thử lại của một yêu cầu, tạo mã mới
/// khi người chơi yêu cầu nhiệm vụ khác. Mỗi lần tao chỉ gửi một HTTP request.
/// maNguoiChoiDemo chỉ dành cho backend đã bật AI_QUEST_DEMO.
/// Client được truyền vào do caller quản lý, có thể gắn xác thực tại tầng đó.
class MayChuNhiemVu {
  final Uri? _diaChi;
  final String? _maNguoiChoiDemo;
  final http.Client? client;
  final Duration thoiGianCho;

  static final _maHopLe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  MayChuNhiemVu({
    String mayChu = const String.fromEnvironment('GOLD_RUSH_API'),
    String? maNguoiChoiDemo,
    this.client,
    this.thoiGianCho = const Duration(seconds: 15),
  }) : _diaChi = _diaChiApi(mayChu),
       _maNguoiChoiDemo = maNguoiChoiDemo {
    if (maNguoiChoiDemo != null && !_maHopLe.hasMatch(maNguoiChoiDemo)) {
      throw ArgumentError('Mã người chơi demo không hợp lệ');
    }
    if (thoiGianCho <= Duration.zero ||
        thoiGianCho > const Duration(seconds: 60)) {
      throw ArgumentError('Thời gian chờ phải nằm trong (0, 60] giây');
    }
  }

  Future<KetQuaNhiemVu> tao({
    required int manChoi,
    required String maYeuCau,
  }) async {
    if (manChoi < 1 || manChoi > 1000 || !_maHopLe.hasMatch(maYeuCau)) {
      return const KetQuaNhiemVu._(loi: LoiNhiemVu.yeuCauKhongHopLe);
    }
    final diaChi = _diaChi;
    if (diaChi == null) {
      return const KetQuaNhiemVu._(loi: LoiNhiemVu.chuaCauHinh);
    }
    final httpClient = client ?? http.Client();
    final huy = Completer<void>();
    try {
      return await _gui(
        httpClient,
        diaChi,
        manChoi,
        maYeuCau,
        huy.future,
      ).timeout(thoiGianCho);
    } on TimeoutException {
      return const KetQuaNhiemVu._(loi: LoiNhiemVu.hetThoiGian);
    } on http.ClientException {
      return const KetQuaNhiemVu._(loi: LoiNhiemVu.ketNoi);
    } on FormatException {
      return const KetQuaNhiemVu._(loi: LoiNhiemVu.phanHoiKhongHopLe);
    } finally {
      huy.complete();
      if (client == null) httpClient.close();
    }
  }

  Future<KetQuaNhiemVu> _gui(
    http.Client client,
    Uri diaChi,
    int manChoi,
    String maYeuCau,
    Future<void> huy,
  ) async {
    final request = http.AbortableRequest('POST', diaChi, abortTrigger: huy)
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Idempotency-Key': maYeuCau,
        if (_maNguoiChoiDemo != null) 'X-Demo-Player': _maNguoiChoiDemo,
      })
      ..body = jsonEncode({'stage_id': manChoi});
    final response = await client.send(request);
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      return KetQuaNhiemVu._(
        loi: response.statusCode >= 500
            ? LoiNhiemVu.mayChu
            : LoiNhiemVu.biTuChoi,
        maHttp: response.statusCode,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 65536) {
        throw const FormatException('Phản hồi nhiệm vụ quá lớn');
      }
      bytes.addAll(chunk);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Phản hồi nhiệm vụ phải là object');
    }
    final nv = NhiemVu.tuJson(json);
    if (nv.manChoi != manChoi) {
      throw const FormatException('Nhiệm vụ không khớp màn đã yêu cầu');
    }
    return KetQuaNhiemVu._(nhiemVu: nv, maHttp: response.statusCode);
  }
}

Uri? _diaChiApi(String mayChu) {
  if (mayChu.isEmpty) return null;
  final uri = Uri.tryParse(mayChu);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('Địa chỉ máy chủ nhiệm vụ không hợp lệ');
  }
  return uri.replace(
    path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/api/ai/nhiem-vu/tao',
  );
}
