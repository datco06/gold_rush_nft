import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> doc(String name) =>
      jsonDecode(File('assets/i18n/$name.json').readAsStringSync())
          as Map<String, dynamic>;

  test('translation directory is bundled once without adding dependencies', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^\s+- assets/i18n/\s*$', multiLine: true).allMatches(pubspec),
      hasLength(1),
    );
  });

  test(
    'every declared locale covers all source keys and preserves parameters',
    () {
      final registry = doc('languages');
      final languages = registry['languages'] as Map<String, dynamic>;
      expect(languages.keys, containsAll(['vi', 'en', 'fr', 'es']));
      expect(registry['default'], 'vi');
      expect(registry['fallback'], 'en');
      final source = doc('vi');
      final pattern = RegExp(r'\{\d+\}');
      List<String> parameters(String text) =>
          pattern.allMatches(text).map((m) => m[0]!).toList()..sort();
      for (final code in languages.keys) {
        final catalog = doc(code);
        expect(catalog.keys.toSet(), source.keys.toSet(), reason: code);
        for (final entry in source.entries) {
          final translated = catalog[entry.key];
          expect(translated, isA<String>(), reason: '$code / ${entry.key}');
          expect(
            (translated as String).trim(),
            isNotEmpty,
            reason: '$code / ${entry.key}',
          );
          expect(
            parameters(translated),
            parameters(entry.key),
            reason: '$code / ${entry.key}',
          );
        }
      }
    },
  );
}
