import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/phat_trien/cap_do.dart';

void main() {
  test('đủ EXP thì lên cấp và có điểm kỹ năng', () {
    final h = HoSoCapDo();
    expect(h.congExp(40), 1);
    expect(h.level, 2);
    expect(h.skillPoints, 1);
  });

  test('nhảy nhiều cấp một lần và EXP dư được giữ', () {
    final h = HoSoCapDo();
    expect(h.congExp(100), 2);
    expect(h.level, 3);
    expect(h.currentExp, 0);
    expect(h.skillPoints, 2);
  });

  test('EXP âm hoặc bằng 0 không làm gì; đạt cấp tối đa thì dừng', () {
    final h = HoSoCapDo();
    expect(h.congExp(0), 0);
    expect(h.congExp(-5), 0);
    h.congExp(100000);
    expect(h.level, HoSoCapDo.capToiDa);
    expect(h.congExp(50), 0);
  });
}