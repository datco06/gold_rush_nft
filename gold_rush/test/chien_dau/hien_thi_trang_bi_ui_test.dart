import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/kho_do/danh_sach_trang_bi.dart';
import 'package:gold_rush/kho_do/nhan_vat_voi_trang_bi.dart';
import 'package:gold_rush/kho_do/vat_pham_hien_thi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HinhTrangBiFrame & NhanVatVoiTrangBi UI', () {
    testWidgets('HinhTrangBiFrame cắt đúng 1 frame 64x64 từ sheet 4x4', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: HinhTrangBiFrame(
                asset: 'assets/images/trang_bi/sung_cap_1_sprite_4x4.png',
                kichThuoc: 34,
              ),
            ),
          ),
        ),
      );

      final frameFinder = find.byType(HinhTrangBiFrame);
      expect(frameFinder, findsOneWidget);

      final clipRectFinder = find.descendant(
        of: frameFinder,
        matching: find.byType(ClipRect),
      );
      expect(clipRectFinder, findsOneWidget);

      final overflowFinder = find.descendant(
        of: frameFinder,
        matching: find.byType(OverflowBox),
      );
      expect(overflowFinder, findsOneWidget);

      final overflow = tester.widget<OverflowBox>(overflowFinder);
      expect(overflow.minWidth, 34 * 4);
      expect(overflow.minHeight, 34 * 4);
      expect(overflow.alignment, Alignment.topLeft);
    });

    testWidgets(
      'NhanVatVoiTrangBi hiển thị nhân vật cùng vũ khí tại vị trí cầm tay đúng như trong game',
      (tester) async {
        final danhSachVp = danhSachTrangBiCuaHang();
        final sung = danhSachVp.first.voiTrangBi(OTrangBi.vuKhiChinh);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: NhanVatVoiTrangBi(
                  tepAnh: 'george.png',
                  kichThuoc: 96,
                  danhSachVatPham: [sung],
                ),
              ),
            ),
          ),
        );

        final nhanVatFinder = find.byType(NhanVatVoiTrangBi);
        expect(nhanVatFinder, findsOneWidget);

        // Tìm Positioned của lớp vũ khí
        final positionedList = tester
            .widgetList<Positioned>(
              find.descendant(
                of: nhanVatFinder,
                matching: find.byType(Positioned),
              ),
            )
            .toList();

        expect(positionedList, isNotEmpty);

        // Vũ khí có kích thước 55% nhân vật và được neo theo tâm lớp.
        final vuKhiPositioned = positionedList.firstWhere(
          (p) => (p.left ?? 0) > 0,
        );
        expect(vuKhiPositioned.left, closeTo(51.6, 0.0001));
        expect(vuKhiPositioned.top, closeTo(45.6, 0.0001));
        expect(vuKhiPositioned.width, closeTo(52.8, 0.0001));
        expect(vuKhiPositioned.height, closeTo(52.8, 0.0001));
      },
    );

    testWidgets('NhanVatVoiTrangBi hiển thị đồng thời cả giáp và giày', (
      tester,
    ) async {
      final danhSachVp = danhSachTrangBiCuaHang();
      final sung = danhSachVp.first.voiTrangBi(OTrangBi.vuKhiChinh);
      final giap = danhSachVp
          .firstWhere((v) => v.loai == LoaiVatPham.giap)
          .voiTrangBi(OTrangBi.giap);
      final giay = danhSachVp
          .firstWhere((v) => v.loai == LoaiVatPham.giay)
          .voiTrangBi(OTrangBi.giay);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NhanVatVoiTrangBi(
                tepAnh: 'george.png',
                kichThuoc: 96,
                danhSachVatPham: [sung, giap, giay],
              ),
            ),
          ),
        ),
      );

      final nhanVatFinder = find.byType(NhanVatVoiTrangBi);
      expect(nhanVatFinder, findsOneWidget);

      final positionedList = tester
          .widgetList<Positioned>(
            find.descendant(
              of: nhanVatFinder,
              matching: find.byType(Positioned),
            ),
          )
          .toList();

      // Có đủ 3 lớp và mỗi lớp được đặt theo tâm của sprite.
      expect(positionedList.length, 3);

      final vuKhiP = positionedList.firstWhere((p) => (p.left ?? 0) > 50);
      expect(vuKhiP.left, closeTo(51.6, 0.0001));
      expect(vuKhiP.top, closeTo(45.6, 0.0001));

      final giayP = positionedList.firstWhere(
        (p) => (p.left ?? 0) > 20 && (p.left ?? 0) < 25,
      );
      expect(giayP.left, closeTo(21.6, 0.0001));
      expect(giayP.top, closeTo(57.6, 0.0001));

      final giapP = positionedList.firstWhere(
        (p) => (p.left ?? 0) > 10 && (p.left ?? 0) < 15,
      );
      expect(giapP.left, closeTo(13.44, 0.0001));
      expect(giapP.top, closeTo(13.44, 0.0001));
    });
  });
}
