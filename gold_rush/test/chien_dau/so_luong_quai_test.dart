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

    game.batDauVanMoi();
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

    // 4. Trôi thêm 15 giây (mới được 20s < chu kỳ 30s): vẫn là 8 con, chưa sinh
    troiThoiGian(15.0);
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(8),
      reason: 'Chưa đủ chu kỳ 30s thì chưa sinh bù',
    );

    // 5. Trôi qua mốc 30 giây (thêm 11s = 31s > 30s): sinh bù lại đủ 9 con
    troiThoiGian(11.0);
    await game.ready();
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(9),
      reason: 'Hết chu kỳ 30s thì sinh bù lại để đủ 9',
    );

    // 6. Khi đã đủ 9 con trở lại, trôi qua tiếp chu kỳ 30 giây nữa: KHÔNG SINH NỮA
    troiThoiGian(31.0);
    await game.ready();
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead),
      hasLength(9),
      reason: 'Đã đủ 9 con thì dừng sinh cơ bản',
    );
  });

  test('Màn có cấu hình sinh thêm (Stage >= 4): quái bổ sung vẫn sinh thêm theo tỷ lệ khi đã đủ quái gốc', () async {
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
    game.batDauVanMoi();
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

    // Đẩy thời gian qua 50s (tiến trình >= 0.5) và qua 2 chu kỳ sinh quái (chu kỳ giai đoạn 2 là 20s: lúc 20s và 40s)
    // Lúc này số quái gốc vẫn đủ 2 (không sinh bù gốc), quái bổ sung sinh thêm 2 con (tối đa cho màn 4 là 2)
    troiThoiGian(51.0);
    await game.ready();

    // Đã sinh thêm 2 quái bổ sung (tổng cộng 2 gốc + 2 bổ sung = 4 quái)
    final quaiHienTai = game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead).toList();
    expect(quaiHienTai.length, 4, reason: 'Quái bổ sung sinh đủ tối đa 2 con ngoài 2 quái gốc (tổng 4)');

    // Trôi tiếp 25s nữa: quái bổ sung đã đạt tối đa (2/2) và quái gốc vẫn đủ (2/2) -> không sinh thêm nữa
    troiThoiGian(25.0);
    await game.ready();
    expect(
      game.theGioi.children.whereType<KeDich>().where((q) => !q.isDead).length,
      4,
      reason: 'Đã đạt tối đa bổ sung và đủ quái gốc thì không sinh thêm',
    );
  });
}
