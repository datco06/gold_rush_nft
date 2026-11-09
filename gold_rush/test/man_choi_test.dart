import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/man_choi.dart';

/// man_choi.json là MỘT nguồn sự thật cho app, máy chủ và hợp đồng — phải khớp bản đồ thật.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ds = ManChoi.docBoManChoi(
    File('assets/tiles/man_choi.json').readAsStringSync(),
    File('assets/tiles/man_mo_rong.json').readAsStringSync(),
  );

  test('màn 1 là luyện tập; màn có cọc đều có giới hạn thời gian', () {
    expect(ds.first.id, 1);
    expect(ds.first.mienPhi, isTrue);
    for (final m in ds.where((m) => !m.mienPhi)) {
      expect(m.gioiHanGiay, greaterThan(0), reason: 'màn ${m.id}');
      expect(m.nhanVeKhiHoanThanh, m.coc + m.soXu + m.thuong);
    }
  });

  test('mỗi màn trỏ tới một tệp .tmx có ĐÚNG số xu ghi trong JSON', () {
    for (final m in ds) {
      final tmx = File('assets/tiles/${m.tep}');
      expect(tmx.existsSync(), isTrue, reason: m.tep);
      final soXu = RegExp(r'name="coin"')
          .allMatches(tmx.readAsStringSync())
          .length;
      expect(soXu, m.soXu, reason: m.tep);
    }
  });

  test('Đủ 20 màn duy nhất; 14 màn mở rộng local không tạo cọc hoặc thưởng blockchain', () {
    expect(ds.map((m) => m.id), orderedEquals(List.generate(20, (i) => i + 1)));
    expect(ds.map((m) => m.tep).toSet(), hasLength(20));
    for (final m in ds.where((m) => m.id > 6)) {
      expect(m.chiChoiLocal, isTrue);
      expect(m.coc, 0);
      expect(m.thuong, 0);
    }
  });

  test('định dạng đồng hồ', () {
    expect(dinhDangGiay(65), '1:05');
    expect(dinhDangGiay(0.2), '0:01');
    expect(dinhDangGiay(-3), '0:00');
  });

  testWidgets('Flame nạp được cả 14 TMX mới với nhân vật, xu và va chạm thật', (
    tester,
  ) async {
    for (final level in ds.where((m) => m.chiChoiLocal)) {
      final map = await tester.runAsync(() => BanDo.nap(level.tep));
      expect(map, isNotNull, reason: level.tep);
      final spawns = map!.diemXuatHien;
      expect(spawns.where((p) => p.ten == 'george'), hasLength(1));
      expect(spawns.where((p) => p.ten == 'coin'), hasLength(level.soXu));
      for (final spawn in spawns) {
        expect(
          map.biChanTaiDiem(spawn.viTri.x, spawn.viTri.y),
          isFalse,
          reason: '${level.tep}: ${spawn.ten} không được nằm trong tường',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });
}
