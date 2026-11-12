import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/chien_dau/quan_ly_trang_bi.dart';
import 'package:gold_rush/chien_dau/vu_khi.dart';

void main() {
  test('đổi qua lại giữa kiếm và cung', () {
    final t = QuanLyTrangBi();

    expect(t.hienTai.id, 'sword_001');

    expect(t.doi(), isTrue);

    expect(t.hienTai.tamXa, isTrue);

    t.doi();

    expect(t.hienTai.loai, LoaiVuKhi.kiem);
  });

  test('không có ô phụ thì không đổi được', () {
    final t = QuanLyTrangBi(phu: null);

    expect(t.doi(), isFalse);

    expect(t.idDangTrang, ['sword_001']);
  });
}