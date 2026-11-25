import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/dieu_khien/nut_ban.dart';
import 'package:gold_rush/gold_rush_game.dart';

void main() {
  testWidgets('Joystick và nút Bắn thẳng hàng và cùng kích thước', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final joystick = JoystickComponent(size: 72);
    final game = GoldRushGame()..joystick = joystick;
    var soLanChamGame = 0;

    for (final (khung, le, kichThuoc) in [
      (const Size(800, 360), const EdgeInsets.only(left: 30, bottom: 12), 78.0),
      (
        const Size(1100, 500),
        const EdgeInsets.only(right: 30, bottom: 20),
        92.0,
      ),
      (const Size(1100, 500), const EdgeInsets.only(left: 24), 92.0),
    ]) {
      await tester.binding.setSurfaceSize(khung);
      game.onGameResize(Vector2(khung.width, khung.height));
      game.capNhatLeAnToanDieuKhien(le);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(size: khung, padding: le),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => soLanChamGame++,
                ),
                NutBan(game: game),
              ],
            ),
          ),
        ),
      );

      final rectBan = tester.getRect(find.byType(Image));
      expect(rectBan.size, Size.square(kichThuoc));
      expect(joystick.scaledSize.x, closeTo(kichThuoc, 0.001));
      expect(joystick.position.y, closeTo(rectBan.center.dy, 0.001));
      expect(
        joystick.position.x - kichThuoc / 2 - le.left,
        closeTo(khung.width - rectBan.right - le.right, 0.001),
      );

      final truocKhiCham = soLanChamGame;
      await tester.tapAt(rectBan.center);
      expect(soLanChamGame, truocKhiCham);
      await tester.tapAt(Offset(joystick.position.x, joystick.position.y));
      expect(soLanChamGame, truocKhiCham + 1);
    }
  });
}
