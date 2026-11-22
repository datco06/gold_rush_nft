import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/kho_do/luu_lua_chon.dart';

void main() {
  final memory = <String, String>{};
  LuuLuaChonKhoDo store(String wallet, [int chain = 31337]) => LuuLuaChonKhoDo(
    wallet: wallet,
    chainId: chain,
    doc: (key) async => memory[key],
    ghi: (key, value) async => memory[key] = value,
  );
  setUp(memory.clear);

  test('restores character and slots after a new login without sharing wallets or chains', () async {
    final first = store('0xABC');
    await first.luuNhanVat('george_tho_mo.png');
    await first.luuOTrangBi('giap', 'armor_01');
    await first.luuOTrangBi('giay', 'boots_02');
    final restored = await store('0xabc').doc();
    expect(restored.nhanVat, 'george_tho_mo.png');
    expect(restored.trangBi, {'giap': 'armor_01', 'giay': 'boots_02'});
    expect((await store('0xDEF').doc()).trangBi, isEmpty);
    expect((await store('0xDEF').doc()).nhanVat, isNull);
    expect((await store('0xabc', 11155111).doc()).nhanVat, isNull);
  });

  test(
    'updates only one slot so delayed inventory cannot erase other selections',
    () async {
      final first = store('A');
      await first.luuOTrangBi('giap', 'pending_armor');
      await first.luuNhanVat('george_cao_boi.png');
      await first.luuOTrangBi('vuKhiChinh', 'gun');
      await first.luuOTrangBi('vuKhiChinh', null);
      expect((await store('A').doc()).trangBi, {'giap': 'pending_armor'});
      expect((await store('A').doc()).nhanVat, 'george_cao_boi.png');
    },
  );

  test(
    'serializes rapid writes even from consecutive game instances',
    () async {
      final blocked = Completer<void>();
      var writes = 0;
      final first = LuuLuaChonKhoDo(
        wallet: 'B',
        chainId: 31337,
        doc: (key) async => memory[key],
        ghi: (key, value) async {
          if (++writes == 1) await blocked.future;
          memory[key] = value;
        },
      );
      final one = first.luuOTrangBi('giap', 'old');
      await Future<void>.delayed(Duration.zero);
      final two = store('B').luuOTrangBi('giap', 'new');
      final three = store('B').luuNhanVat('george.png');
      blocked.complete();
      await Future.wait([one, two, three]);
      final saved = await store('B').doc();
      expect(saved.trangBi, {'giap': 'new'});
      expect(saved.nhanVat, 'george.png');
    },
  );

  test(
    'ignores malformed storage and handles read/write failure without throwing',
    () async {
      final first = store('C');
      await first.luuNhanVat('george.png');
      final key = memory.keys.single;
      memory[key] = '{invalid';
      expect((await first.doc()).nhanVat, isNull);
      memory[key] =
          '{"phien_ban":1,"nhan_vat":42,"trang_bi":{"giap":5,"unknown":"gun"}}';
      expect((await first.doc()).trangBi, isEmpty);
      final broken = LuuLuaChonKhoDo(
        wallet: 'D',
        chainId: 31337,
        doc: (_) async => throw StateError('read'),
        ghi: (_, _) async => throw StateError('write'),
      );
      expect((await broken.doc()).trangBi, isEmpty);
      await broken.luuNhanVat('george.png');
      await broken.luuOTrangBi('giap', 'armor');
      final failedWrite = LuuLuaChonKhoDo(
        wallet: 'E',
        chainId: 31337,
        doc: (_) async => null,
        ghi: (_, _) async => throw StateError('write'),
      );
      await failedWrite.luuNhanVat('george.png');
      expect((await failedWrite.doc()).nhanVat, isNull);
    },
  );
}
