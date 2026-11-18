import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_boundary.dart';
import '../blockchain/sbt/sbt_service.dart';

/// Ghi nhận một ván thắng đủ điều kiện huy hiệu. Cookie SIWE được trình duyệt
/// tự đính kèm; endpoint chỉ mở quyền, còn mint do DichVuSBT thực hiện.
class MayChuHuyHieu implements NguonPhieuSBT {
  final Uri _mayChu;
  final http.Client _client;
  final String? Function()? layCsrfToken;
  final bool _owned;

  MayChuHuyHieu({
    String mayChu = const String.fromEnvironment(
      'GOLD_RUSH_API',
      defaultValue: 'http://localhost:8000',
    ),
    http.Client? client,
    this.layCsrfToken,
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

  @override
  Future<PhieuSBTDaKy> xinPhieu({
    required String player,
    required int achievementId,
    required int chainId,
    required String hopDong,
  }) async {
    final response = await _client
        .post(
          _mayChu.resolve('/api/thanh-tuu/phieu'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if (layCsrfToken?.call() case final csrf? when csrf.isNotEmpty)
              'X-CSRF-Token': csrf,
          },
          body: jsonEncode({'achievement_id': achievementId}),
        )
        .timeout(const Duration(seconds: 8));
    final value = _decodeResponse(response);
    final responseChainId = value['chainId'];
    final responseContract = value['hopDong'];
    if (responseChainId != chainId ||
        responseContract is! String ||
        responseContract.toLowerCase() != hopDong.toLowerCase()) {
      throw const FormatException('Phiếu SBT không khớp mạng hoặc hợp đồng.');
    }
    return PhieuSBTDaKy(
      phieu: PhieuSBT.fromJson(
        Map<String, dynamic>.from(value['phieu'] as Map),
      ),
      chuKy: value['chuKy'] as String,
      cauHinh: CauHinhSBT(chainId: chainId, hopDong: hopDong),
    );
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw StateError(
        'Backend không cấp được phiếu SBT (${response.statusCode}).',
      );
    }
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException(
        'Backend trả dữ liệu phiếu SBT không hợp lệ.',
      );
    }
    return value;
  }

  void dong() {
    if (_owned) _client.close();
  }
}
