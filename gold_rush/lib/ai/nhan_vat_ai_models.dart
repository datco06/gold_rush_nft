import '../blockchain/abi_dang_ky_nhan_vat.dart';

/// Trạng thái đăng ký blockchain của nhân vật AI.
enum TrangThaiOnchain {
  notRegistered('not_registered', 'Chưa đăng ký'),
  pending('pending', 'Đang chờ xác nhận'),
  registered('registered', 'Đã xác minh On-Chain'),
  failed('failed', 'Đăng ký thất bại');

  final String giaTri;
  final String nhan;

  const TrangThaiOnchain(this.giaTri, this.nhan);

  static TrangThaiOnchain tuGiaTri(String? val) {
    for (final e in values) {
      if (e.giaTri == val) return e;
    }
    return TrangThaiOnchain.notRegistered;
  }
}

/// Dữ liệu nhân vật lưu bền vững trong CSDL Backend AI.
class ThongTinNhanVat {
  final String characterId;
  final String name;
  final String imageId;
  final String characterHash;
  final String verifiedWalletAddress;
  final DateTime createdAt;
  final TrangThaiOnchain onchainStatus;
  final String? transactionHash;

  const ThongTinNhanVat({
    required this.characterId,
    required this.name,
    required this.imageId,
    required this.characterHash,
    required this.verifiedWalletAddress,
    required this.createdAt,
    required this.onchainStatus,
    this.transactionHash,
  });

  factory ThongTinNhanVat.tuJson(Map<String, dynamic> json) {
    // 1. character_id (char_<32_hex>)
    final rawId = json['character_id'] ?? json['characterId'];
    if (rawId is! String || !RegExp(r'^char_[0-9a-f]{32}$').hasMatch(rawId)) {
      throw FormatException('character_id không hợp lệ: $rawId');
    }

    // 2. name
    final rawName = json['name'];
    if (rawName != null && rawName is! String) {
      throw FormatException('name không hợp lệ: $rawName');
    }
    final name = (rawName is String && rawName.trim().isNotEmpty)
        ? rawName.trim()
        : 'Nhân vật AI';

    // 3. image_id (img_<32_hex>)
    final rawImgId = json['image_id'] ?? json['imageId'];
    if (rawImgId is! String || !RegExp(r'^img_[0-9a-f]{32}$').hasMatch(rawImgId)) {
      throw FormatException('image_id không hợp lệ: $rawImgId');
    }

    // 4. character_hash (64 hex ký tự SHA-256)
    final rawHash = json['character_hash'] ?? json['characterHash'];
    if (rawHash is! String || !RegExp(r'^(0x)?[0-9a-fA-F]{64}$').hasMatch(rawHash)) {
      throw FormatException('character_hash không hợp lệ: $rawHash');
    }
    final cleanHash = rawHash.startsWith('0x')
        ? rawHash.substring(2).toLowerCase()
        : rawHash.toLowerCase();

    // 5. verified_wallet_address (0x + 40 hex ký tự)
    final rawWallet = json['verified_wallet_address'] ?? json['verifiedWalletAddress'];
    if (rawWallet is! String || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(rawWallet)) {
      throw FormatException('verified_wallet_address không hợp lệ: $rawWallet');
    }

    // 6. created_at (Chuỗi ISO-8601 từ FastAPI backend, hoặc số nguyên timestamp)
    final rawCreatedAt = json['created_at'] ?? json['createdAt'];
    final DateTime createdAt;
    if (rawCreatedAt is String) {
      final str = rawCreatedAt.trim();
      final parsed = str.isNotEmpty ? DateTime.tryParse(str) : null;
      if (parsed == null) {
        throw FormatException('created_at không đúng định dạng ISO-8601: $rawCreatedAt');
      }
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(str)) {
        final parts = str.split(RegExp(r'[-T]'));
        if (parts.length >= 3) {
          final m = int.tryParse(parts[1]) ?? 0;
          final d = int.tryParse(parts[2].length >= 2 ? parts[2].substring(0, 2) : parts[2]) ?? 0;
          if (m < 1 || m > 12 || d < 1 || d > 31) {
            throw FormatException('created_at có tháng hoặc ngày không hợp lệ: $rawCreatedAt');
          }
        }
      }
      createdAt = parsed;
    } else if (rawCreatedAt is int) {
      // Hỗ trợ timestamp Unix (giây hoặc mili-giây)
      createdAt = rawCreatedAt > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(rawCreatedAt, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(rawCreatedAt * 1000, isUtc: true);
    } else {
      throw FormatException('Thiếu trường created_at hoặc sai kiểu dữ liệu: $rawCreatedAt');
    }

    // 7. onchain_status
    final rawStatus = json['onchain_status'] ?? json['onchainStatus'];
    final onchainStatus = TrangThaiOnchain.tuGiaTri(rawStatus as String?);

    // 8. transaction_hash (tuỳ chọn, nếu có phải đúng 66 ký tự hex)
    final rawTx = json['transaction_hash'] ?? json['transactionHash'];
    final String? txHash;
    if (rawTx != null) {
      if (rawTx is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(rawTx)) {
        throw FormatException('transaction_hash không hợp lệ: $rawTx');
      }
      txHash = rawTx.toLowerCase();
    } else {
      txHash = null;
    }

    return ThongTinNhanVat(
      characterId: rawId,
      name: name,
      imageId: rawImgId,
      characterHash: cleanHash,
      verifiedWalletAddress: rawWallet.toLowerCase(),
      createdAt: createdAt,
      onchainStatus: onchainStatus,
      transactionHash: txHash,
    );
  }

  /// Hash rút gọn 10 ký tự đầu và 6 ký tự cuối để hiển thị gọn trên UI.
  String get hashRutGon {
    final clean = characterHash.startsWith('0x') ? characterHash : '0x$characterHash';
    if (clean.length <= 16) return clean;
    return '${clean.substring(0, 10)}…${clean.substring(clean.length - 6)}';
  }

  /// Địa chỉ ví rút gọn để hiển thị.
  String get viRutGon {
    if (verifiedWalletAddress.length <= 10) return verifiedWalletAddress;
    return '${verifiedWalletAddress.substring(0, 6)}…${verifiedWalletAddress.substring(verifiedWalletAddress.length - 4)}';
  }

  /// Character ID rút gọn.
  String get idRutGon {
    if (characterId.length <= 14) return characterId;
    return '${characterId.substring(0, 10)}…${characterId.substring(characterId.length - 4)}';
  }

  bool get daDangKy => onchainStatus == TrangThaiOnchain.registered;
  bool get dangChoXacNhan => onchainStatus == TrangThaiOnchain.pending;
}

/// Phiên người dùng xác thực SIWE từ endpoint `/api/me`.
class NguoiDungAuth {
  final String userId;
  final String walletAddress;
  final String username;
  final String? csrfToken;
  final DateTime? expiresAt;

  const NguoiDungAuth({
    required this.userId,
    required this.walletAddress,
    required this.username,
    this.csrfToken,
    this.expiresAt,
  });

  factory NguoiDungAuth.tuJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final csrf = json['csrf_token'] as String?;
    final expStr = json['expires_at'] as String?;
    final exp = expStr != null ? DateTime.tryParse(expStr) : null;

    return NguoiDungAuth(
      userId: user['user_id'] as String,
      walletAddress: user['wallet_address'] as String,
      username: user['username'] as String? ?? '',
      csrfToken: csrf,
      expiresAt: exp,
    );
  }

  String get viRutGon {
    if (walletAddress.length <= 10) return walletAddress;
    return '${walletAddress.substring(0, 6)}…${walletAddress.substring(walletAddress.length - 4)}';
  }
}

/// Dữ liệu phản hồi khi Backend ký cấp EIP-712 Voucher.
class PhanHoiKyVoucherModel {
  final CharacterVoucher voucher;
  final String signature;
  final String contractAddress;
  final int chainId;
  final String characterId;
  final String? expiresAt;

  const PhanHoiKyVoucherModel({
    required this.voucher,
    required this.signature,
    required this.contractAddress,
    required this.chainId,
    required this.characterId,
    this.expiresAt,
  });

  factory PhanHoiKyVoucherModel.tuJson(Map<String, dynamic> json) {
    // 1. Voucher message
    final rawMsg = json['message'] ?? json['voucher'];
    if (rawMsg is! Map<String, dynamic>) {
      throw const FormatException('Phản hồi ký voucher thiếu trường message hoặc sai cấu trúc');
    }
    final voucher = CharacterVoucher.tuJson(rawMsg);

    // 2. Signature (0x + 130 hex ký tự)
    final sig = json['signature'];
    if (sig is! String || !RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(sig)) {
      throw const FormatException('Chữ ký EIP-712 không hợp lệ (cần 0x kèm 130 ký tự hex)');
    }

    // 3. Contract Address (0x + 40 hex ký tự)
    final cAddr = json['contractAddress'] ?? json['contract_address'];
    if (cAddr is! String || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(cAddr)) {
      throw const FormatException('Địa chỉ hợp đồng contractAddress không hợp lệ');
    }

    // 4. Chain ID
    final cId = json['chainId'] ?? json['chain_id'];
    if (cId is! int || cId <= 0) {
      throw const FormatException('chainId không hợp lệ');
    }

    // 5. characterId lấy từ voucher.characterId theo hợp đồng thật
    final charId = voucher.characterId;

    return PhanHoiKyVoucherModel(
      voucher: voucher,
      signature: sig,
      contractAddress: cAddr,
      chainId: cId,
      characterId: charId,
    );
  }
}

