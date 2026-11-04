import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/tim_duong.dart';

/// Dựng bộ tìm đường từ các dòng chữ: '#' = chặn, '.' = trống.
///
/// Các ca dưới đây dịch NGUYÊN VĂN từ `gold_rush_ai/tests/test_core.py`
/// (lớp TestTimDuong): bản Dart và bản Python phải cho cùng kết quả.
TimDuong luoi(List<String> dong) => TimDuong(
      soCot: dong.first.length,
      soHang: dong.length,
      biChan: (c, h) => dong[h][c] == '#',
    );

O o(int c, int h) => (cot: c, hang: h);

void main() {
  test('đường thẳng', () {
    expect(luoi(['.....']).tim(o(0, 0), o(4, 0)),
        [o(1, 0), o(2, 0), o(3, 0), o(4, 0)]);
  });

  test('đầu trùng đích → danh sách rỗng', () {
    expect(luoi(['...']).tim(o(1, 0), o(1, 0)), isEmpty);
  });

  test('vòng qua tường theo đường ngắn nhất', () {
    final b = luoi([
      '.....',
      '.###.',
      '.....',
    ]);
    final d = b.tim(o(0, 1), o(4, 1))!;
    expect(d.length, 6);
    expect(d.every((x) => !b.biChan(x.cot, x.hang)), isTrue);
  });

  test('không có đường → null', () {
    final b = luoi([
      '..#..',
      '..#..',
      '..#..',
    ]);
    expect(b.tim(o(0, 0), o(4, 0)), isNull);
  });

  test('đích bị chặn hoặc ngoài bản đồ → null', () {
    final b = luoi(['..#']);
    expect(b.tim(o(0, 0), o(2, 0)), isNull);
    expect(b.tim(o(0, 0), o(9, 9)), isNull);
  });

  test('mê cung: mỗi bước là một ô kề', () {
    final b = luoi([
      '..........',
      '.########.',
      '.#......#.',
      '.#.#..#.#.',
      '.#.#..#.#.',
      '...#..#...',
    ]);
    final d = b.tim(o(0, 0), o(4, 4));
    expect(d, isNotNull);
    var truoc = o(0, 0);
    for (final x in d!) {
      expect((x.cot - truoc.cot).abs() + (x.hang - truoc.hang).abs(), 1);
      truoc = x;
    }
  });

  test('vượt giới hạn số ô → null (không làm khựng game)', () {
    final b = TimDuong(
      soCot: 40,
      soHang: 1,
      biChan: (c, h) => false,
      gioiHanO: 10,
    );
    expect(b.tim(o(0, 0), o(39, 0)), isNull);
  });
}
