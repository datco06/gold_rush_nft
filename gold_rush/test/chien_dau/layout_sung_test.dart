import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/cau_hinh.dart';
import 'package:gold_rush/components/nhan_vat.dart';
import 'package:gold_rush/components/trang_bi_george.dart';
import 'package:gold_rush/tai_nguyen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TaiNguyen taiNguyen;

  setUpAll(() async {
    taiNguyen = TaiNguyen();
    await taiNguyen.nap();
  });

  group('TrangBiGeorge - Layout vị trí súng theo 4 hướng', () {
    test('Súng gắn vào tay và cập nhật toạ độ đúng theo từng hướng mặt', () async {
      final vuKhi = taiNguyen.trangBiTheoTep['sung_cap_1_sprite_4x4.png'];
      final trangBi = TrangBiGeorge(vuKhi: vuKhi);
      await trangBi.onLoad();

      // Mặc định ban đầu là hướng xuống
      expect(
        trangBi.viTriLopVuKhi,
        Vector2(
          CauHinh.kichThuocO / 2 + TrangBiGeorge.viTriVuKhi(HuongDi.xuong).dx,
          CauHinh.kichThuocO / 2 + TrangBiGeorge.viTriVuKhi(HuongDi.xuong).dy,
        ),
      );
      expect(trangBi.viTriLopVuKhi, Vector2(13.0, 12.0));

      // Hướng trái
      trangBi.capNhatHuong(HuongDi.trai);
      expect(trangBi.viTriLopVuKhi, Vector2(2.0, 9.0));

      // Hướng phải
      trangBi.capNhatHuong(HuongDi.phai);
      expect(trangBi.viTriLopVuKhi, Vector2(14.0, 9.0));

      // Hướng lên
      trangBi.capNhatHuong(HuongDi.len);
      expect(trangBi.viTriLopVuKhi, Vector2(13.0, 7.0));

      // Đổi súng sang loại khác vẫn giữ đúng toạ độ theo hướng hiện tại (lên)
      final vuKhiCap2 = taiNguyen.trangBiTheoTep['sung_cap_2_sprite_4x4.png'];
      trangBi.capNhatTrangBi(vuKhi: vuKhiCap2);
      expect(trangBi.viTriLopVuKhi, Vector2(13.0, 7.0));

      // Quay lại hướng xuống
      trangBi.capNhatHuong(HuongDi.xuong);
      expect(trangBi.viTriLopVuKhi, Vector2(13.0, 12.0));
    });
  });
}
