import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/world_map/ban_do_the_gioi.dart';
import 'package:gold_rush/world_map/canh_quan_world_map.dart';
import 'package:gold_rush/world_map/hoat_anh_world_map.dart';
import 'package:gold_rush/world_map/nut_man_choi.dart';
import 'package:gold_rush/world_map/tien_trinh_world_map.dart';

void main() {
  final danhSachMan = ManChoi.docDanhSach(
    File('assets/tiles/man_choi.json').readAsStringSync(),
  );

  // Chỉ dùng cho test, không truyền vào luồng game chính.
  final tienTrinhMau = TienTrinhWorldMap(
    cacManDaMo: [1, 2, 3],
    cacManHoanThanh: [1, 2],
    manHienTai: 3,
  );

  Future<void> moBanDo(
    WidgetTester tester, {
    required ValueChanged<ManChoi> khiChon,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(2000, 1200);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    int? idDangChon = tienTrinhMau.manHienTai;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return BanDoTheGioi(
                danhSachMan: danhSachMan,
                trangThaiCacMan: {
                  for (final man in danhSachMan)
                    man.id: tienTrinhMau.trangThaiCuaMan(man.id),
                },
                manDangChon: idDangChon,
                khiChonMan: (man) {
                  setState(() {
                    idDangChon = man.id;
                  });
                  khiChon(man);
                },
              );
            },
          ),
        ),
      ),
    );

    // Cho phép bản đồ hoàn tất bước căn góc nhìn sau khung hình.
    await tester.pumpAndSettle();
  }

  testWidgets('Hiển thị đủ sáu ô từ dữ liệu màn gốc', (tester) async {
    await moBanDo(tester, khiChon: (_) {});

    expect(danhSachMan, hasLength(6));
    expect(find.byType(NutManChoi), findsNWidgets(6));

    for (final man in danhSachMan) {
      expect(find.text('Màn ${man.id}'), findsOneWidget);
      expect(find.text(man.ten), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('Hiển thị đúng trạng thái tiến trình được truyền vào', (
    tester,
  ) async {
    await moBanDo(tester, khiChon: (_) {});

    final cacNut = tester
        .widgetList<NutManChoi>(find.byType(NutManChoi))
        .toList();

    for (final nut in cacNut) {
      expect(
        nut.trangThai,
        tienTrinhMau.trangThaiCuaMan(nut.man.id),
        reason: 'Trạng thái màn ${nut.man.id}',
      );

      expect(
        nut.dangChon,
        nut.man.id == 3,
        reason: 'Màn hiện tại ban đầu là màn 3',
      );
    }

    expect(find.text('Hoàn thành'), findsNWidgets(2));
    expect(find.text('Đã mở'), findsOneWidget);
    expect(find.text('Chưa mở'), findsNWidgets(3));
  });

  testWidgets('Chọn từng ô trả đúng đối tượng màn', (tester) async {
    final cacManDaChon = <ManChoi>[];

    await moBanDo(tester, khiChon: cacManDaChon.add);

    // Dựng bản đồ không tự phát sinh sự kiện chọn.
    expect(cacManDaChon, isEmpty);

    for (final man in danhSachMan) {
      await tester.tap(find.text('Màn ${man.id}'));
      await tester.pumpAndSettle();

      expect(cacManDaChon.last, same(man));

      final cacNutDangChon = tester
          .widgetList<NutManChoi>(find.byType(NutManChoi))
          .where((nut) => nut.dangChon)
          .toList();

      expect(cacNutDangChon, hasLength(1));
      expect(cacNutDangChon.single.man.id, man.id);
    }

    expect(cacManDaChon, hasLength(danhSachMan.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ô khóa vẫn xem được nhưng không tự đổi tiến trình', (
    tester,
  ) async {
    ManChoi? manDaChon;

    await moBanDo(
      tester,
      khiChon: (man) {
        manDaChon = man;
      },
    );

    await tester.tap(find.text('Màn 4'));
    await tester.pumpAndSettle();

    expect(manDaChon?.id, 4);

    final nutMan4 = tester
        .widgetList<NutManChoi>(find.byType(NutManChoi))
        .singleWhere((nut) => nut.man.id == 4);

    expect(nutMan4.dangChon, isTrue);
    expect(nutMan4.trangThai, TrangThaiMan.chuaMo);
    expect(tienTrinhMau.daMoMan(4), isFalse);
    expect(tienTrinhMau.manHienTai, 3);
  });

  group('World Map mở rộng, 6 vùng, đường mòn, George và Camera', () {
    test('Bản đồ mở rộng gấp 4 lần diện tích cũ và giữ vùng cũ tỉ lệ 1:1', () {
      expect(BoCucWorldMap.kichThuocCu, const Size(1465, 980));
      expect(BoCucWorldMap.kichThuoc, const Size(2930, 1960));
      expect(BoCucWorldMap.vungBanDoCu.size, BoCucWorldMap.kichThuocCu);
      expect(
        (Offset.zero & BoCucWorldMap.kichThuoc).contains(
          BoCucWorldMap.vungBanDoCu.topLeft,
        ),
        isTrue,
      );
      expect(
        (Offset.zero & BoCucWorldMap.kichThuoc).contains(
          BoCucWorldMap.vungBanDoCu.bottomRight,
        ),
        isTrue,
      );
    });

    test('Đủ sáu vùng địa lý liên tiếp tương ứng màn 1–6 và mạng đường nối liên tục', () {
      expect(BoCucWorldMap.cacVung, hasLength(6));
      expect(
        BoCucWorldMap.cacVung.map((v) => v.idManChinh).toList(),
        [1, 2, 3, 4, 5, 6],
      );
      expect(
        BoCucWorldMap.cacVung.map((v) => v.loai).toList(),
        [
          LoaiVungWorldMap.langKhoiDau,
          LoaiVungWorldMap.khuRung,
          LoaiVungWorldMap.nuiDaMoVang,
          LoaiVungWorldMap.nuiLua,
          LoaiVungWorldMap.denCoTanTich,
          LoaiVungWorldMap.vungKhoBau,
        ],
      );

      for (final vung in BoCucWorldMap.cacVung) {
        final viTriNode = BoCucWorldMap.viTriMan[vung.idManChinh]!;
        expect(vung.phamVi.contains(viTriNode), isTrue);
        expect(vung.phamVi.contains(vung.viTriBienBao), isTrue);
      }

      // Kiểm tra các đoạn đường 1->2->3->4->5->6 nối khít tọa độ từng node.
      for (var id = 1; id < 6; id++) {
        final doan = BoCucWorldMap.cacTuyenDuong.firstWhere(
          (t) => t.tuMan == id && t.denMan == id + 1,
        );
        expect(doan.cacDiem.first, BoCucWorldMap.viTriMan[id]);
        expect(doan.cacDiem.last, BoCucWorldMap.viTriMan[id + 1]);
        expect(doan.tongChieuDai, greaterThan(100));
      }
    });

    testWidgets(
      'George đi bộ mượt theo đường nối đến đúng node đã mở và dừng tại đích',
      (tester) async {
        await moBanDo(tester, khiChon: (_) {});

        final state = tester.state<BanDoTheGioiState>(
          find.byType(BanDoTheGioi),
        );
        // Ban đầu George ở màn 3 (manHienTai = 3).
        expect(state.nodeGeorgeHienTai, 3);
        expect(state.viTriGeorge, BoCucWorldMap.viTriMan[3]);
        expect(state.dangDiChuyenGeorge, isFalse);

        // Bấm chọn Màn 1 (đã mở) -> George phải đi dọc đường 3 -> 2 -> 1.
        await tester.tap(find.text('Màn 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(state.dangDiChuyenGeorge, isTrue);
        expect(state.loTrinhGeorge?.cacManDiQua, [3, 2, 1]);
        expect(state.viTriGeorge, isNot(BoCucWorldMap.viTriMan[3]));
        expect(state.viTriGeorge, isNot(BoCucWorldMap.viTriMan[1]));
        expect(
          BoCucWorldMap.diemNamTrenDuongDi(state.viTriGeorge, saiSo: 6),
          isTrue,
          reason: 'George chỉ được di chuyển trên đường mòn, không đi xuyên địa hình',
        );

        await tester.pumpAndSettle();

        expect(state.dangDiChuyenGeorge, isFalse);
        expect(state.nodeGeorgeHienTai, 1);
        expect(state.viTriGeorge, BoCucWorldMap.viTriMan[1]);
      },
    );

    testWidgets('George không di chuyển tới màn đang khóa', (tester) async {
      await moBanDo(tester, khiChon: (_) {});

      final state = tester.state<BanDoTheGioiState>(find.byType(BanDoTheGioi));
      expect(state.nodeGeorgeHienTai, 3);

      // Màn 4, 5, 6 đang khóa trong tienTrinhMau.
      for (final idKhoa in [4, 5, 6]) {
        expect(state.diChuyenGeorgeDen(idKhoa), isFalse);
        await tester.tap(find.text('Màn $idKhoa'));
        await tester.pumpAndSettle();

        expect(state.dangDiChuyenGeorge, isFalse);
        expect(state.nodeGeorgeHienTai, 3);
        expect(state.viTriGeorge, BoCucWorldMap.viTriMan[3]);
      }
    });

    testWidgets(
      'Camera giới hạn trong bản đồ, zoom/pan đúng tọa độ và cảnh vật có animation',
      (tester) async {
        await moBanDo(tester, khiChon: (_) {});

        final state = tester.state<BanDoTheGioiState>(
          find.byType(BanDoTheGioi),
        );
        final painterTruoc = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<HoatAnhWorldMapPainter>()
            .single;
        expect(painterTruoc.viTriGeorge, BoCucWorldMap.viTriMan[3]);

        // Định vị George phóng to và căn vào vị trí George trong giới hạn bản đồ.
        await tester.tap(find.byTooltip('Định vị George'));
        await tester.pumpAndSettle();

        final scaleSauDinhVi = state.boDieuKhienCamera.value
            .getMaxScaleOnAxis();
        expect(scaleSauDinhVi, greaterThan(0.59));

        // Thử kéo vượt quá biên bản đồ -> camera vẫn bị kẹp trong phạm vi hợp lệ.
        const kichThuocKhung = Size(2000, 1164);
        final kqCucDai = BoCucWorldMap.gioiHanDichChuyenCamera(
          tiLe: 2.0,
          dichChuyen: const Offset(-99999, -99999),
          kichThuocKhung: kichThuocKhung,
        );
        final kqCucTieu = BoCucWorldMap.gioiHanDichChuyenCamera(
          tiLe: 2.0,
          dichChuyen: const Offset(99999, 99999),
          kichThuocKhung: kichThuocKhung,
        );
        expect(
          kqCucDai.dx,
          closeTo(kichThuocKhung.width - BoCucWorldMap.kichThuoc.width * 2.0, 0.01),
        );
        expect(
          kqCucDai.dy,
          closeTo(kichThuocKhung.height - BoCucWorldMap.kichThuoc.height * 2.0, 0.01),
        );
        expect(kqCucTieu.dx, closeTo(0.0, 0.01));
        expect(kqCucTieu.dy, closeTo(0.0, 0.01));

        // Đổi màn qua lại không làm mất tiến trình hay làm lệch trạng thái 6 màn.
        await tester.tap(find.byTooltip('Toàn bản đồ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Màn 2'));
        await tester.pumpAndSettle();
        expect(state.nodeGeorgeHienTai, 2);
        expect(tienTrinhMau.cacManHoanThanh, {1, 2});
        expect(tienTrinhMau.cacManDaMo, {1, 2, 3});
      },
    );

    testWidgets(
      'Phân cấp 6 màn chính và 14 địa danh phụ: gọn ở toàn cảnh, hiện chi tiết khi zoom gần',
      (tester) async {
        final bo20Man = ManChoi.docBoManChoi(
          File('assets/tiles/man_choi.json').readAsStringSync(),
          File('assets/tiles/man_mo_rong.json').readAsStringSync(),
        );

        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BanDoTheGioi(
                danhSachMan: bo20Man,
                trangThaiCacMan: {
                  for (final m in bo20Man)
                    m.id: tienTrinhMau.trangThaiCuaMan(m.id),
                },
                manDangChon: 3,
                khiChonMan: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ở góc nhìn toàn cảnh: 6 màn chính hiển thị đầy đủ (gon == false),
        // 14 địa danh phụ thu gọn (gon == true) để không rối nhãn.
        final cacNutToanCanh = tester.widgetList<NutManChoi>(
          find.byType(NutManChoi),
        );
        expect(cacNutToanCanh, hasLength(20));
        for (final nut in cacNutToanCanh) {
          if (nut.man.id <= 6) {
            expect(nut.gon, isFalse);
          } else {
            expect(nut.gon, isTrue);
          }
        }

        // Phóng to vào vùng George (Màn 3) -> các địa danh phụ trong khung nhìn hiện tên đầy đủ.
        await tester.tap(find.byTooltip('Định vị George'));
        await tester.pumpAndSettle();
        final cacNutKhiZoom = tester.widgetList<NutManChoi>(
          find.byType(NutManChoi),
        );
        expect(
          cacNutKhiZoom.where((n) => n.man.id > 6).every((n) => !n.gon),
          isTrue,
        );
      },
    );
  });
}
