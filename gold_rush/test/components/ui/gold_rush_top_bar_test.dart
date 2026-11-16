import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/ui/gold_rush_top_bar.dart';

void main() {
  testWidgets('TopBar hiển thị logo, menu và mục đang chọn', (tester) async {
    var khoDoTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            child: GoldRushTopBar(
              activeItem: GoldRushTopBarItem.khoDo,
              onKhoDo: () => khoDoTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('GOLD RUSH'), findsOneWidget);
    expect(find.text('Sảnh chờ'), findsOneWidget);
    expect(find.text('Cửa hàng'), findsOneWidget);
    expect(find.text('Kho đồ'), findsOneWidget);
    expect(find.text('Xưởng AI'), findsNothing);

    await tester.tap(find.text('Kho đồ'));
    expect(khoDoTapped, isTrue);
  });

  testWidgets('TopBar thu gọn vẫn cuộn được menu', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, child: GoldRushTopBar())),
      ),
    );

    expect(find.text('GOLD RUSH'), findsOneWidget);
    expect(find.text('Xưởng AI'), findsNothing);
  });
}
