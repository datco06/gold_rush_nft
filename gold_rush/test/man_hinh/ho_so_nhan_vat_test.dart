import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/kho_do/vat_pham_hien_thi.dart';
import 'package:gold_rush/man_hinh/ho_so_nhan_vat.dart';
import 'package:gold_rush/man_hinh/main_lobby.dart';
import 'package:gold_rush/man_hinh/bang_xep_hang.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';

import '../ngon_ngu/ho_tro_json.dart';

void _registerTestOverlays(GoldRushGame game) {
  for (final name in const [
    LopPhu.menu,
    LopPhu.cuaHang,
    LopPhu.caiDat,
    LopPhu.chonMan,
    LopPhu.khoDo,
  ]) {
    game.overlays.addEntry(name, (_, _) => const SizedBox.shrink());
  }
  game.overlays.add(LopPhu.menu);
}

Widget _wrapScreen(Widget child, Size size) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: SizedBox(width: size.width, height: size.height, child: child),
    ),
  );
}

void main() {
  setUpAll(chuanBiNgonNguChoKiemThu);

  for (final size in const [Size(844, 390), Size(1280, 720)]) {
    testWidgets('Profile right panel opens leaderboard and returns at $size in four languages', (tester) async {
      final game = GoldRushGame();
      addTearDown(game.danhSachVatPham.dispose);
      final lang = NgonNgu(doc: () async => null, ghi: (_) async {});
      addTearDown(lang.dispose);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(PhamViNgonNgu(ngonNgu: lang, child: _wrapScreen(CharacterProfileScreen(game: game), size)));
      for (final code in const ['vi', 'en', 'fr', 'es']) {
        await lang.doi(code);
        await tester.pumpAndSettle();
        final history = find.widgetWithText(OutlinedButton, lang.dich('Lịch sử màn chơi'));
        final rank = find.widgetWithText(OutlinedButton, lang.dich('Bảng xếp hạng tuần'));
        expect(rank, findsOneWidget, reason: code);
        await tester.ensureVisible(rank);
        final bounds = tester.getRect(rank);
        expect(bounds.top, greaterThanOrEqualTo(tester.getRect(history).bottom));
        expect(bounds.left, greaterThan(size.width / 2));
        expect(bounds.right, closeTo(tester.getRect(history).right, 0.1));
        expect(rank.hitTestable(), findsOneWidget);
        final profile = tester.state(find.byType(CharacterProfileScreen));
        await tester.tap(rank);
        await tester.pumpAndSettle();
        expect(find.byType(ManHinhBangXepHang), findsOneWidget);
        expect(tester.widget<ManHinhBangXepHang>(find.byType(ManHinhBangXepHang)).game, same(game));
        await tester.tap(find.byTooltip(lang.dich('Quay lại')));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(CharacterProfileScreen)), same(profile));
        expect(find.text(lang.dich('TRANG BỊ HIỆN TẠI')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size / $code');
      }
    });
  }

  testWidgets(
    'Clicking George in Main Lobby opens CharacterProfileScreen and X returns to Main Lobby',
    (tester) async {
      final game = GoldRushGame();
      _registerTestOverlays(game);
      addTearDown(game.danhSachVatPham.dispose);

      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrapScreen(GoldRushMainLobby(game: game), const Size(1280, 720)),
      );
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('datco6'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HỒ SƠ'), findsOneWidget);
      expect(find.text('THÔNG TIN NHÂN VẬT'), findsOneWidget);

      await tester.tap(find.byTooltip('Đóng Hồ sơ'));
      await tester.pumpAndSettle();

      expect(find.text('BẮT ĐẦU'), findsOneWidget);
      expect(find.text('HỒ SƠ'), findsNothing);
    },
  );

  testWidgets(
    'Profile screen has 4 allowed tabs, no fake Combat Power or Stats, and switches tabs cleanly',
    (tester) async {
      final game = GoldRushGame();
      _registerTestOverlays(game);
      addTearDown(game.danhSachVatPham.dispose);

      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrapScreen(CharacterProfileScreen(game: game), const Size(1280, 720)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 4 required tabs
      expect(find.text('CÁ NHÂN'), findsOneWidget);
      expect(find.text('HUY HIỆU'), findsOneWidget);
      expect(find.text('VŨ KHÍ'), findsOneWidget);
      expect(find.text('NHÂN VẬT'), findsOneWidget);

      // Forbidden sections / fake metrics must not exist
      expect(find.text('Lực chiến'), findsNothing);
      expect(find.text('THỐNG KÊ'), findsNothing);
      expect(find.text('Tỷ lệ thắng'), findsNothing);

      // Default tab: CÁ NHÂN
      expect(find.text('THÔNG TIN NHÂN VẬT'), findsOneWidget);
      expect(find.text('Bảng xếp hạng tuần'), findsOneWidget);
      expect(find.text('TRANG BỊ HIỆN TẠI'), findsOneWidget);
      expect(find.text('HUY HIỆU TRƯNG BÀY'), findsOneWidget);
      expect(find.text('Thợ mỏ tập sự'), findsOneWidget);

      // Tab 2: HUY HIỆU
      await tester.tap(find.text('HUY HIỆU'));
      await tester.pumpAndSettle();
      expect(find.text('Thợ mỏ tập sự'), findsOneWidget);
      expect(find.text('Huyền Thoại Gold Rush'), findsOneWidget);

      // Tab 3: VŨ KHÍ opens pre-built ManHinhKhoDo on Trang bị tab
      await tester.tap(find.text('VŨ KHÍ'));
      await tester.pumpAndSettle();
      expect(find.text('KHO ĐỒ'), findsOneWidget);
      expect(find.text('TÚI VẬT PHẨM'), findsOneWidget);

      // Close back to Profile
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('HỒ SƠ'), findsOneWidget);

      // Tab 4: NHÂN VẬT opens pre-built ManHinhKhoDo on Nhân vật tab
      await tester.tap(find.text('NHÂN VẬT'));
      await tester.pumpAndSettle();
      expect(find.text('KHO ĐỒ'), findsOneWidget);
      expect(find.text('BỘ SƯU TẬP NHÂN VẬT'), findsOneWidget);

      // Close back to Profile
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('HỒ SƠ'), findsOneWidget);
    },
  );

  testWidgets('VŨ KHÍ tab shows honest empty state when no weapons owned', (
    tester,
  ) async {
    final game = GoldRushGame();
    _registerTestOverlays(game);
    addTearDown(game.danhSachVatPham.dispose);
    game.danhSachVatPham.value = <VatPhamHienThi>[];

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrapScreen(CharacterProfileScreen(game: game), const Size(1280, 720)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('VŨ KHÍ'));
    await tester.pumpAndSettle();
    expect(find.text('KHO ĐỒ'), findsOneWidget);
    expect(find.text('Túi vật phẩm đang trống'), findsOneWidget);
  });

  testWidgets(
    'Responsive sizes (1920x1080, 1600x900, 1440x900, 1366x768, 1280x720, 800x600) have no overflow',
    (tester) async {
      for (final size in const [
        Size(1920, 1080),
        Size(1600, 900),
        Size(1440, 900),
        Size(1366, 768),
        Size(1280, 720),
        Size(800, 600),
      ]) {
        final game = GoldRushGame();
        _registerTestOverlays(game);
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          _wrapScreen(CharacterProfileScreen(game: game), size),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'Overflow at $size');
        game.danhSachVatPham.dispose();
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
}
