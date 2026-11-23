import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gold_rush/bang_xep_hang/bang_xep_hang.dart';

Map<String, Object?> duLieuBang({
  List<Map<String, Object?>>? rows,
  Object? mine,
}) => {
  'tuan': '2026-11-23',
  'bat_dau': '2026-11-22T17:00:00+00:00',
  'ket_thuc': '2026-11-29T17:00:00+00:00',
  'chain_id': 31337,
  'man': null,
  'thich_ung': false,
  'tong_nguoi': 106,
  'bang': rows ?? [dongBang()],
  'ban': mine ?? dongBang(rank: 106, name: 'Alice', me: true),
};

Map<String, Object?> dongBang({
  int rank = 1,
  String name = 'Bob',
  bool me = false,
}) => {
  'hang': rank,
  'ten': name,
  'diem': 100,
  'giay': 55.25,
  'so_man': 1,
  'la_ban': me,
};

class _TrackedClient extends MockClient {
  _TrackedClient(super.fn);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test(
    'client sends only ranking filters and parses personal rank beyond top',
    () async {
      final client = _TrackedClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/bang-xep-hang/tuan');
        expect(request.url.queryParameters, {
          'man': '7',
          'thich_ung': 'true',
          'top': '100',
        });
        expect(request.headers['Accept'], 'application/json');
        return http.Response(
          jsonEncode(duLieuBang()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = MayChuBangXepHang(client: client);
      final result = await api.tai(man: 7, thichUng: true);
      expect(result.ban!.hang, 106);
      expect(result.bang.single.ten, 'Bob');
      expect(result.bang.single.giay, 55.25);
      expect(result.ketThuc.isUtc, isTrue);
      api.dong();
      expect(client.closed, isFalse);
      client.close();
    },
  );

  for (final status in [401, 403, 500]) {
    test('HTTP $status returns safe typed error', () async {
      final api = MayChuBangXepHang(
        client: MockClient(
          (_) async => http.Response('private response', status),
        ),
      );
      await expectLater(
        api.tai(),
        throwsA(
          isA<LoiTaiBangXepHang>().having(
            (error) => error.loai,
            'loai',
            status == 401 || status == 403
                ? LoiBangXepHang.dangNhap
                : LoiBangXepHang.mayChu,
          ),
        ),
      );
    });
  }

  test('network and malformed responses are distinct safe errors', () async {
    final offline = MayChuBangXepHang(
      client: MockClient(
        (_) async => throw http.ClientException('private connection details'),
      ),
    );
    await expectLater(
      offline.tai(),
      throwsA(
        isA<LoiTaiBangXepHang>().having(
          (e) => e.loai,
          'loai',
          LoiBangXepHang.ketNoi,
        ),
      ),
    );
    for (final value in [
      <String, Object?>{},
      duLieuBang()..['tong_nguoi'] = -1,
      duLieuBang()..['bang'] = [dongBang()..['giay'] = -2],
      duLieuBang()..['ket_thuc'] = 'bad-date',
    ]) {
      final api = MayChuBangXepHang(
        client: MockClient((_) async => http.Response(jsonEncode(value), 200)),
      );
      await expectLater(
        api.tai(),
        throwsA(
          isA<LoiTaiBangXepHang>().having(
            (e) => e.loai,
            'loai',
            LoiBangXepHang.duLieu,
          ),
        ),
      );
    }
  });

  test('empty leaderboard and null personal row are valid', () {
    final value = duLieuBang(rows: []);
    value['ban'] = null;
    value['tong_nguoi'] = 0;
    final result = BangXepHangTuan.tuJson(value);
    expect(result.bang, isEmpty);
    expect(result.ban, isNull);
  });
}
