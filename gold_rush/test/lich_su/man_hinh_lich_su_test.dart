// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/lich_su/lich_su_man_choi.dart';
import 'package:gold_rush/man_hinh/ho_so_nhan_vat.dart';
import 'package:gold_rush/man_hinh/lich_su_man_choi.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'ho_tro_lich_su.dart';

final class _DocCham extends InMemorySharedPreferencesAsync {
  _DocCham() : super.empty();
  final started = Completer<void>();
  final release = Completer<void>();
  bool block = false;
  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async {
    final value = await super.getString(key, options);
    if (block) {
      block = false;
      started.complete();
      await release.future;
    }
    return value;
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  GoldRushGame game([AuthLichSu? auth]) {
    final g = GoldRushGame(auth: auth);
    addTearDown(g.danhSachVatPham.dispose);
    addTearDown(g.phienVi!.dispose);
    return g;
  }

  Future<void> seed(AuthLichSu auth) async {
    final store = LuuLichSuManChoi(wallet: auth.wallet, chainId: auth.chain);
    for (final win in [true, false]) {
      await store.ghi(
        VanDaChoi(
          maVan: '$win',
          manId: 2,
          tenMan: 'Rừng thưa',
          thang: win,
          giay: 65.25,
          ketThuc: DateTime.utc(2026, 11, 22, 10, win ? 1 : 2),
        ),
      );
    }
  }

  Widget wrap(Widget screen, NgonNgu language) => PhamViNgonNgu(
    ngonNgu: language,
    child: MaterialApp(theme: ThemeData.dark(), home: screen),
  );

  testWidgets('profile opens history and back preserves the profile tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final g = game();
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    await tester.pumpWidget(wrap(CharacterProfileScreen(game: g), language));
    await tester.pumpAndSettle();
    final button = find.text('Lịch sử màn chơi');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(ManHinhLichSuManChoi), findsOneWidget);
    expect(find.text('Chưa có ván chơi hoàn thành.'), findsOneWidget);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('CÁ NHÂN'), findsOneWidget);
    expect(find.text('HUY HIỆU'), findsOneWidget);
  });

  testWidgets('real history supports all four languages on mobile sizes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthLichSu();
    await seed(auth);
    final g = game(auth);
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    final labels = {
      'vi': ['Lịch sử màn chơi', 'Thắng', 'Thua'],
      'en': ['Stage history', 'Victory', 'Defeat'],
      'fr': ['Historique des niveaux', 'Victoire', 'Défaite'],
      'es': ['Historial de niveles', 'Victoria', 'Derrota'],
    };
    for (final size in [
      const Size(844, 390),
      const Size(568, 320),
      const Size(360, 640),
    ]) {
      await tester.binding.setSurfaceSize(size);
      for (final entry in labels.entries) {
        await language.doi(entry.key);
        await tester.pumpWidget(wrap(ManHinhLichSuManChoi(game: g), language));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size / ${entry.key}');
        expect(find.text(entry.value[0]), findsOneWidget);
        expect(find.text(entry.value[1]), findsOneWidget);
        expect(find.text(entry.value[2]), findsOneWidget);
        expect(find.textContaining('01:05'), findsNWidgets(2));
        expect(find.textContaining('22/11/2026'), findsNWidgets(2));
        if (entry.key != 'vi') {
          expect(find.text('Rừng thưa'), findsNothing);
        }
      }
    }
  });

  testWidgets(
    'late read after switching wallet never reveals previous history',
    (tester) async {
      final prefs = _DocCham();
      SharedPreferencesAsyncPlatform.instance = prefs;
      final auth = AuthLichSu();
      await seed(auth);
      final g = game(auth);
      final language = NgonNgu(doc: () async => null, ghi: (_) async {});
      prefs.block = true;
      await tester.pumpWidget(wrap(ManHinhLichSuManChoi(game: g), language));
      await prefs.started.future;
      auth.wallet = '0x${'b' * 40}';
      auth.thayDoi();
      prefs.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('Rừng thưa'), findsNothing);
      expect(find.text('Chưa có ván chơi hoàn thành.'), findsOneWidget);
      auth.allowed = false;
      auth.thayDoi();
      await tester.pumpAndSettle();
      expect(find.text('Rừng thưa'), findsNothing);
    },
  );
}
