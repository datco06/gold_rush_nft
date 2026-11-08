import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/vat_pham_roi.dart';

void main() {
  test('tỉ lệ 0 thì không rơi gì, tỉ lệ 1 thì rơi cả hai', () {
    final rnd = Random(1);
    expect(BangRoi.chon(rnd, tiLeExp: 0, tiLeMau: 0), isEmpty);
    expect(BangRoi.chon(rnd, tiLeExp: 1, tiLeMau: 1).length, 2);
  });

  test('Boss luôn rơi EXP và bình máu', () {
    final r = BangRoi.chon(Random(1), laBoss: true, tiLeExp: 0, tiLeMau: 0);
    expect(r.map((p) => p.loai),
        containsAll([LoaiVatPham.cucExp, LoaiVatPham.binhMau]));
  });
}