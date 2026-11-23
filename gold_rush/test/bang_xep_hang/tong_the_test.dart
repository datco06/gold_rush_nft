import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/bang_xep_hang/bang_xep_hang.dart';
import 'package:gold_rush/bang_xep_hang/tong_the.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> dongTongThe(int rank, {String? name, bool me = false}) => {
  'hang': rank,
  'ten': name ?? 'Player$rank',
  'level': rank == 1 ? 3 : 2,
  'vang': '${1000 - rank}',
  'huy_hieu': rank == 1 ? [1, 2] : [1],
  'la_ban': me,
};

Map<String, Object?> duLieuTongThe({
  int count = 30,
  String viewer = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  bool stale = false,
}) => {
  'chain_id': 31337,
  'viewer': viewer,
  'cap_nhat_luc': '2026-11-23T08:00:00+00:00',
  'du_lieu_cu': stale,
  'tong_nguoi': 35,
  'bang': [for (var i = 1; i <= count; i++) dongTongThe(i)],
  'ban': dongTongThe(35, name: 'Alice', me: true),
};

void main() {
  test(
    'Profile level sync posts only level and identity guards with CSRF',
    () async {
      final api = MayChuBangXepHang(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/bang-xep-hang/cap-ho-so');
          expect(request.headers['X-CSRF-Token'], 'csrf-test');
          expect(jsonDecode(request.body), {
            'level': 7,
            'expected_wallet': '0x${'a' * 40}',
            'expected_chain_id': 31337,
          });
          return http.Response('{"level":7}', 200);
        }),
      );
      expect(
        await api.dongBoCapHoSo(
          level: 7,
          wallet: '0x${'a' * 40}',
          chainId: 31337,
          csrfToken: 'csrf-test',
        ),
        7,
      );
    },
  );

  test(
    'overall refresh never overlaps an underlying timed-out request',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final api = MayChuBangXepHang(
        client: MockClient((_) {
          calls++;
          return pending.future;
        }),
        thoiGianCho: const Duration(milliseconds: 1),
      );
      await expectLater(api.taiTongThe(), throwsA(isA<LoiTaiBangXepHang>()));
      await expectLater(api.taiTongThe(), throwsA(isA<LoiTaiBangXepHang>()));
      expect(calls, 1);
      pending.complete(http.Response(jsonEncode(duLieuTongThe()), 200));
    },
  );
  test('overall client calls fixed Top30 endpoint, parses exact BigInt and immutable badges', () async {
    final data = duLieuTongThe();
    (data['bang'] as List).first['vang'] =
        '100000000000000000000000000000000001';
    final api = MayChuBangXepHang(
      client: MockClient((r) async {
        expect(r.method, 'GET');
        expect(r.url.path, '/api/bang-xep-hang/tong-the');
        expect(r.url.queryParameters, isEmpty);
        return http.Response(jsonEncode(data), 200);
      }),
    );
    final result = await api.taiTongThe();
    expect(result.bang, hasLength(30));
    expect(
      result.bang.first.vang,
      BigInt.parse('100000000000000000000000000000000001'),
    );
    expect(result.ban!.hang, 35);
    expect(() => result.bang.first.huyHieu.add(5), throwsUnsupportedError);
  });

  test('bad ranks, duplicate/unknown badges, floating gold and bad identity are rejected', () {
    for (final mutate in <void Function(Map<String, Object?>)>[
      (d) => (d['bang'] as List).first['huy_hieu'] = [1, 1],
      (d) => (d['bang'] as List).first['huy_hieu'] = [6],
      (d) => (d['bang'] as List).first['vang'] = 1.5,
      (d) => (d['bang'] as List).first['hang'] = 0,
      (d) => d['viewer'] = 'spoofed',
      (d) => d['cap_nhat_luc'] = 'invalid',
      (d) => d['du_lieu_cu'] = 'false',
    ]) {
      final data = duLieuTongThe();
      mutate(data);
      expect(() => BangTongThe.tuJson(data), throwsFormatException);
    }
    expect(
      () => BangTongThe.tuJson(duLieuTongThe(count: 31)),
      throwsFormatException,
    );
  });

  test('small server and no personal rank do not fabricate rows', () {
    final data = duLieuTongThe(count: 2);
    data['ban'] = null;
    data['tong_nguoi'] = 2;
    expect(BangTongThe.tuJson(data).bang, hasLength(2));
    expect(BangTongThe.tuJson(data).ban, isNull);
  });

  test('overall API still reports safe typed errors', () async {
    for (final status in [401, 500]) {
      final api = MayChuBangXepHang(
        client: MockClient((_) async => http.Response('private', status)),
      );
      await expectLater(api.taiTongThe(), throwsA(isA<LoiTaiBangXepHang>()));
    }
  });
}
