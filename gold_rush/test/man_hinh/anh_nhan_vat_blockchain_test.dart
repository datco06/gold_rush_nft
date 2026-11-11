import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/blockchain/vi.dart';
import 'package:gold_rush/man_hinh/anh_nhan_vat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../ai/may_chu_nhan_vat_test.dart' show pngMau;
import '../blockchain/vi_gia.dart';

http.Response _mockJsonResponse(Map<String, dynamic> body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

http.Response _mockJsonListResponse(List<dynamic> body, [int status = 200]) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

Future<void> _bam(WidgetTester tester, String nhan) async {
  await tester.ensureVisible(find.text(nhan));
  await tester.runAsync(() async {
    await tester.tap(find.text(nhan));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
  final images = find.byType(Image);
  if (images.evaluate().isNotEmpty) {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ManHinhAnhNhanVat — Tích hợp Auth SIWE & Blockchain Registry', () {
    testWidgets('1. Hiển thị ảnh AI: xem trước 128x128 và có cảnh báo không phải sprite Flame', (tester) async {
      final png = await tester.runAsync(pngMau);
      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/ai/nhan-vat/tao') {
            return _mockJsonResponse({
              'image_id': 'img_0123456789abcdef0123456789abcdef',
              'image_url': '/api/ai/nhan-vat/anh/img_0123456789abcdef0123456789abcdef',
              'width': 128,
              'height': 128,
              'status': 'ready',
              'generation_source': 'image_model',
              'context_source': 'verified',
              'schema_version': 1,
            });
          }
          if (r.url.path.contains('/api/ai/nhan-vat/anh/')) {
            return http.Response.bytes(png!, 200, headers: {'content-type': 'image/png'});
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(home: ManHinhAnhNhanVat(mayChu: api)));
      await tester.enterText(find.byType(TextFormField), 'Chiến binh rồng lửa');
      await _bam(tester, 'Tạo ảnh');

      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('CHƯA PHẢI sprite sheet điều khiển được'), findsOneWidget);
    });

    testWidgets('2. Lưu nhân vật: gửi X-CSRF-Token, lưu CSDL thành công và hiển thị ID + Hash', (tester) async {
      final png = await tester.runAsync(pngMau);
      final headersSeen = <String, String>{};
      final vi = ViGia(taiKhoan: ['0x2222222222222222222222222222222222222222']);

      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return _mockJsonResponse({
              'user': {
                'user_id': 'usr_tester',
                'wallet_address': '0x2222222222222222222222222222222222222222',
                'username': 'GoldMiner',
              },
              'csrf_token': 'csrf_secret_token_123',
              'expires_at': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            });
          }
          if (r.url.path == '/api/ai/nhan-vat/tao') {
            return _mockJsonResponse({
              'image_id': 'img_0123456789abcdef0123456789abcdef',
              'image_url': '/api/ai/nhan-vat/anh/img_0123456789abcdef0123456789abcdef',
              'width': 128,
              'height': 128,
              'status': 'ready',
              'generation_source': 'image_model',
              'context_source': 'verified',
              'schema_version': 1,
            });
          }
          if (r.url.path.contains('/api/ai/nhan-vat/anh/')) {
            return http.Response.bytes(png!, 200, headers: {'content-type': 'image/png'});
          }
          if (r.url.path == '/api/ai/nhan-vat/luu') {
            r.headers.forEach((k, v) => headersSeen[k.toLowerCase()] = v);
            return _mockJsonResponse({
              'character_id': 'char_abcdef0123456789abcdef0123456789',
              'name': 'Thợ mỏ vàng AI',
              'image_id': 'img_0123456789abcdef0123456789abcdef',
              'character_hash': '1111111111111111111111111111111111111111111111111111111111111111',
              'verified_wallet_address': '0x2222222222222222222222222222222222222222',
              'created_at': '2026-11-09T13:38:28Z',
              'onchain_status': 'not_registered',
            });
          }
          if (r.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([]);
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('0x2222…2222'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Thợ mỏ giáp sắt');
      await _bam(tester, 'Tạo ảnh');

      await _bam(tester, 'LƯU NHÂN VẬT VÀO TÀI KHOẢN');

      expect(headersSeen['x-csrf-token'], 'csrf_secret_token_123');
      expect(find.textContaining('char_abcdef0123456789abcdef0123456789'), findsOneWidget);
      expect(find.textContaining('0x11111111…111111'), findsOneWidget);
    });

    testWidgets('3. Lấy danh sách nhân vật: hiển thị danh sách và huy hiệu trạng thái on-chain', (tester) async {
      final vi = ViGia();
      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return _mockJsonResponse({
              'user': {
                'user_id': 'usr_tester',
                'wallet_address': '0x2222222222222222222222222222222222222222',
                'username': 'GoldMiner',
              },
              'csrf_token': 'csrf_123',
            });
          }
          if (r.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([
              {
                'character_id': 'char_11111111111111111111111111111111',
                'name': 'Nhân vật Chưa Đăng Ký',
                'image_id': 'img_0123456789abcdef0123456789abcdef',
                'character_hash': 'aa' * 32,
                'verified_wallet_address': '0x2222222222222222222222222222222222222222',
                'created_at': '2026-11-09T13:38:28Z',
                'onchain_status': 'not_registered',
              },
              {
                'character_id': 'char_22222222222222222222222222222222',
                'name': 'Nhân vật Đang Chờ',
                'image_id': 'img_0123456789abcdef0123456789abcdef',
                'character_hash': 'bb' * 32,
                'verified_wallet_address': '0x2222222222222222222222222222222222222222',
                'created_at': '2026-11-09T13:38:28Z',
                'onchain_status': 'pending',
                'transaction_hash': '0x${'99' * 32}',
              },
              {
                'character_id': 'char_33333333333333333333333333333333',
                'name': 'Nhân vật Đã Xác Minh',
                'image_id': 'img_0123456789abcdef0123456789abcdef',
                'character_hash': 'cc' * 32,
                'verified_wallet_address': '0x2222222222222222222222222222222222222222',
                'created_at': '2026-11-09T13:38:28Z',
                'onchain_status': 'registered',
                'transaction_hash': '0x${'88' * 32}',
              },
            ]);
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nhân vật Chưa Đăng Ký'), findsOneWidget);
      expect(find.text('Chưa đăng ký'), findsOneWidget);

      expect(find.text('Nhân vật Đang Chờ'), findsOneWidget);
      expect(find.text('Đang chờ xác nhận'), findsOneWidget);

      expect(find.text('Nhân vật Đã Xác Minh'), findsOneWidget);
      expect(find.text('Đã xác minh On-Chain'), findsOneWidget);
    });

    testWidgets('4. Xử lý session hết hạn: trả về 401 SESSION_EXPIRED và khóa nút lưu', (tester) async {
      final png = await tester.runAsync(pngMau);
      final vi = ViGia();
      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return _mockJsonResponse({'detail': {'code': 'SESSION_EXPIRED'}}, 401);
          }
          if (r.url.path == '/api/ai/nhan-vat/tao') {
            return _mockJsonResponse({
              'image_id': 'img_0123456789abcdef0123456789abcdef',
              'image_url': '/api/ai/nhan-vat/anh/img_0123456789abcdef0123456789abcdef',
              'width': 128,
              'height': 128,
              'status': 'ready',
              'generation_source': 'demo',
              'context_source': 'demo',
              'schema_version': 1,
            });
          }
          if (r.url.path.contains('/api/ai/nhan-vat/anh/')) {
            return http.Response.bytes(png!, 200, headers: {'content-type': 'image/png'});
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐĂNG NHẬP SIWE'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
      await _bam(tester, 'Tạo ảnh');

      expect(find.text('CẦN ĐĂNG NHẬP ĐỂ LƯU'), findsOneWidget);
    });

    testWidgets('5. CSRF Token: Backend từ chối khi CSRF sai (403 CSRF_INVALID)', (tester) async {
      final png = await tester.runAsync(pngMau);
      final vi = ViGia();
      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return _mockJsonResponse({
              'user': {'user_id': 'usr_tester', 'wallet_address': '0x2222222222222222222222222222222222222222'},
              'csrf_token': 'wrong_csrf',
            });
          }
          if (r.url.path == '/api/ai/nhan-vat/tao') {
            return _mockJsonResponse({
              'image_id': 'img_0123456789abcdef0123456789abcdef',
              'image_url': '/api/ai/nhan-vat/anh/img_0123456789abcdef0123456789abcdef',
              'width': 128,
              'height': 128,
              'status': 'ready',
              'generation_source': 'demo',
              'context_source': 'demo',
              'schema_version': 1,
            });
          }
          if (r.url.path.contains('/api/ai/nhan-vat/anh/')) {
            return http.Response.bytes(png!, 200, headers: {'content-type': 'image/png'});
          }
          if (r.url.path == '/api/ai/nhan-vat/luu') {
            return _mockJsonResponse({'detail': {'code': 'CSRF_INVALID', 'message': 'CSRF token không hợp lệ'}}, 403);
          }
          if (r.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([]);
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
      await _bam(tester, 'Tạo ảnh');

      await _bam(tester, 'LƯU NHÂN VẬT VÀO TÀI KHOẢN');

      expect(find.textContaining('CSRF token không hợp lệ'), findsOneWidget);
    });

    testWidgets('6. Chống request trùng: khóa nút lưu khi đang xử lý', (tester) async {
      final png = await tester.runAsync(pngMau);
      final vi = ViGia();
      var luuCount = 0;
      final completer = Completer<http.Response>();

      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return _mockJsonResponse({
              'user': {'user_id': 'usr_tester', 'wallet_address': '0x2222222222222222222222222222222222222222'},
              'csrf_token': 'csrf_123',
            });
          }
          if (r.url.path == '/api/ai/nhan-vat/tao') {
            return _mockJsonResponse({
              'image_id': 'img_0123456789abcdef0123456789abcdef',
              'image_url': '/api/ai/nhan-vat/anh/img_0123456789abcdef0123456789abcdef',
              'width': 128,
              'height': 128,
              'status': 'ready',
              'generation_source': 'demo',
              'context_source': 'demo',
              'schema_version': 1,
            });
          }
          if (r.url.path.contains('/api/ai/nhan-vat/anh/')) {
            return http.Response.bytes(png!, 200, headers: {'content-type': 'image/png'});
          }
          if (r.url.path == '/api/ai/nhan-vat/luu') {
            luuCount++;
            return completer.future;
          }
          if (r.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([]);
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Thợ mỏ');
      await _bam(tester, 'Tạo ảnh');

      await tester.ensureVisible(find.text('LƯU NHÂN VẬT VÀO TÀI KHOẢN'));
      await tester.tap(find.text('LƯU NHÂN VẬT VÀO TÀI KHOẢN'));
      await tester.pump();

      // Đang lưu: nút chuyển thành Đang lưu…
      expect(find.text('Đang lưu…'), findsOneWidget);

      await tester.tap(find.text('Đang lưu…'));
      expect(luuCount, 1);

      completer.complete(_mockJsonResponse({
        'character_id': 'char_abcdef0123456789abcdef0123456789',
        'name': 'Thợ mỏ vàng AI',
        'image_id': 'img_0123456789abcdef0123456789abcdef',
        'character_hash': 'aa' * 32,
        'verified_wallet_address': '0x2222222222222222222222222222222222222222',
        'created_at': '2026-11-09T13:38:28Z',
        'onchain_status': 'not_registered',
      }));
      await tester.pumpAndSettle();
    });

    testWidgets('7. Logout / Đổi ví: xóa session và danh sách nhân vật nhạy cảm', (tester) async {
      final vi = ViGia(taiKhoan: ['0x2222222222222222222222222222222222222222']);
      var loggedOut = false;

      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return loggedOut
                ? _mockJsonResponse({'detail': {'code': 'SESSION_REQUIRED'}}, 401)
                : _mockJsonResponse({
                    'user': {'user_id': 'usr_tester', 'wallet_address': '0x2222222222222222222222222222222222222222'},
                    'csrf_token': 'csrf_123',
                  });
          }
          if (r.url.path == '/api/auth/logout') {
            loggedOut = true;
            return http.Response('', 204);
          }
          if (r.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([
              {
                'character_id': 'char_11111111111111111111111111111111',
                'name': 'Nhân vật của Ví A',
                'image_id': 'img_0123456789abcdef0123456789abcdef',
                'character_hash': 'aa' * 32,
                'verified_wallet_address': '0x2222222222222222222222222222222222222222',
                'created_at': '2026-11-09T13:38:28Z',
                'onchain_status': 'not_registered',
              }
            ]);
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nhân vật của Ví A'), findsOneWidget);

      await _bam(tester, 'Đăng xuất');

      expect(find.text('Nhân vật của Ví A'), findsNothing);
      expect(find.text('ĐĂNG NHẬP SIWE'), findsOneWidget);
    });

    test('8. Voucher EIP-712 thành công và thất bại', () async {
      var traLoi = false;

      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path.contains('/ky-voucher')) {
            if (traLoi) {
              return _mockJsonResponse({'detail': {'message': 'Nhân vật không thuộc ví này'}}, 403);
            }
            return _mockJsonResponse({
              'primaryType': 'CharacterVoucher',
              'message': {
                'characterId': 'char_11111111111111111111111111111111',
                'characterHash': '0x${'aa' * 32}',
                'owner': '0x2222222222222222222222222222222222222222',
                'nonce': '0x${'11' * 32}',
                'deadline': 1800000000,
              },
              'signature': '0x${'cc' * 65}',
              'contractAddress': '0x9999999999999999999999999999999999999999',
              'chainId': 31337,
              'signerAddress': '0x2222222222222222222222222222222222222222',
              'deadline': 1800000000,
            });
          }
          return http.Response('', 404);
        }),
      );

      final resSuccess = await api.xinKyVoucher(characterId: 'char_11111111111111111111111111111111');
      expect(resSuccess.thanhCong, isTrue);
      expect(resSuccess.phieu?.contractAddress, '0x9999999999999999999999999999999999999999');

      traLoi = true;
      final resFail = await api.xinKyVoucher(characterId: 'char_11111111111111111111111111111111');
      expect(resFail.thanhCong, isFalse);
      expect(resFail.maHttp, 403);
    });

    testWidgets('9. Giao dịch bị từ chối trên MetaMask (4001): không đánh dấu registered', (tester) async {
      final vi = ViGia(taiKhoan: ['0x2222222222222222222222222222222222222222']);
      vi.loiKhiGui = const LoiVi('User rejected the transaction', ma: 4001, loai: LoaiLoiVi.tuChoi);

      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return _mockJsonResponse({
              'user': {'user_id': 'usr_tester', 'wallet_address': '0x2222222222222222222222222222222222222222'},
              'csrf_token': 'csrf_123',
            });
          }
          if (r.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([
              {
                'character_id': 'char_11111111111111111111111111111111',
                'name': 'Nhân vật Từ Chối',
                'image_id': 'img_0123456789abcdef0123456789abcdef',
                'character_hash': 'aa' * 32,
                'verified_wallet_address': '0x2222222222222222222222222222222222222222',
                'created_at': '2026-11-09T13:38:28Z',
                'onchain_status': 'not_registered',
              }
            ]);
          }
          if (r.url.path.contains('/ky-voucher')) {
            return _mockJsonResponse({
              'primaryType': 'CharacterVoucher',
              'message': {
                'characterId': 'char_11111111111111111111111111111111',
                'characterHash': '0x${'aa' * 32}',
                'owner': '0x2222222222222222222222222222222222222222',
                'nonce': '0x${'11' * 32}',
                'deadline': 1800000000,
              },
              'signature': '0x${'cc' * 65}',
              'contractAddress': '0x9999999999999999999999999999999999999999',
              'chainId': 31337,
              'signerAddress': '0x2222222222222222222222222222222222222222',
              'deadline': 1800000000,
            });
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      await _bam(tester, 'Đăng ký On-Chain (EIP-712)');

      expect(find.textContaining('Bạn đã hủy xác nhận giao dịch trên MetaMask.'), findsOneWidget);
      expect(find.text('Chưa đăng ký'), findsOneWidget);
    });

    testWidgets('10 & 11. Giao dịch thành công & Backend xác nhận On-Chain: chuyển sang registered', (tester) async {
      final vi = ViGia(taiKhoan: ['0x2222222222222222222222222222222222222222']);
      var isRegistered = false;

      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((r) async {
          if (r.url.path == '/api/me') {
            return _mockJsonResponse({
              'user': {'user_id': 'usr_tester', 'wallet_address': '0x2222222222222222222222222222222222222222'},
              'csrf_token': 'csrf_123',
            });
          }
          if (r.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([
              {
                'character_id': 'char_11111111111111111111111111111111',
                'name': 'Nhân vật Thành Công',
                'image_id': 'img_0123456789abcdef0123456789abcdef',
                'character_hash': 'aa' * 32,
                'verified_wallet_address': '0x2222222222222222222222222222222222222222',
                'created_at': '2026-11-09T13:38:28Z',
                'onchain_status': isRegistered ? 'registered' : 'not_registered',
                'transaction_hash': isRegistered ? '0x${'aa' * 32}' : null,
              }
            ]);
          }
          if (r.url.path.contains('/ky-voucher')) {
            return _mockJsonResponse({
              'primaryType': 'CharacterVoucher',
              'message': {
                'characterId': 'char_11111111111111111111111111111111',
                'characterHash': '0x${'aa' * 32}',
                'owner': '0x2222222222222222222222222222222222222222',
                'nonce': '0x${'11' * 32}',
                'deadline': 1800000000,
              },
              'signature': '0x${'cc' * 65}',
              'contractAddress': '0x9999999999999999999999999999999999999999',
              'chainId': 31337,
              'signerAddress': '0x2222222222222222222222222222222222222222',
              'deadline': 1800000000,
            });
          }
          if (r.url.path.contains('/xac-minh-onchain')) {
            isRegistered = true;
            return _mockJsonResponse({
              'character_id': 'char_11111111111111111111111111111111',
              'name': 'Nhân vật Thành Công',
              'image_id': 'img_0123456789abcdef0123456789abcdef',
              'character_hash': 'aa' * 32,
              'verified_wallet_address': '0x2222222222222222222222222222222222222222',
              'created_at': '2026-11-09T13:38:28Z',
              'onchain_status': 'registered',
              'transaction_hash': '0x${'aa' * 32}',
            });
          }
          return http.Response('', 404);
        }),
      );

      await tester.pumpWidget(MaterialApp(
        home: ManHinhAnhNhanVat(mayChu: api, vi: vi, kiemTraPhienTuDong: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chưa đăng ký'), findsOneWidget);

      await _bam(tester, 'Đăng ký On-Chain (EIP-712)');

      expect(find.textContaining('Xác minh thành công! Nhân vật đã được ghi nhận On-Chain.'), findsOneWidget);
      expect(find.text('Đã xác minh On-Chain'), findsOneWidget);
    });
  });
}
