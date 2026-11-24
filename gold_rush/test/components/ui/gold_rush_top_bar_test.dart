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

    final inventory = find.text('Kho đồ');
    await tester.ensureVisible(inventory);
    await tester.pumpAndSettle();
    await tester.tap(inventory);
    expect(khoDoTapped, isTrue);
  });

  testWidgets('Compact top bar keeps navigation readable and scrollable', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: GoldRushTopBar(
              playerName:
                  'A long player name with Vietnamese accents Tiếng Việt',
              onKhoDo: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('GOLD RUSH'), findsOneWidget);
    final firstLabel = tester.getRect(find.text('Sảnh chờ'));
    expect(firstLabel.height, greaterThanOrEqualTo(14));
    final inventory = find.text('Kho đồ');
    await tester.ensureVisible(inventory);
    await tester.pumpAndSettle();
    await tester.tap(inventory);
    expect(tapped, isTrue);
  });
}
