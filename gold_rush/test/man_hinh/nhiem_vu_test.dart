import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhiem_vu.dart';
import 'package:gold_rush/man_hinh/nhiem_vu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ai/nhiem_vu_test.dart' show phanHoiMau;

http.Response _phanHoi([Map<String, dynamic>? json]) =>
    http.Response.bytes(utf8.encode(jsonEncode(json ?? phanHoiMau())), 200);

Future<void> _nap(WidgetTester tester, MayChuNhiemVu api, {int man = 1}) =>
    tester.pumpWidget(
      MaterialApp(
        home: ManHinhNhiemVu(mayChu: api, manChoi: man),
      ),
    );

Future<void> _bamTao(WidgetTester tester) async {
  // Hủy stream của HTTP có thể hoàn tất ở zone thực của Dart SDK.
  await tester.runAsync(() async {
    await tester.tap(find.text('Tạo nhiệm vụ'));
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chỉ gửi yêu cầu khi người chơi bấm tạo', (tester) async {
    var soLan = 0;
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient((_) async {
        soLan++;
        return _phanHoi();
      }),
    );
    await _nap(tester, api);
    expect(soLan, 0);
    expect(find.text('Nhiệm vụ màn 1'), findsOneWidget);
    await _bamTao(tester);
    expect(soLan, 1);
    expect(find.text('Tìm kho báu'), findsOneWidget);
    expect(find.text('Nhặt 6 xu trong màn đầu.'), findsOneWidget);
    expect(find.text('Thu thập 6 xu'), findsOneWidget);
    expect(find.text('Độ khó • Dễ'), findsOneWidget);
    expect(find.text('Thưởng • 0 vàng'), findsOneWidget);
    expect(find.text('Ngữ cảnh demo'), findsOneWidget);
    expect(find.text('Nguồn sinh • Theo luật'), findsOneWidget);
  });

  for (final cap in [('llm', 'LLM'), ('demo', 'Mẫu demo')]) {
    testWidgets('hiện đúng nguồn ${cap.$1} và ngữ cảnh verified', (
      tester,
    ) async {
      final api = MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => _phanHoi(
            phanHoiMau()
              ..['generation_source'] = cap.$1
              ..['context_source'] = 'verified',
          ),
        ),
      );
      await _nap(tester, api);
      await _bamTao(tester);
      expect(find.text('Nguồn sinh • ${cap.$2}'), findsOneWidget);
      expect(find.text('Ngữ cảnh đã xác minh'), findsOneWidget);
      expect(find.text('Ngữ cảnh demo'), findsNothing);
    });
  }

  testWidgets(
    'mục tiêu thời gian và giới hạn trúng đòn đọc được bằng tiếng Việt',
    (tester) async {
      var soLan = 0;
      final api = MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => _phanHoi(
            phanHoiMau()
              ..['objective'] = (++soLan == 1
                  ? 'finish_before_time'
                  : 'finish_with_max_hits')
              ..['target'] = 1
              ..['time_limit_seconds'] = 60,
          ),
        ),
      );
      await _nap(tester, api);
      await _bamTao(tester);
      expect(find.text('Hoàn thành màn trước thời hạn'), findsOneWidget);
      expect(find.text('Thời hạn • 60 giây'), findsOneWidget);
      await tester.tap(find.text('Tạo nhiệm vụ mới'));
      await tester.pumpAndSettle();
      expect(
        find.text('Hoàn thành màn, trúng đòn tối đa 1 lần'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'retry lỗi 503 giữ nguyên khóa, tạo mới sau thành công đổi khóa',
    (tester) async {
      final cacKhoa = <String?>[];
      final api = MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient((request) async {
          cacKhoa.add(request.headers['Idempotency-Key']);
          return cacKhoa.length == 1 ? http.Response('', 503) : _phanHoi();
        }),
      );
      await _nap(tester, api);
      await _bamTao(tester);
      expect(find.text('Thử lại'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Tìm kho báu'), findsOneWidget);
      expect(cacKhoa[1], cacKhoa[0]);
      expect(cacKhoa[0], matches(RegExp(r'^[A-Za-z0-9_-]{1,64}$')));
      await tester.tap(find.text('Tạo nhiệm vụ mới'));
      await tester.pumpAndSettle();
      expect(cacKhoa[2], isNot(cacKhoa[0]));
    },
  );

  testWidgets('đang chờ thì khóa nút, bấm hai lần chỉ gửi một yêu cầu', (
    tester,
  ) async {
    var soLan = 0;
    final cho = Completer<http.Response>();
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient((_) {
        soLan++;
        return cho.future;
      }),
    );
    await _nap(tester, api);
    await tester.tap(find.text('Tạo nhiệm vụ'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final nut = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(nut.onPressed, isNull);
    await tester.tap(find.byType(FilledButton));
    expect(soLan, 1);
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Tìm kho báu'), findsOneWidget);
  });

  testWidgets('chưa cấu hình máy chủ hiện trạng thái offline', (tester) async {
    await _nap(tester, MayChuNhiemVu(mayChu: ''));
    await _bamTao(tester);
    expect(find.textContaining('GOLD_RUSH_API'), findsOneWidget);
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('403 hiện lý do phù hợp và không mời retry lỗi quyền', (
    tester,
  ) async {
    await _nap(
      tester,
      MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient((_) async => http.Response('private detail', 403)),
      ),
    );
    await _bamTao(tester);
    expect(
      find.text('Màn này chưa được ngữ cảnh người chơi cho phép.'),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsNothing);
    expect(find.textContaining('private detail'), findsNothing);
  });

  testWidgets('lỗi mạng có thể thử lại bằng cùng mã', (tester) async {
    final cacKhoa = <String?>[];
    await _nap(
      tester,
      MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient((request) async {
          cacKhoa.add(request.headers['Idempotency-Key']);
          if (cacKhoa.length == 1) throw http.ClientException('private');
          return _phanHoi();
        }),
      ),
    );
    await _bamTao(tester);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(cacKhoa, [cacKhoa.first, cacKhoa.first]);
    expect(find.text('Tìm kho báu'), findsOneWidget);
  });

  testWidgets('đóng màn hình lúc đang tải không gọi setState sau dispose', (
    tester,
  ) async {
    final cho = Completer<http.Response>();
    await _nap(
      tester,
      MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient((_) => cho.future),
      ),
    );
    await tester.tap(find.text('Tạo nhiệm vụ'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('đổi màn bỏ qua phản hồi đang chờ của màn cũ', (tester) async {
    final cho = Completer<http.Response>();
    final cacKhoa = <String?>[];
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient((request) {
        cacKhoa.add(request.headers['Idempotency-Key']);
        if (jsonDecode(request.body)['stage_id'] == 1) return cho.future;
        return Future.value(
          _phanHoi(
            phanHoiMau()
              ..['stage_id'] = 2
              ..['title'] = 'Nhiệm vụ màn mới',
          ),
        );
      }),
    );
    await _nap(tester, api);
    await tester.tap(find.text('Tạo nhiệm vụ'));
    await tester.pump();
    await _nap(tester, api, man: 2);
    await _bamTao(tester);
    expect(find.text('Nhiệm vụ màn mới'), findsOneWidget);
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(find.text('Nhiệm vụ màn mới'), findsOneWidget);
    expect(find.text('Tìm kho báu'), findsNothing);
    expect(cacKhoa[0], isNot(cacKhoa[1]));
  });

  testWidgets('đổi client bỏ qua phản hồi của danh tính trước', (tester) async {
    final cho = Completer<http.Response>();
    final cu = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient((_) => cho.future),
    );
    final moi = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => _phanHoi(phanHoiMau()..['title'] = 'Phiên mới'),
      ),
    );
    await _nap(tester, cu);
    await tester.tap(find.text('Tạo nhiệm vụ'));
    await tester.pump();
    await _nap(tester, moi);
    await _bamTao(tester);
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(find.text('Phiên mới'), findsOneWidget);
    expect(find.text('Tìm kho báu'), findsNothing);
  });

  testWidgets('màn nhỏ và chữ lớn vẫn cuộn đến nút được', (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => _phanHoi(
          phanHoiMau()
            ..['description'] = List.filled(40, 'Thu thập xu').join(' '),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ManHinhNhiemVu(mayChu: api, manChoi: 1),
      ),
    );
    await tester.ensureVisible(find.text('Tạo nhiệm vụ'));
    await _bamTao(tester);
    await tester.ensureVisible(find.text('Tạo nhiệm vụ mới'));
    expect(tester.takeException(), isNull);
  });
}
