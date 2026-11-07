import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/world_map/nut_man_choi.dart';
import 'package:gold_rush/world_map/tien_trinh_world_map.dart';

void main() {
  group('Tiến trình World Map', () {
    test('Phân biệt màn hoàn thành, đã mở và chưa mở', () {
      final tienTrinh = TienTrinhWorldMap(
        cacManDaMo: [1, 2, 3],
        cacManHoanThanh: [1, 2],
        manHienTai: 3,
      );

      expect(tienTrinh.trangThaiCuaMan(1), TrangThaiMan.hoanThanh);
      expect(tienTrinh.trangThaiCuaMan(2), TrangThaiMan.hoanThanh);
      expect(tienTrinh.trangThaiCuaMan(3), TrangThaiMan.daMo);
      expect(tienTrinh.trangThaiCuaMan(4), TrangThaiMan.chuaMo);
    });

    test('Quyền mở màn không phụ thuộc số vàng', () {
      final tienTrinh = TienTrinhWorldMap(
        cacManDaMo: [1, 2],
        cacManHoanThanh: [1],
        manHienTai: 2,
      );

      expect(tienTrinh.daMoMan(2), isTrue);
      expect(tienTrinh.daMoMan(3), isFalse);
    });

    test('Chưa mở màn nào thì tất cả đều khóa', () {
      final tienTrinh = TienTrinhWorldMap(cacManDaMo: [], cacManHoanThanh: []);

      expect(tienTrinh.manHienTai, isNull);
      expect(tienTrinh.daMoMan(1), isFalse);
      expect(tienTrinh.trangThaiCuaMan(1), TrangThaiMan.chuaMo);
    });

    test('Không bị thay đổi khi danh sách đầu vào thay đổi', () {
      final daMo = [1, 2];
      final hoanThanh = [1];

      final tienTrinh = TienTrinhWorldMap(
        cacManDaMo: daMo,
        cacManHoanThanh: hoanThanh,
        manHienTai: 2,
      );

      daMo.add(3);
      hoanThanh.add(2);

      expect(tienTrinh.daMoMan(3), isFalse);
      expect(tienTrinh.trangThaiCuaMan(2), TrangThaiMan.daMo);
    });

    test('Không cho sửa trực tiếp tập màn đã mở', () {
      final tienTrinh = TienTrinhWorldMap(cacManDaMo: [1], cacManHoanThanh: []);

      expect(() => tienTrinh.cacManDaMo.add(2), throwsUnsupportedError);
    });

    test('Từ chối ID màn không hợp lệ', () {
      expect(
        () => TienTrinhWorldMap(cacManDaMo: [0], cacManHoanThanh: []),
        throwsArgumentError,
      );
    });

    test('Từ chối màn hoàn thành chưa nằm trong tập đã mở', () {
      expect(
        () => TienTrinhWorldMap(cacManDaMo: [1], cacManHoanThanh: [2]),
        throwsArgumentError,
      );
    });

    test('Từ chối màn hiện tại chưa được mở', () {
      expect(
        () => TienTrinhWorldMap(
          cacManDaMo: [1],
          cacManHoanThanh: [],
          manHienTai: 2,
        ),
        throwsArgumentError,
      );
    });
  });
}
