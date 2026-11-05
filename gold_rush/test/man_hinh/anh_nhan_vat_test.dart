import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/man_hinh/anh_nhan_vat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ai/anh_nhan_vat_test.dart' show metadataAnhMau;
import '../ai/may_chu_nhan_vat_test.dart' show pngMau;

http.Response _metadata({bool moHinh = false}) => http.Response(
  jsonEncode(
    metadataAnhMau()
      ..['generation_source'] = moHinh ? 'image_model' : 'demo'
      ..['context_source'] = moHinh ? 'verified' : 'demo',
  ),
  200,
  headers: {'content-type': 'application/json'},
);

Future<void> _nap(WidgetTester tester, MayChuNhanVat api) =>
    tester.pumpWidget(MaterialApp(home: ManHinhAnhNhanVat(mayChu: api)));

Future<void> _bam(WidgetTester tester, String nhan) async {
  await tester.ensureVisible(find.text(nhan));
  await tester.runAsync(() async {
    await tester.tap(find.text(nhan));
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pumpAndSettle();
  final images = find.byType(Image);
  if (images.evaluate().isNotEmpty) {
    // Image.memory giải mã frame ngoài đồng hồ giả lập của widget test.
    await tester.runAsync(
      () => precacheImage(
        tester.widget<Image>(images.first).image,
        tester.element(images.first),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('chỉ tạo khi bấm nút, hiển thị PNG và nhãn demo', (tester) async {
    final png = await tester.runAsync(pngMau);
    final requests = <http.Request>[];
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      maNguoiChoiDemo: 'demo_ui',
      client: MockClient((r) async {
        requests.add(r);
        return r.method == 'POST'
            ? _metadata()
            : http.Response.bytes(
                png!,
                200,
                headers: {'content-type': 'image/png'},
              );
      }),
    );
    await _nap(tester, api);
    expect(requests, isEmpty);
    await tester.enterText(find.byType(TextFormField), '  Thợ mỏ mũ vàng  ');
    await _bam(tester, 'Tạo ảnh');
    expect(requests.map((r) => r.method), ['POST', 'GET']);
    expect(jsonDecode(requests.first.body), {'description': 'Thợ mỏ mũ vàng'});
    expect(
      requests.every((r) => r.headers['X-Demo-Player'] == 'demo_ui'),
      isTrue,
    );
    expect(find.text('Ảnh mẫu demo'), findsOneWidget);
    expect(find.text('Phiên demo'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(image.filterQuality, FilterQuality.none);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(find.text('Tạo ảnh mới'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mô tả rỗng hoặc quá dài không gửi mạng', (tester) async {
    var soLan = 0;
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((_) async {
          soLan++;
          return _metadata();
        }),
      ),
    );
    await _bam(tester, 'Tạo ảnh');
    expect(find.text('Hãy nhập mô tả nhân vật.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      List.filled(501, 'a').join(),
    );
    await _bam(tester, 'Tạo ảnh');
    expect(find.text('Mô tả tối đa 500 ký tự.'), findsOneWidget);
    expect(soLan, 0);
  });

  testWidgets('retry POST giữ key và mô tả, tạo mới đổi key', (tester) async {
    final png = await tester.runAsync(pngMau);
    final post = <http.Request>[];
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            post.add(r);
            return post.length == 1
                ? http.Response('', 503)
                : _metadata(moHinh: true);
          }
          return http.Response.bytes(
            png!,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Hiệp sĩ');
    await _bam(tester, 'Tạo ảnh');
    await _bam(tester, 'Thử lại');
    expect(
      post[1].headers['Idempotency-Key'],
      post[0].headers['Idempotency-Key'],
    );
    expect(post[1].body, post[0].body);
    expect(find.text('Ảnh từ mô hình AI'), findsOneWidget);
    expect(find.text('Phiên đã xác minh'), findsOneWidget);
    await _bam(tester, 'Tạo ảnh mới');
    expect(
      post[2].headers['Idempotency-Key'],
      isNot(post[0].headers['Idempotency-Key']),
    );
  });

  testWidgets('retry tải PNG không gửi lại POST tạo ảnh', (tester) async {
    final png = await tester.runAsync(pngMau);
    final methods = <String>[];
    var get = 0;
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          methods.add(r.method);
          if (r.method == 'POST') return _metadata();
          return ++get == 1
              ? http.Response('', 503)
              : http.Response.bytes(
                  png!,
                  200,
                  headers: {'content-type': 'image/png'},
                );
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Cao bồi');
    await _bam(tester, 'Tạo ảnh');
    expect(find.byType(Image), findsNothing);
    await _bam(tester, 'Tải lại ảnh');
    expect(methods, ['POST', 'GET', 'GET']);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('đổi mô tả sau lỗi tạo dùng key mới', (tester) async {
    final post = <http.Request>[];
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          post.add(r);
          return http.Response('', 503);
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    await tester.enterText(find.byType(TextFormField), 'Hiệp sĩ');
    await tester.pump();
    expect(find.text('Thử lại'), findsNothing);
    await _bam(tester, 'Tạo ảnh');
    expect(
      post[1].headers['Idempotency-Key'],
      isNot(post[0].headers['Idempotency-Key']),
    );
    expect(jsonDecode(post[1].body)['description'], 'Hiệp sĩ');
  });

  testWidgets('đang tạo khóa mô tả và nút, bấm đôi chỉ gửi một POST', (
    tester,
  ) async {
    final cho = Completer<http.Response>();
    var soLan = 0;
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((_) {
          soLan++;
          return cho.future;
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await tester.tap(find.text('Tạo ảnh'));
    await tester.pump();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(FilledButton));
    expect(soLan, 1);
    cho.complete(http.Response('', 503));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('đang tải ảnh vẫn khóa thao tác tạo mới', (tester) async {
    final cho = Completer<http.Response>();
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient(
          (r) => r.method == 'POST' ? Future.value(_metadata()) : cho.future,
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await tester.tap(find.text('Tạo ảnh'));
    await tester.pump();
    expect(find.text('Đang tải ảnh…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    cho.complete(http.Response('', 503));
    await tester.pumpAndSettle();
  });

  for (final status in [401, 403, 409, 422]) {
    testWidgets('lỗi POST $status không mời retry và không lộ body', (
      tester,
    ) async {
      await _nap(
        tester,
        MayChuNhanVat(
          mayChu: 'http://localhost',
          client: MockClient(
            (_) async => http.Response('private detail', status),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
      await _bam(tester, 'Tạo ảnh');
      expect(find.text('Thử lại'), findsNothing);
      expect(find.textContaining('private detail'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });
  }

  testWidgets('ảnh hết hạn gợi ý tạo mới, không tự gọi lại', (tester) async {
    var post = 0;
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            post++;
            return _metadata();
          }
          return http.Response('', 404);
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    expect(
      find.text('Ảnh đã hết hạn hoặc không còn khả dụng. Hãy tạo ảnh mới.'),
      findsOneWidget,
    );
    expect(find.text('Tải lại ảnh'), findsNothing);
    expect(post, 1);
  });

  testWidgets('PNG hỏng hiện lỗi và không dựng Image', (tester) async {
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient(
          (r) async => r.method == 'POST'
              ? _metadata()
              : http.Response(
                  'bad png',
                  200,
                  headers: {'content-type': 'image/png'},
                ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    expect(
      find.text('Ảnh nhận được không hợp lệ. Hãy tạo ảnh mới.'),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline hiển thị thông báo', (tester) async {
    await _nap(tester, MayChuNhanVat(mayChu: ''));
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    expect(find.text('Chưa cấu hình máy chủ AI.'), findsOneWidget);
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('đóng màn hình bỏ qua POST đến muộn và không tải ảnh', (
    tester,
  ) async {
    final cho = Completer<http.Response>();
    var soLan = 0;
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((_) {
          soLan++;
          return cho.future;
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await tester.tap(find.text('Tạo ảnh'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    cho.complete(_metadata());
    await tester.pumpAndSettle();
    expect(soLan, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('đổi client xóa dữ liệu và bỏ qua PNG của phiên cũ', (
    tester,
  ) async {
    final png = await tester.runAsync(pngMau);
    final cho = Completer<http.Response>();
    final cu = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient(
        (r) => r.method == 'POST' ? Future.value(_metadata()) : cho.future,
      ),
    );
    await _nap(tester, cu);
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await tester.tap(find.text('Tạo ảnh'));
    await tester.pump();
    await _nap(tester, MayChuNhanVat(mayChu: ''));
    await tester.runAsync(() async {
      cho.complete(
        http.Response.bytes(png!, 200, headers: {'content-type': 'image/png'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Tạo ảnh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chữ lớn và màn nhỏ vẫn cuộn tới nút tạo được', (tester) async {
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ManHinhAnhNhanVat(mayChu: MayChuNhanVat(mayChu: '')),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    expect(find.text('Chưa cấu hình máy chủ AI.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('đổi mô tả xóa preview, lần tạo sau dùng key mới', (
    tester,
  ) async {
    final png = await tester.runAsync(pngMau);
    final keys = <String?>[];
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            keys.add(r.headers['Idempotency-Key']);
            return _metadata();
          }
          return http.Response.bytes(
            png!,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    expect(find.byType(Image), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Cao bồi');
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    await _bam(tester, 'Tạo ảnh');
    expect(keys, hasLength(2));
    expect(keys[1], isNot(keys[0]));
  });

  testWidgets('metadata lỗi không tải PNG và xóa preview trước', (
    tester,
  ) async {
    final png = await tester.runAsync(pngMau);
    var post = 0;
    var get = 0;
    await _nap(
      tester,
      MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            return ++post == 1 ? _metadata() : http.Response('{}', 200);
          }
          get++;
          return http.Response.bytes(
            png!,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    await _bam(tester, 'Tạo ảnh mới');
    expect(find.byType(Image), findsNothing);
    expect(
      find.text('Phản hồi tạo ảnh không hợp lệ. Hãy tạo ảnh mới.'),
      findsOneWidget,
    );
    expect(get, 1);
  });

  testWidgets('đổi client bỏ qua POST phiên cũ trước bước tải PNG', (
    tester,
  ) async {
    final cho = Completer<http.Response>();
    final methods = <String>[];
    final cu = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient((r) {
        methods.add(r.method);
        return cho.future;
      }),
    );
    await _nap(tester, cu);
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await tester.tap(find.text('Tạo ảnh'));
    await tester.pump();
    await _nap(tester, MayChuNhanVat(mayChu: ''));
    cho.complete(_metadata());
    await tester.pumpAndSettle();
    expect(methods, ['POST']);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Tạo ảnh'), findsOneWidget);
  });

  testWidgets('preview chữ lớn màn nhỏ cuộn được, không tràn khung', (
    tester,
  ) async {
    final png = await tester.runAsync(pngMau);
    tester.view.physicalSize = const Size(320, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ManHinhAnhNhanVat(
          mayChu: MayChuNhanVat(
            mayChu: 'http://localhost',
            client: MockClient(
              (r) async => r.method == 'POST'
                  ? _metadata()
                  : http.Response.bytes(
                      png!,
                      200,
                      headers: {'content-type': 'image/png'},
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
    await _bam(tester, 'Tạo ảnh');
    await tester.ensureVisible(find.byType(Image));
    final size = tester.getSize(find.byType(Image));
    expect(size.width, lessThanOrEqualTo(256));
    expect(size.width, size.height);
    await tester.ensureVisible(find.text('Tạo ảnh mới'));
    expect(tester.takeException(), isNull);
  });
}
