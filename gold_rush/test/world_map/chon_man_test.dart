import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/man_hinh/chon_man.dart';
import 'package:gold_rush/world_map/tien_trinh_world_map.dart';

/// Đối tượng chỉ dùng cho test giao diện.
///
/// Không nạp Flame, bản đồ gameplay, âm thanh hoặc kết nối ví.
/// Các hành động ngoài phạm vi test sẽ báo lỗi ngay.
class _GameKiemThu implements GoldRushGame {
  @override
  List<ManChoi> danhSachMan;

  @override
  PhienVi? get phienVi => null;

  final List<ManChoi> cacManDuocYeuCauChoi = [];
  int soLanDong = 0;

  _GameKiemThu(this.danhSachMan);

  @override
  Future<bool> choiMan(
    ManChoi m, {
    String? maVan,
    int ve = 0,
    DateTime? batDauThat,
  }) async {
    cacManDuocYeuCauChoi.add(m);
    return true;
  }

  @override
  void dongChonMan() {
    soLanDong++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Test chưa hỗ trợ thao tác: ${invocation.memberName}',
    );
  }
}

void main() {
  final danhSachMan = ManChoi.docDanhSach(
    File('assets/tiles/man_choi.json').readAsStringSync(),
  );

  late _GameKiemThu game;

  setUp(() {
    game = _GameKiemThu(List<ManChoi>.of(danhSachMan));
  });

  Future<void> moChonMan(
    WidgetTester tester, {
    TienTrinhWorldMap? tienTrinh,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(2000, 1200);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManHinhChonMan(game: game, tienTrinh: tienTrinh),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('Ưu tiên màn hiện tại từ tiến trình khi mới mở', (tester) async {
    await moChonMan(
      tester,
      tienTrinh: TienTrinhWorldMap(
        cacManDaMo: [1, 2, 3],
        cacManHoanThanh: [1, 2],
        manHienTai: 3,
      ),
    );

    expect(find.text('Trạng thái: Đã mở'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Cọc ${danhSachMan[2].coc}'),
      findsOneWidget,
    );
    expect(game.cacManDuocYeuCauChoi, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chọn ô khóa xem được thông tin nhưng nút chơi bị khóa', (
    tester,
  ) async {
    await moChonMan(
      tester,
      tienTrinh: TienTrinhWorldMap(
        cacManDaMo: [1],
        cacManHoanThanh: [],
        manHienTai: 1,
      ),
    );

    await tester.tap(find.text('Màn 4'));
    await tester.pumpAndSettle();

    expect(find.text('Trạng thái: Chưa mở'), findsOneWidget);

    final nutKhoa = find.widgetWithText(FilledButton, 'Màn chưa mở');

    expect(nutKhoa, findsOneWidget);
    expect(tester.widget<FilledButton>(nutKhoa).onPressed, isNull);

    // Bấm ô chỉ xem thông tin, không gọi vào game.
    expect(game.cacManDuocYeuCauChoi, isEmpty);

    await tester.ensureVisible(nutKhoa);
    await tester.pumpAndSettle();
    await tester.tap(nutKhoa);
    await tester.pumpAndSettle();

    expect(game.cacManDuocYeuCauChoi, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Màn hoàn thành hiển thị đúng và có thể chọn chơi lại', (
    tester,
  ) async {
    await moChonMan(
      tester,
      tienTrinh: TienTrinhWorldMap(
        cacManDaMo: [1, 2],
        cacManHoanThanh: [1],
        manHienTai: 2,
      ),
    );

    await tester.tap(find.text('Màn 1'));
    await tester.pumpAndSettle();

    expect(find.text('Trạng thái: Đã hoàn thành'), findsOneWidget);

    final nutChoi = find.widgetWithText(FilledButton, 'Chơi');

    expect(tester.widget<FilledButton>(nutChoi).onPressed, isNotNull);

    // Chọn ô chưa tự vào màn.
    expect(game.cacManDuocYeuCauChoi, isEmpty);

    await tester.ensureVisible(nutChoi);
    await tester.pumpAndSettle();
    await tester.tap(nutChoi);
    await tester.pumpAndSettle();

    expect(game.cacManDuocYeuCauChoi, hasLength(1));
    expect(game.cacManDuocYeuCauChoi.single.id, 1);
  });

  testWidgets('Màn luyện tập đã mở gửi đúng yêu cầu chơi khi chưa có ví', (
    tester,
  ) async {
    await moChonMan(
      tester,
      tienTrinh: TienTrinhWorldMap(
        cacManDaMo: [1],
        cacManHoanThanh: [],
        manHienTai: 1,
      ),
    );

    final nutChoi = find.widgetWithText(FilledButton, 'Chơi');

    expect(tester.widget<FilledButton>(nutChoi).onPressed, isNotNull);

    await tester.ensureVisible(nutChoi);
    await tester.pumpAndSettle();
    await tester.tap(nutChoi);
    await tester.pumpAndSettle();

    expect(game.cacManDuocYeuCauChoi, hasLength(1));
    expect(game.cacManDuocYeuCauChoi.single, same(danhSachMan.first));
  });

  testWidgets('Màn có cọc đã mở vẫn không vào được khi chưa có phiên ví', (
    tester,
  ) async {
    await moChonMan(
      tester,
      tienTrinh: TienTrinhWorldMap(
        cacManDaMo: [1, 2],
        cacManHoanThanh: [1],
        manHienTai: 2,
      ),
    );

    final man2 = danhSachMan.singleWhere((man) => man.id == 2);
    final nutCoc = find.widgetWithText(FilledButton, 'Cọc ${man2.coc}');

    expect(find.text('Trạng thái: Đã mở'), findsOneWidget);
    expect(tester.widget<FilledButton>(nutCoc).onPressed, isNull);
    expect(game.cacManDuocYeuCauChoi, isEmpty);
  });

  testWidgets('Chưa có tiến trình vẫn giữ luồng luyện tập bản gốc', (
    tester,
  ) async {
    await moChonMan(tester);

    expect(
      find.text(
        'Tiến trình mở khóa chưa được kết nối. '
        'Hiện giữ quyền chọn màn như phiên bản gốc.',
      ),
      findsOneWidget,
    );

    final nutChoi = find.widgetWithText(FilledButton, 'Chơi');

    expect(tester.widget<FilledButton>(nutChoi).onPressed, isNotNull);

    await tester.ensureVisible(nutChoi);
    await tester.pumpAndSettle();
    await tester.tap(nutChoi);
    await tester.pumpAndSettle();

    expect(game.cacManDuocYeuCauChoi, hasLength(1));
    expect(game.cacManDuocYeuCauChoi.single.id, 1);
  });

  testWidgets('Nút đóng gửi yêu cầu quay lại Menu', (tester) async {
    await moChonMan(tester);

    await tester.tap(find.byTooltip('Quay lại Menu'));
    await tester.pumpAndSettle();

    expect(game.soLanDong, 1);
    expect(game.cacManDuocYeuCauChoi, isEmpty);
  });
}
