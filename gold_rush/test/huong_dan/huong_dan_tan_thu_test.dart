import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/huong_dan/huong_dan_tan_thu.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';

void main() {
  test(
    'seen state survives a new controller and failed storage is harmless',
    () async {
      bool? saved;
      final store = LuuHuongDan(
        doc: () async => saved,
        ghi: () async => saved = true,
      );
      expect(await store.nenHienTuDong(), isTrue);
      await store.danhDauDaXem();
      expect(await store.nenHienTuDong(), isFalse);
      expect(
        await LuuHuongDan(doc: () async => saved).nenHienTuDong(),
        isFalse,
      );
      final broken = LuuHuongDan(
        doc: () async => throw StateError('read'),
        ghi: () async => throw StateError('write'),
      );
      expect(await broken.nenHienTuDong(), isFalse);
      await broken.danhDauDaXem();
      expect(await broken.nenHienTuDong(), isFalse);
    },
  );

  Future<void> open(
    WidgetTester tester,
    LuuHuongDan store, {
    NgonNgu? language,
  }) async {
    await tester.pumpWidget(
      PhamViNgonNgu(
        ngonNgu: language ?? NgonNgu(doc: () async => null, ghi: (_) async {}),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => moHuongDanTanThu(context, luu: store),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  testWidgets('five pages support back and finish without starting a game', (
    tester,
  ) async {
    var writes = 0;
    final store = LuuHuongDan(
      doc: () async => false,
      ghi: () async => writes++,
    );
    await open(tester, store);
    expect(find.text('Bước 1/5'), findsOneWidget);
    expect(find.text('Làm quen với sảnh'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Quay lại'), findsNothing);
    await tester.tap(find.text('Tiếp theo'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn màn chơi đầu tiên'), findsOneWidget);
    await tester.tap(find.text('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Bước 1/5'), findsOneWidget);
    const titles = [
      'Chọn màn chơi đầu tiên',
      'Điều khiển nhân vật',
      'Mục tiêu ván chơi',
      'Chuẩn bị cho hành trình',
    ];
    for (final title in titles) {
      await tester.tap(find.text('Tiếp theo'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Bước 5/5'), findsOneWidget);
    expect(writes, 0);
    await tester.tap(find.text('Hoàn tất'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(writes, 1);
    expect(await store.nenHienTuDong(), isFalse);
    expect(find.text('OPEN'), findsOneWidget);
  });

  testWidgets('skip saves seen state and replay starts at step one', (
    tester,
  ) async {
    var writes = 0;
    final store = LuuHuongDan(
      doc: () async => false,
      ghi: () async => writes++,
    );
    await open(tester, store);
    await tester.tap(find.text('Tiếp theo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bỏ qua'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Bước 1/5'), findsOneWidget);
    await tester.tap(find.text('Bỏ qua'));
    await tester.pumpAndSettle();
    expect(writes, 2);
  });

  testWidgets('all five pages fit four languages on narrow and short screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    for (final size in [const Size(320, 568), const Size(844, 390)]) {
      tester.view.physicalSize = size;
      for (final code in NgonNgu.hoTro.keys) {
        await language.doi(code);
        final store = LuuHuongDan(doc: () async => false, ghi: () async {});
        await open(tester, store, language: language);
        for (var page = 1; page <= 5; page++) {
          final label = page == 5 ? 'Hoàn tất' : 'Tiếp theo';
          final button = find.widgetWithText(
            FilledButton,
            language.dich(label),
          );
          expect(button, findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$size/$code/$page');
          await tester.tap(button);
          await tester.pumpAndSettle();
        }
      }
    }
  });

  testWidgets(
    'first-entry gate checks readiness after delayed storage and unmount',
    (tester) async {
      final read = Completer<bool?>();
      final store = LuuHuongDan(doc: () => read.future, ghi: () async {});
      var ready = true;
      await tester.pumpWidget(
        MaterialApp(
          home: HuongDanLanDau(
            luu: store,
            sanSang: () => ready,
            child: const Text('LOBBY'),
          ),
        ),
      );
      ready = false;
      read.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(await store.nenHienTuDong(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('first-entry gate opens once and ignores rebuilds', (
    tester,
  ) async {
    final store = LuuHuongDan(doc: () async => false, ghi: () async {});
    Widget lobby() => MaterialApp(
      home: HuongDanLanDau(luu: store, child: const Text('LOBBY')),
    );
    await tester.pumpWidget(lobby());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Bỏ qua'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(lobby());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
