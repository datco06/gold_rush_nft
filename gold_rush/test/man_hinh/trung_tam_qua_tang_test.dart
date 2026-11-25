import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/ui/gold_rush_top_bar.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_hinh/trung_tam_qua_tang.dart';

void main() {
  testWidgets('Quà tặng hiện nút quét và trạng thái trong khung hình', (
    tester,
  ) async {
    final game = GoldRushGame();
    addTearDown(game.danhSachVatPham.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final camera = find.widgetWithText(FilledButton, 'MỞ CAMERA QUÉT QR');
    final status = find.text('Chưa có mã quà nào đang xử lý.');
    final gift = find.byWidgetPredicate(
      (widget) => widget is AspectRatio && widget.aspectRatio == 1.52,
    );

    for (final size in const [
      Size(1600, 1080),
      Size(1600, 720),
      Size(800, 360),
      Size(640, 320),
      Size(420, 720),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(home: ManHinhTrungTamQuaTang(game: game)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'Khung hình $size');
      expect(find.byType(GoldRushTopBar), findsOneWidget);
      expect(camera.hitTestable(), findsOneWidget, reason: 'Khung hình $size');
      expect(tester.getRect(camera).bottom, lessThanOrEqualTo(size.height));
      expect(tester.getRect(status).bottom, lessThanOrEqualTo(size.height));
      expect(tester.getRect(gift).bottom, lessThanOrEqualTo(size.height));
      if (size == const Size(1600, 1080)) {
        expect(tester.getSize(gift).width, 720);
        expect(tester.getSize(camera).height, 62);
      }
    }
  });
}
