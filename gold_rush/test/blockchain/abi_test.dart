import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/abi.dart';

/// So từng byte với bộ mã hoá ABI tổng quát bên Python
/// (`gold_rush_ai/scripts/sinh_abi_mau.py` → `test/blockchain/abi_mau.json`).
/// Bài kiểm thử Hardhat so CÙNG tệp này với viem → Dart = Python = viem.
void main() {
  final mau = jsonDecode(File('test/blockchain/abi_mau.json').readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> ca(String k) => mau[k] as Map<String, dynamic>;

  test('bộ chọn hàm khớp Python', () {
    final bc = ca('bo_chon');
    expect(chonNhanVang, bc['nhanVang((address,uint256,uint256,uint256,bytes32,uint256),bytes)']);
    expect(chonVaoMan, bc['vaoMan(uint256)']);
    expect(chonMua, bc['mua(uint256)']);
    expect(chonMulticall, bc['multicall(bytes[])']);
    expect(chonBalanceOf, bc['balanceOf(address,uint256)']);
    expect(chonGia, bc['gia(uint256)']);
    expect(chonDaDoi, bc['daDoi(bytes32)']);
    expect(chonVe, bc['ve(address)']);
    expect(chonManChoi, bc['manChoi(uint256)']);
  });

  test('nhanVang(phiếu màn có cọc, chữ ký) khớp Python — 356 byte', () {
    final m = ca('nhanVang');
    final kq = maHoaNhanVang(PhieuVang.tuJson(m['phieu'] as Map<String, dynamic>), m['chu_ky'] as String);
    expect(kq, m['calldata']);
    expect((kq.length - 2) ~/ 2, 4 + 32 * 7 + 32 + 96);
  });

  test('multicall([nhanVang, nhanVang, vaoMan]) khớp Python', () {
    final m = ca('multicall');
    final lenh = (m['cac_lenh'] as List).cast<String>();
    expect(maHoaMulticall(lenh), m['calldata']);
  });

  test('vaoMan, mua, balanceOf, gia, daDoi, ve, manChoi khớp Python', () {
    expect(maHoaVaoMan(ca('vaoMan')['man'] as int), ca('vaoMan')['calldata']);
    expect(maHoaMua(ca('mua')['nhan_vat'] as int), ca('mua')['calldata']);
    final b = ca('balanceOf');
    expect(maHoaBalanceOf(b['vi'] as String, b['id'] as int), b['calldata']);
    expect(maHoaGia(ca('gia')['nhan_vat'] as int), ca('gia')['calldata']);
    expect(maHoaDaDoi(ca('daDoi')['ma_van'] as String), ca('daDoi')['calldata']);
    expect(maHoaVe(ca('ve')['vi'] as String), ca('ve')['calldata']);
    expect(maHoaManChoi(ca('manChoi')['man'] as int), ca('manChoi')['calldata']);
  });

  test('giải mã ve(address) → (màn, số vé, cọc)', () {
    final v = docVe(ca('ve')['ket_qua'] as String);
    expect([v.man, v.so, v.coc.toInt()], ca('ve')['giai_ma']);
    expect(v.dangMo, isTrue);
    expect(docVe('0x').dangMo, isFalse);
  });

  test('từ chối dữ liệu sai', () {
    expect(() => tuDiaChi('0x123'), throwsArgumentError);
    expect(() => tu(BigInt.from(-1)), throwsArgumentError);
    expect(() => tu(BigInt.two.pow(256)), throwsArgumentError);
    expect(() => maHoaMulticall(['0x123']), throwsArgumentError); // hex lẻ
    final p = PhieuVang(
      nguoiChoi: '0x${'1' * 40}',
      man: BigInt.one,
      ve: BigInt.zero,
      soVang: BigInt.one,
      maVan: '0x${'2' * 64}',
      hanChot: BigInt.one,
    );
    expect(() => maHoaNhanVang(p, '0x1234'), throwsArgumentError);
  });

  test('đọc uint256 từ eth_call', () {
    expect(docUint256('0x${'0' * 63}7'), BigInt.from(7));
    expect(docUint256('0x'), BigInt.zero);
    expect(docCacUint256('0x${'0' * 63}1${'0' * 63}2', 2), [BigInt.one, BigInt.two]);
  });
}
