import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_de_xuat_do_kho.dart';
import 'package:gold_rush/man_hinh/de_xuat_do_kho.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ai/de_xuat_do_kho_test.dart' show deXuatMau;

http.Response _phanHoi([Map<String, dynamic>? data]) =>
    http.Response.bytes(utf8.encode(jsonEncode(data ?? deXuatMau())), 200);

Future<void> _nap(WidgetTester tester, MayChuDeXuatDoKho api, {int man = 1}) =>
    tester.pumpWidget(
      MaterialApp(
        home: ManHinhDeXuatDoKho(mayChu: api, manChoi: man),
      ),
    );

Future<void> _bamXem(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Xem đề xuất'));
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chỉ gọi API khi bấm xem và hiển thị fallback demo', (
    tester,
  ) async {
    var soLan = 0;
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient((_) async {
        soLan++;
        return _phanHoi();
      }),
    );
    await _nap(tester, api);
    expect(soLan, 0);
    expect(find.text('Đề xuất độ khó màn 1'), findsOneWidget);
    await _bamXem(tester);
    expect(soLan, 1);
    expect(find.text('Dữ liệu demo'), findsOneWidget);
    expect(find.text('Độ khó đề xuất • Trung bình'), findsOneWidget);
    expect(find.text('Điểm hiệu suất • Chưa đủ dữ liệu'), findsOneWidget);
    expect(find.text('Hệ số tốc độ đề xuất • ×1.00'), findsOneWidget);
    expect(find.text('Ván được đánh giá • 0'), findsOneWidget);
    expect(find.text('Nguồn đề xuất • Dự phòng'), findsOneWidget);
    expect(
      find.text('Chưa đủ lịch sử, đề xuất mức trung tính.'),
      findsOneWidget,
    );
  });

  for (final cap in [
    ('easy', 0.075, 0.95, 'Dễ', '7.5'),
    ('medium', 0.575, 1.03, 'Trung bình', '57.5'),
    ('hard', 1.0, 1.05, 'Khó', '100.0'),
  ]) {
    testWidgets('hiển thị mức ${cap.$1} từ lịch sử đã xác minh', (
      tester,
    ) async {
      final api = MayChuDeXuatDoKho(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => _phanHoi(
            deXuatMau()
              ..['difficulty'] = cap.$1
              ..['performance_score'] = cap.$2
              ..['adjustments'] = {'enemy_speed_multiplier': cap.$3}
              ..['sample_count'] = 4
              ..['source'] = 'rule_based'
              ..['context_source'] = 'verified',
          ),
        ),
      );
      await _nap(tester, api);
      await _bamXem(tester);
      expect(find.text('Lịch sử đã xác minh'), findsOneWidget);
      expect(find.text('Độ khó đề xuất • ${cap.$4}'), findsOneWidget);
      expect(find.text('Điểm hiệu suất • ${cap.$5} / 100'), findsOneWidget);
      expect(find.text('Ván được đánh giá • 4'), findsOneWidget);
      expect(find.text('Nguồn đề xuất • Theo luật'), findsOneWidget);
      expect(find.text('Dữ liệu demo'), findsNothing);
    });
  }

  testWidgets('cập nhật đề xuất khi người chơi bấm lại', (tester) async {
    var soLan = 0;
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => _phanHoi(
          deXuatMau()..['reason'] = (++soLan == 1 ? 'Lý do đầu' : 'Lý do mới'),
        ),
      ),
    );
    await _nap(tester, api);
    await _bamXem(tester);
    expect(find.text('Lý do đầu'), findsOneWidget);
    await tester.tap(find.text('Cập nhật đề xuất'));
    await tester.pumpAndSettle();
    expect(soLan, 2);
    expect(find.text('Lý do mới'), findsOneWidget);
    expect(find.text('Lý do đầu'), findsNothing);
  });

  testWidgets('đang chờ khóa nút để bấm hai lần chỉ gửi một request', (
    tester,
  ) async {
    var soLan = 0;
    final cho = Completer<http.Response>();
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient((_) {
        soLan++;
        return cho.future;
      }),
    );
    await _nap(tester, api);
    await tester.tap(find.text('Xem đề xuất'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(FilledButton));
    expect(soLan, 1);
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('503 cho thử lại và thành công sau khi kết nối phục hồi', (
    tester,
  ) async {
    var soLan = 0;
    await _nap(
      tester,
      MayChuDeXuatDoKho(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => ++soLan == 1 ? http.Response('', 503) : _phanHoi(),
        ),
      ),
    );
    await _bamXem(tester);
    expect(find.text('Thử lại'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(soLan, 2);
    expect(find.text('Dữ liệu demo'), findsOneWidget);
  });

  testWidgets('offline có thông báo để người chơi hiểu', (tester) async {
    await _nap(tester, MayChuDeXuatDoKho(mayChu: ''));
    await _bamXem(tester);
    expect(find.text('Chưa cấu hình máy chủ AI.'), findsOneWidget);
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('403 hiện lỗi quyền và giữ kín nội dung lỗi máy chủ', (
    tester,
  ) async {
    await _nap(
      tester,
      MayChuDeXuatDoKho(
        mayChu: 'http://localhost',
        client: MockClient((_) async => http.Response('private detail', 403)),
      ),
    );
    await _bamXem(tester);
    expect(
      find.text('Bạn chưa có quyền xem đề xuất cho màn này.'),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsNothing);
    expect(find.textContaining('private detail'), findsNothing);
  });

  testWidgets('phản hồi sai cấu trúc hiển thị lỗi thay vì kết quả cũ', (
    tester,
  ) async {
    var soLan = 0;
    await _nap(
      tester,
      MayChuDeXuatDoKho(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => ++soLan == 1 ? _phanHoi() : http.Response('{}', 200),
        ),
      ),
    );
    await _bamXem(tester);
    await tester.tap(find.text('Cập nhật đề xuất'));
    await tester.pumpAndSettle();
    expect(
      find.text('Chưa đọc được đề xuất. Hãy thử lại sau.'),
      findsOneWidget,
    );
    expect(find.text('Hệ số tốc độ đề xuất • ×1.00'), findsNothing);
  });

  testWidgets('đóng route trong lúc tải không cập nhật widget đã dispose', (
    tester,
  ) async {
    final cho = Completer<http.Response>();
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient((_) => cho.future),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ManHinhDeXuatDoKho(mayChu: api, manChoi: 1),
                ),
              ),
              child: const Text('Mở đề xuất'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở đề xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem đề xuất'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(find.text('Mở đề xuất'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('đổi màn bỏ qua phản hồi đến muộn của màn trước', (tester) async {
    final cho = Completer<http.Response>();
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient(
        (request) => jsonDecode(request.body)['stage_id'] == 1
            ? cho.future
            : Future.value(
                _phanHoi(
                  deXuatMau()
                    ..['stage_id'] = 2
                    ..['reason'] = 'Lý do màn mới',
                ),
              ),
      ),
    );
    await _nap(tester, api);
    await tester.tap(find.text('Xem đề xuất'));
    await tester.pump();
    await _nap(tester, api, man: 2);
    await _bamXem(tester);
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(find.text('Đề xuất độ khó màn 2'), findsOneWidget);
    expect(find.text('Lý do màn mới'), findsOneWidget);
    expect(find.text('Chưa đủ lịch sử, đề xuất mức trung tính.'), findsNothing);
  });

  testWidgets('đổi client bỏ qua kết quả của phiên người chơi trước', (
    tester,
  ) async {
    final cho = Completer<http.Response>();
    final apiCu = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient((_) => cho.future),
    );
    final apiMoi = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => _phanHoi(deXuatMau()..['reason'] = 'Phiên mới'),
      ),
    );
    await _nap(tester, apiCu);
    await tester.tap(find.text('Xem đề xuất'));
    await tester.pump();
    await _nap(tester, apiMoi);
    await _bamXem(tester);
    cho.complete(_phanHoi());
    await tester.pumpAndSettle();
    expect(find.text('Phiên mới'), findsOneWidget);
    expect(find.text('Chưa đủ lịch sử, đề xuất mức trung tính.'), findsNothing);
  });

  testWidgets('chữ lớn và màn nhỏ vẫn cuộn tới nút cập nhật được', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => _phanHoi(
          deXuatMau()..['reason'] = List.filled(40, 'Đề xuất dễ').join(' '),
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
        home: ManHinhDeXuatDoKho(mayChu: api, manChoi: 1),
      ),
    );
    await tester.ensureVisible(find.text('Xem đề xuất'));
    await _bamXem(tester);
    await tester.ensureVisible(find.text('Cập nhật đề xuất'));
    expect(tester.takeException(), isNull);
  });
}
