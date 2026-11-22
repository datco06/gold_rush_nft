import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:gold_rush/ngon_ngu/nguon_ban_dich.dart';

Map<String, String> _files() => {
  'assets/i18n/languages.json': jsonEncode({
    'default': 'vi',
    'fallback': 'en',
    'languages': {'vi': 'Tiếng Việt', 'en': 'English', 'ja': '日本語'},
  }),
  'assets/i18n/vi.json': jsonEncode({'Kho đồ': 'Kho đồ'}),
  'assets/i18n/en.json': jsonEncode({
    'Kho đồ': 'Inventory',
    '{0} vàng': '{0} gold',
  }),
  'assets/i18n/ja.json': jsonEncode({'Kho đồ': '持ち物'}),
};

void main() {
  test('a JSON-only locale can restore switch and use fallback without a Dart registry entry', () async {
    final files = _files();
    String? saved = 'ja';
    final source = NguonBanDich(taiTep: (path) async => files[path]!);
    final language = NgonNgu(
      nguon: source,
      doc: () async => saved,
      ghi: (code) async {
        saved = code;
      },
    );
    await language.nap();
    expect(language.ma, 'ja');
    expect(language.cacNgonNgu.keys, ['vi', 'en', 'ja']);
    expect(language.dich('Kho đồ'), '持ち物');
    expect(language.dich('25 vàng'), '25 gold');
    expect(language.dich('Alice \$5 {0} 0x123'), 'Alice \$5 {0} 0x123');
    await language.doi('en');
    expect(saved, 'en');
    expect(language.dich('Kho đồ'), 'Inventory');
  });

  test(
    'a newer choice wins while the first asset load is still pending',
    () async {
      final files = _files();
      final release = Completer<void>();
      final writes = <String>[];
      final source = NguonBanDich(
        taiTep: (path) async {
          await release.future;
          return files[path]!;
        },
      );
      final language = NgonNgu(
        nguon: source,
        doc: () async => null,
        ghi: (code) async {
          writes.add(code);
        },
      );
      final first = language.doi('ja');
      final second = language.doi('en');
      release.complete();
      expect(await first, isFalse);
      expect(await second, isTrue);
      expect(language.ma, 'en');
      expect(writes, ['en']);
    },
  );

  test(
    'a failed locale stays unselected while healthy choices still work',
    () async {
      final files = _files()..['assets/i18n/ja.json'] = '{bad';
      final writes = <String>[];
      final language = NgonNgu(
        nguon: NguonBanDich(taiTep: (path) async => files[path]!),
        doc: () async => 'ja',
        ghi: (code) async {
          writes.add(code);
        },
      );
      await language.nap();
      expect(language.ma, 'vi');
      expect(await language.doi('ja'), isFalse);
      expect(writes, isEmpty);
      expect(await language.doi('en'), isTrue);
      expect(language.dich('Kho đồ'), 'Inventory');
    },
  );

  test(
    'an invalid cold choice does not cancel an earlier valid pending choice',
    () async {
      final files = _files();
      final release = Completer<void>();
      final language = NgonNgu(
        nguon: NguonBanDich(
          taiTep: (path) async {
            await release.future;
            return files[path]!;
          },
        ),
        doc: () async => null,
        ghi: (_) async {},
      );
      final valid = language.doi('ja');
      final invalid = language.doi('xx');
      release.complete();
      expect(await invalid, isFalse);
      expect(await valid, isTrue);
      expect(language.ma, 'ja');
    },
  );

  test(
    'restoring absent preferences preserves a choice already made in memory',
    () async {
      final files = _files();
      final language = NgonNgu(
        nguon: NguonBanDich(taiTep: (path) async => files[path]!),
        doc: () async => null,
        ghi: (_) async {},
      );
      await language.doi('ja');
      await language.nap();
      expect(language.ma, 'ja');
    },
  );

  test('disposing during asset loading does not notify or persist a late selection', () async {
    final release = Completer<void>();
    final files = _files();
    var notifications = 0;
    final writes = <String>[];
    final language =
        NgonNgu(
          nguon: NguonBanDich(
            taiTep: (path) async {
              await release.future;
              return files[path]!;
            },
          ),
          doc: () async => null,
          ghi: (code) async {
            writes.add(code);
          },
        )..addListener(() {
          notifications++;
        });
    final selecting = language.doi('ja');
    language.dispose();
    release.complete();
    expect(await selecting, isFalse);
    expect(notifications, 0);
    expect(writes, isEmpty);
  });

  testWidgets(
    'the existing selector discovers a JSON-only locale and preserves child state',
    (tester) async {
      final files = _files();
      final language = NgonNgu(
        nguon: NguonBanDich(taiTep: (path) async => files[path]!),
        doc: () async => null,
        ghi: (_) async {},
      );
      await language.nap();
      var mounts = 0;
      await tester.pumpWidget(
        PhamViNgonNgu(
          ngonNgu: language,
          child: MaterialApp(
            home: _Probe(
              onMount: () {
                mounts++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日本語').last);
      await tester.pumpAndSettle();
      expect(find.text('持ち物'), findsOneWidget);
      expect(mounts, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Column(children: [ChonNgonNgu(), ChuGame('Kho đồ')]),
  );
}
