import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  final Uint8List? bytes;
  final String? contentType;
  final LoiApiAi? loi;
  final int? maHttp;

  const KetQuaApiAi._({
    this.duLieu,
    this.bytes,
    this.contentType,
    this.loi,
    this.maHttp,
  });
}

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
    final kq = await _goi(
      'POST',
      duongDan,
      body: body,
      headers: headers,
      gioiHanByte: 65536,
    );
    if (kq.loi != null) return kq;
    try {
      final json = jsonDecode(utf8.decode(kq.bytes!));
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Phản hồi AI phải là object');
      }
      return KetQuaApiAi._(duLieu: json, maHttp: kq.maHttp);
    } on FormatException {
      return const KetQuaApiAi._(loi: LoiApiAi.phanHoiKhongHopLe);
    }
  }

  Future<KetQuaApiAi> getBytes(
    String duongDan, {
    Map<String, String> headers = const {},
  }) => _goi('GET', duongDan, headers: headers, gioiHanByte: 1024 * 1024);

  Future<KetQuaApiAi> _goi(
    String method,
    String duongDan, {
    Map<String, Object>? body,
    required Map<String, String> headers,
    required int gioiHanByte,
  }) async {
    final mayChu = _mayChu;
    if (mayChu == null) return const KetQuaApiAi._(loi: LoiApiAi.chuaCauHinh);
    final diaChi = mayChu.replace(
      path: '${mayChu.path.replaceFirst(RegExp(r'/+$'), '')}$duongDan',
    );
    final httpClient = client ?? http.Client();
    final huy = Completer<void>();
    try {
      final request =
          http.AbortableRequest(method, diaChi, abortTrigger: huy.future)
            ..followRedirects = false
            ..headers.addAll({
              if (body != null) 'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (_maNguoiChoiDemo != null) 'X-Demo-Player': _maNguoiChoiDemo,
              ...headers,
            });
      if (body != null) request.body = jsonEncode(body);
      return await _gui(httpClient, request, gioiHanByte).timeout(thoiGianCho);
    } on TimeoutException {
      return const KetQuaApiAi._(loi: LoiApiAi.hetThoiGian);
    } on FormatException {
      return const KetQuaApiAi._(loi: LoiApiAi.phanHoiKhongHopLe);
    } on Exception {
      return const KetQuaApiAi._(loi: LoiApiAi.ketNoi);
    } finally {
      huy.complete();
      if (client == null) httpClient.close();
    }
  }

  Future<KetQuaApiAi> _gui(
    http.Client client,
    http.BaseRequest request,
    int gioiHanByte,
  ) async {
    final response = await client.send(request);
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      return KetQuaApiAi._(
        loi: response.statusCode >= 500 ? LoiApiAi.mayChu : LoiApiAi.biTuChoi,
        maHttp: response.statusCode,
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > gioiHanByte) {
        throw const FormatException('Phản hồi AI quá lớn');
      }
      bytes.add(chunk);
    }
    return KetQuaApiAi._(
      bytes: bytes.takeBytes().asUnmodifiableView(),
      contentType: response.headers['content-type'],
      maHttp: response.statusCode,
    );
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
