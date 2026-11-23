import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/bang_xep_hang/bang_xep_hang.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/man_hinh/bang_xep_hang.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lich_su/ho_tro_lich_su.dart';
import '../ngon_ngu/ho_tro_json.dart';
import 'may_chu_bang_xep_hang_test.dart' show duLieuBang, dongBang;

void main() {
  setUpAll(chuanBiNgonNguChoKiemThu);
  final stages = ManChoi.docDanhSach(
    File('assets/tiles/man_choi.json').readAsStringSync(),
  );

  Future<({AuthLichSu auth, GoldRushGame game, NgonNgu lang})> mount(
    WidgetTester tester,
    http.Client client, {
    bool login = true,
    String code = 'vi',
    Size size = const Size(844, 390),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthLichSu()..allowed = login;
    final game = GoldRushGame(auth: auth)..danhSachMan = stages;
    final lang = NgonNgu(doc: () async => null, ghi: (_) async {});
    await lang.doi(code);
    addTearDown(auth.dispose);
    addTearDown(lang.dispose);
    addTearDown(game.danhSachVatPham.dispose);
    addTearDown(game.phienVi!.dispose);
    await tester.pumpWidget(
      PhamViNgonNgu(
        ngonNgu: lang,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: ManHinhBangXepHang(
            game: game,
            mayChu: MayChuBangXepHang(client: client),
          ),
        ),
      ),
    );
    return (auth: auth, game: game, lang: lang);
  }

  for (final size in const [Size(844, 390), Size(568, 320), Size(360, 640)]) {
    testWidgets('Top and personal rank fit $size in all four languages', (
      tester,
    ) async {
      for (final code in const ['vi', 'en', 'fr', 'es']) {
        await tester.pumpWidget(const SizedBox.shrink());
        final client = MockClient(
          (_) async => http.Response(jsonEncode(duLieuBang()), 200),
        );
        final env = await mount(tester, client, code: code, size: size);
        await tester.pumpAndSettle();
        expect(find.text(env.lang.dich('Bảng xếp hạng tuần')), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text(env.lang.dich('Hạng 106')), findsOneWidget);
        expect(find.text(env.lang.dich('Hạng của bạn')), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, -220));
        await tester.pumpAndSettle();
        expect(find.text('Bob'), findsOneWidget);
        if (code != 'vi') expect(find.text('Bảng xếp hạng tuần'), findsNothing);
        expect(tester.takeException(), isNull, reason: '$size / $code');
      }
    });
  }

  testWidgets('loading and fast filter changes ignore old responses', (
    tester,
  ) async {
    final requests = <Uri>[];
    final pending = <Completer<http.Response>>[];
    await mount(
      tester,
      MockClient((r) {
        requests.add(r.url);
        final c = Completer<http.Response>();
        pending.add(c);
        return c.future;
      }),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bxh-stage')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Màn 1').last);
    await tester.pump();
    expect(requests.last.queryParameters['man'], '1');
    final filtered = duLieuBang(rows: [dongBang(name: 'New stage')])
      ..['man'] = 1;
    pending[1].complete(http.Response(jsonEncode(filtered), 200));
    await tester.pumpAndSettle();
    pending[0].complete(
      http.Response(
        jsonEncode(duLieuBang(rows: [dongBang(name: 'Old response')])),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New stage'), findsOneWidget);
    expect(find.text('Old response'), findsNothing);
  });

  testWidgets('logout and wallet switch hide old personal data immediately', (
    tester,
  ) async {
    final late = Completer<http.Response>();
    var count = 0;
    final env = await mount(
      tester,
      MockClient((_) {
        count++;
        return count == 1
            ? late.future
            : Future.value(
                http.Response(
                  jsonEncode(duLieuBang(rows: [])..['ban'] = null),
                  200,
                ),
              );
      }),
    );
    env.auth.allowed = false;
    env.auth.thayDoi();
    await tester.pump();
    expect(find.text('Đăng nhập để xem bảng xếp hạng.'), findsOneWidget);
    late.complete(http.Response(jsonEncode(duLieuBang()), 200));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    env.auth.wallet = '0x${'b' * 40}';
    env.auth.allowed = true;
    env.auth.thayDoi();
    await tester.pumpAndSettle();
    expect(count, 2);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('network error offers retry, empty result and mode filter work', (
    tester,
  ) async {
    var attempt = 0;
    final requests = <Uri>[];
    await mount(
      tester,
      MockClient((r) async {
        requests.add(r.url);
        if (attempt++ == 0) throw http.ClientException('test offline');
        final value = duLieuBang(rows: []);
        value['ban'] = null;
        value['tong_nguoi'] = 0;
        value['thich_ung'] = r.url.queryParameters['thich_ung'] == 'true';
        return http.Response(jsonEncode(value), 200);
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Không tải được bảng xếp hạng. Kiểm tra kết nối và thử lại.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(
      find.text('Chưa có thành tích được xác minh trong tuần này.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('bxh-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Độ khó thích ứng').last);
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters['thich_ung'], 'true');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unauthenticated page does not request or fabricate rankings', (
    tester,
  ) async {
    var calls = 0;
    await mount(
      tester,
      MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
      login: false,
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Đăng nhập để xem bảng xếp hạng.'), findsOneWidget);
  });

  testWidgets(
    'another tab changing the server session cannot display its personal rank',
    (tester) async {
      final response = duLieuBang();
      response['viewer'] = '0x${'b' * 40}';
      await mount(
        tester,
        MockClient((_) async => http.Response(jsonEncode(response), 200)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsNothing);
      expect(
        find.text('Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'),
        findsOneWidget,
      );
    },
  );
}
