import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ngon_ngu/nguon_ban_dich.dart';

Map<String, String> taiNguyen({bool tiengNhat = false}) => {
  'assets/i18n/languages.json': jsonEncode({
    'default': 'vi',
    'fallback': 'en',
    'languages': {
      'vi': 'Tiếng Việt',
      'en': 'English',
      if (tiengNhat) 'ja': '日本語',
    },
  }),
  'assets/i18n/vi.json': jsonEncode({
    'Kho đồ': 'Kho đồ',
    '{0} vàng': '{0} vàng',
  }),
  'assets/i18n/en.json': jsonEncode({
    'Kho đồ': 'Inventory',
    '{0} vàng': '{0} gold',
  }),
  if (tiengNhat) 'assets/i18n/ja.json': jsonEncode({'Kho đồ': '持ち物'}),
};

void main() {
  test(
    'loads new locale from JSON and manifest alone and caches concurrent calls',
    () async {
      final files = taiNguyen(tiengNhat: true);
      final reads = <String, int>{};
      final source = NguonBanDich(
        taiTep: (path) async {
          reads.update(path, (n) => n + 1, ifAbsent: () => 1);
          return files[path]!;
        },
      );
      await Future.wait([source.nap(), source.nap()]);
      await source.nap();
      expect(source.cacNgonNgu['ja'], '日本語');
      expect(source.banDich('ja')['Kho đồ'], '持ち物');
      expect(source.duPhong, 'en');
      expect(reads.values.every((n) => n == 1), isTrue);
      expect(() => source.cacNgonNgu['xx'] = 'Bad', throwsUnsupportedError);
      expect(
        () => source.banDich('ja')['Kho đồ'] = 'Bad',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'a missing or malformed extra locale cannot remove healthy languages',
    () async {
      for (final value in [
        null,
        '{broken',
        '{"Kho đồ":42}',
        '{"{0} vàng":"gold"}',
      ]) {
        final files = taiNguyen(tiengNhat: true);
        if (value == null) {
          files.remove('assets/i18n/ja.json');
        } else {
          files['assets/i18n/ja.json'] = value;
        }
        final source = NguonBanDich(
          taiTep: (path) async {
            if (!files.containsKey(path)) throw StateError('missing asset');
            return files[path]!;
          },
        );
        await source.nap();
        expect(source.cacNgonNgu.keys, ['vi', 'en']);
        expect(source.banDich('en')['Kho đồ'], 'Inventory');
      }
    },
  );

  test(
    'failed manifest can retry and unsafe language paths are rejected',
    () async {
      final files = taiNguyen();
      final source = NguonBanDich(taiTep: (path) async => files[path]!);
      final valid = files['assets/i18n/languages.json']!;
      files['assets/i18n/languages.json'] = '{invalid';
      await expectLater(source.nap(), throwsFormatException);
      expect(source.cacNgonNgu.keys, ['vi']);
      files['assets/i18n/languages.json'] = valid;
      await source.nap();
      expect(source.cacNgonNgu.keys, ['vi', 'en']);
      final unsafe = NguonBanDich(
        taiTep: (path) async {
          expect(path, 'assets/i18n/languages.json');
          return jsonEncode({
            'default': 'vi',
            'fallback': 'vi',
            'languages': {'vi': 'Tiếng Việt', '../secret': 'Bad'},
          });
        },
      );
      await expectLater(unsafe.nap(), throwsFormatException);
    },
  );
}
