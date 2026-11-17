import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/huong_dan/huong_dan_tan_thu.dart';
import 'package:gold_rush/man_hinh/lop_phu.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing transitive test fake; no dependency is added to the project.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets(
    'lobby first visit and settings replay preserve the existing game',
    (tester) async {
      final previous = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final game = GoldRushGame();
      for (final name in [LopPhu.menu, LopPhu.chonMan, LopPhu.caiDat]) {
        game.overlays.addEntry(name, (_, _) => const SizedBox.shrink());
      }
      game.overlays.add(LopPhu.menu);
      addTearDown(game.danhSachVatPham.dispose);
      final stage = game.manHienTai;
      final items = game.danhSachVatPham.value;
      final language = NgonNgu(doc: () async => null, ghi: (_) async {});
      await language.doi('en');
      Widget app(Widget screen) => PhamViNgonNgu(
        ngonNgu: language,
        child: MaterialApp(home: screen),
      );

      await tester.pumpWidget(app(ManHinhMenu(game: game)));
      await tester.pumpAndSettle();
      expect(find.text('Beginner guide'), findsOneWidget);
      expect(find.text('Step 1/5'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(await SharedPreferencesAsync().getBool(LuuHuongDan.khoa), isTrue);
      expect(game.overlays.activeOverlays, [LopPhu.menu]);

      await tester.pumpWidget(app(ManHinhCaiDat(game: game)));
      await tester.pumpAndSettle();
      await language.doi('fr');
      await tester.pumpAndSettle();
      final replay = find.text('Revoir le guide');
      await tester.ensureVisible(replay);
      await tester.tap(replay);
      await tester.pumpAndSettle();
      expect(find.text('Guide du débutant'), findsOneWidget);
      expect(find.text('Étape 1/5'), findsOneWidget);
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Étape 2/5'), findsOneWidget);
      await tester.tap(find.text('Passer'));
      await tester.pumpAndSettle();
      expect(find.byType(ManHinhCaiDat), findsOneWidget);
      expect(game.manHienTai, same(stage));
      expect(game.danhSachVatPham.value, same(items));
      expect(game.overlays.activeOverlays, [LopPhu.menu]);

      await tester.pumpWidget(app(ManHinhMenu(game: game)));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final settingsVisible = ValueNotifier(true);
      addTearDown(settingsVisible.dispose);
      await tester.pumpWidget(
        app(
          ValueListenableBuilder<bool>(
            valueListenable: settingsVisible,
            builder: (_, visible, _) =>
                visible ? ManHinhCaiDat(game: game) : const Text('WELCOME'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Revoir le guide'));
      final openAgain = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Revoir le guide'),
          )
          .onPressed!;
      openAgain();
      openAgain();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      settingsVisible.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('WELCOME'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
