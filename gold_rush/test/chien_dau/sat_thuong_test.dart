import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/chien_dau/sat_thuong.dart';

void main() {
  test('máu không bao giờ âm', () {
    final m = SucKhoe(30);
    expect(m.nhan(50), 30);
    expect(m.hien, 0);
    expect(m.conSong, isFalse);
    expect(m.nhan(-5), 0);
  });

  test('hồi máu không vượt tối đa', () {
    final m = SucKhoe(30, 10);
    expect(m.hoi(100), 20);
    expect(m.hien, 30);
  });

  test('thời gian hồi', () {
    final h = HoiChieu(1.0);
    expect(h.thu(), isTrue);
    expect(h.thu(), isFalse);
    h.troiQua(0.5);
    expect(h.san, isFalse);
    h.troiQua(0.6);
    expect(h.thu(), isTrue);
  });

  test('tầm đánh hình quạt phía trước', () {
    final tu = Vector2.zero();
    final huong = Vector2(1, 0);
    bool trung(double x, double y) =>
        trongTamDanh(tu: tu, huong: huong, muc: Vector2(x, y), tam: 28);
    expect(trung(20, 0), isTrue);
    expect(trung(20, 10), isTrue);
    expect(trung(-20, 0), isFalse);
    expect(trung(0, 20), isFalse);
    expect(trung(40, 0), isFalse);
  });
}
