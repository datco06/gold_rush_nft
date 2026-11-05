import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/nhiem_vu.dart';

Map<String, dynamic> phanHoiMau() => {
  'id': 'quest_abc123',
  'stage_id': 1,
  'title': 'Tìm kho báu',
  'description': 'Nhặt 6 xu trong màn đầu.',
  'objective': 'collect_coins',
  'target': 6,
  'time_limit_seconds': null,
  'difficulty': 'easy',
  'reward': {'gold': 0},
  'status': 'offered',
  'generation_source': 'rule_based',
  'schema_version': 1,
  'context_source': 'demo',
};

void main() {
  test('đọc phản hồi tiếng Việt và nguồn demo từ API', () {
    final nv = NhiemVu.tuJson(phanHoiMau());
    expect(nv.id, 'quest_abc123');
    expect(nv.manChoi, 1);
    expect(nv.tieuDe, 'Tìm kho báu');
    expect(nv.moTa, 'Nhặt 6 xu trong màn đầu.');
    expect(nv.mucTieu, 'collect_coins');
    expect(nv.soLuong, 6);
    expect(nv.gioiHanGiay, isNull);
    expect(nv.doKho, 'easy');
    expect(nv.vangThuong, 0);
    expect(nv.nguonSinh, 'rule_based');
    expect(nv.nguonNguCanh, 'demo');
  });

  test('đọc hai mục tiêu hoàn thành màn', () {
    final thoiGian = NhiemVu.tuJson(
      phanHoiMau()
        ..['objective'] = 'finish_before_time'
        ..['target'] = 1
        ..['time_limit_seconds'] = 60
        ..['context_source'] = 'verified'
        ..['generation_source'] = 'llm',
    );
    expect(thoiGian.gioiHanGiay, 60);
    expect(thoiGian.nguonNguCanh, 'verified');
    final trungDon = NhiemVu.tuJson(
      phanHoiMau()
        ..['objective'] = 'finish_with_max_hits'
        ..['target'] = 0,
    );
    expect(trungDon.soLuong, 0);
  });

  final duLieuSai = <String, dynamic>{
    'id': 'other_abc',
    'stage_id': 1.0,
    'title': ' ',
    'description': 3,
    'objective': 'kill_enemies',
    'target': true,
    'time_limit_seconds': 0,
    'difficulty': 'extreme',
    'reward': {'gold': 100},
    'status': 'completed',
    'generation_source': 'unknown',
    'schema_version': 2,
    'context_source': 'client',
  };
  for (final truong in duLieuSai.entries) {
    test('từ chối trường ${truong.key} sai hợp đồng', () {
      expect(
        () => NhiemVu.tuJson(phanHoiMau()..[truong.key] = truong.value),
        throwsFormatException,
      );
    });
  }
  for (final truong in ['id', 'stage_id', 'reward', 'context_source']) {
    test('từ chối thiếu $truong', () {
      expect(
        () => NhiemVu.tuJson(phanHoiMau()..remove(truong)),
        throwsFormatException,
      );
    });
  }
  test('từ chối target không phù hợp từng mục tiêu', () {
    for (final cap in [
      ('collect_coins', 0),
      ('finish_with_max_hits', 4),
      ('finish_before_time', 1),
    ]) {
      expect(
        () => NhiemVu.tuJson(
          phanHoiMau()
            ..['objective'] = cap.$1
            ..['target'] = cap.$2,
        ),
        throwsFormatException,
      );
    }
  });
}
