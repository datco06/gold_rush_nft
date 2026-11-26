import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/world_map/canh_quan_world_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  test(
    'Giữ ảnh khi còn màn dùng, giải phóng khi đóng và nạp lại đủ ảnh',
    () async {
      final traAnhDau = TaiNguyenWorldMap.giuAnhKhiMoBanDo()!;
      final traAnhSau = TaiNguyenWorldMap.giuAnhKhiMoBanDo()!;
      final anhDau = await TaiNguyenWorldMap.nap();
      final kichThuoc = {
        for (final anh in anhDau.entries)
          anh.key: (anh.value.width, anh.value.height),
      };

      traAnhDau();
      await Future<void>.delayed(Duration.zero);
      expect(identical(TaiNguyenWorldMap.anhDaNap, anhDau), isTrue);
      expect(anhDau.values.every((anh) => !anh.debugDisposed), isTrue);

      traAnhSau();
      await Future<void>.delayed(Duration.zero);
      expect(TaiNguyenWorldMap.anhDaNap, isNull);
      expect(anhDau.values.every((anh) => anh.debugDisposed), isTrue);

      final traAnhMoi = TaiNguyenWorldMap.giuAnhKhiMoBanDo()!;
      final anhMoi = await TaiNguyenWorldMap.nap();
      expect(anhMoi.keys, unorderedEquals(TaiNguyenWorldMap.tenAnh));
      expect({
        for (final anh in anhMoi.entries)
          anh.key: (anh.value.width, anh.value.height),
      }, kichThuoc);
      expect(anhMoi.values.every((anh) => !anh.debugDisposed), isTrue);
      traAnhMoi();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'Đóng trong lúc đang nạp thì bỏ ảnh và cho lần mở sau nạp lại',
    () async {
      final traAnh = TaiNguyenWorldMap.giuAnhKhiMoBanDo()!;
      final dangNap = TaiNguyenWorldMap.nap();
      traAnh();
      expect(await dangNap, isEmpty);
      expect(TaiNguyenWorldMap.anhDaNap, isNull);

      final traAnhMoi = TaiNguyenWorldMap.giuAnhKhiMoBanDo()!;
      final anhMoi = await TaiNguyenWorldMap.nap();
      expect(anhMoi.length, TaiNguyenWorldMap.tenAnh.length);
      traAnhMoi();
      await Future<void>.delayed(Duration.zero);
    },
  );
}
