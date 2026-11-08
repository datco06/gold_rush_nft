import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/boss.dart';

void main() {
  const max = 300;

  test('trên 50% là phase 1', () {
    expect(xacDinhPhase(300, max), PhaseBoss.mot);
    expect(xacDinhPhase(151, max), PhaseBoss.mot);
  });

  test('đúng 50% chuyển sang phase 2', () {
    expect(xacDinhPhase(150, max), PhaseBoss.hai);
    expect(xacDinhPhase(61, max), PhaseBoss.hai);
  });

  test('từ 20% trở xuống là phase 3', () {
    expect(xacDinhPhase(60, max), PhaseBoss.ba);
    expect(xacDinhPhase(1, max), PhaseBoss.ba);
    expect(xacDinhPhase(0, max), PhaseBoss.ba);
  });
}