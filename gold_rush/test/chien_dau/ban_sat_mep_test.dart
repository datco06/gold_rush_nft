import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/dan_ban.dart';
import 'package:gold_rush/components/george.dart';
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

  test('George đứng sát 4 mép nhưng bắn thẳng với đường cỏ: đạn vẫn bay ra bình thường không bị huỷ', () async {
    final anh = await _taoAnhGia();
    final taiNguyen = TaiNguyen();
    taiNguyen.napTuAnhGia(anh);

    // Tạo bản đồ 6x6 ô (96x96 pixel):
    // Hàng 0: NƯỚC/TƯỜNG (bị chặn)
    // Hàng 1..4: CỎ (đi được)
    // Hàng 5: NƯỚC/TƯỜNG (bị chặn)
    // Cột 0: TƯỜNG (bị chặn)
    // Cột 1..4: CỎ (đi được)
    // Cột 5: TƯỜNG (bị chặn)
    final chan = List.generate(6, (r) => List.generate(6, (c) {
      if (r == 0 || r == 5 || c == 0 || c == 5) return true;
      return false;
    }));

    final luoi = LuoiVaCham(chan);
    final banDo = BanDo.gia(
      luoi: luoi,
      diemXuatHien: [],
      tep: 'test_mep.tmx',
    );

    // 1. ĐỨNG SÁT MÉP TRÊN (như ảnh người dùng gửi: mép nước ở trên y < 16, chân George ở y = 19, vị trí sprite y = 15)
    // Bắn sang phải (hướng HuongDi.phai) thẳng theo thảm cỏ
    {
      final theGioi = World();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(32, 15), // Chân y = 19 (an toàn trên cỏ), tâm sprite y = 15
        khiChet: () {},
        khiChiSoDoi: () {},
      );
      george.dieuKhienDuoc = true;
      george.datChiSoTrangBi(satThuong: 8, tamBan: 140);
      george.current = HuongDi.phai;
      await theGioi.add(george);

      expect(george.banTheoHuongNhin(), isTrue);

      final dan = theGioi.children.whereType<DanBan>().first;
      expect(dan.isRemoving, isFalse);

      // Cập nhật 15 khung hình (đạn bay dọc theo thảm cỏ)
      for (var i = 0; i < 15; i++) {
        dan.update(1 / 60);
      }
      expect(dan.isRemoving, isFalse, reason: 'Mép TRÊN: Đạn bay thẳng theo cỏ không được bị huỷ');
    }

    // 2. ĐỨNG SÁT MÉP DƯỚI (hàng 5 là vật cản y >= 80, chân George ở y = 76, sprite y = 72)
    // Bắn sang phải (hướng HuongDi.phai) thẳng theo thảm cỏ
    {
      final theGioi = World();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(32, 72),
        khiChet: () {},
        khiChiSoDoi: () {},
      );
      george.dieuKhienDuoc = true;
      george.datChiSoTrangBi(satThuong: 8, tamBan: 140);
      george.current = HuongDi.phai;
      await theGioi.add(george);

      expect(george.banTheoHuongNhin(), isTrue);

      final dan = theGioi.children.whereType<DanBan>().first;
      expect(dan.isRemoving, isFalse);

      for (var i = 0; i < 15; i++) {
        dan.update(1 / 60);
      }
      expect(dan.isRemoving, isFalse, reason: 'Mép DƯỚI: Đạn bay thẳng theo cỏ không được bị huỷ');
    }

    // 3. ĐỨNG SÁT MÉP TRÁI (cột 0 là vật cản x < 16, chân George ở x = 21, sprite x = 21)
    // Bắn xuống dưới (hướng HuongDi.xuong) thẳng theo thảm cỏ
    {
      final theGioi = World();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(21, 32),
        khiChet: () {},
        khiChiSoDoi: () {},
      );
      george.dieuKhienDuoc = true;
      george.datChiSoTrangBi(satThuong: 8, tamBan: 140);
      george.current = HuongDi.xuong;
      await theGioi.add(george);

      expect(george.banTheoHuongNhin(), isTrue);

      final dan = theGioi.children.whereType<DanBan>().first;
      expect(dan.isRemoving, isFalse);

      for (var i = 0; i < 15; i++) {
        dan.update(1 / 60);
      }
      expect(dan.isRemoving, isFalse, reason: 'Mép TRÁI: Đạn bay thẳng theo cỏ không được bị huỷ');
    }

    // 4. ĐỨNG SÁT MÉP PHẢI (cột 5 là vật cản x >= 80, chân George ở x = 75, sprite x = 75)
    // Bắn xuống dưới (hướng HuongDi.xuong) thẳng theo thảm cỏ
    {
      final theGioi = World();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(75, 32),
        khiChet: () {},
        khiChiSoDoi: () {},
      );
      george.dieuKhienDuoc = true;
      george.datChiSoTrangBi(satThuong: 8, tamBan: 140);
      george.current = HuongDi.xuong;
      await theGioi.add(george);

      expect(george.banTheoHuongNhin(), isTrue);

      final dan = theGioi.children.whereType<DanBan>().first;
      expect(dan.isRemoving, isFalse);

      for (var i = 0; i < 15; i++) {
        dan.update(1 / 60);
      }
      expect(dan.isRemoving, isFalse, reason: 'Mép PHẢI: Đạn bay thẳng theo cỏ không được bị huỷ');
    }
  });
}

