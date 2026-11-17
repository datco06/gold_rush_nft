import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/de_xuat_do_kho.dart';

Map<String, dynamic> deXuatMau() => {
  'stage_id': 1,
  'difficulty': 'medium',
  'performance_score': null,
  'reason': 'Chưa đủ lịch sử, đề xuất mức trung tính.',
  'adjustments': {'enemy_speed_multiplier': 1.0},
  'source': 'fallback',
  'sample_count': 0,
  'schema_version': 1,
  'context_source': 'demo',
};

void main() {
  test('đọc fallback demo có điểm null và lý do tiếng Việt', () {
    final kq = DeXuatDoKho.tuJson(deXuatMau());
    expect(kq.manChoi, 1);
    expect(kq.doKho, 'medium');
    expect(kq.diemHieuSuat, isNull);
    expect(kq.lyDo, 'Chưa đủ lịch sử, đề xuất mức trung tính.');
    expect(kq.heSoTocDo, 1.0);
    expect(kq.nguon, 'fallback');
    expect(kq.soVan, 0);
    expect(kq.nguonNguCanh, 'demo');
  });

  test('đọc đề xuất từ lịch sử đã xác minh và giá trị số nguyên JSON', () {
    final kq = DeXuatDoKho.tuJson(
      deXuatMau()
        ..['performance_score'] = 1
        ..['difficulty'] = 'hard'
        ..['sample_count'] = 10
        ..['source'] = 'rule_based'
        ..['context_source'] = 'verified'
        ..['adjustments'] = {'enemy_speed_multiplier': 1},
    );
    expect(kq.diemHieuSuat, 1.0);
    expect(kq.heSoTocDo, 1.0);
    expect(kq.soVan, 10);
    expect(kq.nguonNguCanh, 'verified');
  });

  final sai = <String, dynamic>{
    'stage_id': 1.0,
    'difficulty': 'extreme',
    'performance_score': '0.5',
    'reason': ' ',
    'adjustments': [],
    'source': 'llm',
    'sample_count': true,
    'schema_version': true,
    'context_source': 'client',
  };
  for (final truong in sai.entries) {
    test('từ chối trường ${truong.key} sai kiểu hoặc giá trị', () {
      expect(
        () => DeXuatDoKho.tuJson(deXuatMau()..[truong.key] = truong.value),
        throwsFormatException,
      );
    });
  }
  for (final truong in deXuatMau().keys) {
    test('từ chối thiếu trường $truong', () {
      expect(
        () => DeXuatDoKho.tuJson(deXuatMau()..remove(truong)),
        throwsFormatException,
      );
    });
  }
  for (final heSo in [
    0.79,
    1.16,
    double.nan,
    double.infinity,
    true,
    '1.0',
    null,
  ]) {
    test('từ chối hệ số không hợp lệ $heSo', () {
      expect(
        () => DeXuatDoKho.tuJson(
          deXuatMau()..['adjustments'] = {'enemy_speed_multiplier': heSo},
        ),
        throwsFormatException,
      );
    });
  }
  test('đọc đúng hai biên hệ số', () {
    for (final heSo in [0.8, 1.15]) {
      expect(
        DeXuatDoKho.tuJson(
          deXuatMau()..['adjustments'] = {'enemy_speed_multiplier': heSo},
        ).heSoTocDo,
        heSo,
      );
    }
  });
  for (final diem in [-0.1, 1.1, double.nan, double.infinity, true]) {
    test('từ chối điểm hiệu suất sai $diem', () {
      expect(
        () => DeXuatDoKho.tuJson(deXuatMau()..['performance_score'] = diem),
        throwsFormatException,
      );
    });
  }
  test('từ chối số ván vượt cửa sổ và phiên bản JSON mới', () {
    for (final soVan in [-1, 11]) {
      expect(
        () => DeXuatDoKho.tuJson(deXuatMau()..['sample_count'] = soVan),
        throwsFormatException,
      );
    }
    for (final phienBan in [1.0, 2]) {
      expect(
        () => DeXuatDoKho.tuJson(deXuatMau()..['schema_version'] = phienBan),
        throwsFormatException,
      );
    }
  });
}
