// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/kho_do/danh_sach_trang_bi.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/man_hinh/ho_so_nhan_vat.dart';
import 'package:gold_rush/man_hinh/so_tay_kham_pha.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:gold_rush/so_tay/so_tay_kham_pha.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'ho_tro_so_tay.dart';

final class _DocCham extends InMemorySharedPreferencesAsync {
  _DocCham() : super.empty();
  bool block = false;
  final started = Completer<void>();
  final release = Completer<void>();
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
  final stages = ManChoi.docDanhSach(
    File('assets/tiles/man_choi.json').readAsStringSync(),
  );
  final items = danhSachTrangBiCuaHang();
  GoldRushGame game([AuthLichSu? auth]) {
    final g = GoldRushGame(auth: auth)..danhSachMan = stages;
    addTearDown(g.danhSachVatPham.dispose);
    addTearDown(g.phienVi!.dispose);
    return g;
  }

  Widget wrap(Widget screen, NgonNgu language) => PhamViNgonNgu(
    ngonNgu: language,
    child: MaterialApp(theme: ThemeData.dark(), home: screen),
  );
  NgonNgu language() => NgonNgu(doc: () async => null, ghi: (_) async {});

  testWidgets(
    'profile opens notebook and back keeps history and profile tabs',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final g = game();
      await tester.pumpWidget(
        wrap(CharacterProfileScreen(game: g), language()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sổ tay khám phá'));
      await tester.tap(find.text('Sổ tay khám phá'));
      await tester.pumpAndSettle();
      expect(find.byType(ManHinhSoTayKhamPha), findsOneWidget);
      expect(find.text('Đã khám phá 0/20'), findsOneWidget);
      expect(find.text(stages.first.ten), findsNothing);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.text('Lịch sử màn chơi'), findsOneWidget);
      expect(find.text('CÁ NHÂN'), findsOneWidget);
    },
  );

  testWidgets(
    'all three groups hide locked names and descriptions, and show discovered entries',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthLichSu();
      await LuuSoTayKhamPha(
        wallet: auth.wallet,
        chainId: auth.chain,
      ).ghi({'dia_diem:1', 'quai:zombie', 'trang_bi:${items.first.id}'});
      await tester.pumpWidget(
        wrap(ManHinhSoTayKhamPha(game: game(auth)), language()),
      );
      await tester.pumpAndSettle();
      expect(find.text(stages.first.ten), findsOneWidget);
      expect(find.text(stages[1].ten), findsNothing);
      expect(find.text(stages[1].moTa), findsNothing);
      expect(find.text('Đã khám phá 1/20'), findsOneWidget);
      await tester.tap(find.text('Quái & Boss'));
      await tester.pumpAndSettle();
      expect(find.text('Zombie'), findsOneWidget);
      expect(find.text('Bộ xương'), findsNothing);
      expect(
        find.text('Di chuyển nhanh hơn Zombie, tầm nhìn xa hơn.'),
        findsNothing,
      );
      expect(find.text('Đã khám phá 1/6'), findsOneWidget);
      await tester.tap(find.text('Trang bị đã biết'));
      await tester.pumpAndSettle();
      expect(find.text(items.first.ten), findsOneWidget);
      expect(find.text(items[1].ten), findsNothing);
      expect(find.text('Đã khám phá 1/27'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'four languages fit mobile sizes and localize unlocked and locked content',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthLichSu();
      await LuuSoTayKhamPha(
        wallet: auth.wallet,
        chainId: auth.chain,
      ).ghi({'quai:skeleton'});
      final g = game(auth);
      final lang = language();
      final labels = {
        'vi': [
          'Sổ tay khám phá',
          'Quái & Boss',
          'Bộ xương',
          'Trang bị đã biết',
        ],
        'en': [
          'Discovery notebook',
          'Enemies & Boss',
          'Skeleton',
          'Known equipment',
        ],
        'fr': [
          'Carnet d’exploration',
          'Ennemis et Boss',
          'Squelette',
          'Équipement connu',
        ],
        'es': [
          'Cuaderno de exploración',
          'Enemigos y Boss',
          'Esqueleto',
          'Equipo conocido',
        ],
      };
      for (final size in [
        const Size(844, 390),
        const Size(568, 320),
        const Size(360, 640),
      ]) {
        await tester.binding.setSurfaceSize(size);
        for (final entry in labels.entries) {
          await lang.doi(entry.key);
          await tester.pumpWidget(wrap(ManHinhSoTayKhamPha(game: g), lang));
          await tester.pumpAndSettle();
          expect(find.text(entry.value[0]), findsOneWidget);
          await tester.tap(find.text(entry.value[1]));
          await tester.pumpAndSettle();
          expect(find.text(entry.value[2]), findsOneWidget);
          if (entry.key != 'vi') {
            expect(find.text('Chưa khám phá'), findsNothing);
            expect(
              find.text('Di chuyển nhanh hơn Zombie, tầm nhìn xa hơn.'),
              findsNothing,
            );
          }
          await tester.tap(find.text(entry.value[3]));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$size / ${entry.key}',
          );
        }
      }
    },
  );

  testWidgets('late reads after wallet change cannot reveal old discoveries', (
    tester,
  ) async {
    final prefs = _DocCham();
    SharedPreferencesAsyncPlatform.instance = prefs;
    final auth = AuthLichSu();
    await LuuSoTayKhamPha(
      wallet: auth.wallet,
      chainId: auth.chain,
    ).ghi({'dia_diem:1'});
    prefs.block = true;
    await tester.pumpWidget(
      wrap(ManHinhSoTayKhamPha(game: game(auth)), language()),
    );
    await prefs.started.future;
    auth.wallet = '0x${'b' * 40}';
    auth.thayDoi();
    prefs.release.complete();
    await tester.pumpAndSettle();
    expect(find.text(stages.first.ten), findsNothing);
    expect(find.text('Đã khám phá 0/20'), findsOneWidget);
    auth.allowed = false;
    auth.thayDoi();
    await tester.pumpAndSettle();
    expect(find.text(stages.first.ten), findsNothing);
  });
}
