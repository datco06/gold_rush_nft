import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/dan_ban.dart';
import 'package:gold_rush/components/george.dart';
import 'package:gold_rush/components/ke_dich.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';
import 'package:gold_rush/components/nhan_vat.dart';
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

  test('Không trang bị súng thì nút bắn không tạo đạn', () async {
    final anh = await _taoAnhGia();
    final taiNguyen = TaiNguyen();
    taiNguyen.napTuAnhGia(anh);
    final banDo = BanDo.gia(
      luoi: LuoiVaCham.trong(20, 20),
      diemXuatHien: [],
      tep: 'test_map.tmx',
    );
    final george = George(
      banDo: banDo,
      hoatAnh: taiNguyen.george,
      viTri: Vector2(100, 100),
      khiChet: () {},
      khiChiSoDoi: () {},
    )..dieuKhienDuoc = true;
    final theGioi = World();
    await theGioi.add(george);

    expect(george.banTheoHuongNhin(), isFalse);
    expect(theGioi.children.whereType<DanBan>(), isEmpty);
  });

  test('Quái áp sát thẳng mặt George: bắn (banTheoHuongNhin) vẫn trúng và gây sát thương', () async {
    final anh = await _taoAnhGia();
    final taiNguyen = TaiNguyen();
    taiNguyen.napTuAnhGia(anh);

    final banDo = BanDo.gia(
      luoi: LuoiVaCham.trong(20, 20),
      diemXuatHien: [
        DiemXuatHien('george', Vector2(100, 100)),
        DiemXuatHien('skeleton', Vector2(108, 100)), // Áp sát ngay trước mặt (cách 8px)
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
    george.dieuKhienDuoc = true;
    george.datChiSoTrangBi(satThuong: 8, tamBan: 140);
    george.current = HuongDi.phai; // Nhìn sang phải

    final quai = KeDich.skeleton(
      banDo: banDo,
      hoatAnh: taiNguyen.skeleton,
      viTri: Vector2(108, 100), // Ở bên phải George 8px
      viTriNguoiChoi: () => george.position,
    );

    final theGioi = World();
    await theGioi.add(george);
    await theGioi.add(quai);

    final mauTruoc = quai.currentHp;
    expect(mauTruoc, greaterThan(0));

    // Bắn thẳng mặt khi quái đang áp sát
    expect(george.banTheoHuongNhin(), isTrue);

    // Quái bị trúng đạn và mất máu
    expect(quai.currentHp, lessThan(mauTruoc), reason: 'Quái áp sát thẳng mặt phải bị bắn trúng');
  });

  test('Kiểm tra 4 hướng nhìn: LÊN, XUỐNG, TRÁI, PHẢI khi quái áp sát thẳng mặt', () async {
    final anh = await _taoAnhGia();
    final taiNguyen = TaiNguyen();
    taiNguyen.napTuAnhGia(anh);

    final cacHuong = [
      (HuongDi.phai, Vector2(110, 100)), // Phải (10px)
      (HuongDi.trai, Vector2(90, 100)),  // Trái (10px)
      (HuongDi.len, Vector2(100, 90)),   // Lên (10px)
      (HuongDi.xuong, Vector2(100, 110)),// Xuống (10px)
    ];

    for (final (huong, viTriQuai) in cacHuong) {
      final banDo = BanDo.gia(
        luoi: LuoiVaCham.trong(20, 20),
        diemXuatHien: [],
        tep: 'test_map.tmx',
      );

      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(100, 100),
        khiChet: () {},
        khiChiSoDoi: () {},
      );
      george.dieuKhienDuoc = true;
      george.datChiSoTrangBi(satThuong: 8, tamBan: 140);
      george.current = huong;

      final quai = KeDich.skeleton(
        banDo: banDo,
        hoatAnh: taiNguyen.skeleton,
        viTri: viTriQuai,
        viTriNguoiChoi: () => george.position,
      );

      final theGioi = World();
      await theGioi.add(george);
      await theGioi.add(quai);

      final mauTruoc = quai.currentHp;
      expect(george.banTheoHuongNhin(), isTrue);
      expect(
        quai.currentHp,
        lessThan(mauTruoc),
        reason: 'Hướng $huong: Quái tại $viTriQuai phải trúng đạn',
      );
    }
  });

  test('Quái ở sau lưng hoặc ở bên hông không thẳng mặt: bắn KHÔNG trúng quái đó', () async {
    final anh = await _taoAnhGia();
    final taiNguyen = TaiNguyen();
    taiNguyen.napTuAnhGia(anh);

    final banDo = BanDo.gia(
      luoi: LuoiVaCham.trong(20, 20),
      diemXuatHien: [],
      tep: 'test_map.tmx',
    );

    final george = George(
      banDo: banDo,
      hoatAnh: taiNguyen.george,
      viTri: Vector2(100, 100),
      khiChet: () {},
      khiChiSoDoi: () {},
    );
    george.dieuKhienDuoc = true;
    george.datChiSoTrangBi(satThuong: 8, tamBan: 140);
    george.current = HuongDi.phai; // Nhìn sang phải

    // Quái ở sau lưng (bên trái George)
    final quaiSauLung = KeDich.skeleton(
      banDo: banDo,
      hoatAnh: taiNguyen.skeleton,
      viTri: Vector2(88, 100),
      viTriNguoiChoi: () => george.position,
    );

    // Quái ở bên cạnh (phía dưới lệch hẳn sang cột khác)
    final quaiBenHong = KeDich.skeleton(
      banDo: banDo,
      hoatAnh: taiNguyen.skeleton,
      viTri: Vector2(100, 125),
      viTriNguoiChoi: () => george.position,
    );

    final theGioi = World();
    await theGioi.add(george);
    await theGioi.add(quaiSauLung);
    await theGioi.add(quaiBenHong);

    final mauSauLung = quaiSauLung.currentHp;
    final mauBenHong = quaiBenHong.currentHp;

    expect(george.banTheoHuongNhin(), isTrue);

    expect(quaiSauLung.currentHp, mauSauLung, reason: 'Quái sau lưng không bị trúng');
    expect(quaiBenHong.currentHp, mauBenHong, reason: 'Quái bên hông không bị trúng');
  });
}
