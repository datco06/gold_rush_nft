import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'http_client_boundary.dart';

/// Gửi nhật ký ván chơi về máy chủ `gold_rush_ai` (FastAPI, `POST /api/nhat-ky`).
///
/// Địa chỉ máy chủ KHÔNG viết cứng trong mã mà truyền lúc chạy — cùng tinh thần
/// "cấu hình bằng biến môi trường" của notebook AI Web Apps:
///
///     flutter run -d chrome --web-port 5000 --dart-define=GOLD_RUSH_API=http://localhost:8000
///     flutter run --dart-define=GOLD_RUSH_API=http://10.0.2.2:8000     # máy ảo Android
///
/// Không truyền gì thì game chạy offline như bản gốc, không gửi gì cả.
class GuiNhatKy {
  GuiNhatKy._();

  static const String mayChu = String.fromEnvironment(
    'GOLD_RUSH_API',
    defaultValue: 'http://localhost:8000',
  );

  static bool get daCauHinh => mayChu.isNotEmpty;

  /// Gửi một ván, thử lại tối đa 3 lần khi lỗi mạng/máy chủ (máy chủ bỏ qua bản trùng mã ván,
  /// nên gửi lại an toàn). Lỗi KHÔNG BAO GIỜ được làm hỏng trải nghiệm chơi: mọi ngoại lệ bị nuốt.
  static Future<bool> gui(
    Map<String, Object> nhatKy, {
    http.Client? client,
    String? csrfToken,
  }) async {
    if (!daCauHinh) return false;
    final requestClient = client ?? taoHttpClientTrinhDuyet();
    final tuSoHuu = client == null;
    try {
      for (final cho in const [0, 2, 5]) {
        if (cho > 0) await Future<void>.delayed(Duration(seconds: cho));
        final kq = await _guiMotLan(requestClient, nhatKy, csrfToken);
        if (kq != null) return kq;
      }
      return false;
    } finally {
      if (tuSoHuu) requestClient.close();
    }
  }

  /// true = đã lưu · false = máy chủ từ chối (4xx, gửi lại vô ích) · null = lỗi tạm thời, nên thử lại.
  static Future<bool?> _guiMotLan(
    http.Client client,
    Map<String, Object> nhatKy,
    String? csrfToken,
  ) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (csrfToken != null && csrfToken.isNotEmpty)
          'X-CSRF-Token': csrfToken,
      };
      final r = await client
          .post(
            Uri.parse('$mayChu/api/nhat-ky'),
            headers: headers,
            body: jsonEncode(nhatKy),
          )
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 201 || r.statusCode == 200) return true;
      debugPrint('Máy chủ từ chối nhật ký (${r.statusCode}): ${r.body}');
      return r.statusCode >= 500 ? null : false;
    } catch (e) {
      debugPrint('Không gửi được nhật ký: $e');
      return null;
    }
  }
}
