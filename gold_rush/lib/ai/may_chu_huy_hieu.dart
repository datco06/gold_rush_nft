import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_boundary.dart';

/// Ghi nhận một ván thắng đủ điều kiện huy hiệu. Cookie SIWE được trình duyệt
/// tự đính kèm; endpoint chỉ mở quyền, còn mint do DichVuSBT thực hiện.
class MayChuHuyHieu {
  final Uri _mayChu;
  final http.Client _client;
  final bool _owned;

  MayChuHuyHieu({
    String mayChu = const String.fromEnvironment(
      'GOLD_RUSH_API',
      defaultValue: 'http://localhost:8000',
    ),
    http.Client? client,
  }) : _mayChu = Uri.parse(mayChu),
       _client = client ?? taoHttpClientTrinhDuyet(),
       _owned = client == null;

  Future<Map<String, dynamic>?> danhGia({
    required String maVan,
    String? csrfToken,
  }) async {
    try {
      final response = await _client
          .post(
            _mayChu.resolve('/api/thanh-tuu/danh-gia'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (csrfToken != null && csrfToken.isNotEmpty)
                'X-CSRF-Token': csrfToken,
            },
            body: jsonEncode({'ma_van': maVan}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      return value is Map<String, dynamic> ? value : null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> taiDanhSach() async {
    try {
      final response = await _client
          .get(_mayChu.resolve('/api/thanh-tuu'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  void dong() {
    if (_owned) _client.close();
  }
}
