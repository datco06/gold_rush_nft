import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/ui/auth_gate.dart';
import 'package:gold_rush/auth/ui/welcome_screen.dart';
import 'package:gold_rush/main.dart';

void main() {
  testWidgets('real app starts behind AuthGate without constructing gameplay', (
    tester,
  ) async {
    await tester.pumpWidget(const UngDungGoldRush());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(AuthGate), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(ManHinhGame), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is GameWidget),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
