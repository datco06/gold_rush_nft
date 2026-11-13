import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/components/ai/nhan_vat_ai_gallery.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../ai/may_chu_nhan_vat_test.dart' show pngMau;

const _characterId = 'char_0123456789abcdef0123456789abcdef';

Map<String, Object?> _nhanVatJson() => {
  'character_id': _characterId,
  'name': 'Nhà thám hiểm AI',
  'image_id': 'img_0123456789abcdef0123456789abcdef',
  'character_hash': '1' * 64,
  'verified_wallet_address': '0x${'2' * 40}',
  'created_at': '2026-11-12T09:00:00Z',
  'onchain_status': 'not_registered',
  'transaction_hash': null,
};

Widget _app(MayChuNhanVat api) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(body: NhanVatAiGallery(mayChu: api)),
);

Future<void> _choTai(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  final images = find.byType(Image);
  if (images.evaluate().isNotEmpty) {
    await tester.runAsync(
      () => precacheImage(
        tester.widget<Image>(images.first).image,
        tester.element(images.first),
      ),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hiển thị ảnh thật từ danh sách đã lưu và nhãn không phải NFT', (
    tester,
  ) async {
    final png = await tester.runAsync(pngMau);
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient((request) async {
        if (request.url.path == '/api/ai/nhan-vat/danh-sach') {
          return http.Response(
            jsonEncode([_nhanVatJson()]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/ai/nhan-vat/$_characterId/anh') {
          return http.Response.bytes(
            png!,
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        return http.Response('', 404);
      }),
    );

    await tester.pumpWidget(_app(api));
    await _choTai(tester);

    expect(find.text('Nhà thám hiểm AI'), findsOneWidget);
    expect(find.text('Đã lưu · PNG tĩnh'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-image-$_characterId')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Xem chi tiết'));
    await tester.pumpAndSettle();
    expect(find.text('Trạng thái: Đã lưu trong Backend'), findsOneWidget);
    expect(
      find.text('Loại tài sản: Nhân vật AI, không phải NFT'),
      findsOneWidget,
    );
  });

  testWidgets('danh sách rỗng kết thúc loading và cho phép mở màn tạo', (
    tester,
  ) async {
    var daMo = false;
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NhanVatAiGallery(
            mayChu: api,
            khiMoTaoNhanVat: () async => daMo = true,
          ),
        ),
      ),
    );
    await _choTai(tester);

    expect(find.textContaining('chưa tạo nhân vật AI'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Tạo nhân vật AI'));
    expect(daMo, isTrue);
  });

  testWidgets('thumbnail lỗi không giữ gallery ở trạng thái tải mãi', (
    tester,
  ) async {
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient((request) async {
        if (request.url.path == '/api/ai/nhan-vat/danh-sach') {
          return http.Response(
            jsonEncode([_nhanVatJson()]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 404);
      }),
    );

    await tester.pumpWidget(_app(api));
    await _choTai(tester);

    expect(find.text('Nhà thám hiểm AI'), findsOneWidget);
    expect(find.text('Làm mới'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
