import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/mo_hinh_do_kho.dart';

/// Kiểm thử HỢP ĐỒNG giữa Python (huấn luyện) và Dart (suy luận).
///
/// Tệp mô hình do `gold_rush_ai` xuất ra có sẵn trường `kiem_tra`: vài vector
/// đặc trưng kèm xác suất Python đã tính. Dart nạp CHÍNH tệp đó và phải ra
/// cùng con số. Ai sửa công thức một bên mà quên bên kia, test này báo đỏ.
void main() {
  // `flutter test` chạy với thư mục làm việc = gốc dự án.
  final tep = File('assets/models/do_kho_v1.json');
  final json = jsonDecode(tep.readAsStringSync()) as Map<String, dynamic>;
  final moHinh = MoHinhDoKho.tuJson(json);

  test('đọc đúng phiên bản và 5 đặc trưng', () {
    expect(moHinh.phienBan, 'do_kho_v1');
    expect(moHinh.dacTrung, MoHinhDoKho.dacTrungHoTro);
  });

  test('khớp từng ca kiểm thử Python đã nhúng sẵn', () {
    final cacCa = json['kiem_tra'] as List;
    expect(cacCa, isNotEmpty);
    for (final ca in cacCa) {
      final x = (ca['x'] as List).map((v) => (v as num).toDouble()).toList();
      final p = (ca['p'] as num).toDouble();
      expect(moHinh.duDoan(x), closeTo(p, 1e-6), reason: 'x = $x');
    }
  });

  test('xác suất luôn trong (0, 1)', () {
    for (final x in [
      [0.0, 50.0, 0.0, 0.0, 30.0],
      [1.0, 0.0, 100.0, 1.0, 0.0],
    ]) {
      final p = moHinh.duDoan(x);
      expect(p, greaterThan(0));
      expect(p, lessThan(1));
    }
  });

  test('từ chối mô hình đòi đặc trưng app không tính được', () {
    final sai = Map<String, dynamic>.from(json)
      ..['dac_trung'] = ['ti_le_mau', 'so_lan_nhay', 'a', 'b', 'c'];
    expect(() => MoHinhDoKho.tuJson(sai), throwsFormatException);
  });

  test('từ chối vector sai độ dài', () {
    expect(() => moHinh.duDoan([1, 2]), throwsArgumentError);
  });
}
