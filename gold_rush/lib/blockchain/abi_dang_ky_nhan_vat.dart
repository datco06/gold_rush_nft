/// Mã hoá ABI cho hợp đồng `CharacterRegistry` — đăng ký nhân vật AI on-chain.
///
/// Khớp 100% với phương thức:
/// `registerCharacter((string,bytes32,address,bytes32,uint256),bytes)`
/// Selector: `0x402c91a0` (keccak256 của chữ ký hàm cắt 4 byte đầu).
library;

import 'dart:convert';

import 'abi.dart';

/// Selector của hàm `registerCharacter((string,bytes32,address,bytes32,uint256),bytes)`.
const String chonRegisterCharacter = '402c91a0';

/// Phiếu ủy quyền đăng ký nhân vật AI (EIP-712 CharacterVoucher) từ Backend AI Signer.
class CharacterVoucher {
  final String characterId; // Định dạng char_<32 ký tự hex>
  final String characterHash; // 0x + 64 ký tự hex SHA-256
  final String owner; // 0x + 40 ký tự hex địa chỉ ví MetaMask
  final String nonce; // 0x + 64 ký tự hex
  final BigInt deadline; // Unix timestamp

  const CharacterVoucher({
    required this.characterId,
    required this.characterHash,
    required this.owner,
    required this.nonce,
    required this.deadline,
  });

  factory CharacterVoucher.tuJson(Map<String, dynamic> json) {
    final rawId = json['characterId'] ?? json['character_id'];
    if (rawId is! String || !RegExp(r'^char_[0-9a-f]{32}$').hasMatch(rawId)) {
      throw FormatException('characterId không hợp lệ: $rawId');
    }

    final rawHash = json['characterHash'] ?? json['character_hash'];
    if (rawHash is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(rawHash)) {
      throw FormatException('characterHash bytes32 không hợp lệ: $rawHash');
    }

    final rawOwner = json['owner'];
    if (rawOwner is! String || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(rawOwner)) {
      throw FormatException('owner address không hợp lệ: $rawOwner');
    }

    final rawNonce = json['nonce'];
    if (rawNonce is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(rawNonce)) {
      throw FormatException('nonce bytes32 không hợp lệ: $rawNonce');
    }

    final rawDeadline = json['deadline'];
    final BigInt dl;
    if (rawDeadline is int && rawDeadline > 0) {
      dl = BigInt.from(rawDeadline);
    } else if (rawDeadline is String) {
      final parsed = BigInt.tryParse(rawDeadline);
      if (parsed == null || parsed <= BigInt.zero) {
        throw FormatException('deadline không hợp lệ: $rawDeadline');
      }
      dl = parsed;
    } else if (rawDeadline is BigInt && rawDeadline > BigInt.zero) {
      dl = rawDeadline;
    } else {
      throw FormatException('deadline không hợp lệ: $rawDeadline');
    }

    return CharacterVoucher(
      characterId: rawId,
      characterHash: rawHash.toLowerCase(),
      owner: rawOwner,
      nonce: rawNonce.toLowerCase(),
      deadline: dl,
    );
  }

  Map<String, dynamic> toJson() => {
    'characterId': characterId,
    'characterHash': characterHash,
    'owner': owner,
    'nonce': nonce,
    'deadline': deadline.toString(),
  };
}

/// Mã hoá chuỗi UTF-8 dạng dynamic string theo chuẩn ABI (chiều dài 1 từ + dữ liệu đệm phải bội số 32 byte).
String _duoiString(String str) {
  final bytes = utf8.encode(str);
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final padLength = (64 - (hex.length % 64)) % 64;
  final lenWord = BigInt.from(bytes.length).toRadixString(16).padLeft(64, '0');
  return '$lenWord$hex${'0' * padLength}';
}

/// Mã hoá dữ liệu bytes dynamic (chiều dài 1 từ + dữ liệu đệm phải bội số 32 byte).
String _duoiBytes(String hex) {
  final h = boOx(hex).toLowerCase();
  if (h.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(h)) {
    throw ArgumentError('Dữ liệu bytes không phải hex chẵn');
  }
  final lenWord = BigInt.from(h.length ~/ 2).toRadixString(16).padLeft(64, '0');
  final padLength = (64 - (h.length % 64)) % 64;
  return '$lenWord$h${'0' * padLength}';
}

/// Mã hoá calldata gọi hàm `registerCharacter(voucher, signature)`:
///
/// Bố cục tham số của hàm:
/// - Offset tới `voucher` (tuple dynamic): 64 bytes (0x40 = 2 words)
/// - Offset tới `signature` (bytes dynamic): 320 bytes (0x140 = 10 words)
///
/// Phần tuple `voucher`:
/// - Offset tới `characterId` (tính từ đầu tuple): 160 bytes (0xa0 = 5 words)
/// - `characterHash`: 32 bytes
/// - `owner`: 20 bytes (đệm trái thành 32 bytes)
/// - `nonce`: 32 bytes
/// - `deadline`: 32 bytes
/// - Dữ liệu chuỗi `characterId`: độ dài 37 (1 word) + 37 bytes ASCII đệm phải (2 words) = 3 words (96 bytes)
/// Tổng kích thước tuple = 5 words đầu + 3 words chuỗi = 8 words (256 bytes).
///
/// Phần `signature`:
/// - Bắt đầu tại offset 64 + 256 = 320 (0x140).
/// - Độ dài chữ ký 65 bytes (0x41) + 65 bytes hex đệm phải thành 96 bytes.
String maHoaDangKyNhanVat(CharacterVoucher voucher, String chuKy) {
  final sigHex = boOx(chuKy).toLowerCase();
  if (sigHex.length != 130) {
    throw ArgumentError('Chữ ký EIP-712 phải đúng 65 byte (130 ký tự hex)');
  }
  if (!RegExp(r'^char_[0-9a-f]{32}$').hasMatch(voucher.characterId)) {
    throw ArgumentError('characterId không hợp lệ: ${voucher.characterId}');
  }

  final charIdTail = _duoiString(voucher.characterId);
  final sigTail = _duoiBytes(sigHex);

  // Đầu tham số hàm (2 words)
  const offsetVoucher = '0000000000000000000000000000000000000000000000000000000000000040';
  const offsetSignature = '0000000000000000000000000000000000000000000000000000000000000140';

  // Phần đầu của voucher tuple (5 words)
  const offsetCharIdInVoucher = '00000000000000000000000000000000000000000000000000000000000000a0';
  final hashWord = tuBytes32(voucher.characterHash);
  final ownerWord = tuDiaChi(voucher.owner);
  final nonceWord = tuBytes32(voucher.nonce);
  final deadlineWord = tu(voucher.deadline);

  return '0x$chonRegisterCharacter'
      '$offsetVoucher$offsetSignature'
      '$offsetCharIdInVoucher$hashWord$ownerWord$nonceWord$deadlineWord'
      '$charIdTail'
      '$sigTail';
}

