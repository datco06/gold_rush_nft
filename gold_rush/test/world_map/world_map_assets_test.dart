import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/man_hinh/chon_man.dart';
import 'package:gold_rush/world_map/canh_quan_world_map.dart';
import 'package:gold_rush/world_map/nut_man_choi.dart';
import 'package:gold_rush/world_map/luu_tien_trinh.dart';

class _KhoMayMoi implements KhoTienTrinhLocal {
  @override
  Future<String?> doc() async => null;
  @override
  Future<void> ghi(String noiDung) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<ManChoi> cacMan;

  setUpAll(() async {
    // Đọc asset bundle thật và dữ liệu level thật, không tạo tiến trình mẫu.
    await TaiNguyenWorldMap.nap();
    await TaiNguyenWorldMap.napAnhGeorge();
    cacMan = ManChoi.docBoManChoi(
      await rootBundle.loadString('assets/tiles/man_choi.json'),
      await rootBundle.loadString('assets/tiles/man_mo_rong.json'),
    );
    final font = Platform.environment['WORLD_MAP_PREVIEW_FONT'];
    if (font != null) {
      final loader = FontLoader('Roboto')
        ..addFont(File(font).readAsBytes().then(ByteData.sublistView));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  test(
    'Lâu đài và nhà mới giải mã được, không còn render PNG trang trí cũ',
    () async {
      final first = await TaiNguyenWorldMap.nap();
      final second = await TaiNguyenWorldMap.nap();
      expect(first.keys, unorderedEquals(TaiNguyenWorldMap.tenAnh));
      expect(first, hasLength(TaiNguyenWorldMap.tenAnh.length));
      expect(identical(first, second), isTrue);
      expect(first.keys, contains('lau_dai.png'));
      for (final removed in [
        'hang_da.png',
        'thac_nuoc.png',
        'day_nui.png',
        'den_co.png',
        'cay_co_thu.png',
        'mat_nuoc.png',
        'nha_lang.png',
        'xoay_nuoc.png',
      ]) {
        expect(first.containsKey(removed), isFalse);
      }
      for (final image in first.values) {
        expect(image.width, greaterThan(0));
        expect(image.height, greaterThan(0));
      }
      for (final building in BoCucWorldMap.congTrinh) {
        final image = first[building.anh]!;
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var transparent = 0;
        for (var i = 3; i < rgba.lengthInBytes; i += 4) {
          if (rgba.getUint8(i) < 16) transparent++;
        }
        expect(
          transparent / (image.width * image.height),
          greaterThan(0.05),
          reason:
              '${building.anh} phải có nền trong suốt, không lộ hình chữ nhật.',
        );
        final crop =
            TaiNguyenWorldMap.khungNguon[building.anh] ??
            const Rect.fromLTWH(0, 0, 1, 1);
        final height =
            building.chieuRong *
            image.height *
            crop.height /
            (image.width * crop.width);
        expect(
          height,
          lessThanOrEqualTo(190),
          reason: 'Nhà/tháp không lấn át lâu đài.',
        );
        final bounds = Rect.fromLTWH(
          building.chan.dx - building.chieuRong / 2,
          building.chan.dy - height,
          building.chieuRong,
          height,
        );
        expect(
          (Offset.zero & BoCucWorldMap.kichThuoc).contains(bounds.topLeft),
          isTrue,
        );
        expect(
          (Offset.zero & BoCucWorldMap.kichThuoc).contains(bounds.bottomRight),
          isTrue,
        );
      }
    },
  );

  for (final size in [
    const Size(1440, 900),
    const Size(1280, 720),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('20 công trình và khóa hoạt động ở ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Dùng màn chọn thật và Game thật nhưng không mount Gameplay/khởi tạo ví.
      final progress = BoTienTrinhWorldMap(kho: _KhoMayMoi());
      addTearDown(progress.dispose);
      await progress.nap(cacMan);
      final game = GoldRushGame()..danhSachMan = cacMan;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFE3A008),
                brightness: Brightness.dark,
              ),
              fontFamily:
                  Platform.environment.containsKey('WORLD_MAP_PREVIEW_FONT')
                  ? 'Roboto'
                  : null,
            ),
            home: Scaffold(
              body: ManHinhChonMan(game: game, tienTrinh: progress.tienTrinh),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scene = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<CanhQuanWorldMap>()
          .single;
      expect(
        scene.anh,
        hasLength(TaiNguyenWorldMap.tenAnh.length),
        reason: 'Cảnh chỉ dùng lâu đài và bộ nhà mới.',
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(NutManChoi), findsNWidgets(20));
      expect(find.textContaining('Chưa nạp được ảnh'), findsNothing);
      expect(cacMan, hasLength(20));
      expect(
        BoCucWorldMap.congTrinh.map((c) => c.id).toSet(),
        unorderedEquals(cacMan.map((m) => m.id)),
      );
      expect(
        scene.trangThaiCacMan.values.where((s) => s == TrangThaiMan.chuaMo),
        hasLength(19),
      );
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(19));

      final view = tester.getRect(find.byType(InteractiveViewer));
      final rects = <Rect>[];
      for (final man in cacMan) {
        final finder = find.byKey(ValueKey('world-map-level-${man.id}'));
        final rect = tester.getRect(finder);
        expect(view.contains(rect.topLeft), isTrue);
        expect(view.contains(rect.bottomRight), isTrue);
        expect(rects.every((other) => !other.overlaps(rect)), isTrue);
        rects.add(rect);
      }

      // Xuất chính Widget Flutter đã render, không ghép ảnh mô phỏng giao diện.
      final output = Platform.environment['WORLD_MAP_SCREENSHOT_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory(output);
            await dir.create(recursive: true);
            await File(
              '$output/world-map-${size.width.toInt()}x${size.height.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      for (final man in cacMan) {
        await tester.tap(find.byKey(ValueKey('world-map-level-${man.id}')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final selected = tester
            .widgetList<NutManChoi>(find.byType(NutManChoi))
            .where((node) => node.dangChon);
        expect(selected.single.man.id, man.id);
        if (man.id != 1) {
          final button = find.widgetWithText(FilledButton, 'Màn chưa mở');
          expect(tester.widget<FilledButton>(button).onPressed, isNull);
        }
      }
      if (size == const Size(1440, 900)) {
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final transform = viewer.transformationController!;
        final oldScale = transform.value.getMaxScaleOnAxis();
        final marker = find.byKey(const ValueKey('world-map-level-1'));
        final oldSize = tester.getSize(marker);
        final oldPosition = tester.getCenter(marker);
        await tester.tap(find.byTooltip('Phóng to'));
        await tester.pumpAndSettle();
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(oldScale));
        expect(tester.getSize(marker).width, closeTo(oldSize.width, 0.001));
        expect(
          tester.getSize(marker).height,
          closeTo(oldSize.height, 0.001),
          reason: 'Nhãn và vùng bấm giữ kích thước đọc được khi zoom.',
        );
        expect(
          tester.getCenter(marker),
          isNot(oldPosition),
          reason: 'Marker phải di chuyển cùng địa điểm trên bản đồ.',
        );
        await tester.tap(find.byTooltip('Toàn bản đồ'));
        await tester.pumpAndSettle();
        expect(transform.value.getMaxScaleOnAxis(), closeTo(oldScale, 0.001));
        final beforePan = transform.value.clone();
        await tester.dragFrom(
          view.topLeft + const Offset(25, 100),
          const Offset(80, 20),
        );
        await tester.pumpAndSettle();
        expect(transform.value, isNot(beforePan));

        if (output != null) {
          Future<void> chupThem(String tenTep) async {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$output/$tenTep',
                ).writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }

          // 1. Chụp George nổi bật tại vùng Làng / Rừng khi zoom vào George:
          await tester.tap(find.byTooltip('Định vị George'));
          await tester.pumpAndSettle();
          await chupThem('world-map-zoom-lang-rung.png');

          // 2. Chụp góc nhìn zoom gần vùng Núi lửa / Đền cổ:
          const scaleZoom = 0.88;
          final dichNuiLua = BoCucWorldMap.tinhDichChuyenTapTrungDiem(
            diemTheGioi: const Offset(2340, 780),
            tiLe: scaleZoom,
            kichThuocKhung: view.size,
          );
          transform.value = Matrix4.identity()
            ..setEntry(0, 0, scaleZoom)
            ..setEntry(1, 1, scaleZoom)
            ..setEntry(2, 2, scaleZoom)
            ..setEntry(0, 3, dichNuiLua.dx)
            ..setEntry(1, 3, dichNuiLua.dy);
          await tester.pumpAndSettle();
          await chupThem('world-map-zoom-nuilua-denco.png');

          // 3. Chụp góc nhìn zoom gần vùng Mỏ vàng / Kho báu trung tâm:
          final dichMoVang = BoCucWorldMap.tinhDichChuyenTapTrungDiem(
            diemTheGioi: const Offset(1440, 840),
            tiLe: scaleZoom,
            kichThuocKhung: view.size,
          );
          transform.value = Matrix4.identity()
            ..setEntry(0, 0, scaleZoom)
            ..setEntry(1, 1, scaleZoom)
            ..setEntry(2, 2, scaleZoom)
            ..setEntry(0, 3, dichMoVang.dx)
            ..setEntry(1, 3, dichMoVang.dy);
          await tester.pumpAndSettle();
          await chupThem('world-map-zoom-movang-khobau.png');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
