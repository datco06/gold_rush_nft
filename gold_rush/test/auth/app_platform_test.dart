@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/app_platform_web.dart';
import 'package:gold_rush/blockchain/vi.dart';

const address = '0x1111111111111111111111111111111111111111';

// No extension, HTTP, signature or transaction. Only EIP-1193 identity reads.
class _Provider {
  final object = JSObject();
  final calls = <String>[];
  final listeners = <String, Set<JSFunction>>{};

  _Provider() {
    object.setProperty('isMetaMask'.toJS, true.toJS);
    object.setProperty(
      'request'.toJS,
      ((JSObject request) {
        final method = request.getProperty<JSString>('method'.toJS).toDart;
        calls.add(method);
        final JSAny value = switch (method) {
          'eth_accounts' || 'eth_requestAccounts' => [address.toJS].toJS,
          'eth_chainId' => '0x7a69'.toJS,
          _ => throw StateError('Unexpected RPC in identity-only test'),
        };
        return Future<JSAny>.value(value).toJS;
      }).toJS,
    );
    object.setProperty(
      'on'.toJS,
      ((JSString name, JSFunction callback) {
        listeners.putIfAbsent(name.toDart, () => {}).add(callback);
      }).toJS,
    );
    object.setProperty(
      'removeListener'.toJS,
      ((JSString name, JSFunction callback) {
        listeners[name.toDart]?.remove(callback);
      }).toJS,
    );
  }

  int count(String event) => listeners[event]?.length ?? 0;
}

void main() {
  test(
    'transaction wallet uses the exact provider selected for SIWE',
    () async {
      final provider = _Provider();
      final auth = MetamaskSiweWeb(provider: provider.object);
      addTearDown(auth.dispose);
      expect(provider.calls, isEmpty);
      await auth.connect();
      expect(
        auth.selectedProvider!.strictEquals(provider.object).toDart,
        isTrue,
      );
      final game = createGameWallet(auth);
      addTearDown(game.dispose);
      expect(await game.vi.ketNoi(), address);
      expect(await game.vi.taiKhoan(), [address]);
      expect(await game.vi.chainId(), 31337);
      expect(provider.calls, isNot(contains('eth_sendTransaction')));
      expect(provider.calls, isNot(contains('personal_sign')));
    },
  );

  test(
    'game disposal removes only its listeners and closes its wallet',
    () async {
      final provider = _Provider();
      final auth = MetamaskSiweWeb(provider: provider.object);
      addTearDown(auth.dispose);
      await auth.checkAvailability();
      final game = createGameWallet(auth);
      addTearDown(game.dispose);
      final subscription = game.vi.suKien.listen((_) {});
      expect(provider.count('accountsChanged'), 2);
      expect(provider.count('chainChanged'), 2);
      game.dispose();
      game.dispose();
      await subscription.cancel();
      expect(provider.count('accountsChanged'), 1);
      expect(provider.count('chainChanged'), 1);
      expect(provider.count('disconnect'), 1);
      expect(await auth.getAccounts(), [address]);
      await expectLater(game.vi.taiKhoan(), throwsA(isA<LoiVi>()));
    },
  );
}
