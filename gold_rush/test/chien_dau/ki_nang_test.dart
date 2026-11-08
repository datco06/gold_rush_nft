import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/chien_dau/ky_nang.dart';

void main() {
  test('thời gian hồi chặn dùng liên tiếp', () {
    final bo = BoKyNang();
    expect(bo.kich(LoaiKyNang.dash), isTrue);
    expect(bo.kich(LoaiKyNang.dash), isFalse);
    bo.troiQua(KyNang.dash.thoiGianHoi + 0.1);
    expect(bo.kich(LoaiKyNang.dash), isTrue);
  });

  test('shield có hiệu lực rồi hết', () {
    final bo = BoKyNang();
    bo.kich(LoaiKyNang.shield);
    expect(bo.trangThai(LoaiKyNang.shield), TrangThaiKyNang.dangDung);
    bo.troiQua(1.6);
    expect(bo.dangDung(LoaiKyNang.shield), isFalse);
    expect(bo.trangThai(LoaiKyNang.shield), TrangThaiKyNang.hoi);
  });

  test('nâng cấp có giới hạn', () {
    final bo = BoKyNang();
    expect(bo.nangCap(LoaiKyNang.dash), isTrue);
    expect(bo.nangCap(LoaiKyNang.dash), isTrue);
    expect(bo.nangCap(LoaiKyNang.dash), isFalse);
  });
}