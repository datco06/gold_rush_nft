// ignore_for_file: depend_on_referenced_packages
import '../ngon_ngu/ho_tro_json.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/kho_do/danh_sach_trang_bi.dart';
import 'package:gold_rush/kho_do/danh_sach_nhan_vat.dart';
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
  setUpAll(chuanBiNgonNguChoKiemThu);
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
    'all location and enemy pictures remain visible, dimmed until discovered',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthLichSu();
      await LuuSoTayKhamPha(
        wallet: auth.wallet,
        chainId: auth.chain,
      ).ghi({'dia_diem:1', 'quai:zombie', 'quai:boss'});
      await tester.pumpWidget(
        wrap(ManHinhSoTayKhamPha(game: game(auth)), language()),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('so-tay-anh:dia_diem:1')),
        findsOneWidget,
      );
      Future<void> picture(
        String key, {
        required bool unlocked,
        String? sprite,
      }) async {
        final finder = find.byKey(ValueKey('so-tay-anh:$key'));
        await tester.scrollUntilVisible(finder, 160);
        final opacity = tester.widget<Opacity>(finder);
        expect(
          opacity.opacity,
          unlocked ? 1.0 : allOf(greaterThan(0), lessThan(1)),
        );
        final image = find.descendant(of: finder, matching: find.byType(Image));
        expect(image, findsOneWidget);
        final imageErrors = <Object>[];
        await tester.runAsync(
          () => precacheImage(
            tester.widget<Image>(image).image,
            tester.element(image),
            onError: (error, _) => imageErrors.add(error),
          ),
        );
        await tester.pumpAndSettle();
        expect(imageErrors, isEmpty, reason: key);
        expect(
          tester
              .getRect(find.byType(ListView))
              .overlaps(tester.getRect(finder)),
          isTrue,
        );
        if (sprite != null) {
          expect(
            tester
                .widget<AnhNhanVat>(
                  find.descendant(
                    of: finder,
                    matching: find.byType(AnhNhanVat),
                  ),
                )
                .tepAnh,
            sprite,
          );
        }
      }

      for (var id = 1; id <= 20; id++) {
        await picture('dia_diem:$id', unlocked: id == 1);
      }
      expect(find.text('Đã khám phá 1/20'), findsOneWidget);
      expect(find.text(stages.last.ten), findsNothing);
      await tester.tap(find.text('Quái & Boss'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 5000));
      await tester.pumpAndSettle();
      for (final entry in const {
        'zombie': 'zombie.png',
        'skeleton': 'skeleton.png',
        'thuong': 'quai_thuong.png',
        'giap': 'quai_giap.png',
        'khong_lo': 'quai_khong_lo.png',
        'boss': 'skeleton.png',
      }.entries) {
        await picture(
          'quai:${entry.key}',
          unlocked: entry.key == 'zombie' || entry.key == 'boss',
          sprite: entry.value,
        );
      }
      expect(find.text('Đã khám phá 2/6'), findsOneWidget);
      auth.wallet = '0x${'b' * 40}';
      auth.thayDoi();
      await tester.pumpAndSettle();
      await picture('quai:boss', unlocked: false, sprite: 'skeleton.png');
      expect(find.text('Boss'), findsNothing);
      expect(find.text('Đã khám phá 0/6'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile keeps history and tabs without notebook shortcut',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final g = game();
      await tester.pumpWidget(
        wrap(CharacterProfileScreen(game: g), language()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sổ tay khám phá'), findsNothing);
      expect(find.text('Lịch sử màn chơi'), findsOneWidget);
      expect(find.text('CÁ NHÂN'), findsOneWidget);
    },
  );

  testWidgets(
    'only locations and enemies remain, hiding equipment even when discovered',
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
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(find.text('Trang bị đã biết'), findsNothing);
      expect(find.text(items.first.ten), findsNothing);
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
      expect(find.text('Trang bị đã biết'), findsNothing);
      expect(find.text(items.first.ten), findsNothing);
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
          expect(find.text(entry.value[3]), findsNothing);
          expect(find.byType(ChoiceChip), findsNWidgets(2));
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
