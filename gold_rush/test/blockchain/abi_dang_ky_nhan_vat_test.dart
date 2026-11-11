import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/abi_dang_ky_nhan_vat.dart';

void main() {
  group('ABI CharacterRegistry — maHoaDangKyNhanVat', () {
    test('mã hoá khớp từng byte với viem và chuẩn Solidity ABI', () {
      final voucher = CharacterVoucher(
        characterId: 'char_0123456789abcdef0123456789abcdef',
        characterHash: '0x1111111111111111111111111111111111111111111111111111111111111111',
        owner: '0x2222222222222222222222222222222222222222',
        nonce: '0x3333333333333333333333333333333333333333333333333333333333333333',
        deadline: BigInt.from(1800000000),
      );
      final sig = '0x${'aa' * 65}';

      final calldata = maHoaDangKyNhanVat(voucher, sig);

      const viemCalldata =
          '0x402c91a0'
          '0000000000000000000000000000000000000000000000000000000000000040'
          '0000000000000000000000000000000000000000000000000000000000000140'
          '00000000000000000000000000000000000000000000000000000000000000a0'
          '1111111111111111111111111111111111111111111111111111111111111111'
          '0000000000000000000000002222222222222222222222222222222222222222'
          '3333333333333333333333333333333333333333333333333333333333333333'
          '000000000000000000000000000000000000000000000000000000006b49d200'
          '0000000000000000000000000000000000000000000000000000000000000025'
          '636861725f303132333435363738396162636465663031323334353637383961'
          '6263646566000000000000000000000000000000000000000000000000000000'
          '0000000000000000000000000000000000000000000000000000000000000041'
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
          'aa00000000000000000000000000000000000000000000000000000000000000';

      expect(calldata.toLowerCase(), viemCalldata.toLowerCase());
    });

    test('từ chối characterId sai định dạng', () {
      final voucher = CharacterVoucher(
        characterId: 'invalid_id',
        characterHash: '0x${'11' * 32}',
        owner: '0x${'22' * 20}',
        nonce: '0x${'33' * 32}',
        deadline: BigInt.from(1800000000),
      );
      expect(
        () => maHoaDangKyNhanVat(voucher, '0x${'aa' * 65}'),
        throwsArgumentError,
      );
    });

    test('từ chối chữ ký sai độ dài', () {
      final voucher = CharacterVoucher(
        characterId: 'char_0123456789abcdef0123456789abcdef',
        characterHash: '0x${'11' * 32}',
        owner: '0x${'22' * 20}',
        nonce: '0x${'33' * 32}',
        deadline: BigInt.from(1800000000),
      );
      expect(
        () => maHoaDangKyNhanVat(voucher, '0xdeadbeef'),
        throwsArgumentError,
      );
    });
  });
}

