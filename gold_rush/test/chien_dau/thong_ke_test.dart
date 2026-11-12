import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/nhat_ky_choi.dart';

void main() {
  test('thống kê chiến đấu khớp hợp đồng dữ liệu đề xuất', () {
    final nk = NhatKyChoi()..batDau(24);
    nk.ghiHaKeDich();
    nk.ghiHaKeDich();
    nk.satThuongNhan = 25;
    nk.bossDaHa = true;
    nk.trangBi = ['sword_001', 'bow_001'];

    final j = nk.thongKeChienDau(stageId: 6, won: true);
    expect(j['stage_id'], 6);
    expect(j['won'], true);
    expect(j['enemies_defeated'], 2);
    expect(j['boss_defeated'], true);
    expect(j['damage_taken'], 25);
    expect(j['equipment_ids'], ['sword_001', 'bow_001']);
  });

  test('nhật ký gửi máy chủ không bị thay đổi', () {
    final nk = NhatKyChoi()..batDau(24);
    nk.ghiHaKeDich();
    final j = nk.thanhJson(
      ketQua: 'thang',
      diem: 0,
      phienBanApp: '1.3.0',
      doKhoThichUng: false,
    );
    expect(j.containsKey('chien_dau'), isFalse);
    const hopLe = {'nhat_xu', 'trung_don', 'ket_thuc'};
    for (final e in j['su_kien'] as List) {
      expect(hopLe.contains((e as Map)['loai']), isTrue);
    }
  });
}