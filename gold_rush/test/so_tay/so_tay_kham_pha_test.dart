import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/kho_do/danh_sach_trang_bi.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:gold_rush/so_tay/danh_muc_so_tay.dart';
import 'package:gold_rush/so_tay/so_tay_kham_pha.dart';

void main() {
  final memory = <String, String>{};
  LuuSoTayKhamPha kho(String wallet, [int chain = 31337]) => LuuSoTayKhamPha(
    wallet: wallet,
    chainId: chain,
    doc: (key) async => memory[key],
    ghi: (key, value) async {
      memory[key] = value;
    },
  );
  setUp(memory.clear);

  test(
    'discovery survives a new login only for the same wallet and chain',
    () async {
      await kho('0xABC')
          .ghi({'dia_diem:1', 'quai:zombie', 'trang_bi:sung_cap_1'});
      final saved = await kho('0xabc').doc();
      expect(saved.daMo, {'dia_diem:1', 'quai:zombie', 'trang_bi:sung_cap_1'});
      expect(await kho('0xDEF').doc().then((s) => s.daMo), isEmpty);
      expect(await kho('0xabc', 11155111).doc().then((s) => s.daMo), isEmpty);
      expect(() => saved.daMo.add('quai:boss'), throwsUnsupportedError);
    },
  );

  test('concurrent discoveries merge across instances without erasing earlier entries', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final first = LuuSoTayKhamPha(
      wallet: 'B',
      chainId: 31337,
      doc: (key) async => memory[key],
      ghi: (key, value) async {
        started.complete();
        await release.future;
        memory[key] = value;
      },
    );
    final one = first.ghi({'dia_diem:1'});
    await started.future;
    final two = kho('B').ghi({'quai:boss', 'dia_diem:1'});
    final reading = kho('B').doc();
    release.complete();
    await Future.wait([one, two]);
    expect((await reading).daMo, {'dia_diem:1', 'quai:boss'});
    await kho('B').ghi({});
    expect((await kho('B').doc()).daMo, {'dia_diem:1', 'quai:boss'});
  });

  test(
    'filters invalid IDs, corrupted data and unavailable storage safely',
    () async {
      final store = kho('C');
      await store.ghi({
        'quai:zombie',
        'quai:invented',
        'dia_diem:-1',
        'other:1',
      });
      expect((await store.doc()).daMo, {'quai:zombie'});
      final key = memory.keys.single;
      memory[key] = '{invalid';
      expect((await store.doc()).daMo, isEmpty);
      memory[key] = jsonEncode({
        'phien_ban': 1,
        'da_mo': ['quai:zombie', null, 3, 'other:1'],
      });
      expect((await store.doc()).daMo, {'quai:zombie'});
      final broken = LuuSoTayKhamPha(
        wallet: 'D',
        chainId: 31337,
        doc: (_) async => throw StateError('read'),
        ghi: (_, _) async => throw StateError('write'),
      );
      await broken.ghi({'quai:boss'});
      expect((await broken.doc()).daMo, isEmpty);
      final failedWrite = LuuSoTayKhamPha(
        wallet: 'E',
        chainId: 31337,
        doc: (_) async => null,
        ghi: (_, _) async => throw StateError('write'),
      );
      await failedWrite.ghi({'quai:boss'});
      expect((await failedWrite.doc()).daMo, isEmpty);
    },
  );

  test(
    'every notebook description has an English French and Spanish translation',
    () async {
      final stages = ManChoi.docDanhSach(
        File('assets/tiles/man_choi.json').readAsStringSync(),
      );
      final language = NgonNgu(doc: () async => null, ghi: (_) async {});
      for (final code in ['en', 'fr', 'es']) {
        await language.doi(code);
        for (final entry in danhMucSoTay(stages)) {
          expect(
            language.dich(entry.moTa),
            isNot(entry.moTa),
            reason: '$code / ${entry.khoa}',
          );
        }
      }
    },
  );

  test('catalog uses actual locations, enemy types and equipment without granting assets', () {
    final stages = ManChoi.docDanhSach(
      File('assets/tiles/man_choi.json').readAsStringSync(),
    );
    final items = danhSachTrangBiCuaHang();
    final catalog = danhMucSoTay(stages);
    expect(catalog, hasLength(stages.length + 6 + items.length));
    expect(catalog.map((m) => m.khoa).toSet(), hasLength(catalog.length));
    expect(
      catalog.where((m) => m.nhom == NhomSoTay.diaDiem).map((m) => m.ten),
      stages.map((m) => m.ten),
    );
    expect(
      catalog.where((m) => m.nhom == NhomSoTay.trangBi).map((m) => m.ten),
      items.map((m) => m.ten),
    );
    expect(
      catalog.where((m) => m.nhom == NhomSoTay.quai).map((m) => m.khoa).toSet(),
      {
        'quai:zombie',
        'quai:skeleton',
        'quai:thuong',
        'quai:giap',
        'quai:khong_lo',
        'quai:boss',
      },
    );
  });
}
