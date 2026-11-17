import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:gold_rush/ngon_ngu/ban_dich.dart';
import 'package:gold_rush/ngon_ngu/ban_dich_phap.dart';
import 'package:gold_rush/ngon_ngu/ban_dich_tay_ban_nha.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_hinh/lop_phu.dart';
import 'package:gold_rush/auth/auth_controller.dart';

void main() {
  test('new catalogs cover every UI key and preserve all placeholders', () {
    final placeholders = RegExp(r'\{\d+\}');
    List<String> parameters(String text) =>
        placeholders.allMatches(text).map((m) => m[0]!).toList()..sort();
    for (final catalog in [banDichPhap, banDichTayBanNha]) {
      expect(catalog.keys.toSet(), banDichAnh.keys.toSet());
      for (final entry in banDichAnh.entries) {
        final translated = catalog[entry.key]!;
        expect(translated.trim(), isNotEmpty, reason: entry.key);
        expect(
          parameters(translated),
          parameters(entry.value),
          reason: entry.key,
        );
        expect(
          '\n'.allMatches(translated).length,
          '\n'.allMatches(entry.value).length,
          reason: entry.key,
        );
      }
    }
  });

  test('French and Spanish selections persist and restore', () async {
    for (final code in ['fr', 'es']) {
      String? saved;
      final language = NgonNgu(
        doc: () async => null,
        ghi: (v) async => saved = v,
      );
      expect(await language.doi(code), isTrue);
      expect(language.ma, code);
      expect(saved, code);
      final restored = NgonNgu(doc: () async => saved, ghi: (_) async {});
      await restored.nap();
      expect(restored.ma, code);
    }
  });

  test(
    'new languages preserve dynamic amounts and protected content',
    () async {
      for (final entry in {'fr': 'Inventaire', 'es': 'Inventario'}.entries) {
        final language = NgonNgu(doc: () async => null, ghi: (_) async {});
        await language.doi(entry.key);
        expect(language.dich('Kho đồ'), entry.value);
        expect(language.dich('Alice 0x123'), 'Alice 0x123');
        final result = language.dich('Ví: Alice \$5 {0}');
        expect(result, contains('Alice \$5 {0}'));
        expect(
          language.dich('25 vàng'),
          '${25} ${entry.key == 'fr' ? 'or' : 'oro'}',
        );
        expect(
          language.dich('Độ khó • Dễ'),
          entry.key == 'fr' ? 'Difficulté • Facile' : 'Dificultad • Fácil',
        );
        expect(
          language.dich('CÀI ĐẶT'),
          entry.key == 'fr' ? 'PARAMÈTRES' : 'CONFIGURACIÓN',
        );
      }
    },
  );

  testWidgets('settings fit both new languages on narrow and desktop screens', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    final game = GoldRushGame(auth: _LayoutAuth());
    await tester.pumpWidget(
      PhamViNgonNgu(
        ngonNgu: language,
        child: MaterialApp(home: ManHinhCaiDat(game: game)),
      ),
    );
    for (final size in [const Size(390, 844), const Size(1280, 720)]) {
      tester.view.physicalSize = size;
      for (final entry in {'fr': 'PARAMÈTRES', 'es': 'CONFIGURACIÓN'}.entries) {
        await language.doi(entry.key);
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        final catalog = entry.key == 'fr' ? banDichPhap : banDichTayBanNha;
        final logoutLabel = find.text(catalog['Đăng xuất & Ngắt kết nối ví']!);
        final paragraph = tester.renderObject<RenderParagraph>(logoutLabel);
        final fullText = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: paragraph.size.width);
        expect(fullText.height, lessThanOrEqualTo(paragraph.size.height + 0.1));
        fullText.dispose();
        expect(
          tester.widget<ManHinhCaiDat>(find.byType(ManHinhCaiDat)).game,
          same(game),
        );
        expect(tester.takeException(), isNull, reason: '$size / ${entry.key}');
      }
    }
  });

  testWidgets(
    'dropdown switches all four languages without remounting content',
    (tester) async {
      final saved = <String>[];
      final language = NgonNgu(
        doc: () async => null,
        ghi: (v) async => saved.add(v),
      );
      var mounts = 0;
      await tester.pumpWidget(
        PhamViNgonNgu(
          ngonNgu: language,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const ChonNgonNgu(),
                  _Probe(onMount: () => mounts++),
                  const ChuGame('Vàng', dichNoiDung: false),
                ],
              ),
            ),
          ),
        ),
      );
      for (final entry in {
        'Français': ('fr', 'Inventaire'),
        'Español': ('es', 'Inventario'),
        'English': ('en', 'Inventory'),
        'Tiếng Việt': ('vi', 'Kho đồ'),
      }.entries) {
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.key).last);
        await tester.pumpAndSettle();
        expect(language.ma, entry.value.$1);
        expect(saved.last, entry.value.$1);
        expect(find.text(entry.value.$2), findsOneWidget);
        expect(find.text('Vàng'), findsOneWidget);
        expect(mounts, 1);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

// Presence enables the real settings logout button; any auth action is forbidden.
class _LayoutAuth implements AuthController {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'No auth calls in localization layout tests: ${invocation.memberName}',
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
  Widget build(BuildContext context) => const ChuGame('Kho đồ');
}
