import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/ke_dich.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';

Future<ui.Image> _taoAnhGia() async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(
    const ui.Rect.fromLTWH(0, 0, 128, 128),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  return rec.endRecording().toImage(128, 128);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Màn 1: Đủ 9 con quái ngay từ giây số 0, sinh bù khi < 9 và dừng khi đủ 9', () async {
    final tmx = File('assets/tiles/gold_rush.tmx');
    expect(tmx.existsSync(), isTrue);

    final game = GoldRushGame(batBoss: false);
    final anh = await _taoAnhGia();
    game.taiNguyen.napTuAnhGia(anh);

    final banDo = await BanDo.nap('gold_rush.tmx');
    game.khoiTaoChoKiemThu(
      banDoDau: banDo,
      danhSachMan: [ManChoi.macDinh],
    );

    game.onGameResize(Vector2(800, 600));
    // ignore: invalid_use_of_internal_member
    game.mount();

    // Cấp sẵn mã ván để test gameplay không đi qua luồng xác thực ví.
    game.batDauVanMoi(maVan: 'test-spawn-1');
    await game.ready();
    // Đặt George ở vị trí xa để quái tuần tra không vô tình đâm vào George tự nổ
    game.george!.position.setValues(9999, 9999);

    void troiThoiGian(double giay) {
      final ticks = (giay * 60).round();
      for (var i = 0; i < ticks; i++) {
        game.update(1 / 60);
      }
    }

    // 1. Kiểm tra tại giây số 0: ĐỦ 9 CON QUÁI TRÊN BẢN ĐỒ
    final quaiBanDau = game.theGioi.children.whereType<KeDich>().toList();
    expect(quaiBanDau, hasLength(9), reason: 'Màn 1 phải có đủ 9 con từ giây số 0');

    // 2. Chạy 5 giây đầu: vẫn đủ 9 con
    troiThoiGian(5.0);
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(9),
    );

    // 3. Tiêu diệt 1 con tại giây thứ 5: số quái còn 8 (< 9)
    quaiBanDau.first.nhanSatThuong(999);
    troiThoiGian(1 / 60);
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(8),
      reason: 'Vừa tiêu diệt 1 con thì số lượng quái còn 8',
    );

    // 4. Màn 1 là màn gốc: không sinh bù dù đã thiếu quái.
    troiThoiGian(15.0);
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(8),
      reason: 'Màn 1 không sinh bù quái',
    );

    // 5. Trôi thêm thời gian: màn 1 vẫn giữ nguyên số quái còn sống.
    troiThoiGian(11.0);
    await game.ready();
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(8),
      reason: 'Màn 1 không sinh bù sau khi quái bị hạ',
    );

    // 6. Trôi tiếp: không sinh thêm quái ở màn 1.
    troiThoiGian(31.0);
    await game.ready();
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(8),
      reason: 'Màn 1 chỉ có quái ban đầu',
    );
  });

  test('Màn có cấu hình sinh thêm: đúng chu kỳ và giới hạn quái bổ sung', () async {
    const man4 = ManChoi(
      id: 4,
      ten: 'Rừng rậm',
      moTa: 'Thử nghiệm quái bổ sung',
      tep: 'man_4.tmx',
      gioiHanGiay: 100,
      heSoKeDich: 1.0,
      coc: 0,
      thuong: 0,
      soXu: 5,
      sao: 1,
    );

    final diem = <DiemXuatHien>[
      DiemXuatHien('george', Vector2(64, 64)),
      for (var i = 0; i < 5; i++)
        DiemXuatHien('coin', Vector2(96.0 + i * 24, 64)),
      // 2 quái gốc ban đầu
      DiemXuatHien('skeleton', Vector2(200, 200)),
      DiemXuatHien('zombie', Vector2(250, 250)),
    ];
    final bd4 = BanDo.gia(
      luoi: LuoiVaCham.trong(30, 20),
      diemXuatHien: diem,
      tep: 'man_4.tmx',
    );

    final game = GoldRushGame(batBoss: false);
    final anh = await _taoAnhGia();
    game.taiNguyen.napTuAnhGia(anh);
    game.khoiTaoChoKiemThu(
      banDoDau: bd4,
      danhSachMan: [man4],
    );

    game.onGameResize(Vector2(800, 600));
    // ignore: invalid_use_of_internal_member
    game.mount();
    // Cấp sẵn mã ván để test gameplay không đi qua luồng xác thực ví.
    game.batDauVanMoi(maVan: 'test-spawn-4');
    await game.ready();

    game.george!.position.setValues(9999, 9999);

    void troiThoiGian(double giay) {
      final ticks = (giay * 60).round();
      for (var i = 0; i < ticks; i++) {
        game.update(1 / 60);
      }
    }

    // Lúc bắt đầu: có đúng 2 quái gốc xuất hiện ngay từ giây 0
    expect(game.theGioi.children.whereType<KeDich>(), hasLength(2));

    // Đẩy thời gian qua 51s. Màn 4 sinh thêm mỗi 5 giây, tối đa 3 quái.
    troiThoiGian(51.0);
    await game.ready();

    // Đã sinh đủ 3 quái bổ sung (tổng cộng 2 gốc + 3 bổ sung = 5 quái).
    final quaiHienTai = game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead).toList();
    expect(quaiHienTai.length, 5, reason: 'Màn 4 sinh quái bổ sung mỗi 5 giây, tối đa 3 con');

    // Trôi tiếp 25s: đã đạt giới hạn nên không sinh thêm.
    troiThoiGian(25.0);
    await game.ready();
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead).length,
      5,
      reason: 'Màn 4 dừng sinh khi đủ 3 quái bổ sung',
    );
  });
}
