import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/auth_api_client.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/auth/metamask_siwe_contract.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _address = '0x1111111111111111111111111111111111111111';

class _Wallet implements AuthWallet {
  final eventsController = StreamController<MetamaskSiweEventType>.broadcast();
  bool available = true;

  @override
  Stream<MetamaskSiweEventType> get events => eventsController.stream;

  @override
  Future<bool> checkAvailability() async => available;

  @override
  Future<List<String>> getAccounts() async => available ? [_address] : [];

  @override
  Future<BigInt> getChainId() async => BigInt.one;

  @override
  Future<MetamaskWalletConnection> connect() => throw UnimplementedError();

  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) => throw UnimplementedError();

  @override
  void dispose() => unawaited(eventsController.close());
}

void main() {
  testWidgets(
    'Android keeps game and session across a temporary wallet handoff',
    (tester) async {
      final start = DateTime.utc(2026, 11, 27);
      final expiry = start.add(const Duration(hours: 8));
      final wallet = _Wallet();
      Completer<http.Response>? pending;
      var unavailable = false;
      var revoked = false;
      var checks = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          return http.Response('', 204);
        }
        checks++;
        if (pending case final request?) return request.future;
        if (unavailable) throw http.ClientException('Offline');
        if (revoked) {
          return http.Response(
            '{"detail":{"code":"SESSION_INVALID","message":"Invalid session"}}',
            401,
          );
        }
        return http.Response(
          jsonEncode({
            'user': {
              'id': '80574202-05bd-4577-8edf-d480b37cf9a2',
              'wallet_address': _address,
              'username': 'Demo',
              'avatar': 'george',
              'created_at': start.toIso8601String(),
            },
            'chain_id': 1,
            'expires_at': expiry.toIso8601String(),
            'csrf_token': 'test-session-csrf',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = AuthController(
        wallet: wallet,
        api: AuthApiClient(baseUrl: 'https://example.test', client: client),
        clock: () => start,
        passiveServerSessionCheck: true,
        disposeDependencies: true,
      );
      addTearDown(controller.dispose);
      await controller.restoreSession();
      expect(controller.canEnterGame, isTrue, reason: controller.errorMessage);

      wallet.available = false;
      pending = Completer<http.Response>();
      await tester.pump(const Duration(minutes: 1));
      expect(checks, 2);
      expect(controller.canEnterGame, isTrue);
      pending.complete(http.Response('', 503));
      pending = null;
      await tester.pump();
      expect(controller.canEnterGame, isTrue);

      unavailable = true;
      await tester.pump(const Duration(minutes: 1));
      expect(checks, 3);
      expect(controller.canEnterGame, isTrue);

      unavailable = false;
      await tester.pump(const Duration(minutes: 1));
      expect(checks, 4);
      expect(controller.canEnterGame, isTrue);

      revoked = true;
      await tester.pump(const Duration(minutes: 1));
      expect(checks, 5);
      expect(controller.canEnterGame, isFalse);
      controller.dispose();
    },
  );
}
