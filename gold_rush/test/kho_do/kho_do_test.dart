import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/kho_do/the_vat_pham.dart';
import 'package:gold_rush/kho_do/vat_pham_hien_thi.dart';
import 'package:gold_rush/man_hinh/kho_do.dart';

VatPhamHienThi taoKiemMau({bool dangTrangBi = false}) {
  return VatPhamHienThi(
    id: 'test_kiem',
    ten: 'Kiếm kiểm thử',
    loai: LoaiVatPham.vuKhi,
    doHiem: DoHiemVatPham.thuong,
    nguon: NguonVatPham.game,
    bieuTuong: BieuTuongVatPham.kiem,
    laDuLieuMau: true,
    thuocTinh: const {'Sát thương mẫu': '12'},
    oDangTrangBi: dangTrangBi ? OTrangBi.vuKhiChinh : null,
  );
}

void main() {
  void cauHinhKichThuoc(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> moKhoDo(
    WidgetTester tester, {
    List<VatPhamHienThi> danhSach = const [],
    Future<void> Function(String)? khiTrangBi,
    VoidCallback? khiDong,
  }) async {
    cauHinhKichThuoc(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManHinhKhoDo(
            khiDong: khiDong ?? () {},
            trangThaiTrangBi: TrangThaiKhoDo.daTai,
            trangThaiNhanVat: TrangThaiKhoDo.trong,
            danhSachVatPham: danhSach,
            khiTrangBi: khiTrangBi,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  Future<void> chonKiem(WidgetTester tester) async {
    final theKiem = find.byType(TheVatPham);

    await tester.ensureVisible(theKiem);
    await tester.pumpAndSettle();
    await tester.tap(theKiem);
    await tester.pumpAndSettle();
  }

  testWidgets('Danh sách trống không hiển thị vật phẩm mẫu', (tester) async {
    await moKhoDo(tester);

    expect(find.byType(TheVatPham), findsNothing);
    expect(find.text('Túi vật phẩm đang trống'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chưa có callback thì nút Trang bị bị vô hiệu hóa', (
    tester,
  ) async {
    await moKhoDo(tester, danhSach: [taoKiemMau()]);

    await chonKiem(tester);

    final nutTrangBi = find.widgetWithText(FilledButton, 'Trang bị');

    expect(nutTrangBi, findsOneWidget);
    expect(tester.widget<FilledButton>(nutTrangBi).onPressed, isNull);
  });

  testWidgets('Chờ xác nhận khóa nút; thất bại không tự đổi trang bị', (
    tester,
  ) async {
    final xacNhan = Completer<void>();
    final cacIdDaGui = <String>[];
    final kiem = taoKiemMau();

    await moKhoDo(
      tester,
      danhSach: [kiem],
      khiTrangBi: (id) {
        cacIdDaGui.add(id);
        return xacNhan.future;
      },
    );

    await chonKiem(tester);

    final nutTrangBi = find.widgetWithText(FilledButton, 'Trang bị');

    await tester.ensureVisible(nutTrangBi);
    await tester.pumpAndSettle();
    await tester.tap(nutTrangBi);

    // Không dùng pumpAndSettle khi vòng chờ đang quay.
    await tester.pump();

    expect(cacIdDaGui, ['test_kiem']);
    expect(kiem.dangTrangBi, isFalse);

    final nutDangXuLy = find.widgetWithText(FilledButton, 'Đang xử lý…');

    expect(nutDangXuLy, findsOneWidget);
    expect(tester.widget<FilledButton>(nutDangXuLy).onPressed, isNull);

    // Bấm lại không được gửi thêm yêu cầu.
    await tester.tap(nutDangXuLy);
    await tester.pump();

    expect(cacIdDaGui, hasLength(1));

    xacNhan.completeError(StateError('Lỗi mô phỏng trong test'));

    await tester.pumpAndSettle();

    expect(kiem.dangTrangBi, isFalse);
    expect(find.textContaining('Thao tác không thành công.'), findsOneWidget);

    final nutThuLai = find.widgetWithText(FilledButton, 'Trang bị');

    expect(tester.widget<FilledButton>(nutThuLai).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Callback thành công chưa tự đổi dữ liệu trang bị', (
    tester,
  ) async {
    final kiem = taoKiemMau();
    var soLanGoi = 0;

    await moKhoDo(
      tester,
      danhSach: [kiem],
      khiTrangBi: (id) async {
        expect(id, 'test_kiem');
        soLanGoi++;
      },
    );

    await chonKiem(tester);

    final nutTrangBi = find.widgetWithText(FilledButton, 'Trang bị');

    await tester.ensureVisible(nutTrangBi);
    await tester.pumpAndSettle();
    await tester.tap(nutTrangBi);
    await tester.pumpAndSettle();

    expect(soLanGoi, 1);
    expect(kiem.dangTrangBi, isFalse);

    // Nguồn bên ngoài chưa gửi dữ liệu cập nhật.
    // Widget không tự coi kiếm là đang trang bị.
    expect(find.widgetWithText(FilledButton, 'Tháo trang bị'), findsNothing);
    expect(find.textContaining('Yêu cầu đã được xác nhận.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dữ liệu cập nhật từ bên ngoài đổi nút sang Tháo', (
    tester,
  ) async {
    cauHinhKichThuoc(tester);

    var danhSach = [taoKiemMau()];
    late VoidCallback capNhatDuLieu;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              capNhatDuLieu = () {
                setState(() {
                  danhSach = [taoKiemMau(dangTrangBi: true)];
                });
              };

              return ManHinhKhoDo(
                khiDong: () {},
                trangThaiTrangBi: TrangThaiKhoDo.daTai,
                trangThaiNhanVat: TrangThaiKhoDo.trong,
                danhSachVatPham: danhSach,
                khiTrangBi: (_) async {},
                khiThao: (_) async {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await chonKiem(tester);

    expect(find.widgetWithText(FilledButton, 'Trang bị'), findsOneWidget);

    capNhatDuLieu();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Tháo trang bị'), findsOneWidget);
    expect(find.text('Đang trang bị: Vũ khí chính'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nút đóng gửi callback đúng một lần', (tester) async {
    var soLanDong = 0;

    await moKhoDo(
      tester,
      khiDong: () {
        soLanDong++;
      },
    );

    await tester.tap(find.byTooltip('Quay lại Menu'));
    await tester.pumpAndSettle();

    expect(soLanDong, 1);
    expect(tester.takeException(), isNull);
  });
}
