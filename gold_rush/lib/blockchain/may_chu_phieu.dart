import 'dart:convert';

import 'package:http/http.dart' as http;

import 'abi.dart';
import 'cua_hang.dart';
import 'vi.dart';

/// Cấu hình chuỗi do máy chủ công bố: mạng nào, hợp đồng nào.
class CauHinhChuoi {
  final int chainId;
  final String hopDong;
  final String trongTai;

  const CauHinhChuoi({
    required this.chainId,
    required this.hopDong,
    required this.trongTai,
  });
}

/// Gọi máy chủ trọng tài `gold_rush_ai`: cấu hình, bắt đầu màn có cọc, xin phiếu, phiếu chờ nhận.
///
/// Địa chỉ máy chủ dùng chung `--dart-define=GOLD_RUSH_API` với phần gửi nhật ký.
class MayChuPhieu {
  final String mayChu;
  final http.Client _client;
  static const Duration _hetGio = Duration(seconds: 10);

  MayChuPhieu({required this.mayChu, http.Client? client}) : _client = client ?? http.Client();

  Future<CauHinhChuoi> cauHinh() async {
    final j = await _json(() => _client.get(Uri.parse('$mayChu/api/vang/cau-hinh')));
    return CauHinhChuoi(
      chainId: j['chain_id'] as int,
      hopDong: j['hop_dong'] as String,
      trongTai: j['trong_tai'] as String,
    );
  }

  /// Đăng ký bắt đầu màn có cọc NGAY TRƯỚC khi chơi. Mỗi vé chỉ đăng ký được MỘT lần (409 nếu đã dùng).
  Future<void> batDauMan({
    required String maVan,
    required String vi,
    required int man,
    required int ve,
  }) async {
    await _json(
      () => _client.post(
        Uri.parse('$mayChu/api/man/bat-dau'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'ma_van': maVan, 'vi': vi, 'man': man, 've': ve}),
      ),
      thanhCong: 201,
      khi409: 'Vé này đã dùng cho một ván — cần vào màn bằng vé mới.',
    );
  }

  /// Vé (ví, số vé) đã được dùng để bắt đầu một ván chưa.
  Future<bool> veDaDung({required String vi, required int ve}) async {
    final j = await _json(() => _client.get(Uri.parse('$mayChu/api/man/ve?vi=$vi&ve=$ve')));
    return j['da_dung'] == true;
  }

  /// Xin phiếu cho một ván. Xin lại cùng ván = máy chủ ký lại đúng nội dung với hạn mới.
  Future<PhieuCho> xinPhieu({required String maVan, required String vi}) async {
    final j = await _json(
      () => _client.post(
        Uri.parse('$mayChu/api/vang/phieu'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'ma_van': maVan, 'vi': vi}),
      ),
      khi409: 'Ván này đã cấp phiếu cho một ví khác.',
    );
    return _doc(() => _phieuTu(j, maVan));
  }

  /// Mọi phiếu đã cấp cho ví trong 7 ngày (đã ký lại hạn mới) — app tự lọc phiếu đã nhận.
  Future<List<PhieuCho>> phieuChoNhan(String vi) async {
    final j = await _json(() => _client.get(Uri.parse('$mayChu/api/vang/cho-nhan?vi=$vi')));
    return _doc(() => [
          for (final p in j['phieu'] as List<dynamic>)
            _phieuTu(p as Map<String, dynamic>, p['ma_van'] as String),
        ]);
  }

  /// Dữ liệu máy chủ sai dạng (khác phiên bản?) → LoiVi, không để TypeError lọt ra ngoài.
  T _doc<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      throw const LoiVi('Máy chủ trả dữ liệu không đúng dạng — app và máy chủ có cùng phiên bản không?');
    }
  }

  PhieuCho _phieuTu(Map<String, dynamic> j, String maVan) => PhieuCho(
        phieu: PhieuVang.tuJson(j['phieu'] as Map<String, dynamic>),
        chuKy: j['chu_ky'] as String,
        maVan: maVan,
      );

  Future<Map<String, dynamic>> _json(
    Future<http.Response> Function() goi, {
    int thanhCong = 200,
    String khi409 = 'Xung đột dữ liệu trên máy chủ.',
  }) async {
    final http.Response r;
    try {
      r = await goi().timeout(_hetGio);
    } catch (_) {
      throw LoiVi('Không liên lạc được máy chủ trọng tài ($mayChu). Kiểm tra uvicorn đang chạy.');
    }
    final than = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (r.statusCode == thanhCong) return _doc(() => jsonDecode(than) as Map<String, dynamic>);
    final chiTiet = switch (r.statusCode) {
      404 => 'Máy chủ chưa có nhật ký ván này — chơi xong một ván khi đã cấu hình máy chủ.',
      409 => khi409,
      422 => 'Máy chủ không công nhận ván này: ${lyDoTu(than)}',
      429 => 'Ví đã nhận đủ vàng hôm nay.',
      503 => 'Máy chủ chưa bật cửa hàng (thiếu khoá trọng tài, địa chỉ hợp đồng hoặc man_choi.json).',
      _ => 'Máy chủ trả về lỗi ${r.statusCode}.',
    };
    throw LoiVi(chiTiet, ma: r.statusCode); // ma = mã HTTP (409: vé/ván đã dùng)
  }
}

/// `{"detail": {"ly_do": ["…", …]}}` hoặc `{"detail": "…"}` → câu đầu tiên đọc được.
String lyDoTu(String than) {
  try {
    final d = (jsonDecode(than) as Map<String, dynamic>)['detail'];
    if (d is Map && d['ly_do'] is List && (d['ly_do'] as List).isNotEmpty) {
      return '${(d['ly_do'] as List).first}';
    }
    if (d is String) return d;
    if (d is List && d.isNotEmpty) return '${(d.first as Map?)?['msg'] ?? d.first}';
  } catch (_) {
    // không phải JSON
  }
  return than.length > 160 ? '${than.substring(0, 160)}…' : than;
}
