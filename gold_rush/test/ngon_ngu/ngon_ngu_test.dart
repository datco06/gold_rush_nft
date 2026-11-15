import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:gold_rush/main.dart';
import 'package:gold_rush/components/ui/gold_rush_top_bar.dart';

void main() {
  test('defaults to Vietnamese and restores only supported languages', () async {
    final language = NgonNgu(doc: () async => 'fr', ghi: (_) async {});
    expect(language.ma, 'vi');
    await language.nap();
    expect(language.ma, 'vi');
    final english = NgonNgu(doc: () async => 'en', ghi: (_) async {});
    await english.nap();
    expect(english.ma, 'en');
  });

  test('switches immediately and serializes preference writes', () async {
    final saved = <String>[];
    final language = NgonNgu(
      doc: () async => null,
      ghi: (code) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        saved.add(code);
      },
    );
    final first = language.doi('en');
    expect(language.ma, 'en');
    final second = language.doi('vi');
    await Future.wait([first, second]);
    expect(saved, ['en', 'vi']);
    expect(language.ma, 'vi');
  });

  test('storage failures and unsupported codes do not break the app', () async {
    final language = NgonNgu(
      doc: () async => throw StateError('read'),
      ghi: (_) async => throw StateError('write'),
    );
    await language.nap();
    expect(await language.doi('fr'), isFalse);
    expect(language.ma, 'vi');
    expect(await language.doi('en'), isFalse);
    expect(language.ma, 'en');
  });

  test('translates known labels but preserves unknown content', () {
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    expect(language.dich('Kho đồ'), 'Kho đồ');
    language.doi('en');
    expect(language.dich('Kho đồ'), 'Inventory');
    expect(language.dich('Alice 0x123'), 'Alice 0x123');
  });

  test('dynamic labels retain amounts and user text verbatim', () async {
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    await language.doi('en');
    expect(language.dich('25 vàng'), '25 gold');
    expect(language.dich('Ví: Alice \$5 {0}'), 'Wallet: Alice \$5 {0}');
    expect(language.dich('CÀI ĐẶT'), 'SETTINGS');
  });

  testWidgets('text reacts without remounting child state', (tester) async {
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    var mounts = 0;
    await tester.pumpWidget(PhamViNgonNgu(
      ngonNgu: language,
      child: MaterialApp(home: _Probe(onMount: () => mounts++)),
    ));
    expect(find.text('Kho đồ'), findsOneWidget);
    await language.doi('en');
    await tester.pump();
    expect(find.text('Inventory'), findsOneWidget);
    expect(mounts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selector switches both ways and persists the choice', (tester) async {
    final saved = <String>[];
    final language = NgonNgu(doc: () async => null, ghi: (v) async => saved.add(v));
    await tester.pumpWidget(PhamViNgonNgu(
      ngonNgu: language,
      child: const MaterialApp(home: Scaffold(body: Column(children: [
        ChonNgonNgu(), ChuGame('Kho đồ'),
      ]))),
    ));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Inventory'), findsOneWidget);
    expect(saved.last, 'en');
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();
    expect(find.text('Kho đồ'), findsOneWidget);
    expect(saved.last, 'vi');
  });

  testWidgets('welcome switches language without entering gameplay', (tester) async {
    await NgonNgu.chung.doi('vi');
    await tester.pumpWidget(const UngDungGoldRush());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('WELCOME,\nADVENTURER!'), findsOneWidget);
    expect(find.byType(ManHinhGame), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await NgonNgu.chung.doi('vi');
  });

  testWidgets('navigation uses translated labels and keeps player identity', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    await language.doi('en');
    await tester.pumpWidget(PhamViNgonNgu(
      ngonNgu: language,
      child: const MaterialApp(home: Scaffold(body: GoldRushTopBar(
        playerName: 'Alice', walletAddress: '0x1234',
      ))),
    ));
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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

