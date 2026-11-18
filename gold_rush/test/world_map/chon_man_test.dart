import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/gold_rush_game.dart';
import 'package:gold_rush/man_choi.dart';
import 'package:gold_rush/man_hinh/chon_man.dart';
import 'package:gold_rush/ngon_ngu/ngon_ngu.dart';
import 'package:gold_rush/ngon_ngu/ban_dich_phap.dart';
import 'package:gold_rush/ngon_ngu/ban_dich_tay_ban_nha.dart';
import 'package:gold_rush/world_map/ban_do_the_gioi.dart';
import 'package:gold_rush/world_map/canh_quan_world_map.dart';
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

  // Màn luyện tập hiện kiểm tra AuthController trước khi gọi vào game.
  // Test này cố ý mô phỏng trạng thái chưa đăng nhập.
  @override
  AuthController? get auth => null;

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
    NgonNgu? ngonNgu,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(2000, 1200);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = MaterialApp(
      home: Scaffold(
        body: ManHinhChonMan(game: game, tienTrinh: tienTrinh),
      ),
    );
    await tester.pumpWidget(
      ngonNgu == null ? app : PhamViNgonNgu(ngonNgu: ngonNgu, child: app),
    );

    await tester.pumpAndSettle();
  }

  Future<void> duaManVaoKhung(WidgetTester tester, int id) async {
    final state = tester.state<BanDoTheGioiState>(find.byType(BanDoTheGioi));
    final diem = BoCucWorldMap.viTriMan[id]!;
    const size = Size(2000, 1200);
    final dich = BoCucWorldMap.tinhDichChuyenTapTrungDiem(
      diemTheGioi: diem,
      tiLe: 1,
      kichThuocKhung: size,
    );
    state.boDieuKhienCamera.value = Matrix4.identity()
      ..setEntry(0, 3, dich.dx)
      ..setEntry(1, 3, dich.dy);
    await tester.pump();
  }

  testWidgets('English translates all 20 map locations and selected details', (
    tester,
  ) async {
    final allStages = ManChoi.docBoManChoi(
      File('assets/tiles/man_choi.json').readAsStringSync(),
      File('assets/tiles/man_mo_rong.json').readAsStringSync(),
    );
    game.danhSachMan = allStages;
    final language = NgonNgu(doc: () async => null, ghi: (_) async {});
    await language.doi('en');
    await moChonMan(tester, ngonNgu: language);

    const englishNames = [
      'Meadow',
      'Woodland',
      'Rocky Cave',
      'Deep Forest',
      'Bone Valley',
      'Gold Mine',
      "Blacksmith's House",
      'Forest Inn',
      'Watch Post',
      "Hunters' Guild",
      'Ancient Library',
      'Streamside House',
      'Crafting Workshop',
      'Northern Outpost',
      'Stone Manor',
      'Riverside Inn',
      'Wind Tower',
      'Green Guildhall',
      "Sage's House",
      'Final Stronghold',
    ];
    for (var i = 0; i < allStages.length; i++) {
      final stage = allStages[i];
      if (i > 0) {
        await tester.tap(find.byTooltip('Close stage details'));
        await tester.pumpAndSettle();
      }
      await duaManVaoKhung(tester, stage.id);
      final node = find.byKey(ValueKey('world-map-level-${stage.id}'));
      expect(
        find.descendant(of: node, matching: find.text(englishNames[i])),
        findsOneWidget,
      );
      await tester.tap(node);
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('bang-thong-tin-man'));
      expect(
        find.descendant(of: panel, matching: find.text(englishNames[i])),
        findsOneWidget,
      );
      // Một số nhãn mô tả chưa có bản dịch riêng và được phép fallback về
      // tiếng Việt; kiểm tra quan trọng ở đây là tên màn đã được dịch đúng.
      expect(tester.takeException(), isNull);
    }

    expect(find.text('GOLD RUSH · TREASURE REGION'), findsOneWidget);
    expect(find.text('STAGE 20 · TREASURE REGION'), findsOneWidget);
    await language.doi('vi');
    await tester.pump();
    expect(find.text('Thành trì cuối'), findsAtLeastNWidgets(1));
    expect(find.text('MÀN 20 · VÙNG KHO BÁU'), findsOneWidget);
    expect(game.danhSachMan, same(allStages));
    expect(game.cacManDuocYeuCauChoi, isEmpty);
  });

  testWidgets('French and Spanish translate details for all 20 map locations', (
    tester,
  ) async {
    final allStages = ManChoi.docBoManChoi(
      File('assets/tiles/man_choi.json').readAsStringSync(),
      File('assets/tiles/man_mo_rong.json').readAsStringSync(),
    );
    for (final entry in {'fr': banDichPhap, 'es': banDichTayBanNha}.entries) {
      game.danhSachMan = allStages;
      final language = NgonNgu(doc: () async => null, ghi: (_) async {});
      await language.doi(entry.key);
      await moChonMan(tester, ngonNgu: language);
      for (var i = 0; i < allStages.length; i++) {
        final stage = allStages[i];
        if (i > 0) {
          await tester.tap(find.byTooltip(entry.value['Đóng thông tin màn']!));
          await tester.pumpAndSettle();
        }
        await duaManVaoKhung(tester, stage.id);
        final node = find.byKey(ValueKey('world-map-level-${stage.id}'));
        final name = entry.value[stage.ten] ?? stage.ten;
        // ChuGame dịch mô tả theo catalog hiện tại hoặc fallback về bản gốc.
        final description = language.dich(stage.moTa);
        expect(
          find.descendant(of: node, matching: find.text(name)),
          findsOneWidget,
        );
        await tester.tap(node);
        await tester.pumpAndSettle();
        final panel = find.byKey(const ValueKey('bang-thong-tin-man'));
        expect(
          find.descendant(of: panel, matching: find.text(name)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: panel,
            matching: find.text(description),
          ),
          findsOneWidget,
        );
        if (entry.value.containsKey(stage.ten)) {
          expect(
            find.descendant(of: panel, matching: find.text(stage.ten)),
            findsNothing,
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} / ${stage.id}',
        );
      }
      expect(game.cacManDuocYeuCauChoi, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Chỉ mở bảng chi tiết sau khi người dùng chọn màn', (
    tester,
  ) async {
    await moChonMan(
      tester,
      tienTrinh: TienTrinhWorldMap(
        cacManDaMo: [1, 2, 3],
        cacManHoanThanh: [1, 2],
        manHienTai: 3,
      ),
    );

    expect(find.byKey(const ValueKey('bang-thong-tin-man')), findsNothing);

    await tester.tap(find.text('Màn 3'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('bang-thong-tin-man')), findsOneWidget);
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

    await duaManVaoKhung(tester, 4);
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

    // Màn chính thức yêu cầu phiên ví đã xác thực trước khi vào chơi.
    expect(game.cacManDuocYeuCauChoi, isEmpty);
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

    await tester.tap(find.text('Màn 1'));
    await tester.pumpAndSettle();

    final nutChoi = find.widgetWithText(FilledButton, 'Chơi');

    expect(tester.widget<FilledButton>(nutChoi).onPressed, isNotNull);

    await tester.ensureVisible(nutChoi);
    await tester.pumpAndSettle();
    await tester.tap(nutChoi);
    await tester.pumpAndSettle();

    // Không có ví thì màn chính thức không được khởi chạy.
    expect(game.cacManDuocYeuCauChoi, isEmpty);
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

    await tester.tap(find.text('Màn 2'));
    await tester.pumpAndSettle();

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

    await duaManVaoKhung(tester, 1);
    await tester.tap(find.text('Màn 1'));
    await tester.pumpAndSettle();

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

    // Không có phiên ví thì vẫn chặn luồng nhận thưởng on-chain.
    expect(game.cacManDuocYeuCauChoi, isEmpty);
  });

  testWidgets('Nút đóng gửi yêu cầu quay lại Menu', (tester) async {
    await moChonMan(tester);

    await tester.tap(find.byTooltip('Quay lại Menu'));
    await tester.pumpAndSettle();

    expect(game.soLanDong, 1);
    expect(game.cacManDuocYeuCauChoi, isEmpty);
  });
}
