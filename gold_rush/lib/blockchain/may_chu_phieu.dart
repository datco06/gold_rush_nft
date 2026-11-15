import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/http_client_boundary.dart';
import 'abi.dart';
import 'cua_hang.dart';
import 'vi.dart';

/// Cấu hình chuỗi do máy chủ công bố: mạng nào, hợp đồng nào.
class CauHinhChuoi {
  final int chainId;
  final String hopDong;
  final String? hopDongVatPham;
  final String trongTai;

  const CauHinhChuoi({
    required this.chainId,
    required this.hopDong,
    this.hopDongVatPham,
    required this.trongTai,
  });
}

class KetQuaMoRuong {
  final PhieuMoRuong phieu;
  final String loai;
  final int giaTri;
  final int soLuong;

  const KetQuaMoRuong({
    required this.phieu,
    required this.loai,
    required this.giaTri,
    required this.soLuong,
  });

  bool get laVang => loai == 'vang';
}

class PhieuVatPhamQuaTang {
  final String player;
  final int tokenId;
  final int amount;
  final String nonce;
  final int deadline;
  final String signature;
  final int chainId;
  final String contractAddress;

  const PhieuVatPhamQuaTang({
    required this.player,
    required this.tokenId,
    required this.amount,
    required this.nonce,
    required this.deadline,
    required this.signature,
    required this.chainId,
    required this.contractAddress,
  });
}

class KetQuaDoiQuaTang {
  final String claimId;
  final String rewardType;
  final int tokenId;
  final int amount;
  final String name;
  final String imageUrl;
  final String rarity;
  final String status;
  final List<PhieuCho> vouchers;
  final PhieuVatPhamQuaTang? voucher;
  final String? transactionHash;
  final int? goldBalance;

  const KetQuaDoiQuaTang({
    required this.claimId,
    required this.rewardType,
    required this.tokenId,
    required this.amount,
    required this.name,
    required this.imageUrl,
    required this.rarity,
    required this.status,
    this.vouchers = const [],
    this.voucher,
    this.transactionHash,
    this.goldBalance,
  });

  bool get laVang => rewardType == 'gold';
}

/// Gọi máy chủ trọng tài `gold_rush_ai`: cấu hình, bắt đầu màn có cọc, xin phiếu, phiếu chờ nhận.
///
/// Địa chỉ máy chủ dùng chung `--dart-define=GOLD_RUSH_API` với phần gửi nhật ký.
class MayChuPhieu {
  final String mayChu;
  final http.Client _client;
  final String? Function()? layCsrfToken;
  static const Duration _hetGio = Duration(seconds: 10);

  MayChuPhieu({required this.mayChu, http.Client? client, this.layCsrfToken})
    : _client = client ?? taoHttpClientTrinhDuyet();

  Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final csrf = layCsrfToken?.call();
    if (csrf != null && csrf.isNotEmpty) {
      h['X-CSRF-Token'] = csrf;
    }
    return h;
  }

  Future<CauHinhChuoi> cauHinh() async {
    final j = await _json(
      () => _client.get(Uri.parse('$mayChu/api/vang/cau-hinh')),
    );
    return CauHinhChuoi(
      chainId: j['chain_id'] as int,
      hopDong: j['hop_dong'] as String,
      hopDongVatPham: j['hop_dong_vat_pham'] as String?,
      trongTai: j['trong_tai'] as String,
    );
  }

  Future<KetQuaDoiQuaTang> doiMaQuaTang(String ma) async {
    final j = await _json(
      () => _client.post(
        Uri.parse('$mayChu/api/qua-tang/claim'),
        headers: _headers(),
        body: jsonEncode({'ma': ma}),
      ),
      khi409: 'Mã quà tặng đã được dùng hoặc đạt giới hạn.',
    );
    return _doc(() => _quaTangTu(j));
  }

  Future<KetQuaDoiQuaTang> xacNhanQuaTang({
    required String claimId,
    required String transactionHash,
  }) async {
    final j = await _json(
      () => _client.post(
        Uri.parse('$mayChu/api/qua-tang/confirm'),
        headers: _headers(),
        body: jsonEncode({
          'claim_id': claimId,
          'transaction_hash': transactionHash,
        }),
      ),
      khi409: 'Lượt cấp thưởng này đã kết thúc.',
    );
    return _doc(() => _quaTangTu(j));
  }

  Future<KetQuaDoiQuaTang> trangThaiQuaTang(String claimId) async {
    final j = await _json(
      () => _client.get(Uri.parse('$mayChu/api/qua-tang/status/$claimId')),
    );
    return _doc(() => _quaTangTu(j));
  }

  KetQuaDoiQuaTang _quaTangTu(Map<String, dynamic> j) {
    int so(Object? value) => value is int ? value : int.parse('$value');
    final danhSach = <PhieuCho>[];
    for (final raw in (j['vouchers'] as List<dynamic>? ?? const [])) {
      final p = raw as Map<String, dynamic>;
      final phieu = p['phieu'] as Map<String, dynamic>;
      danhSach.add(_phieuTu(p, phieu['maVan'] as String));
    }
    final rawVoucher = j['voucher'] as Map<String, dynamic>?;
    final cauHinh = rawVoucher == null
        ? null
        : PhieuVatPhamQuaTang(
            player: rawVoucher['player'] as String,
            tokenId: so(rawVoucher['tokenId']),
            amount: so(rawVoucher['amount']),
            nonce: rawVoucher['nonce'] as String,
            deadline: so(rawVoucher['deadline']),
            signature: j['signature'] as String,
            chainId: so(j['chainId']),
            contractAddress: j['contractAddress'] as String,
          );
    return KetQuaDoiQuaTang(
      claimId: j['claimId'] as String,
      rewardType: j['rewardType'] as String,
      tokenId: so(j['tokenId']),
      amount: so(j['amount']),
      name: j['name'] as String,
      imageUrl: (j['imageUrl'] as String?) ?? '',
      rarity: (j['rarity'] as String?) ?? '',
      status: j['status'] as String,
      vouchers: danhSach,
      voucher: cauHinh,
      transactionHash: j['transactionHash'] as String?,
      goldBalance: j['goldBalance'] == null ? null : so(j['goldBalance']),
    );
  }

  /// Đồng bộ bản ghi kho đồ NFT theo số dư on-chain mà máy chủ tự xác minh.
  /// Payload chỉ mang metadata hiển thị; số lượng không được tin từ client.
  Future<void> dongBoKhoNFT({
    required List<Map<String, dynamic>> vatPham,
  }) async {
    await _json(
      () => _client.post(
        Uri.parse('$mayChu/api/inventory/sync-nft'),
        headers: _headers(),
        body: jsonEncode({'vat_pham': vatPham}),
      ),
      khi409: 'Không thể đồng bộ quyền sở hữu NFT lúc này.',
    );
  }

  Future<KetQuaMoRuong> moRuong({required String vi}) async {
    final j = await _json(
      () => _client.post(
        Uri.parse('$mayChu/api/rung-ruong/ket-qua'),
        headers: _headers(),
        body: jsonEncode({'vi': vi}),
      ),
      khi409: 'Rương này đã được xử lý.',
    );
    final p = j['phieu'] as Map<String, dynamic>;
    final thuong = j['phan_thuong'] as Map<String, dynamic>;
    return KetQuaMoRuong(
      phieu: PhieuMoRuong(
        nguoiChoi: p['nguoiChoi'] as String,
        loai: p['loai'] as int,
        giaTri: p['giaTri'] as int,
        soLuong: p['soLuong'] as int,
        maRuong: p['maRuong'] as String,
        hanChot: p['hanChot'] as int,
        chuKy: j['chu_ky'] as String,
      ),
      loai: thuong['loai'] as String,
      giaTri: thuong['gia_tri'] as int,
      soLuong: thuong['so_luong'] as int,
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
        headers: _headers(),
        body: jsonEncode({'ma_van': maVan, 'vi': vi, 'man': man, 've': ve}),
      ),
      thanhCong: 201,
      khi409: 'Vé này đã dùng cho một ván — cần vào màn bằng vé mới.',
    );
  }

  /// Vé (ví, số vé) đã được dùng để bắt đầu một ván chưa.
  Future<bool> veDaDung({required String vi, required int ve}) async {
    final j = await _json(
      () => _client.get(Uri.parse('$mayChu/api/man/ve?vi=$vi&ve=$ve')),
    );
    return j['da_dung'] == true;
  }

  /// Xin phiếu cho một ván. Xin lại cùng ván = máy chủ ký lại đúng nội dung với hạn mới.
  Future<PhieuCho> xinPhieu({required String maVan, required String vi}) async {
    final j = await _json(
      () => _client.post(
        Uri.parse('$mayChu/api/vang/phieu'),
        headers: _headers(),
        body: jsonEncode({'ma_van': maVan, 'vi': vi}),
      ),
      khi409: 'Ván này đã cấp phiếu cho một ví khác.',
    );
    return _doc(() => _phieuTu(j, maVan));
  }

  /// Mọi phiếu đã cấp cho ví trong 7 ngày (đã ký lại hạn mới) — app tự lọc phiếu đã nhận.
  Future<List<PhieuCho>> phieuChoNhan(String vi) async {
    final j = await _json(
      () => _client.get(Uri.parse('$mayChu/api/vang/cho-nhan?vi=$vi')),
    );
    return _doc(
      () => [
        for (final p in j['phieu'] as List<dynamic>)
          _phieuTu(p as Map<String, dynamic>, p['ma_van'] as String),
      ],
    );
  }

  /// Dữ liệu máy chủ sai dạng (khác phiên bản?) → LoiVi, không để TypeError lọt ra ngoài.
  T _doc<T>(T Function() f) {
    try {
      return f();
    } catch (_) {
      throw const LoiVi(
        'Máy chủ trả dữ liệu không đúng dạng — app và máy chủ có cùng phiên bản không?',
      );
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
      throw LoiVi(
        'Không liên lạc được máy chủ trọng tài ($mayChu). Kiểm tra uvicorn đang chạy.',
      );
    }
    final than = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (r.statusCode == thanhCong)
      return _doc(() => jsonDecode(than) as Map<String, dynamic>);
    final chiTiet = switch (r.statusCode) {
      404 => 'Máy chủ chưa có nhật ký ván này — chơi xong một ván khi đã cấu hình máy chủ.',
      410 => 'Mã quà tặng đã hết hạn.',
      409 => khi409,
      422 => 'Máy chủ không công nhận ván này: ${lyDoTu(than)}',
      429 => 'Ví đã nhận đủ vàng hôm nay.',
      503 => 'Máy chủ chưa bật cửa hàng (thiếu khoá trọng tài, địa chỉ hợp đồng hoặc man_choi.json).',
      _ => 'Máy chủ trả về lỗi ${r.statusCode}.',
    };
    throw LoiVi(
      chiTiet,
      ma: r.statusCode,
    ); // ma = mã HTTP (409: vé/ván đã dùng)
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
    if (d is List && d.isNotEmpty)
      return '${(d.first as Map?)?['msg'] ?? d.first}';
  } catch (_) {
    // không phải JSON
  }
  return than.length > 160 ? '${than.substring(0, 160)}…' : than;
}
