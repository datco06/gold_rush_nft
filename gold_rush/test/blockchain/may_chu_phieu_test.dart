import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/may_chu_phieu.dart';
import 'package:gold_rush/blockchain/vi.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MayChuPhieu voi(int ma, Object than, {void Function(http.Request)? xem}) => MayChuPhieu(
      mayChu: 'http://may-chu',
      client: MockClient((r) async {
        xem?.call(r);
        return http.Response.bytes(utf8.encode(jsonEncode(than)), ma,
            headers: {'content-type': 'application/json'});
      }),
    );

const _vi = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';
final _phieu = {
  'phieu': {'nguoiChoi': _vi, 'man': 2, 've': 1, 'soVang': 23, 'maVan': '0x${'d' * 64}', 'hanChot': 2000000000},
  'chu_ky': '0x${'1' * 130}',
};

void main() {
  test('xin phiếu: đọc phiếu bản 2 (màn, vé)', () async {
    final p = await voi(200, _phieu).xinPhieu(maVan: 'van-1', vi: _vi);
    expect(p.phieu.soVang, BigInt.from(23));
    expect(p.phieu.ve, BigInt.one);
    expect(p.coCoc, isTrue);
    expect(p.maVan, 'van-1');
  });

  test('phiếu chờ nhận', () async {
    final ds = await voi(200, {
      'phieu': [
        {..._phieu, 'ma_van': 'van-a'},
        {..._phieu, 'ma_van': 'van-b'},
      ],
    }).phieuChoNhan(_vi);
    expect(ds.map((p) => p.maVan), ['van-a', 'van-b']);
  });

  test('bắt đầu màn: gửi đúng thân, 409 mang mã để app mua vé mới', () async {
    late Map<String, dynamic> than;
    await voi(201, {'da_bat_dau': true}, xem: (r) => than = jsonDecode(r.body) as Map<String, dynamic>)
        .batDauMan(maVan: 'van-1', vi: _vi, man: 2, ve: 1);
    expect(than, {'ma_van': 'van-1', 'vi': _vi, 'man': 2, 've': 1});
    await expectLater(
      voi(409, {'detail': 'x'}).batDauMan(maVan: 'v', vi: _vi, man: 2, ve: 1),
      throwsA(isA<LoiVi>().having((e) => e.ma, 'ma', 409)),
    );
  });

  test('422 hiện lý do đầu tiên của trọng tài', () async {
    await expectLater(
      voi(422, {
        'detail': {
          'ly_do': ['Màn 2 có cọc: chỉ trả vàng khi nhặt hết 18 xu (cọc đã mất)'],
        },
      }).xinPhieu(maVan: 'van-1', vi: _vi),
      throwsA(isA<LoiVi>().having((e) => e.thongBao, 'tb', contains('nhặt hết 18 xu'))),
    );
  });

  test('các mã lỗi của máy chủ thành câu đọc được', () async {
    for (final ma in [404, 409, 422, 429, 503, 500]) {
      await expectLater(voi(ma, {'detail': 'x'}).xinPhieu(maVan: 'van-1', vi: _vi), throwsA(isA<LoiVi>()));
    }
  });

  test('cấu hình chuỗi', () async {
    final c = await voi(200, {
      'chain_id': 31337,
      'hop_dong': '0x5FbDB2315678afecb367f032d93F642f64180aa3',
      'trong_tai': '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
    }).cauHinh();
    expect(c.chainId, 31337);
  });
}
