import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/blockchain/nhan_vat.dart';
import 'package:gold_rush/blockchain/phien_vi.dart';
import 'package:gold_rush/kho_do/danh_sach_nhan_vat.dart';

/// Phiên ví giả chỉ phục vụ test giao diện.
/// Không gọi API hoặc Blockchain.
class _PhienViKiemThu extends ChangeNotifier implements PhienVi {
  bool _ketNoi = true;

  @override
  bool get daKetNoi => _ketNoi;

  @override
  String? diaChi = 'vi-kiem-thu';

  @override
  final Set<int> daCo = {};

  @override
  bool dangXuLy = false;

  @override
  bool dangHoi = false;

  @override
  String? thongBao;

  @override
  bool thongBaoLaLoi = false;

  void datNhanVatSoHuu(Set<int> cacId) {
    daCo
      ..clear()
      ..addAll(cacId);

    notifyListeners();
  }

  void ngatKetNoiKiemThu() {
    _ketNoi = false;
    diaChi = null;
    daCo.clear();
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Test chưa hỗ trợ: ${invocation.memberName}');
  }
}

void main() {
  Future<void> moDanhSach(
    WidgetTester tester, {
    PhienVi? phienVi,
    String tepDangDung = '',
    Future<void> Function(String)? khiChon,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DanhSachNhanVat(
              phienVi: phienVi,
              tepNhanVatDangDung: tepDangDung,
              khiChonNhanVat: khiChon,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('Chưa có ví vẫn hiện George, không hiện nhân vật cửa hàng', (
    tester,
  ) async {
    await moDanhSach(tester, tepDangDung: georgeGoc.tepAnh);

    expect(find.text(georgeGoc.ten), findsOneWidget);
    expect(find.text('Đang dùng'), findsOneWidget);

    for (final nv in bangNhanVat) {
      expect(find.text(nv.ten), findsNothing);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('Chỉ hiển thị nhân vật được phiên ví xác nhận sở hữu', (
    tester,
  ) async {
    final pv = _PhienViKiemThu();
    addTearDown(pv.dispose);

    pv.datNhanVatSoHuu({1});

    await moDanhSach(tester, phienVi: pv, tepDangDung: georgeGoc.tepAnh);

    expect(find.text('George'), findsOneWidget);
    expect(find.text('Thợ mỏ'), findsOneWidget);
    expect(find.text('Cao bồi'), findsNothing);
    expect(find.text('Hiệp sĩ vàng'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Thay đổi quyền sở hữu cập nhật lại danh sách', (tester) async {
    final pv = _PhienViKiemThu();
    addTearDown(pv.dispose);

    pv.datNhanVatSoHuu({1});

    await moDanhSach(tester, phienVi: pv, tepDangDung: georgeGoc.tepAnh);

    expect(find.text('Thợ mỏ'), findsOneWidget);
    expect(find.text('Cao bồi'), findsNothing);

    pv.datNhanVatSoHuu({2});
    await tester.pumpAndSettle();

    expect(find.text('Thợ mỏ'), findsNothing);
    expect(find.text('Cao bồi'), findsOneWidget);
    expect(find.text('George'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('Ngắt ví ẩn nhân vật cửa hàng nhưng vẫn giữ George', (
    tester,
  ) async {
    final pv = _PhienViKiemThu();
    addTearDown(pv.dispose);

    pv.datNhanVatSoHuu({1, 2, 3});

    await moDanhSach(tester, phienVi: pv, tepDangDung: georgeGoc.tepAnh);

    for (final nv in bangNhanVat) {
      expect(find.text(nv.ten), findsOneWidget);
    }

    pv.ngatKetNoiKiemThu();
    await tester.pumpAndSettle();

    expect(find.text('George'), findsOneWidget);

    for (final nv in bangNhanVat) {
      expect(find.text(nv.ten), findsNothing);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('Chọn nhân vật gửi đúng ID, không tự đổi nhãn đang dùng', (
    tester,
  ) async {
    final cacIdDaGui = <String>[];

    await moDanhSach(
      tester,
      khiChon: (id) async {
        cacIdDaGui.add(id);
      },
    );

    final nutChon = find.widgetWithText(OutlinedButton, 'Chọn nhân vật');

    await tester.ensureVisible(nutChon);
    await tester.pumpAndSettle();
    await tester.tap(nutChon);
    await tester.pumpAndSettle();

    expect(cacIdDaGui, ['0']);

    // Bên ngoài chưa cập nhật tepNhanVatDangDung.
    // Widget không được tự coi lựa chọn là đang dùng.
    expect(find.text('Đang dùng'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Callback thất bại hiện lỗi và cho phép chọn lại', (
    tester,
  ) async {
    await moDanhSach(
      tester,
      khiChon: (_) async {
        throw StateError('Lỗi mô phỏng');
      },
    );

    final nutChon = find.widgetWithText(OutlinedButton, 'Chọn nhân vật');

    await tester.ensureVisible(nutChon);
    await tester.pumpAndSettle();
    await tester.tap(nutChon);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Không chọn được nhân vật. '
        'Vui lòng kiểm tra dữ liệu và thử lại.',
      ),
      findsOneWidget,
    );

    expect(find.text('Đang dùng'), findsNothing);
    expect(tester.widget<OutlinedButton>(nutChon).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
