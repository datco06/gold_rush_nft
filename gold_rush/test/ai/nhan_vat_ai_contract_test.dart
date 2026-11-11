import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/ai/nhan_vat_ai_models.dart';
import 'package:gold_rush/blockchain/abi_dang_ky_nhan_vat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('Group A: MayChuNhanVat.layDanhSach (Contract Schema Tests)', () {
    test('A1: Parse thành công JSON Array gồm 2 nhân vật chuẩn từ Backend thật', () async {
      final backendJson = [
        {
          'character_id': 'char_0123456789abcdef0123456789abcdef',
          'name': 'Thợ mỏ vàng AI',
          'image_id': 'img_0123456789abcdef0123456789abcdef',
          'character_hash': '0x1111111111111111111111111111111111111111111111111111111111111111',
          'verified_wallet_address': '0x2222222222222222222222222222222222222222',
          'created_at': '2026-11-09T13:38:28Z',
          'onchain_status': 'registered',
          'transaction_hash': '0x3333333333333333333333333333333333333333333333333333333333333333',
        },
        {
          'character_id': 'char_fedcba9876543210fedcba9876543210',
          'name': 'Chiến binh AI',
          'image_id': 'img_fedcba9876543210fedcba9876543210',
          'character_hash': '0x4444444444444444444444444444444444444444444444444444444444444444',
          'verified_wallet_address': '0x2222222222222222222222222222222222222222',
          'created_at': '2026-11-09T14:15:30Z',
          'onchain_status': 'not_registered',
          'transaction_hash': null,
        },
      ];

      final client = MockClient((request) async {
        if (request.url.path == '/api/ai/nhan-vat/danh-sach') {
          return http.Response(
            jsonEncode(backendJson),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('', 404);
      });

      final api = MayChuNhanVat(mayChu: 'http://localhost', client: client);
      final res = await api.layDanhSach();

      expect(res.thanhCong, isTrue);
      expect(res.loi, isNull);
      expect(res.danhSach.length, 2);

      // Nhân vật 1
      final nv1 = res.danhSach[0];
      expect(nv1.characterId, 'char_0123456789abcdef0123456789abcdef');
      expect(nv1.name, 'Thợ mỏ vàng AI');
      expect(nv1.imageId, 'img_0123456789abcdef0123456789abcdef');
      expect(nv1.characterHash, '1111111111111111111111111111111111111111111111111111111111111111');
      expect(nv1.verifiedWalletAddress, '0x2222222222222222222222222222222222222222');
      expect(nv1.createdAt, DateTime.parse('2026-11-09T13:38:28Z'));
      expect(nv1.onchainStatus, TrangThaiOnchain.registered);
      expect(nv1.daDangKy, isTrue);
      expect(nv1.transactionHash, '0x3333333333333333333333333333333333333333333333333333333333333333');

      // Nhân vật 2
      final nv2 = res.danhSach[1];
      expect(nv2.characterId, 'char_fedcba9876543210fedcba9876543210');
      expect(nv2.name, 'Chiến binh AI');
      expect(nv2.imageId, 'img_fedcba9876543210fedcba9876543210');
      expect(nv2.onchainStatus, TrangThaiOnchain.notRegistered);
      expect(nv2.daDangKy, isFalse);
      expect(nv2.transactionHash, isNull);
    });

    test('A2: Parse thành công mảng rỗng []', () async {
      final client = MockClient((request) async {
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final api = MayChuNhanVat(mayChu: 'http://localhost', client: client);
      final res = await api.layDanhSach();

      expect(res.thanhCong, isTrue);
      expect(res.loi, isNull);
      expect(res.danhSach, isEmpty);
    });

    test('A3: Từ chối phản hồi sai định dạng (JSON Object {"characters": [...]}, null, String)', () async {
      // Trường hợp 1: JSON Object cũ {"characters": [...]}
      var client = MockClient((request) async {
        return http.Response(
          jsonEncode({'characters': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      var api = MayChuNhanVat(mayChu: 'http://localhost', client: client);
      var res = await api.layDanhSach();
      expect(res.thanhCong, isFalse);
      expect(res.loi, LoiAnhNhanVat.phanHoiKhongHopLe);
      expect(res.danhSach, isEmpty);

      // Trường hợp 2: JSON Object với detail lỗi
      client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Lỗi server'}),
          500,
          headers: {'content-type': 'application/json'},
        );
      });
      api = MayChuNhanVat(mayChu: 'http://localhost', client: client);
      res = await api.layDanhSach();
      expect(res.thanhCong, isFalse);
      expect(res.maHttp, 500);

      // Trường hợp 3: Chuỗi văn bản không phải JSON array
      client = MockClient((request) async {
        return http.Response('Không phải json', 200, headers: {'content-type': 'application/json'});
      });
      api = MayChuNhanVat(mayChu: 'http://localhost', client: client);
      res = await api.layDanhSach();
      expect(res.thanhCong, isFalse);
      expect(res.loi, LoiAnhNhanVat.phanHoiKhongHopLe);
    });

    test('A4: Từ chối danh sách có phần tử thiếu trường bắt buộc hoặc sai schema', () async {
      final malformedList = [
        {
          // Thiếu image_id, character_hash, created_at
          'character_id': 'char_0123456789abcdef0123456789abcdef',
          'name': 'Nhân vật thiếu trường',
        }
      ];

      final client = MockClient((request) async {
        return http.Response(jsonEncode(malformedList), 200, headers: {'content-type': 'application/json'});
      });

      final api = MayChuNhanVat(mayChu: 'http://localhost', client: client);
      final res = await api.layDanhSach();

      expect(res.thanhCong, isFalse);
      expect(res.loi, LoiAnhNhanVat.phanHoiKhongHopLe);
      expect(res.danhSach, isEmpty);
    });
  });

  group('Group B: ThongTinNhanVat.tuJson (Schema & Field Validation)', () {
    final hopLeJson = {
      'character_id': 'char_0123456789abcdef0123456789abcdef',
      'name': 'Thợ mỏ vàng AI',
      'image_id': 'img_0123456789abcdef0123456789abcdef',
      'character_hash': '0x1111111111111111111111111111111111111111111111111111111111111111',
      'verified_wallet_address': '0x2222222222222222222222222222222222222222',
      'created_at': '2026-11-09T13:38:28Z',
      'onchain_status': 'registered',
      'transaction_hash': '0x3333333333333333333333333333333333333333333333333333333333333333',
    };

    test('B1: Parse chính xác created_at từ chuỗi ISO-8601 UTC và timestamp số nguyên', () {
      final nv = ThongTinNhanVat.tuJson(hopLeJson);
      expect(nv.createdAt, DateTime.utc(2026, 11, 9, 13, 38, 28));

      // Hỗ trợ cả timestamp số nguyên (backward compatibility)
      final jsonTimestamp = Map<String, dynamic>.from(hopLeJson);
      jsonTimestamp['created_at'] = 1794231508;
      final nvTs = ThongTinNhanVat.tuJson(jsonTimestamp);
      expect(nvTs.createdAt.year, 2026);
    });

    test('B2: Ném FormatException khi created_at không đúng định dạng ngày giờ', () {
      final badDates = ['invalid-date', '2026-99-99', '', 'not-iso'];
      for (final bad in badDates) {
        final j = Map<String, dynamic>.from(hopLeJson);
        j['created_at'] = bad;
        expect(() => ThongTinNhanVat.tuJson(j), throwsFormatException);
      }
    });

    test('B3: Ném FormatException khi thiếu trường hoặc sai định dạng', () {
      // Thiếu character_id
      var j = Map<String, dynamic>.from(hopLeJson)..remove('character_id');
      expect(() => ThongTinNhanVat.tuJson(j), throwsFormatException);

      // character_id sai định dạng (không đủ 32 hex)
      j = Map<String, dynamic>.from(hopLeJson);
      j['character_id'] = 'char_short';
      expect(() => ThongTinNhanVat.tuJson(j), throwsFormatException);

      // image_id sai định dạng
      j = Map<String, dynamic>.from(hopLeJson);
      j['image_id'] = 'invalid_img';
      expect(() => ThongTinNhanVat.tuJson(j), throwsFormatException);

      // character_hash không đủ 64 ký tự hex
      j = Map<String, dynamic>.from(hopLeJson);
      j['character_hash'] = '0x1234';
      expect(() => ThongTinNhanVat.tuJson(j), throwsFormatException);

      // verified_wallet_address không đúng định dạng EVM address
      j = Map<String, dynamic>.from(hopLeJson);
      j['verified_wallet_address'] = '0xnotanaddress';
      expect(() => ThongTinNhanVat.tuJson(j), throwsFormatException);

      // transaction_hash không đúng định dạng bytes32
      j = Map<String, dynamic>.from(hopLeJson);
      j['transaction_hash'] = '0xshorttx';
      expect(() => ThongTinNhanVat.tuJson(j), throwsFormatException);
    });
  });

  group('Group C: PhanHoiKyVoucherModel & CharacterVoucher (EIP-712 Contract Schema)', () {
    final hopLeVoucherJson = {
      'primaryType': 'CharacterVoucher',
      'message': {
        'characterId': 'char_0123456789abcdef0123456789abcdef',
        'characterHash': '0x1111111111111111111111111111111111111111111111111111111111111111',
        'owner': '0x2222222222222222222222222222222222222222',
        'nonce': '0x3333333333333333333333333333333333333333333333333333333333333333',
        'deadline': 1800000000,
      },
      'signature': '0x${'aa' * 65}',
      'contractAddress': '0x9999999999999999999999999999999999999999',
      'chainId': 31337,
      'signerAddress': '0x5555555555555555555555555555555555555555',
    };

    test('C1: Parse đúng phản hồi có cấu trúc message, contractAddress, chainId', () {
      final phanHoi = PhanHoiKyVoucherModel.tuJson(hopLeVoucherJson);

      expect(phanHoi.characterId, 'char_0123456789abcdef0123456789abcdef');
      expect(phanHoi.contractAddress, '0x9999999999999999999999999999999999999999');
      expect(phanHoi.chainId, 31337);
      expect(phanHoi.signature, '0x${'aa' * 65}');

      final v = phanHoi.voucher;
      expect(v.characterId, 'char_0123456789abcdef0123456789abcdef');
      expect(v.characterHash, '0x1111111111111111111111111111111111111111111111111111111111111111');
      expect(v.owner, '0x2222222222222222222222222222222222222222');
      expect(v.nonce, '0x3333333333333333333333333333333333333333333333333333333333333333');
      expect(v.deadline, BigInt.from(1800000000));
    });

    test('C2: Ném FormatException khi thiếu trường message hoặc sai cấu trúc', () {
      final j = Map<String, dynamic>.from(hopLeVoucherJson)..remove('message');
      expect(() => PhanHoiKyVoucherModel.tuJson(j), throwsFormatException);
    });

    test('C3: Ném FormatException khi owner không phải địa chỉ EVM 40 ký tự hex có 0x', () {
      final badOwners = ['0x123', 'not_an_address', '2222222222222222222222222222222222222222'];
      for (final bad in badOwners) {
        final j = Map<String, dynamic>.from(hopLeVoucherJson);
        final msg = Map<String, dynamic>.from(j['message'] as Map<String, dynamic>);
        msg['owner'] = bad;
        j['message'] = msg;
        expect(() => PhanHoiKyVoucherModel.tuJson(j), throwsFormatException);
      }
    });

    test('C4: Ném FormatException khi characterHash không phải 64 hex có 0x', () {
      final badHashes = ['0x123', 'not_a_hash', '1111111111111111111111111111111111111111111111111111111111111111'];
      for (final bad in badHashes) {
        final j = Map<String, dynamic>.from(hopLeVoucherJson);
        final msg = Map<String, dynamic>.from(j['message'] as Map<String, dynamic>);
        msg['characterHash'] = bad;
        j['message'] = msg;
        expect(() => PhanHoiKyVoucherModel.tuJson(j), throwsFormatException);
      }
    });

    test('C5: Ném FormatException khi signature không đủ 130 hex + 0x (65 bytes = 132 ký tự)', () {
      final badSigs = ['0x1234', 'not_a_signature', '0x${'aa' * 64}', '0x${'aa' * 66}'];
      for (final bad in badSigs) {
        final j = Map<String, dynamic>.from(hopLeVoucherJson);
        j['signature'] = bad;
        expect(() => PhanHoiKyVoucherModel.tuJson(j), throwsFormatException);
      }
    });

    test('C6: Xác minh calldata tạo ra từ maHoaDangKyNhanVat với voucher thật khớp selector CharacterRegistry', () {
      final phanHoi = PhanHoiKyVoucherModel.tuJson(hopLeVoucherJson);
      final calldata = maHoaDangKyNhanVat(phanHoi.voucher, phanHoi.signature);

      // Function selector của registerCharacter((string,bytes32,address,bytes32,uint256),bytes) là 0x402c91a0
      expect(calldata.startsWith('0x$chonRegisterCharacter'), isTrue);
      expect(calldata.substring(0, 10).toLowerCase(), '0x402c91a0');

      // Calldata hợp lệ phải có độ dài tối thiểu bao gồm selector + 2 words offsets + 8 words voucher + 4 words sig
      expect(calldata.length, greaterThan(10 + 64 * 10));
    });
  });
}

