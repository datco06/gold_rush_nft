import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/lich_su/lich_su_man_choi.dart';

VanDaChoi van(int id, {bool thang = true}) => VanDaChoi(
  maVan: 'van-$id',
  manId: 2,
  tenMan: 'Rừng thưa',
  thang: thang,
  giay: 65.25,
  ketThuc: DateTime.utc(2026, 11, 22).add(Duration(seconds: id)),
);

void main() {
  final memory = <String, String>{};
  LuuLichSuManChoi kho(String wallet, [int chain = 31337]) => LuuLichSuManChoi(
    wallet: wallet,
    chainId: chain,
    doc: (key) async => memory[key],
    ghi: (key, value) async {
      memory[key] = value;
    },
  );
  setUp(memory.clear);

  test(
    'new login restores wins/losses newest first and separates wallets/chains',
    () async {
      await kho('0xAbC').ghi(van(1));
      await kho('0xAbC').ghi(van(2, thang: false));
      final saved = await kho('0xabc').doc();
      expect(saved.map((v) => v.maVan), ['van-2', 'van-1']);
      expect(saved.first.thang, isFalse);
      expect(saved.first.manId, 2);
      expect(saved.first.tenMan, 'Rừng thưa');
      expect(saved.first.giay, 65.25);
      expect(saved.first.ketThuc, van(2).ketThuc);
      expect(await kho('0xdef').doc(), isEmpty);
      expect(await kho('0xabc', 11155111).doc(), isEmpty);
    },
  );

  test(
    'keeps only newest 100 completed matches and ignores duplicate IDs',
    () async {
      final store = kho('A');
      for (var i = 0; i < 105; i++) {
        await store.ghi(van(i));
      }
      await store.ghi(van(104, thang: false));
      await store.ghi(van(0));
      final saved = await store.doc();
      expect(saved, hasLength(100));
      expect(saved.first.maVan, 'van-104');
      expect(saved.first.thang, isTrue);
      expect(saved.last.maVan, 'van-5');
    },
  );

  test(
    'serializes writes across game instances and reads wait for pending saves',
    () async {
      final blocked = Completer<void>();
      final started = Completer<void>();
      final first = LuuLichSuManChoi(
        wallet: 'B',
        chainId: 31337,
        doc: (key) async => memory[key],
        ghi: (key, value) async {
          started.complete();
          await blocked.future;
          memory[key] = value;
        },
      );
      final one = first.ghi(van(1));
      await started.future;
      final two = kho('B').ghi(van(2));
      final reading = kho('B').doc();
      blocked.complete();
      await Future.wait([one, two]);
      expect((await reading).map((v) => v.maVan), ['van-2', 'van-1']);
    },
  );

  test(
    'ignores corrupt entries and safely handles unavailable storage',
    () async {
      final store = kho('C');
      await store.ghi(van(1));
      final key = memory.keys.single;
      final data = jsonDecode(memory[key]!) as Map<String, dynamic>;
      final entries = data['cac_van'] as List;
      entries.addAll([
        null,
        {},
        {...entries.first as Map, 'giay': -1},
        {...entries.first as Map, 'thang': 'thua'},
      ]);
      memory[key] = jsonEncode(data);
      expect((await store.doc()).single.maVan, 'van-1');
      memory[key] = '{broken';
      expect(await store.doc(), isEmpty);
      await store.ghi(van(2));
      expect((await store.doc()).single.maVan, 'van-2');
      final broken = LuuLichSuManChoi(
        wallet: 'D',
        chainId: 31337,
        doc: (_) async => throw StateError('read'),
        ghi: (_, _) async => throw StateError('write'),
      );
      expect(await broken.doc(), isEmpty);
      await broken.ghi(van(1));
      final failedWrite = LuuLichSuManChoi(
        wallet: 'E',
        chainId: 31337,
        doc: (_) async => null,
        ghi: (_, _) async => throw StateError('write'),
      );
      await failedWrite.ghi(van(1));
      expect(await failedWrite.doc(), isEmpty);
    },
  );
}
