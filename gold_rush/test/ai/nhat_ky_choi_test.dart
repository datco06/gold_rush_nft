import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/nhat_ky_choi.dart';

void main() {
  late NhatKyChoi nk;

  setUp(() {
    nk = NhatKyChoi(rnd: Random(1))..batDau(24);
  });

  test('đầu ván: không chia cho 0', () {
    expect(nk.dacTrung(100, 100), [1.0, 0.0, 0.0, 0.0, 0.0]);
  });

  test('khớp do_kho.dac_trung(100, 100, 0, 3, 24, 30) bên Python', () {
    for (var i = 0; i < 3; i++) {
      nk.ghiNhatXu(10, 10);
    }
    nk.troiThoiGian(30);
    expect(nk.dacTrung(100, 100), [1.0, 0.0, 6.0, 0.125, 0.5]);
  });

  test('cứ 10 giây báo chụp một lần', () {
    var soLan = 0;
    for (var i = 0; i < 60 * 35; i++) {
      if (nk.troiThoiGian(1 / 60)) soLan++;
    }
    expect(soLan, 3); // 35 giây → chụp ở giây 10, 20, 30
  });

  test('nhật ký đúng lược đồ máy chủ', () {
    nk.ghiTrungDon(300, 200);
    nk.troiThoiGian(12);
    nk.chup(75, 100);
    final j = nk.thanhJson(
      ketQua: 'thua',
      diem: 40,
      phienBanApp: '1.1.0',
      doKhoThichUng: true,
      tenHienThi: '  Một cái tên rất rất rất dài quá  ',
    );
    expect(j['ma_van'] as String, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect((j['ten_hien_thi'] as String).length, lessThanOrEqualTo(20));
    expect((j['su_kien'] as List).single, {
      'loai': 'trung_don',
      'giay': 0.0,
      'x': 300.0,
      'y': 200.0,
    });
    expect((j['anh_chup'] as List).single['ti_le_mau'], 0.75);
  });

  test('mỗi ván một mã khác nhau', () {
    final a = nk.maVan;
    nk.batDau(24);
    expect(nk.maVan, isNot(a));
  });

  test('màn có cọc: dùng mã ván đã đăng ký với máy chủ, ghi id màn và bản đồ', () {
    final ma = nk.sinhMaVan();
    nk.batDau(18, maVanCoSan: ma);
    expect(nk.maVan, ma);
    final j = nk.thanhJson(
      ketQua: 'thang',
      diem: 360,
      phienBanApp: '1.3.0',
      doKhoThichUng: false,
      banDo: 'man_2.tmx',
      man: 2,
    );
    expect([j['ma_van'], j['man'], j['ban_do']], [ma, 2, 'man_2.tmx']);
  });
}
