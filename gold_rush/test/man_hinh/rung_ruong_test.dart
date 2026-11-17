import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_hinh/rung_ruong.dart';

void main() {
  testWidgets('trang Rung rương không lỗi layout ở desktop và màn hình hẹp', (
    tester,
  ) async {
    final game = GoldRushGame();
    addTearDown(game.danhSachVatPham.dispose);

    for (final size in const [Size(1280, 720), Size(420, 720)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(MaterialApp(home: ManHinhRungRuong(game: game)));
      await tester.pump();

      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Lỗi layout tại $size');
      expect(find.text('RƯƠNG MAY MẮN'), findsOneWidget);
    }

    await tester.binding.setSurfaceSize(null);
  });
}
