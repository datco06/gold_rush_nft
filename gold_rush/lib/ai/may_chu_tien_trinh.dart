import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_boundary.dart';
import 'tien_trinh_models.dart';

enum LoiTienTrinh {
  hetPhien, // 401: Session hết hạn hoặc chưa đăng nhập SIWE
  quyen, // 403: Không có quyền truy cập, CSRF sai, hoặc sai ví
  trungBangChung, // 409: Bằng chứng đã được sử dụng (Replay Attack)
  khongTimThay, // 404: Màn chơi chưa hoàn thành
  khongHopLe, // 422: Payload hoặc bằng chứng không hợp lệ
  mayChu, // 500-599: Lỗi nội bộ hoặc RPC chưa sẵn sàng
  ketNoi, // Mất mạng / không kết nối được
  hetThoiGian, // Quá thời gian chờ
  phanHoiKhongHopLe, // JSON sai định dạng
}

class KetQuaTienTrinh {
  final PhanHoiTienTrinh? tienTrinh;
  final LoiTienTrinh? loi;
  final int? maHttp;
  final String? chiTietLoi;

  const KetQuaTienTrinh({
    this.tienTrinh,
    this.loi,
    this.maHttp,
    this.chiTietLoi,
  });

  bool get thanhCong => tienTrinh != null;
  bool get hetPhien => loi == LoiTienTrinh.hetPhien || maHttp == 401;
  bool get chuaSanSang => loi == LoiTienTrinh.mayChu || maHttp == 503;
  bool get matMang => loi == LoiTienTrinh.ketNoi || loi == LoiTienTrinh.hetThoiGian;
}

class KetQuaBanGhiTienTrinh {
  final BanGhiTienTrinh? banGhi;
  final LoiTienTrinh? loi;
  final int? maHttp;
  final String? chiTietLoi;

  const KetQuaBanGhiTienTrinh({
    this.banGhi,
    this.loi,
    this.maHttp,
    this.chiTietLoi,
  });

  bool get thanhCong => banGhi != null;
  bool get trungBangChung => loi == LoiTienTrinh.trungBangChung || maHttp == 409;
  bool get hetPhien => loi == LoiTienTrinh.hetPhien || maHttp == 401;
  bool get chuaSanSang => loi == LoiTienTrinh.mayChu || maHttp == 503;
}

/// Client HTTP tương tác với API tiến trình người chơi SIWE (`/api/ai/tien-trinh`).
class MayChuTienTrinh {
  final Uri _mayChu;
  final http.Client _client;
  final bool _ownedClient;
  final Duration thoiGianCho;

  MayChuTienTrinh({
    String mayChu = const String.fromEnvironment(
      'GOLD_RUSH_API',
      defaultValue: 'http://localhost:8000',
    ),
    http.Client? client,
    this.thoiGianCho = const Duration(seconds: 15),
  })  : _mayChu = _chuanHoaMayChu(mayChu),
        _client = client ?? taoHttpClientTrinhDuyet(),
        _ownedClient = client == null;

  static Uri _chuanHoaMayChu(String diaChi) {
    var raw = diaChi.trim();
    if (raw.isEmpty) raw = 'http://localhost:8000';
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'http://$raw';
    }
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError('Địa chỉ máy chủ API không hợp lệ: $diaChi');
    }
    return uri;
  }

  void dong() {
    if (_ownedClient) {
      _client.close();
    }
  }

  /// Lấy tổng quan tiến trình 6 màn chơi của người chơi SIWE hiện tại.
  Future<KetQuaTienTrinh> layTienTrinh() async {
    final uri = _mayChu.resolve('/api/ai/tien-trinh');
    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(thoiGianCho);

      final status = response.statusCode;
      final bodyText = utf8.decode(response.bodyBytes);

      if (status == 200) {
        final decoded = jsonDecode(bodyText);
        if (decoded is! Map<String, dynamic>) {
          return const KetQuaTienTrinh(
            loi: LoiTienTrinh.phanHoiKhongHopLe,
            maHttp: 200,
            chiTietLoi: 'Phản hồi không phải là JSON Object',
          );
        }
        return KetQuaTienTrinh(
          tienTrinh: PhanHoiTienTrinh.tuJson(decoded),
          maHttp: 200,
        );
      }

      final detail = _docChiTietLoi(bodyText);
      return KetQuaTienTrinh(
        loi: _chuyenMaLoi(status),
        maHttp: status,
        chiTietLoi: detail,
      );
    } on TimeoutException {
      return const KetQuaTienTrinh(
        loi: LoiTienTrinh.hetThoiGian,
        chiTietLoi: 'Quá thời gian kết nối máy chủ tiến trình',
      );
    } on FormatException catch (e) {
      return KetQuaTienTrinh(
        loi: LoiTienTrinh.phanHoiKhongHopLe,
        chiTietLoi: e.message,
      );
    } catch (e) {
      return KetQuaTienTrinh(
        loi: LoiTienTrinh.ketNoi,
        chiTietLoi: e.toString(),
      );
    }
  }

  /// Lấy chi tiết bằng chứng hoàn thành của một màn cụ thể (1–6).
  Future<KetQuaBanGhiTienTrinh> layChiTietTienTrinh(int stageId) async {
    if (stageId < 1 || stageId > 6) {
      return const KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.khongHopLe,
        chiTietLoi: 'stageId phải từ 1 đến 6',
      );
    }
    final uri = _mayChu.resolve('/api/ai/tien-trinh/$stageId');
    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(thoiGianCho);

      final status = response.statusCode;
      final bodyText = utf8.decode(response.bodyBytes);

      if (status == 200) {
        final decoded = jsonDecode(bodyText);
        if (decoded is! Map<String, dynamic>) {
          return const KetQuaBanGhiTienTrinh(
            loi: LoiTienTrinh.phanHoiKhongHopLe,
            maHttp: 200,
            chiTietLoi: 'Phản hồi không phải là JSON Object',
          );
        }
        return KetQuaBanGhiTienTrinh(
          banGhi: BanGhiTienTrinh.tuJson(decoded),
          maHttp: 200,
        );
      }

      final detail = _docChiTietLoi(bodyText);
      return KetQuaBanGhiTienTrinh(
        loi: _chuyenMaLoi(status),
        maHttp: status,
        chiTietLoi: detail,
      );
    } on TimeoutException {
      return const KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.hetThoiGian,
        chiTietLoi: 'Quá thời gian kết nối máy chủ tiến trình',
      );
    } on FormatException catch (e) {
      return KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.phanHoiKhongHopLe,
        chiTietLoi: e.message,
      );
    } catch (e) {
      return KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.ketNoi,
        chiTietLoi: e.toString(),
      );
    }
  }

  /// Gửi bằng chứng xác minh hoàn thành màn chơi (referee_log hoặc blockchain_tx).
  Future<KetQuaBanGhiTienTrinh> xacMinhManChoi({
    required int stageId,
    required String evidenceType,
    required String evidence,
    String? csrfToken,
  }) async {
    if (stageId < 1 || stageId > 6) {
      return const KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.khongHopLe,
        chiTietLoi: 'stageId phải từ 1 đến 6',
      );
    }
    if (evidenceType != 'referee_log' && evidenceType != 'blockchain_tx') {
      return const KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.khongHopLe,
        chiTietLoi: 'evidenceType phải là referee_log hoặc blockchain_tx',
      );
    }
    final trimmedEvidence = evidence.trim();
    if (trimmedEvidence.length < 8 || trimmedEvidence.length > 128) {
      return const KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.khongHopLe,
        chiTietLoi: 'Độ dài bằng chứng phải từ 8 đến 128 ký tự',
      );
    }

    final uri = _mayChu.resolve('/api/ai/tien-trinh/xac-minh');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (csrfToken != null && csrfToken.isNotEmpty) 'X-CSRF-Token': csrfToken,
    };
    final body = jsonEncode({
      'stage_id': stageId,
      'evidence_type': evidenceType,
      'evidence': trimmedEvidence,
    });

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(thoiGianCho);

      final status = response.statusCode;
      final bodyText = utf8.decode(response.bodyBytes);

      if (status == 200) {
        final decoded = jsonDecode(bodyText);
        if (decoded is! Map<String, dynamic>) {
          return const KetQuaBanGhiTienTrinh(
            loi: LoiTienTrinh.phanHoiKhongHopLe,
            maHttp: 200,
            chiTietLoi: 'Phản hồi không phải là JSON Object',
          );
        }
        return KetQuaBanGhiTienTrinh(
          banGhi: BanGhiTienTrinh.tuJson(decoded),
          maHttp: 200,
        );
      }

      final detail = _docChiTietLoi(bodyText);
      return KetQuaBanGhiTienTrinh(
        loi: _chuyenMaLoi(status),
        maHttp: status,
        chiTietLoi: detail,
      );
    } on TimeoutException {
      return const KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.hetThoiGian,
        chiTietLoi: 'Quá thời gian chờ phản hồi xác minh tiến trình',
      );
    } on FormatException catch (e) {
      return KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.phanHoiKhongHopLe,
        chiTietLoi: e.message,
      );
    } catch (e) {
      return KetQuaBanGhiTienTrinh(
        loi: LoiTienTrinh.ketNoi,
        chiTietLoi: e.toString(),
      );
    }
  }

  static LoiTienTrinh _chuyenMaLoi(int status) {
    switch (status) {
      case 401:
        return LoiTienTrinh.hetPhien;
      case 403:
        return LoiTienTrinh.quyen;
      case 404:
        return LoiTienTrinh.khongTimThay;
      case 409:
        return LoiTienTrinh.trungBangChung;
      case 422:
        return LoiTienTrinh.khongHopLe;
      default:
        return LoiTienTrinh.mayChu;
    }
  }

  static String? _docChiTietLoi(String bodyText) {
    if (bodyText.isEmpty) return null;
    try {
      final decoded = jsonDecode(bodyText);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is Map<String, dynamic>) {
          return detail['message'] as String? ?? detail.toString();
        }
      }
    } catch (_) {}
    return bodyText;
  }
}

