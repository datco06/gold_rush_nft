import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'anh_nhan_vat.dart';
import 'http_client_boundary.dart';
import 'may_chu_ai.dart';
import 'nhan_vat_ai_models.dart';

typedef LoiAnhNhanVat = LoiApiAi;

class KetQuaAnhNhanVat {
  final AnhNhanVat? anh;
  final Uint8List? png;
  final LoiAnhNhanVat? loi;
  final int? maHttp;

  const KetQuaAnhNhanVat._({this.anh, this.png, this.loi, this.maHttp});

  bool get coTheThuLai =>
      loi == LoiAnhNhanVat.hetThoiGian ||
      loi == LoiAnhNhanVat.ketNoi ||
      loi == LoiAnhNhanVat.mayChu ||
      maHttp == 429;
}

class KetQuaKiemTraPhien {
  final NguoiDungAuth? nguoiDung;
  final LoiAnhNhanVat? loi;
  final int? maHttp;

  const KetQuaKiemTraPhien({this.nguoiDung, this.loi, this.maHttp});

  bool get daXacThuc => nguoiDung != null;
}

class KetQuaAuthChallenge {
  final String? challengeId;
  final String? message;
  final LoiAnhNhanVat? loi;
  final int? maHttp;

  const KetQuaAuthChallenge({this.challengeId, this.message, this.loi, this.maHttp});
}

class KetQuaAuthVerify {
  final NguoiDungAuth? nguoiDung;
  final LoiAnhNhanVat? loi;
  final int? maHttp;
  final String? thongBao;

  const KetQuaAuthVerify({this.nguoiDung, this.loi, this.maHttp, this.thongBao});
}

class KetQuaLuuNhanVat {
  final ThongTinNhanVat? nhanVat;
  final LoiAnhNhanVat? loi;
  final int? maHttp;
  final String? chiTietLoi;

  const KetQuaLuuNhanVat({this.nhanVat, this.loi, this.maHttp, this.chiTietLoi});

  bool get thanhCong => nhanVat != null;
}

class KetQuaDanhSachNhanVat {
  final List<ThongTinNhanVat> danhSach;
  final LoiAnhNhanVat? loi;
  final int? maHttp;
  final String? chiTietLoi;

  const KetQuaDanhSachNhanVat({
    this.danhSach = const [],
    this.loi,
    this.maHttp,
    this.chiTietLoi,
  });

  bool get thanhCong => loi == null;
}

class KetQuaKyVoucher {
  final PhanHoiKyVoucherModel? phieu;
  final LoiAnhNhanVat? loi;
  final int? maHttp;
  final String? chiTietLoi;

  const KetQuaKyVoucher({this.phieu, this.loi, this.maHttp, this.chiTietLoi});

  bool get thanhCong => phieu != null;
}

class KetQuaXacMinhOnchain {
  final ThongTinNhanVat? nhanVat;
  final LoiAnhNhanVat? loi;
  final int? maHttp;
  final String? chiTietLoi;

  const KetQuaXacMinhOnchain({this.nhanVat, this.loi, this.maHttp, this.chiTietLoi});

  bool get thanhCong => nhanVat != null;
}

class MayChuNhanVat {
  final MayChuAi _api;
  final http.Client? _ownedClient;

  MayChuNhanVat({
    String mayChu = const String.fromEnvironment('GOLD_RUSH_API'),
    String? maNguoiChoiDemo,
    http.Client? client,
    Duration thoiGianCho = const Duration(seconds: 15),
  }) : this._(
         mayChu: mayChu,
         maNguoiChoiDemo: maNguoiChoiDemo,
         client: client ?? taoHttpClientTrinhDuyet(),
         ownedClient: client == null,
         thoiGianCho: thoiGianCho,
       );

  MayChuNhanVat._({
    required String mayChu,
    required String? maNguoiChoiDemo,
    required http.Client client,
    required bool ownedClient,
    required Duration thoiGianCho,
  }) : _ownedClient = ownedClient ? client : null,
       _api = MayChuAi(
         mayChu: mayChu,
         maNguoiChoiDemo: maNguoiChoiDemo,
         client: client,
         thoiGianCho: thoiGianCho,
       );

  void dong() {
    _ownedClient?.close();
  }

  Uri? get mayChu => _api.mayChu;

  // --------------------------------------------------------------------------
  // Tạo và Tải Preview Ảnh Nhân Vật
  // --------------------------------------------------------------------------

  Future<KetQuaAnhNhanVat> tao({
    required String moTa,
    required String maYeuCau,
  }) async {
    final noiDung = moTa.trim();
    if (!_moTaHopLe(noiDung) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(maYeuCau)) {
      return const KetQuaAnhNhanVat._(loi: LoiAnhNhanVat.yeuCauKhongHopLe);
    }
    final kq = await _api.postJson(
      '/api/ai/nhan-vat/tao',
      body: {'description': noiDung},
      headers: {'Idempotency-Key': maYeuCau},
    );
    if (kq.loi != null) {
      return KetQuaAnhNhanVat._(loi: kq.loi, maHttp: kq.maHttp);
    }
    try {
      return KetQuaAnhNhanVat._(
        anh: AnhNhanVat.tuJson(kq.duLieu!),
        maHttp: kq.maHttp,
      );
    } on FormatException {
      return const KetQuaAnhNhanVat._(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  Future<KetQuaAnhNhanVat> tai(AnhNhanVat anh) async {
    final kq = await _api.getBytes(
      anh.duongDanAnh,
      headers: const {'Accept': 'image/png'},
    );
    if (kq.loi != null) {
      return KetQuaAnhNhanVat._(loi: kq.loi, maHttp: kq.maHttp);
    }
    try {
      if (kq.contentType?.split(';').first.trim().toLowerCase() !=
          'image/png') {
        throw const FormatException('Phản hồi ảnh cần image/png');
      }
      final png = kq.bytes!;
      _kiemTraHeader(png, anh);
      final codec = await ui.instantiateImageCodec(png);
      try {
        if (codec.frameCount != 1) {
          throw const FormatException('Preview cần ảnh tĩnh');
        }
        final frame = await codec.getNextFrame();
        try {
          if (frame.image.width != anh.chieuRong ||
              frame.image.height != anh.chieuCao) {
            throw const FormatException('Kích thước ảnh không khớp metadata');
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      return KetQuaAnhNhanVat._(anh: anh, png: png, maHttp: kq.maHttp);
    } on Exception {
      return const KetQuaAnhNhanVat._(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  // --------------------------------------------------------------------------
  // Quản lý Phiên SIWE & CSRF (/api/me, /api/auth)
  // --------------------------------------------------------------------------

  /// Đọc phiên người dùng hiện tại và CSRF token qua `/api/me`.
  Future<KetQuaKiemTraPhien> kiemTraPhien() async {
    final kq = await _api.getJson('/api/me');
    if (kq.loi != null) {
      return KetQuaKiemTraPhien(loi: kq.loi, maHttp: kq.maHttp);
    }
    try {
      final duLieu = kq.duLieu!;
      return KetQuaKiemTraPhien(
        nguoiDung: NguoiDungAuth.tuJson(duLieu),
        maHttp: kq.maHttp,
      );
    } catch (_) {
      return const KetQuaKiemTraPhien(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  /// Yêu cầu challenge SIWE từ Backend qua `POST /api/auth/challenge`.
  Future<KetQuaAuthChallenge> taoChallenge({
    required String diaChiVi,
    required int chainId,
  }) async {
    final kq = await _api.postJson(
      '/api/auth/challenge',
      body: {'wallet_address': diaChiVi, 'chain_id': chainId},
      headers: {'X-Gold-Rush-Auth': '1'},
    );
    if (kq.loi != null) {
      return KetQuaAuthChallenge(loi: kq.loi, maHttp: kq.maHttp);
    }
    final d = kq.duLieu;
    if (d == null || d['challenge_id'] is! String || d['message'] is! String) {
      return const KetQuaAuthChallenge(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
    return KetQuaAuthChallenge(
      challengeId: d['challenge_id'] as String,
      message: d['message'] as String,
      maHttp: kq.maHttp,
    );
  }

  /// Xác minh chữ ký SIWE qua `POST /api/auth/verify`.
  Future<KetQuaAuthVerify> xacMinhSiwe({
    required String challengeId,
    required String message,
    required String signature,
  }) async {
    final kq = await _api.postJson(
      '/api/auth/verify',
      body: {
        'challenge_id': challengeId,
        'message': message,
        'signature': signature,
      },
      headers: {'X-Gold-Rush-Auth': '1'},
    );
    if (kq.loi != null) {
      return KetQuaAuthVerify(loi: kq.loi, maHttp: kq.maHttp);
    }
    final d = kq.duLieu;
    if (d == null) {
      return const KetQuaAuthVerify(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
    if (d['user'] is Map<String, dynamic>) {
      return KetQuaAuthVerify(
        nguoiDung: NguoiDungAuth.tuJson(d),
        maHttp: kq.maHttp,
      );
    }
    return KetQuaAuthVerify(maHttp: kq.maHttp, thongBao: 'Cần đăng ký tài khoản');
  }

  /// Đăng xuất phiên hiện tại qua `POST /api/auth/logout`.
  Future<bool> dangXuat({String? csrfToken}) async {
    final kq = await _api.postJson(
      '/api/auth/logout',
      body: {},
      headers: {
        'X-CSRF-Token': ?csrfToken,
      },
    );
    return kq.loi == null || kq.maHttp == 200 || kq.maHttp == 204;
  }

  // --------------------------------------------------------------------------
  // Lưu & Quản lý Nhân Vật AI Bền Vững
  // --------------------------------------------------------------------------

  /// Lưu nhân vật vĩnh viễn gắn với ví MetaMask của phiên SIWE (`POST /api/ai/nhan-vat/luu`).
  Future<KetQuaLuuNhanVat> luu({
    required String imageId,
    required String ten,
    String? csrfToken,
  }) async {
    final tenTrimmed = ten.trim();
    if (tenTrimmed.isEmpty || tenTrimmed.runes.length > 32) {
      return const KetQuaLuuNhanVat(
        loi: LoiAnhNhanVat.yeuCauKhongHopLe,
        chiTietLoi: 'Tên nhân vật phải từ 1 đến 32 ký tự.',
      );
    }

    final kq = await _api.postJson(
      '/api/ai/nhan-vat/luu',
      body: {'image_id': imageId, 'name': tenTrimmed},
      headers: {
        'X-CSRF-Token': ?csrfToken,
      },
    );

    if (kq.loi != null) {
      return KetQuaLuuNhanVat(
        loi: kq.loi,
        maHttp: kq.maHttp,
        chiTietLoi: _trichXuatThongBaoLoi(kq.duLieu) ??
            (kq.maHttp == 403
                ? 'CSRF token không hợp lệ hoặc đã hết hạn.'
                : null),
      );
    }

    try {
      final nv = ThongTinNhanVat.tuJson(kq.duLieu!);
      return KetQuaLuuNhanVat(nhanVat: nv, maHttp: kq.maHttp);
    } catch (_) {
      return const KetQuaLuuNhanVat(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  /// Lấy danh sách nhân vật đã lưu của người chơi hiện tại (`GET /api/ai/nhan-vat/danh-sach`).
  Future<KetQuaDanhSachNhanVat> layDanhSach() async {
    final kq = await _api.getJsonList('/api/ai/nhan-vat/danh-sach');
    if (kq.loi != null) {
      return KetQuaDanhSachNhanVat(
        loi: kq.loi,
        maHttp: kq.maHttp,
        chiTietLoi: _trichXuatThongBaoLoi(kq.duLieuLoi),
      );
    }

    final rawList = kq.danhSach;
    if (rawList == null) {
      return const KetQuaDanhSachNhanVat(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }

    try {
      final danhSach = <ThongTinNhanVat>[];
      for (final item in rawList) {
        if (item is! Map<String, dynamic>) {
          return const KetQuaDanhSachNhanVat(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
        }
        danhSach.add(ThongTinNhanVat.tuJson(item));
      }
      return KetQuaDanhSachNhanVat(danhSach: danhSach, maHttp: kq.maHttp);
    } catch (_) {
      return const KetQuaDanhSachNhanVat(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  /// Lấy chi tiết nhân vật (`GET /api/ai/nhan-vat/{character_id}`).
  Future<KetQuaLuuNhanVat> layChiTiet(String characterId) async {
    final kq = await _api.getJson('/api/ai/nhan-vat/$characterId');
    if (kq.loi != null) {
      return KetQuaLuuNhanVat(loi: kq.loi, maHttp: kq.maHttp);
    }
    try {
      return KetQuaLuuNhanVat(
        nhanVat: ThongTinNhanVat.tuJson(kq.duLieu!),
        maHttp: kq.maHttp,
      );
    } catch (_) {
      return const KetQuaLuuNhanVat(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  /// Xin cấp EIP-712 Voucher từ Backend (`POST /api/ai/nhan-vat/{id}/ky-voucher`).
  Future<KetQuaKyVoucher> xinKyVoucher({
    required String characterId,
    String? csrfToken,
  }) async {
    final kq = await _api.postJson(
      '/api/ai/nhan-vat/$characterId/ky-voucher',
      body: {},
      headers: {
        'X-CSRF-Token': ?csrfToken,
      },
    );

    if (kq.loi != null) {
      return KetQuaKyVoucher(
        loi: kq.loi,
        maHttp: kq.maHttp,
        chiTietLoi: _trichXuatThongBaoLoi(kq.duLieu),
      );
    }

    try {
      final model = PhanHoiKyVoucherModel.tuJson(kq.duLieu!);
      return KetQuaKyVoucher(phieu: model, maHttp: kq.maHttp);
    } catch (_) {
      return const KetQuaKyVoucher(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }

  /// Gửi transaction hash để Backend RPC Verifier xác minh (`POST /api/ai/nhan-vat/{id}/xac-minh-onchain`).
  Future<KetQuaXacMinhOnchain> xacMinhOnchain({
    required String characterId,
    required String transactionHash,
    String? csrfToken,
  }) async {
    final cleanTx = transactionHash.trim();
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(cleanTx)) {
      return const KetQuaXacMinhOnchain(
        loi: LoiAnhNhanVat.yeuCauKhongHopLe,
        chiTietLoi: 'Mã giao dịch transaction_hash phải đúng 66 ký tự hex.',
      );
    }

    final kq = await _api.postJson(
      '/api/ai/nhan-vat/$characterId/xac-minh-onchain',
      body: {'transaction_hash': cleanTx},
      headers: {
        'X-CSRF-Token': ?csrfToken,
      },
    );

    if (kq.loi != null) {
      return KetQuaXacMinhOnchain(
        loi: kq.loi,
        maHttp: kq.maHttp,
        chiTietLoi: _trichXuatThongBaoLoi(kq.duLieu),
      );
    }

    try {
      final nv = ThongTinNhanVat.tuJson(kq.duLieu!);
      return KetQuaXacMinhOnchain(nhanVat: nv, maHttp: kq.maHttp);
    } catch (_) {
      return const KetQuaXacMinhOnchain(loi: LoiAnhNhanVat.phanHoiKhongHopLe);
    }
  }
}

String? _trichXuatThongBaoLoi(Map<String, dynamic>? duLieu) {
  if (duLieu == null) return null;
  final detail = duLieu['detail'];
  if (detail is Map) {
    final msg = detail['message'];
    if (msg is String) return msg;
    final code = detail['code'];
    if (code is String) return code;
  }
  if (detail is String) return detail;
  return null;
}

bool _moTaHopLe(String value) {
  if (value.isEmpty || value.runes.length > 500) return false;
  return !value.runes.any(
    (rune) =>
        (rune < 32 && rune != 9 && rune != 10 && rune != 13) ||
        (rune >= 127 && rune <= 159) ||
        (rune >= 0xd800 && rune <= 0xdfff),
  );
}

void _kiemTraHeader(Uint8List png, AnhNhanVat anh) {
  if (png.length < 33) throw const FormatException('Thiếu header PNG');
  final header = ByteData.sublistView(png);
  if (header.getUint32(0) != 0x89504e47 ||
      header.getUint32(4) != 0x0d0a1a0a ||
      header.getUint32(8) != 13 ||
      header.getUint32(12) != 0x49484452 ||
      header.getUint32(16) != anh.chieuRong ||
      header.getUint32(20) != anh.chieuCao) {
    throw const FormatException('Header PNG không khớp ảnh xem trước');
  }
}
