import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/components/ban_do.dart';
import 'package:gold_rush/components/george.dart';
import 'package:gold_rush/components/luoi_va_cham.dart';
import 'package:gold_rush/components/trang_bi_george.dart';
import 'package:gold_rush/tai_nguyen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TaiNguyen taiNguyen;

  setUpAll(() async {
    taiNguyen = TaiNguyen();
    await taiNguyen.nap();
  });

  group('TrangBiGeorge - Kiểm tra các cấu hình trang bị', () {
    test('1. Không trang bị: nạp, đổi hướng và bắn khi cả 3 ô trống', () async {
      final trangBi = TrangBiGeorge();
      await trangBi.onLoad();

      for (final huong in HuongDi.values) {
        trangBi.capNhatHuong(huong);
        trangBi.datDangDi(true);
        trangBi.updateTree(1 / 60);
        trangBi.phatBan();
      }

      final soLopCoAnimation = trangBi.children
          .whereType<SpriteAnimationGroupComponent<HuongDi>>()
          .where((lop) => lop.animation != null);
      expect(soLopCoAnimation, isEmpty);
    });

    test('2. Chỉ cầm súng: nạp, đổi hướng và bắn khi giáp/giày trống', () async {
      final trangBi = TrangBiGeorge(
        vuKhi: taiNguyen.trangBiTheoTep['sung_cap_1_sprite_4x4.png'],
      );
      await trangBi.onLoad();

      for (final huong in HuongDi.values) {
        trangBi.capNhatHuong(huong);
        trangBi.datDangDi(true);
        trangBi.updateTree(1 / 60);
        trangBi.phatBan();
      }

      final soLopCoAnimation = trangBi.children
          .whereType<SpriteAnimationGroupComponent<HuongDi>>()
          .where((lop) => lop.animation != null);
      expect(soLopCoAnimation, hasLength(1));
    });

    test('3. Chỉ mặc giáp: nạp, đổi hướng khi súng/giày trống', () async {
      final trangBi = TrangBiGeorge(
        giap: taiNguyen.trangBiTheoTep['giap_thuong_cap_1.png'],
      );
      await trangBi.onLoad();

      for (final huong in HuongDi.values) {
        trangBi.capNhatHuong(huong);
        trangBi.datDangDi(true);
        trangBi.updateTree(1 / 60);
        trangBi.phatBan(); // Bắn khi không có súng không được lỗi
      }

      final soLopCoAnimation = trangBi.children
          .whereType<SpriteAnimationGroupComponent<HuongDi>>()
          .where((lop) => lop.animation != null);
      expect(soLopCoAnimation, hasLength(1));
    });

    test('4. Chỉ mang giày: nạp, đổi hướng khi súng/giáp trống', () async {
      final trangBi = TrangBiGeorge(
        giay: taiNguyen.trangBiTheoTep['giay_thuong_cap_1.png'],
      );
      await trangBi.onLoad();

      for (final huong in HuongDi.values) {
        trangBi.capNhatHuong(huong);
        trangBi.datDangDi(true);
        trangBi.updateTree(1 / 60);
        trangBi.phatBan();
      }

      final soLopCoAnimation = trangBi.children
          .whereType<SpriteAnimationGroupComponent<HuongDi>>()
          .where((lop) => lop.animation != null);
      expect(soLopCoAnimation, hasLength(1));
    });

    test('5. Trang bị đủ 3 món: súng, giáp, giày hoạt động đồng bộ', () async {
      final trangBi = TrangBiGeorge(
        vuKhi: taiNguyen.trangBiTheoTep['sung_cap_1_sprite_4x4.png'],
        giap: taiNguyen.trangBiTheoTep['giap_thuong_cap_1.png'],
        giay: taiNguyen.trangBiTheoTep['giay_thuong_cap_1.png'],
      );
      await trangBi.onLoad();

      for (final huong in HuongDi.values) {
        trangBi.capNhatHuong(huong);
        trangBi.datDangDi(true);
        trangBi.updateTree(1 / 60);
        trangBi.phatBan();
      }

      final soLopCoAnimation = trangBi.children
          .whereType<SpriteAnimationGroupComponent<HuongDi>>()
          .where((lop) => lop.animation != null);
      expect(soLopCoAnimation, hasLength(3));
    });

    test('6. Trang bị, tháo hoặc đổi món kể cả khi asset rỗng hoặc đang tải', () async {
      final trangBi = TrangBiGeorge();
      await trangBi.onLoad();

      // Asset đang tải trả về map rỗng: an toàn, không có animation
      trangBi.capNhatTrangBi(vuKhi: const {}, giap: const {}, giay: const {});
      trangBi.capNhatHuong(HuongDi.len);
      expect(
        trangBi.children
            .whereType<SpriteAnimationGroupComponent<HuongDi>>()
            .where((lop) => lop.animation != null),
        isEmpty,
      );

      // Trang bị súng
      trangBi.capNhatTrangBi(
        vuKhi: taiNguyen.trangBiTheoTep['sung_cap_1_sprite_4x4.png'],
      );
      trangBi.capNhatHuong(HuongDi.phai);
      expect(
        trangBi.children
            .whereType<SpriteAnimationGroupComponent<HuongDi>>()
            .where((lop) => lop.animation != null),
        hasLength(1),
      );

      // Mặc thêm giáp và giày
      trangBi.capNhatTrangBi(
        giap: taiNguyen.trangBiTheoTep['giap_thuong_cap_1.png'],
        giay: taiNguyen.trangBiTheoTep['giay_thuong_cap_1.png'],
      );
      trangBi.capNhatHuong(HuongDi.trai);
      expect(
        trangBi.children
            .whereType<SpriteAnimationGroupComponent<HuongDi>>()
            .where((lop) => lop.animation != null),
        hasLength(3),
      );

      // Tháo giáp (truyền map rỗng hoặc null)
      trangBi.capNhatTrangBi(giap: const {});
      expect(
        trangBi.children
            .whereType<SpriteAnimationGroupComponent<HuongDi>>()
            .where((lop) => lop.animation != null),
        hasLength(2),
      );

      // Đổi súng sang súng cấp 2
      trangBi.capNhatTrangBi(
        vuKhi: taiNguyen.trangBiTheoTep['sung_cap_2_sprite_4x4.png'],
      );
      trangBi.capNhatHuong(HuongDi.xuong);
      expect(
        trangBi.children
            .whereType<SpriteAnimationGroupComponent<HuongDi>>()
            .where((lop) => lop.animation != null),
        hasLength(2),
      );
    });
  });

  group('George - Di chuyển WASD, mũi tên, cảm ứng & đổi hướng liên tục', () {
    BanDo taoBanDo() {
      return BanDo.gia(
        luoi: LuoiVaCham.trong(30, 20),
        diemXuatHien: [DiemXuatHien('george', Vector2(100, 100))],
        tep: 'gold_rush.tmx',
      );
    }

    test('George di chuyển bằng WASD và đổi hướng liên tục khi chưa có giáp/giày', () async {
      final banDo = taoBanDo();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(100, 100),
        khiChiSoDoi: () {},
        khiChet: () {},
        trangBiVuKhi: taiNguyen.trangBiTheoTep['sung_cap_1_sprite_4x4.png'] ?? const {},
      );
      await george.onLoad();
      george.dieuKhienDuoc = true;

      // Phím W (Đi lên)
      george.onKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          timeStamp: Duration.zero,
        ),
        {LogicalKeyboardKey.keyW},
      );
      george.update(1 / 60);
      expect(george.current, HuongDi.len);

      // Phím D (Đi sang phải)
      george.onKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyD,
          logicalKey: LogicalKeyboardKey.keyD,
          timeStamp: Duration.zero,
        ),
        {LogicalKeyboardKey.keyD},
      );
      george.update(1 / 60);
      expect(george.current, HuongDi.phai);

      // Phím S (Đi xuống)
      george.onKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyS,
          logicalKey: LogicalKeyboardKey.keyS,
          timeStamp: Duration.zero,
        ),
        {LogicalKeyboardKey.keyS},
      );
      george.update(1 / 60);
      expect(george.current, HuongDi.xuong);

      // Phím A (Đi sang trái)
      george.onKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          timeStamp: Duration.zero,
        ),
        {LogicalKeyboardKey.keyA},
      );
      george.update(1 / 60);
      expect(george.current, HuongDi.trai);
    });

    test('George di chuyển bằng phím mũi tên và đổi hướng liên tục khi không trang bị', () async {
      final banDo = taoBanDo();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(100, 100),
        khiChiSoDoi: () {},
        khiChet: () {},
      );
      await george.onLoad();
      george.dieuKhienDuoc = true;

      final phimVaHuong = [
        (PhysicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp, HuongDi.len),
        (PhysicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight, HuongDi.phai),
        (PhysicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowDown, HuongDi.xuong),
        (PhysicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft, HuongDi.trai),
      ];

      for (final (physical, logical, huongKyVong) in phimVaHuong) {
        george.onKeyEvent(
          KeyDownEvent(
            physicalKey: physical,
            logicalKey: logical,
            timeStamp: Duration.zero,
          ),
          {logical},
        );
        george.update(1 / 60);
        expect(george.current, huongKyVong);
      }
    });

    test('George di chuyển bằng Joystick cảm ứng & đổi hướng liên tục', () async {
      final banDo = taoBanDo();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(100, 100),
        khiChiSoDoi: () {},
        khiChet: () {},
        trangBiGiay: taiNguyen.trangBiTheoTep['giay_thuong_cap_1.png'] ?? const {},
      );
      await george.onLoad();
      george.dieuKhienDuoc = true;

      // Joystick kéo các hướng liên tục
      final cacHuong = [
        Vector2(0, -1),
        Vector2(1, 0),
        Vector2(0, 1),
        Vector2(-1, 0),
        Vector2(1, 1),
        Vector2(-1, -1),
      ];

      for (final vec in cacHuong) {
        george.huongJoystick.setFrom(vec);
        george.update(1 / 60);
      }

      // Nhấp chạm di chuyển tới đích viTriDich
      george.huongJoystick.setZero();
      george.viTriDich = Vector2(150, 150);
      george.update(1 / 60);
      expect(george.dieuKhienDuoc, isTrue);
    });

    test('George đổi trang bị và bắn ngay khi đang di chuyển đổi hướng', () async {
      final banDo = taoBanDo();
      final george = George(
        banDo: banDo,
        hoatAnh: taiNguyen.george,
        viTri: Vector2(100, 100),
        khiChiSoDoi: () {},
        khiChet: () {},
      );
      await george.onLoad();
      george.dieuKhienDuoc = true;

      // Di chuyển sang phải
      george.capNhatHuong(Vector2(1, 0));
      george.update(1 / 60);

      // Bắn khi chưa có súng
      expect(george.banTheoHuongNhin(), isFalse); // chưa có cha (parent)

      // Cập nhật trang bị súng và giáp khi đang chạy
      george.capNhatTrangBiHienThi(
        vuKhi: taiNguyen.trangBiTheoTep['sung_cap_1_sprite_4x4.png'],
        giap: taiNguyen.trangBiTheoTep['giap_thuong_cap_1.png'],
      );

      // Đổi hướng sang trái
      george.capNhatHuong(Vector2(-1, 0));
      george.update(1 / 60);
      expect(george.current, HuongDi.trai);

      // Tháo súng và đổi sang giày
      george.capNhatTrangBiHienThi(
        vuKhi: const {},
        giay: taiNguyen.trangBiTheoTep['giay_thuong_cap_1.png'],
      );
      george.capNhatHuong(Vector2(0, 1));
      george.update(1 / 60);
      expect(george.current, HuongDi.xuong);
    });
  });
}
