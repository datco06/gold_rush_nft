import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/man_choi.dart';

/// man_choi.json là MỘT nguồn sự thật cho app, máy chủ và hợp đồng — phải khớp bản đồ thật.
void main() {
  final ds = ManChoi.docDanhSach(File('assets/tiles/man_choi.json').readAsStringSync());

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
      final soXu = RegExp(r'name="coin"').allMatches(tmx.readAsStringSync()).length;
      expect(soXu, m.soXu, reason: m.tep);
    }
  });

  test('định dạng đồng hồ', () {
    expect(dinhDangGiay(65), '1:05');
    expect(dinhDangGiay(0.2), '0:01');
    expect(dinhDangGiay(-3), '0:00');
  });
}
