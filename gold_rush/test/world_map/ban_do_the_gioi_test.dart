import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/world_map/ban_do_the_gioi.dart';
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
}
