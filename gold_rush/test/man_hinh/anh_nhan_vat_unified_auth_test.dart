import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/auth/auth_api_client.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/auth/metamask_siwe_contract.dart';
import 'package:gold_rush/man_hinh/anh_nhan_vat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../blockchain/vi_gia.dart';

class _FakeAuthWallet implements AuthWallet {
  final _eventsController =
      StreamController<MetamaskSiweEventType>.broadcast(sync: true);
  List<String> accounts = ['0x1111111111111111111111111111111111111111'];
  BigInt chain = BigInt.from(31337);

  @override
  Stream<MetamaskSiweEventType> get events => _eventsController.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<MetamaskWalletConnection> connect() async => MetamaskWalletConnection(
        address: accounts.first,
        chainId: chain,
      );

  @override
  Future<List<String>> getAccounts() async => accounts;

  @override
  Future<BigInt> getChainId() async => chain;

  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) async =>
      '0x${'a' * 130}';

  void emit(MetamaskSiweEventType event) => _eventsController.add(event);

  @override
  void dispose() {
    _eventsController.close();
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ManHinhAnhNhanVat ↔ Unified AuthController Integration', () {
    const walletAddress = '0x1111111111111111111111111111111111111111';
    const userId = '12345678-1234-1234-1234-123456789abc';
    const username = 'MinerGeorge';
    const csrfToken = 'test-session-csrf-999';

    late _FakeAuthWallet fakeWallet;
    late AuthApiClient authApi;
    late AuthController authController;
    late MayChuNhanVat characterApi;
    late ViGia fakeVi;

    setUp(() {
      fakeWallet = _FakeAuthWallet();
      fakeVi = ViGia(taiKhoan: [walletAddress], mang: 31337);

      authApi = AuthApiClient(
        baseUrl: 'http://localhost:8000',
        client: MockClient((req) async {
          if (req.url.path == '/api/me') {
            final futureExpiry =
                DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String();
            return _mockJsonResponse({
              'user': {
                'id': userId,
                'wallet_address': walletAddress,
                'username': username,
                'avatar': 'george',
                'created_at': '2026-11-08T10:00:00Z',
              },
              'chain_id': 31337,
              'csrf_token': csrfToken,
              'expires_at': futureExpiry,
            });
          }
          if (req.url.path == '/api/auth/logout') {
            return http.Response('', 204);
          }
          return http.Response('Not Found', 404);
        }),
      );

      authController = AuthController(
        wallet: fakeWallet,
        api: authApi,
      );

      characterApi = MayChuNhanVat(
        mayChu: 'http://localhost:8000',
        client: MockClient((req) async {
          if (req.url.path == '/api/ai/nhan-vat/danh-sach') {
            return _mockJsonListResponse([
              {
                'character_id': 'char_${'a' * 32}',
                'name': 'George Gold Miner',
                'image_id': 'img_${'b' * 32}',
                'prompt': 'a miner with a pickaxe',
                'character_hash': '0x${'f' * 64}',
                'verified_wallet_address': walletAddress,
                'onchain_status': 'registered',
                'token_id': 101,
                'transaction_hash': '0x${'e' * 64}',
                'created_at': '2026-11-08T10:00:00Z',
              }
            ]);
          }
          return http.Response('Not Found', 404);
        }),
      );
    });

    tearDown(() {
      authController.dispose();
      fakeWallet.dispose();
    });

    testWidgets(
      '1. Tự động nhận diện phiên SIWE đã xác thực từ AuthController (không cần đăng nhập lại)',
      (tester) async {
        // Authenticate AuthController via restoreSession (mocking AuthGate session check)
        await authController.restoreSession();
        expect(authController.canEnterGame, isTrue);
        expect(authController.user?.username, username);

        // Mount ManHinhAnhNhanVat with the active authController
        await tester.pumpWidget(
          MaterialApp(
            home: ManHinhAnhNhanVat(
              mayChu: characterApi,
              authController: authController,
              vi: fakeVi,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Must display user's short wallet and username
        expect(find.text('Người chơi: $username'), findsOneWidget);
        expect(find.textContaining('0x1111…1111'), findsOneWidget);

        // Does NOT display the SIWE login button
        expect(find.text('Đăng nhập MetaMask SIWE'), findsNothing);

        // Displays the user's characters fetched using the session
        expect(find.text('George Gold Miner'), findsOneWidget);
        expect(find.text('Đã xác minh On-Chain'), findsOneWidget);
        expect(find.textContaining('0xeeeeeeee'), findsOneWidget);

        authController.dispose();
      },
    );

    testWidgets(
      '2. Bấm Đăng xuất trên ManHinhAnhNhanVat gọi authController.logout() và xoá dữ liệu nhân vật',
      (tester) async {
        await authController.restoreSession();
        expect(authController.canEnterGame, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: ManHinhAnhNhanVat(
              mayChu: characterApi,
              authController: authController,
              vi: fakeVi,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('George Gold Miner'), findsOneWidget);

        // Click Đăng xuất button
        final logoutBtn = find.text('Đăng xuất');
        expect(logoutBtn, findsOneWidget);
        await tester.tap(logoutBtn);
        await tester.pumpAndSettle();

        // AuthController must have transitioned out of authenticated status
        expect(authController.canEnterGame, isFalse);
        expect(authController.status, AuthStatus.unauthenticated);

        // Characters and user identity must be cleared
        expect(find.text('George Gold Miner'), findsNothing);
        expect(find.text('Người chơi: $username'), findsNothing);
      },
    );

    testWidgets(
      '3. Khi ví đổi tài khoản, ManHinhAnhNhanVat tự động dọn dẹp phiên và danh sách',
      (tester) async {
        await authController.restoreSession();
        expect(authController.canEnterGame, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: ManHinhAnhNhanVat(
              mayChu: characterApi,
              authController: authController,
              vi: fakeVi,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('George Gold Miner'), findsOneWidget);

        // Wallet changes account
        fakeWallet.accounts = ['0x2222222222222222222222222222222222222222'];
        fakeWallet.emit(MetamaskSiweEventType.accountsChanged);
        await tester.pumpAndSettle();

        // AuthController invalidates session
        expect(authController.canEnterGame, isFalse);

        // ManHinhAnhNhanVat clears characters
        expect(find.text('George Gold Miner'), findsNothing);

        authController.dispose();
      },
    );
  });
}
