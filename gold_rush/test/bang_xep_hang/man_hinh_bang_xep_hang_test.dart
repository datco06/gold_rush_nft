import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/bang_xep_hang/bang_xep_hang.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_hinh/bang_xep_hang.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../lich_su/ho_tro_lich_su.dart';
import '../ngon_ngu/ho_tro_json.dart';
import 'tong_the_test.dart' show duLieuTongThe;

class _IdentityTransport extends http.BaseClient {
  int calls = 0;
  final pending = Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    calls++;
    if (calls == 1) {
      if (request case http.AbortableRequest(:final abortTrigger?)) {
        unawaited(
          abortTrigger.then((_) {
            if (!pending.isCompleted) {
              pending.completeError(http.RequestAbortedException());
            }
          }),
        );
      }
      return pending.future;
    }
    final data = duLieuTongThe(viewer: '0x${'b' * 40}');
    (data['ban'] as Map)['ten'] = 'Bob';
    return Future.value(
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(data))), 200),
    );
  }
}

void main() {
  setUpAll(chuanBiNgonNguChoKiemThu);

  Future<({AuthLichSu auth, NgonNgu lang})> mount(
    WidgetTester tester,
    http.Client client, {
    String code = 'vi',
    Size size = const Size(844, 390),
    bool login = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthLichSu()..allowed = login;
    final game = GoldRushGame(auth: auth);
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
    return (auth: auth, lang: lang);
  }

  http.Response response([Map<String, Object?>? data]) =>
      http.Response(jsonEncode(data ?? duLieuTongThe()), 200);

  testWidgets(
    'identity change starts a new HTTP exchange and keeps the valid session polling',
    (tester) async {
      final transport = _IdentityTransport();
      final env = await mount(tester, transport);
      env.auth.wallet = '0x${'b' * 40}';
      env.auth.thayDoi();
      await tester.pump();
      if (!transport.pending.isCompleted) {
        transport.pending.complete(
          http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(duLieuTongThe()))),
            200,
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(
        find.text('Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'),
        findsNothing,
      );
      expect(transport.calls, 2);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(transport.calls, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  Future<void> close(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('English and French show current gold balance as a grouped integer', (
    tester,
  ) async {
    for (final code in ['en', 'fr']) {
      final data = duLieuTongThe();
      (data['bang'] as List).first['vang'] = '1234';
      await mount(tester, MockClient((_) async => response(data)), code: code);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('bxh-row-1')),
        180,
      );
      expect(
        find.text(
          code == 'en' ? 'Gold: 1,234' : 'Or : 1\u202f234',
        ),
        findsOneWidget,
      );
      await close(tester);
    }
  });

  for (final size in const [Size(844, 390), Size(568, 320), Size(360, 640)]) {
    testWidgets(
      'Overall Top30 fits $size in four languages and keeps own rank',
      (tester) async {
        for (final code in const ['vi', 'en', 'fr', 'es']) {
          await close(tester);
          final env = await mount(
            tester,
            MockClient((_) async => response()),
            code: code,
            size: size,
          );
          await tester.pumpAndSettle();
          expect(find.text(env.lang.dich('Bảng xếp hạng')), findsOneWidget);
          expect(find.text('Alice'), findsOneWidget);
          expect(find.text(env.lang.dich('Hạng 35')), findsOneWidget);
          expect(find.byType(DropdownButton<int>), findsNothing);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('bxh-row-30')),
            250,
          );
          expect(find.text('Player30'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$size / $code');
        }
        await close(tester);
      },
    );
  }

  testWidgets('Three position bands have distinct borders and tier labels', (
    tester,
  ) async {
    await mount(tester, MockClient((_) async => response()));
    await tester.pumpAndSettle();
    final colors = <Color>[];
    for (final rank in [1, 11, 21, 30]) {
      final row = find.byKey(ValueKey('bxh-row-$rank'));
      await tester.scrollUntilVisible(row, 180);
      final box = tester.widget<Container>(row).decoration! as BoxDecoration;
      colors.add((box.border! as Border).top.color);
      if (rank != 30) {
        expect(
          find.text(
            rank <= 10
                ? 'Top 10'
                : rank <= 20
                ? 'Top 20'
                : 'Top 30',
          ),
          findsWidgets,
        );
      }
    }
    expect(colors.take(3).toSet(), hasLength(3));
    expect(colors[2], colors[3]);
    await close(tester);
  });

  testWidgets(
    'Refresh every 60 seconds without overlap, pause in background and cancel on dispose',
    (tester) async {
      var calls = 0;
      final pending = Completer<http.Response>();
      await mount(
        tester,
        MockClient((_) {
          calls++;
          return calls == 1 ? pending.future : Future.value(response());
        }),
      );
      await tester.pump(const Duration(seconds: 60));
      expect(calls, 1);
      pending.complete(response());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 120));
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 3);
      await close(tester);
      await tester.pump(const Duration(seconds: 120));
      expect(calls, 3);
    },
  );

  testWidgets(
    'Account switch rejects old responses and cross-tab server identity',
    (tester) async {
      final late = Completer<http.Response>();
      var calls = 0;
      final env = await mount(
        tester,
        MockClient((_) {
          calls++;
          return calls == 1 ? late.future : Future.value(response());
        }),
      );
      env.auth.wallet = '0x${'b' * 40}';
      env.auth.thayDoi();
      await tester.pump();
      late.complete(response());
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsNothing);
      expect(
        find.text('Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'),
        findsOneWidget,
      );
      env.auth.allowed = false;
      env.auth.thayDoi();
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập để xem bảng xếp hạng.'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'Refresh error retains same-session list and stale source is labelled',
    (tester) async {
      var calls = 0;
      await mount(
        tester,
        MockClient((_) async {
          if (++calls == 1) return response(duLieuTongThe(stale: true));
          throw http.ClientException('offline');
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Đang hiển thị dữ liệu cập nhật lần trước.'),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsOneWidget);
      await tester.tap(find.byTooltip('Làm mới'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(
        find.text('Không tải được bảng xếp hạng. Kiểm tra kết nối và thử lại.'),
        findsOneWidget,
      );
      await close(tester);
    },
  );

  testWidgets('Empty and unauthenticated states create no fake players', (
    tester,
  ) async {
    final empty = duLieuTongThe(count: 0)..['tong_nguoi'] = 0;
    empty['ban'] = null;
    await mount(tester, MockClient((_) async => response(empty)));
    await tester.pumpAndSettle();
    expect(
      find.text('Chưa có người chơi trong bảng xếp hạng.'),
      findsOneWidget,
    );
    await close(tester);
    var calls = 0;
    await mount(
      tester,
      MockClient((_) async {
        calls++;
        return response();
      }),
      login: false,
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Đăng nhập để xem bảng xếp hạng.'), findsOneWidget);
    await close(tester);
  });
}
