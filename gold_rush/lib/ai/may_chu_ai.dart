import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum LoiApiAi {
  chuaCauHinh,
  yeuCauKhongHopLe,
  hetThoiGian,
  ketNoi,
  biTuChoi,
  mayChu,
  phanHoiKhongHopLe,
}

class KetQuaApiAi {
  final Map<String, dynamic>? duLieu;
  final LoiApiAi? loi;
  final int? maHttp;

  const KetQuaApiAi._({this.duLieu, this.loi, this.maHttp});
}

/// Gọi JSON cho các API AI. Client truyền vào do caller quản lý.
/// Mỗi lần gọi gửi một request, timeout hủy riêng request đó qua abort trigger.
class MayChuAi {
  final Uri? _mayChu;
  final String? _maNguoiChoiDemo;
  final http.Client? client;
  final Duration thoiGianCho;

  MayChuAi({
    String mayChu = const String.fromEnvironment('GOLD_RUSH_API'),
    String? maNguoiChoiDemo,
    this.client,
    this.thoiGianCho = const Duration(seconds: 15),
  }) : _mayChu = _kiemTraMayChu(mayChu),
       _maNguoiChoiDemo = maNguoiChoiDemo {
    if (maNguoiChoiDemo != null &&
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(maNguoiChoiDemo)) {
      throw ArgumentError('Mã người chơi demo không hợp lệ');
    }
    if (thoiGianCho <= Duration.zero ||
        thoiGianCho > const Duration(seconds: 60)) {
      throw ArgumentError('Thời gian chờ phải nằm trong (0, 60] giây');
    }
  }

  Future<KetQuaApiAi> postJson(
    String duongDan, {
    required Map<String, Object> body,
    Map<String, String> headers = const {},
  }) async {
    final mayChu = _mayChu;
    if (mayChu == null) {
      return const KetQuaApiAi._(loi: LoiApiAi.chuaCauHinh);
    }
    final diaChi = mayChu.replace(
      path: '${mayChu.path.replaceFirst(RegExp(r'/+$'), '')}$duongDan',
    );
    final httpClient = client ?? http.Client();
    final huy = Completer<void>();
    try {
      return await _gui(
        httpClient,
        diaChi,
        body,
        headers,
        huy.future,
      ).timeout(thoiGianCho);
    } on TimeoutException {
      return const KetQuaApiAi._(loi: LoiApiAi.hetThoiGian);
    } on FormatException {
      return const KetQuaApiAi._(loi: LoiApiAi.phanHoiKhongHopLe);
    } on Exception {
      // Gồm lỗi HTTP, socket và TLS của các client nền tảng.
      return const KetQuaApiAi._(loi: LoiApiAi.ketNoi);
    } finally {
      huy.complete();
      if (client == null) httpClient.close();
    }
  }

  Future<KetQuaApiAi> _gui(
    http.Client client,
    Uri diaChi,
    Map<String, Object> body,
    Map<String, String> headers,
    Future<void> huy,
  ) async {
    final request = http.AbortableRequest('POST', diaChi, abortTrigger: huy)
      ..followRedirects = false
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_maNguoiChoiDemo != null) 'X-Demo-Player': _maNguoiChoiDemo,
        ...headers,
      })
      ..body = jsonEncode(body);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      return KetQuaApiAi._(
        loi: response.statusCode >= 500 ? LoiApiAi.mayChu : LoiApiAi.biTuChoi,
        maHttp: response.statusCode,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 65536) {
        throw const FormatException('Phản hồi AI quá lớn');
      }
      bytes.addAll(chunk);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Phản hồi AI phải là object');
    }
    return KetQuaApiAi._(duLieu: json, maHttp: response.statusCode);
  }
}

Uri? _kiemTraMayChu(String mayChu) {
  if (mayChu.isEmpty) return null;
  final uri = Uri.tryParse(mayChu);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('Địa chỉ máy chủ AI không hợp lệ');
  }
  return uri;
}
