import 'ho_tro_json.dart';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/hud.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';

void main() {
  setUpAll(chuanBiNgonNguChoKiemThu);
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'HUD changes labels while preserving score and remaining coins',
    () async {
      final language = NgonNgu(doc: () async => null, ghi: (_) async {});
      var score = 120;
      final hud = Hud(
        layMau: () => 100,
        layDiem: () => score,
        layXuConLai: () => 7,
        layGiayConLai: () => null,
        ngonNgu: language,
      );
      final game = FlameGame(children: [hud]);
      game.onGameResize(Vector2(800, 600));
    // Mount a bare Flame game without assets, HTTP or a running render loop.
    // ignore: invalid_use_of_internal_member
    await game.load();
    // ignore: invalid_use_of_internal_member
    game.mount();
      await game.ready();
      game.update(0);
      List<String> labels() =>
          hud.children.whereType<TextComponent>().map((c) => c.text).toList();
      expect(labels(), containsAll(['ĐIỂM 120', 'XU CÒN 7']));
      await language.doi('en');
      game.update(0);
      expect(labels(), containsAll(['SCORE 120', 'COINS LEFT 7']));
      score = 140;
      game.update(0);
      expect(labels(), contains('SCORE 140'));
      await language.doi('vi');
      game.update(0);
      expect(labels(), contains('ĐIỂM 140'));
      game.onRemove();
    },
  );
}
