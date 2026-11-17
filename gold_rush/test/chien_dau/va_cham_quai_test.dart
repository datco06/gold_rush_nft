import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/dan_ban.dart';
import 'package:gold_rush/components/george.dart';
import 'package:gold_rush/components/ke_dich.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';
import 'package:gold_rush/tai_nguyen.dart';

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

  test('Quái chạm vào George: George mất máu nhưng quái KHÔNG biến mất; quái chỉ biến mất khi trúng đạn chết', () async {
    final anh = await _taoAnhGia();
    final taiNguyen = TaiNguyen();
    taiNguyen.napTuAnhGia(anh);

    final banDo = BanDo.gia(
      luoi: LuoiVaCham.trong(20, 20),
      diemXuatHien: [
        DiemXuatHien('george', Vector2(100, 100)),
        DiemXuatHien('skeleton', Vector2(100, 100)),
      ],
      tep: 'test_map.tmx',
    );

    final george = George(
      banDo: banDo,
      hoatAnh: taiNguyen.george,
      viTri: Vector2(100, 100),
      khiChet: () {},
      khiChiSoDoi: () {},
    );

    final quai = KeDich.skeleton(
      banDo: banDo,
      hoatAnh: taiNguyen.skeleton,
      viTri: Vector2(100, 100),
      viTriNguoiChoi: () => george.position,
    );

    final theGioi = World();
    await theGioi.add(george);
    await theGioi.add(quai);

    final mauTruoc = george.mau;

    // 1. Va chạm xảy ra: George đụng trúng quái
    george.onCollisionStart({}, quai);
    george.onCollision({}, quai);

    // George mất máu
    expect(george.mau, mauTruoc - quai.satThuongCham);
    expect(george.dangBatTu, isTrue);

    // QUÁI KHÔNG BIẾN MẤT VÀ KHÔNG CHẾT
    expect(quai.isDead, isFalse, reason: 'Quái không được chết khi đụng trúng George');
    expect(quai.daNo, isFalse, reason: 'Quái không được tự nổ khi đụng trúng George');
    expect(quai.isRemoving, isFalse, reason: 'Quái không bị xoá khỏi game');

    // 2. Tiếp tục chạm trong lúc George đang bất tử: quái vẫn sống
    george.onCollision({}, quai);
    expect(george.mau, mauTruoc - quai.satThuongCham);
    expect(quai.isDead, isFalse);

    // 3. Quái chỉ chết và biến mất khi bị trúng đạn
    final dan = DanBan(
      banDo: banDo,
      viTri: quai.position.clone(),
      huong: Vector2(1, 0),
      satThuong: 999, // Đòn kết liễu
      tamBay: 100,
    );
    dan.onCollisionStart({}, quai);

    expect(quai.isDead, isTrue, reason: 'Quái phải chết khi bị trúng đạn hết máu');
    expect(quai.daNo, isTrue, reason: 'Quái nổ tung khi chết do đạn');
  });
}
