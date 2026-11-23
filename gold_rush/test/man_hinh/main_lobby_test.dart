import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/ui/gold_rush_top_bar.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/kho_do/vat_pham_hien_thi.dart';
import 'package:gold_rush/man_hinh/main_lobby.dart';
import 'package:gold_rush/man_hinh/so_tay_kham_pha.dart';
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

Widget _wrapLobby(GoldRushGame game, Size size) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: GoldRushMainLobby(game: game),
      ),
    ),
  );
}

void main() {
  setUpAll(chuanBiNgonNguChoKiemThu);

  for (final size in const [Size(844, 390), Size(1280, 720)]) {
    testWidgets('Lobby opens notebook and returns at $size in all languages', (
      tester,
    ) async {
      final game = GoldRushGame();
      _registerTestOverlays(game);
      addTearDown(game.danhSachVatPham.dispose);
      final language = NgonNgu(doc: () async => null, ghi: (_) async {});
      addTearDown(language.dispose);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        PhamViNgonNgu(ngonNgu: language, child: _wrapLobby(game, size)),
      );
      for (final code in const ['vi', 'en', 'fr', 'es']) {
        await language.doi(code);
        await tester.pumpAndSettle();
        final button = find.byTooltip(language.dich('Sổ tay khám phá'));
        expect(button, findsOneWidget, reason: code);
        expect(find.text(language.dich('Sổ tay khám phá')), findsNothing);
        expect(
          find.descendant(
            of: button,
            matching: find.byIcon(Icons.menu_book_rounded),
          ),
          findsOneWidget,
        );
        final bounds = tester.getRect(button);
        expect(bounds.size, const Size(48, 48));
        final topBar = tester.getRect(find.byType(GoldRushTopBar));
        expect(bounds.top, closeTo(topBar.bottom + 12, 0.1));
        expect(bounds.right, closeTo(topBar.right, 0.1));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(size.width));
        expect(bounds.bottom, lessThanOrEqualTo(size.height));
        expect(button.hitTestable(), findsOneWidget, reason: code);
        final lobby = tester.state(find.byType(GoldRushMainLobby));

        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(ManHinhSoTayKhamPha), findsOneWidget);
        expect(
          tester.widget<ManHinhSoTayKhamPha>(
            find.byType(ManHinhSoTayKhamPha),
          ).game,
          same(game),
        );
        await tester.tap(find.byTooltip(language.dich('Quay lại')));
        await tester.pumpAndSettle();
        expect(find.byType(ManHinhSoTayKhamPha), findsNothing);
        expect(tester.state(find.byType(GoldRushMainLobby)), same(lobby));
        expect(find.text(language.dich('BẮT ĐẦU')), findsOneWidget);
        expect(game.overlays.isActive(LopPhu.menu), isTrue);
        expect(tester.takeException(), isNull, reason: '$size / $code');
      }
    });
  }

  testWidgets(
    'Main Lobby renders header, George mini-profile, equipment panel, and START button without old menu buttons',
    (tester) async {
      final game = GoldRushGame();
      _registerTestOverlays(game);
      addTearDown(game.danhSachVatPham.dispose);

      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapLobby(game, const Size(1280, 720)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('GOLD RUSH'), findsOneWidget);
      expect(find.text('Sảnh chờ'), findsOneWidget);
      expect(find.text('Cửa hàng'), findsOneWidget);
      expect(find.text('datco6'), findsOneWidget);

      // No fake hardcoded gold or fake +15/+12 stats
      expect(find.text('46.384'), findsNothing);
      expect(find.text('+15'), findsNothing);
      expect(find.text('+12'), findsNothing);
      expect(find.text('0'), findsOneWidget);

      // Equipment panel & Start button
      expect(find.text('TRANG BỊ HIỆN TẠI'), findsOneWidget);
      expect(find.text('BẮT ĐẦU'), findsOneWidget);
      expect(find.text('« Phiêu Lưu Ngay »'), findsOneWidget);

      // Old vertical menu buttons must not appear directly on lobby
      expect(find.text('CHƠI'), findsNothing);
      expect(find.text('Đề xuất độ khó'), findsNothing);
      expect(find.text('Nhiệm vụ AI'), findsNothing);
      expect(find.text('Ảnh nhân vật AI'), findsNothing);
      expect(find.text('Cửa hàng nhân vật'), findsNothing);
    },
  );

  testWidgets(
    'Top-right Shop/Settings, George mini-profile dialog, and START button callbacks work',
    (tester) async {
      final game = GoldRushGame();
      _registerTestOverlays(game);
      addTearDown(game.danhSachVatPham.dispose);

      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapLobby(game, const Size(1280, 720)));
      await tester.pump(const Duration(milliseconds: 500));

      // Tap Shop & Settings
      await tester.tap(find.text('Cửa hàng'));
      await tester.pump();
      expect(game.overlays.isActive(LopPhu.cuaHang), isTrue);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump();
      expect(game.overlays.isActive(LopPhu.caiDat), isTrue);

      // Tap BẮT ĐẦU
      await tester.tap(find.text('BẮT ĐẦU'));
      await tester.pump();
      expect(game.overlays.isActive(LopPhu.chonMan), isTrue);

      // Tap George mini-profile opens full CharacterProfileScreen
      await tester.tap(find.text('datco6'));
      await tester.pumpAndSettle();

      expect(find.text('HỒ SƠ'), findsOneWidget);
      expect(find.text('CÁ NHÂN'), findsOneWidget);
      expect(find.text('HUY HIỆU'), findsOneWidget);
      expect(find.text('VŨ KHÍ'), findsOneWidget);
      expect(find.text('NHÂN VẬT'), findsOneWidget);

      // Tap X close button returns to Main Lobby
      await tester.tap(find.byTooltip('Đóng Hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.text('BẮT ĐẦU'), findsOneWidget);
    },
  );

  testWidgets(
    'TRANG BỊ HIỆN TẠI reflects live equipped items from game.danhSachVatPham',
    (tester) async {
      final game = GoldRushGame();
      _registerTestOverlays(game);
      addTearDown(game.danhSachVatPham.dispose);

      game.danhSachVatPham.value = [
        VatPhamHienThi(
          id: 'cuoc_vang_01',
          ten: 'Cuốc Vàng Cổ',
          moTa: 'Tăng tốc đào vàng',
          loai: LoaiVatPham.vuKhi,
          danhMuc: DanhMucVatPham.vuKhi,
          doHiem: DoHiemVatPham.suThi,
          nguon: NguonVatPham.game,
          bieuTuong: BieuTuongVatPham.kiem,
          thuocTinh: const {'Sát thương': '+24'},
        ),
      ];
      game.danhSachVatPham.value = [
        game.danhSachVatPham.value.single.voiTrangBi(OTrangBi.vuKhiChinh),
      ];

      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapLobby(game, const Size(1280, 720)));
      await tester.pump(const Duration(milliseconds: 500));

      // Tap supported primary weapon slot to inspect equipped item
      await tester.tap(find.byTooltip('Vũ khí chính: Cuốc Vàng Cổ'));
      await tester.pumpAndSettle();

      expect(find.text('Cuốc Vàng Cổ'), findsWidgets);
      expect(find.text('Sát thương'), findsOneWidget);
      expect(find.text('+24'), findsWidgets);
      expect(find.text('Mở Kho đồ'), findsOneWidget);
    },
  );

  testWidgets(
    'Responsive desktop sizes 1440x900 and 1920x1080 have no overflow',
    (tester) async {
      for (final size in const [Size(1440, 900), Size(1920, 1080)]) {
        final game = GoldRushGame();
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(_wrapLobby(game, size));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'Overflow at $size');
        game.danhSachVatPham.dispose();
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
}
