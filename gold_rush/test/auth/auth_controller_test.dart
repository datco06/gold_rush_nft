/// Browser unit tests: AuthController transitively imports dart:js_interop.
/// Run with flutter test --platform chrome test/auth/auth_controller_test.dart.
/// No extension, real HTTP, RPC, Database, private key or real token is used.
/// Fake mutations cannot prove browser Set-Cookie ordering or server revocation.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/auth_api_client.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/auth/metamask_siwe_web.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _walletA = '0x1111111111111111111111111111111111111111';
const _walletB = '0x2222222222222222222222222222222222222222';
const _userId = '80574202-05bd-4577-8edf-d480b37cf9a2';
const _challengeId = 'c21ad4be-b54e-4ecb-9c99-62dbdcedc677';
const _sessionCsrf = 'test-session-csrf-only';
const _grantCsrf = 'test-registration-csrf-only';
const _rotatedCsrf = 'test-rotated-csrf-only';
final _chain = BigInt.from(31337);
final _start = DateTime.utc(2026, 11, 8, 10);
final _sessionExpiry = _start.add(const Duration(hours: 8));
final _grantExpiry = _start.add(const Duration(minutes: 10));
final _signature = '0x${'1' * 130}'; // Deliberately not a cryptographic proof.
const _message =
    'localhost:5000 wants you to sign in with your Ethereum account:\n'
    '$_walletA\n\n'
    'Sign in to Gold Rush. Preserve UTF-8: e\u0301.\n\n'
    'URI: http://localhost:5000\nVersion: 1\nChain ID: 31337\n'
    'Nonce: 7d82b0539c4a6f219b08a175e6d24310\n'
    'Issued At: 2026-11-08T10:00:00Z\n'
    'Expiration Time: 2026-11-08T10:05:00Z';

Map<String, Object?> _userJson({
  String wallet = _walletA,
  String id = _userId,
  String username = 'Nhà Thám Hiểm',
}) => {
  'id': id,
  'wallet_address': wallet,
  'username': username,
  'avatar': 'george',
  'created_at': _start.toIso8601String(),
};

Map<String, Object?> _authenticatedJson({
  String wallet = _walletA,
  String csrf = _sessionCsrf,
  DateTime? expires,
}) => {
  'status': 'authenticated',
  'user': _userJson(wallet: wallet),
  'expires_at': (expires ?? _sessionExpiry).toIso8601String(),
  'csrf_token': csrf,
};

AuthAuthenticatedResult _authenticated({
  String wallet = _walletA,
  String csrf = _sessionCsrf,
  DateTime? expires,
}) => AuthAuthenticatedResult.fromJson(
  _authenticatedJson(wallet: wallet, csrf: csrf, expires: expires),
);

Map<String, Object?> _grantJson({
  String wallet = _walletA,
  DateTime? expires,
}) => {
  'status': 'registration_required',
  'wallet_address': wallet,
  'expires_at': (expires ?? _grantExpiry).toIso8601String(),
  'csrf_token': _grantCsrf,
};

AuthRegistrationRequired _grant({
  String wallet = _walletA,
  DateTime? expires,
}) => AuthRegistrationRequired.fromJson(
  _grantJson(wallet: wallet, expires: expires),
);

Map<String, Object?> _meJson({
  String wallet = _walletA,
  String id = _userId,
  String username = 'Nhà Thám Hiểm',
  String csrf = _sessionCsrf,
  BigInt? chain,
  DateTime? expires,
}) => {
  'user': _userJson(wallet: wallet, id: id, username: username),
  'chain_id': chain ?? _chain,
  'expires_at': (expires ?? _sessionExpiry).toIso8601String(),
  'csrf_token': csrf,
};

AuthMeResponse _me({
  String wallet = _walletA,
  String id = _userId,
  String username = 'Nhà Thám Hiểm',
  String csrf = _sessionCsrf,
  BigInt? chain,
  DateTime? expires,
}) => AuthMeResponse.fromJson(
  _meJson(
    wallet: wallet,
    id: id,
    username: username,
    csrf: csrf,
    chain: chain,
    expires: expires,
  ),
);

Map<String, Object?> _challengeJson({DateTime? expires}) => {
  'challenge_id': _challengeId,
  'message': _message,
  'expires_at': (expires ?? _start.add(const Duration(minutes: 5)))
      .toIso8601String(),
};

/// A test chooses exactly when an external operation starts and finishes.
/// No sleep, elapsed-wall-time assertion, polling or production API is needed.
class _Gate<T> {
  final _entered = Completer<void>();
  final _result = Completer<T>();
  Future<void> get entered => _entered.future;

  Future<T> call() {
    if (!_entered.isCompleted) _entered.complete();
    return _result.future;
  }

  void complete(T value) => _result.complete(value);
  void fail(Object error) => _result.completeError(error);
}

class _FakeWallet implements AuthWallet {
  _FakeWallet(this.calls) {
    _events = StreamController<MetamaskSiweEventType>.broadcast(
      sync: true,
      onListen: () => subscriptions++,
      onCancel: () => cancellations++,
    );
  }

  final List<String> calls;
  late final StreamController<MetamaskSiweEventType> _events;
  List<String> accounts = [_walletA];
  BigInt chain = _chain;
  bool available = true;
  bool emitPermissionEvent = false;
  int eventReads = 0;
  int subscriptions = 0;
  int cancellations = 0;
  int connectCalls = 0;
  int disposeCalls = 0;
  final signatures = <({String address, String message, BigInt? chain})>[];
  FutureOr<bool> Function()? onAvailability;
  FutureOr<MetamaskWalletConnection> Function()? onConnect;
  FutureOr<List<String>> Function()? onAccounts;
  FutureOr<BigInt> Function()? onChain;
  FutureOr<String> Function()? onSign;

  @override
  Stream<MetamaskSiweEventType> get events {
    eventReads++;
    return _events.stream;
  }

  @override
  Future<bool> checkAvailability() async {
    calls.add('wallet.available');
    return onAvailability == null ? available : await onAvailability!();
  }

  @override
  Future<MetamaskWalletConnection> connect() async {
    calls.add('wallet.connect');
    connectCalls++;
    if (emitPermissionEvent) emit(MetamaskSiweEventType.accountsChanged);
    return onConnect == null
        ? MetamaskWalletConnection(address: accounts.first, chainId: chain)
        : await onConnect!();
  }

  @override
  Future<List<String>> getAccounts() async {
    calls.add('wallet.accounts');
    return onAccounts == null ? List.of(accounts) : await onAccounts!();
  }

  @override
  Future<BigInt> getChainId() async {
    calls.add('wallet.chain');
    return onChain == null ? chain : await onChain!();
  }

  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) async {
    calls.add('wallet.sign');
    signatures.add((
      address: address,
      message: message,
      chain: expectedChainId,
    ));
    return onSign == null ? _signature : await onSign!();
  }

  void emit(MetamaskSiweEventType type) => _events.add(type);
  void emitError() => _events.addError(StateError('untrusted provider error'));
  Future<void> closeEvents() => _events.close();

  @override
  void dispose() {
    disposeCalls++;
    unawaited(closeEvents());
  }
}

/// Implements only the real public API; never constructs BrowserClient.
/// pending is controlled explicitly to model a transport whose underlying
/// mutation is still running after its returned Future timed out.
class _FakeApi implements AuthApiClient {
  _FakeApi(this.calls);
  final List<String> calls;
  bool pending = false;
  int closeCalls = 0;
  AuthChallengeResponse challenge = AuthChallengeResponse.fromJson(
    _challengeJson(),
  );
  AuthVerifyResult verifyResult = _authenticated();
  AuthAuthenticatedResult registerResult = _authenticated();
  AuthMeResponse meResult = _me();
  FutureOr<AuthChallengeResponse> Function()? onChallenge;
  FutureOr<AuthVerifyResult> Function()? onVerify;
  FutureOr<AuthAuthenticatedResult> Function()? onRegister;
  FutureOr<AuthMeResponse> Function()? onMe;
  FutureOr<void> Function()? onLogout;
  final challenges = <({String walletAddress, BigInt chainId})>[];
  final verifications =
      <({String challengeId, String message, String signature})>[];
  final registrations = <({String username, String csrfToken})>[];
  final logouts = <String>[];

  @override
  final Uri baseUri = Uri.parse('https://auth.invalid');
  @override
  final Duration timeout = const Duration(seconds: 10);
  @override
  bool get mutationPending => pending;

  @override
  Future<AuthChallengeResponse> createChallenge({
    required String walletAddress,
    required BigInt chainId,
  }) async {
    calls.add('api.challenge');
    challenges.add((walletAddress: walletAddress, chainId: chainId));
    return onChallenge == null ? challenge : await onChallenge!();
  }

  @override
  Future<AuthVerifyResult> verify({
    required String challengeId,
    required String message,
    required String signature,
  }) async {
    calls.add('api.verify');
    verifications.add((
      challengeId: challengeId,
      message: message,
      signature: signature,
    ));
    return onVerify == null ? verifyResult : await onVerify!();
  }

  @override
  Future<AuthAuthenticatedResult> register({
    required String username,
    required String csrfToken,
  }) async {
    calls.add('api.register');
    registrations.add((username: username, csrfToken: csrfToken));
    return onRegister == null ? registerResult : await onRegister!();
  }

  @override
  Future<AuthMeResponse> getMe() async {
    calls.add('api.me');
    return onMe == null ? meResult : await onMe!();
  }

  @override
  Future<void> logout({required String csrfToken}) async {
    calls.add('api.logout');
    logouts.add(csrfToken);
    if (onLogout != null) await onLogout!();
  }

  @override
  void close() => closeCalls++;
  @override
  void dispose() => close();
}

class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}

class _Rig {
  _Rig({AuthApiClient? transport, bool ownsDependencies = false}) {
    wallet = _FakeWallet(calls);
    api = _FakeApi(calls);
    controller = AuthController(
      wallet: wallet,
      api: transport ?? api,
      clock: () => time,
      timerFactory: (delay, callback) {
        final timer = _ManualTimer(delay, callback);
        timers.add(timer);
        return timer;
      },
      disposeDependencies: ownsDependencies,
    );
    addTearDown(() async {
      controller.dispose();
      await wallet.closeEvents();
      expect(timers.where((timer) => timer.isActive), isEmpty);
    });
  }

  final calls = <String>[];
  final timers = <_ManualTimer>[];
  late final _FakeWallet wallet;
  late final _FakeApi api;
  late final AuthController controller;
  DateTime time = _start;

  Future<void> drainCleanup() async {
    if (controller.logoutPending) await controller.logout();
  }

  Future<void> enterRegistration() async {
    api.verifyResult = _grant();
    await controller.connectAndSignIn();
    expect(controller.status, AuthStatus.registrationRequired);
  }
}

void _expectLocked(AuthController controller) {
  expect(controller.canEnterGame, isFalse);
  expect(controller.isAuthenticated, isFalse);
  expect(controller.user, isNull);
}

void _expectSafeDiagnostic(AuthController controller) {
  final diagnostic = '${controller.errorMessage} ${controller.toString()}';
  for (final sensitive in [
    _sessionCsrf,
    _grantCsrf,
    _rotatedCsrf,
    _signature,
    _message,
  ]) {
    expect(diagnostic, isNot(contains(sensitive)));
  }
}

// Read-only inspection of the isolated test browser. Nothing is stored or
// removed by these tests. This is not a test of HttpOnly cookie enforcement.
@JS('localStorage')
external _BrowserStorage get _localStorage;
@JS('sessionStorage')
external _BrowserStorage get _sessionStorage;

extension type _BrowserStorage._(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
}

List<String> _storageValues(_BrowserStorage storage) => [
  for (var i = 0; i < storage.length; i++)
    if (storage.key(i) case final String key) '${storage.getItem(key)}',
];

void main() {
  group('initial state and notifications', () {
    test(
      'constructor has no HTTP, RPC, popup, profile or gameplay authority',
      () {
        final rig = _Rig();
        expect(rig.controller.status, AuthStatus.initial);
        expect(rig.calls, isEmpty);
        expect(rig.controller.walletAddress, isNull);
        expect(rig.controller.chainId, isNull);
        expect(rig.controller.expiresAt, isNull);
        expect(rig.controller.errorMessage, isNull);
        expect(rig.controller.logoutPending, isFalse);
        expect(rig.controller.isLoading, isFalse);
        _expectLocked(rig.controller);
      },
    );

    test(
      'one subscription survives repeated restore without duplicate listeners',
      () async {
        final rig = _Rig();
        await rig.controller.restoreSession();
        await rig.controller.restoreSession();
        expect(rig.wallet.eventReads, 1);
        expect(rig.wallet.subscriptions, 1);
        expect(rig.wallet.cancellations, 0);
        rig.controller.dispose();
        expect(rig.wallet.cancellations, 1);
      },
    );

    test(
      'listeners see all login stages; loading states never permit gameplay',
      () async {
        final rig = _Rig();
        final statuses = <AuthStatus>[];
        rig.controller.addListener(() {
          statuses.add(rig.controller.status);
          if (rig.controller.status != AuthStatus.authenticated) {
            _expectLocked(rig.controller);
            expect(rig.controller.isLoading, isTrue);
          }
        });
        await rig.controller.connectAndSignIn();
        expect(statuses, [
          AuthStatus.connectingWallet,
          AuthStatus.requestingChallenge,
          AuthStatus.awaitingSignature,
          AuthStatus.verifying,
          AuthStatus.authenticated,
        ]);
        expect(rig.controller.isLoading, isFalse);
        expect(rig.controller.canEnterGame, isTrue);
      },
    );
  });

  group('connect, challenge, sign, verify and me', () {
    test(
      'calls occur in order and the original Unicode SIWE message is preserved',
      () async {
        final rig = _Rig();
        await rig.controller.connectAndSignIn();
        expect(
          rig.calls,
          containsAllInOrder([
            'wallet.available',
            'wallet.connect',
            'wallet.accounts',
            'wallet.chain',
            'api.challenge',
            'wallet.sign',
            'api.verify',
            'api.me',
            'wallet.accounts',
            'wallet.chain',
          ]),
        );
        expect(rig.api.challenges.single, (
          walletAddress: _walletA,
          chainId: _chain,
        ));
        expect(rig.wallet.signatures.single, (
          address: _walletA,
          message: _message,
          chain: _chain,
        ));
        expect(rig.api.verifications.single, (
          challengeId: _challengeId,
          message: _message,
          signature: _signature,
        ));
        expect(rig.controller.user!.id, _userId);
        expect(rig.controller.walletAddress, _walletA);
        expect(rig.controller.chainId, _chain);
        expect(rig.controller.expiresAt, _sessionExpiry);
        expect(rig.controller.serverSessionMayBeActive, isTrue);
        expect(rig.controller.canEnterGame, isTrue);
        _expectSafeDiagnostic(rig.controller);
      },
    );

    test(
      'authenticated verify alone cannot grant play while me is pending',
      () async {
        final rig = _Rig();
        final gate = _Gate<AuthMeResponse>();
        rig.api.onMe = gate.call;
        final task = rig.controller.connectAndSignIn();
        await gate.entered;
        expect(rig.controller.status, AuthStatus.verifying);
        _expectLocked(rig.controller);
        gate.complete(_me());
        await task;
        expect(rig.controller.canEnterGame, isTrue);
      },
    );

    test(
      'normal first permission event during connect does not abort login',
      () async {
        final rig = _Rig();
        rig.wallet.emitPermissionEvent = true;
        await rig.controller.connectAndSignIn();
        expect(rig.controller.canEnterGame, isTrue);
        expect(rig.wallet.connectCalls, 1);
      },
    );

    test(
      'expired challenge is rejected before asking MetaMask to sign',
      () async {
        final rig = _Rig();
        rig.api.challenge = AuthChallengeResponse.fromJson(
          _challengeJson(expires: _start),
        );
        await rig.controller.connectAndSignIn();
        _expectLocked(rig.controller);
        expect(rig.controller.errorCode, 'CHALLENGE_EXPIRED');
        expect(rig.wallet.signatures, isEmpty);
        expect(rig.api.verifications, isEmpty);
      },
    );

    test(
      'wallet changes without an event between challenge and sign are detected',
      () async {
        final rig = _Rig();
        rig.api.onChallenge = () {
          rig.wallet.accounts = [_walletB];
          return rig.api.challenge;
        };
        await rig.controller.connectAndSignIn();
        _expectLocked(rig.controller);
        expect(rig.wallet.signatures, isEmpty);
        expect(rig.api.verifications, isEmpty);
      },
    );

    test(
      'chain changes without an event after signing never reach verify',
      () async {
        final rig = _Rig();
        rig.wallet.onSign = () {
          rig.wallet.chain = BigInt.one;
          return _signature;
        };
        await rig.controller.connectAndSignIn();
        _expectLocked(rig.controller);
        expect(rig.api.verifications, isEmpty);
      },
    );

    for (final mismatch in [
      'wallet',
      'user id',
      'username',
      'chain',
      'csrf',
      'expiry',
    ]) {
      test('me mismatch is locked and revoked: $mismatch', () async {
        final rig = _Rig();
        rig.api.meResult = _me(
          wallet: mismatch == 'wallet' ? _walletB : _walletA,
          id: mismatch == 'user id' ? _challengeId : _userId,
          username: mismatch == 'username' ? 'Khác Tên' : 'Nhà Thám Hiểm',
          chain: mismatch == 'chain' ? BigInt.one : _chain,
          csrf: mismatch == 'csrf' ? _rotatedCsrf : _sessionCsrf,
          expires: mismatch == 'expiry'
              ? _sessionExpiry.add(const Duration(seconds: 1))
              : _sessionExpiry,
        );
        await rig.controller.connectAndSignIn();
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.api.logouts.single, rig.api.meResult.csrfToken);
        expect(rig.controller.errorCode, 'IDENTITY_MISMATCH');
      });
    }

    test('verify response for another wallet is rejected before me', () async {
      final rig = _Rig();
      rig.api.verifyResult = _authenticated(wallet: _walletB);
      await rig.controller.connectAndSignIn();
      await rig.drainCleanup();
      _expectLocked(rig.controller);
      expect(rig.calls, isNot(contains('api.me')));
      expect(rig.api.logouts, [_sessionCsrf]);
    });
  });

  group('registration grant and character name', () {
    test('grant retains the verified wallet but never a user or gameplay authority', () async {
      final rig = _Rig();
      await rig.enterRegistration();
      _expectLocked(rig.controller);
      expect(rig.controller.walletAddress, _walletA);
      expect(rig.controller.chainId, _chain);
      expect(rig.controller.expiresAt, _grantExpiry);
      expect(rig.controller.isLoading, isFalse);
      expect(rig.calls, isNot(contains('api.me')));
    });

    test('register uses grant CSRF and waits for matching me before authenticating', () async {
      final rig = _Rig();
      await rig.enterRegistration();
      final gate = _Gate<AuthMeResponse>();
      rig.api.onMe = gate.call;
      final task = rig.controller.register('Nhà Thám Hiểm');
      await gate.entered;
      expect(rig.controller.status, AuthStatus.registering);
      _expectLocked(rig.controller);
      expect(rig.api.registrations.single, (
        username: 'Nhà Thám Hiểm',
        csrfToken: _grantCsrf,
      ));
      gate.complete(_me());
      await task;
      expect(rig.controller.canEnterGame, isTrue);
      expect(rig.controller.user!.username, 'Nhà Thám Hiểm');
    });

    final nameErrors = <String, AuthApiException>{
      'name already used': const AuthApiException(
        AuthApiErrorKind.conflict,
        code: 'USERNAME_TAKEN',
      ),
      'invalid name': const AuthApiException(
        AuthApiErrorKind.validation,
        code: 'USERNAME_INVALID',
      ),
      'FastAPI field validation': const AuthApiException(
        AuthApiErrorKind.validation,
        field: 'username',
      ),
      'local request validation': const AuthApiException(
        AuthApiErrorKind.invalidRequest,
      ),
    };
    for (final entry in nameErrors.entries) {
      test(
        '${entry.key}: retry keeps a valid grant without another signature',
        () async {
          final rig = _Rig();
          await rig.enterRegistration();
          rig.api.onRegister = () => throw entry.value;
          await rig.controller.register('tên bị từ chối');
          expect(rig.controller.status, AuthStatus.registrationRequired);
          _expectLocked(rig.controller);
          expect(
            rig.controller.errorCode,
            entry.value.code == 'USERNAME_TAKEN'
                ? 'USERNAME_TAKEN'
                : 'USERNAME_INVALID',
          );
          expect(rig.controller.errorMessage, isNotEmpty);
          expect(rig.api.logouts, isEmpty);
          rig.api.onRegister = null;
          await rig.controller.register('Nhà Thám Hiểm');
          expect(rig.api.registrations.map((request) => request.csrfToken), [
            _grantCsrf,
            _grantCsrf,
          ]);
          expect(rig.wallet.signatures, hasLength(1));
          expect(rig.api.challenges, hasLength(1));
          expect(rig.controller.canEnterGame, isTrue);
        },
      );
    }

    test(
      'register before verify is rejected without an API registration request',
      () async {
        final rig = _Rig();
        await rig.controller.register('Nhà Thám Hiểm');
        _expectLocked(rig.controller);
        expect(rig.controller.errorCode, 'REGISTRATION_REQUIRED');
        expect(rig.api.registrations, isEmpty);
      },
    );

    test('local grant expiry is checked before submitting a name', () async {
      final rig = _Rig();
      await rig.enterRegistration();
      rig.time = _grantExpiry;
      await rig.controller.register('Nhà Thám Hiểm');
      await rig.drainCleanup();
      _expectLocked(rig.controller);
      expect(rig.controller.walletAddress, isNull);
      expect(rig.api.registrations, isEmpty);
      expect(rig.api.logouts, [_grantCsrf]);
      expect(rig.controller.errorCode, 'GRANT_EXPIRED');
    });

    test(
      'server-expired grant clears temporary identity and allows a fresh login',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        rig.api.onRegister = () => throw const AuthApiException(
          AuthApiErrorKind.unauthenticated,
          code: 'GRANT_EXPIRED',
          statusCode: 401,
        );
        await rig.controller.register('Nhà Thám Hiểm');
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.controller.walletAddress, isNull);
        rig.api.verifyResult = _authenticated();
        await rig.controller.connectAndSignIn();
        expect(rig.wallet.signatures, hasLength(2));
        expect(rig.controller.canEnterGame, isTrue);
      },
    );

    test('grant for a different wallet is never accepted', () async {
      final rig = _Rig();
      rig.api.verifyResult = _grant(wallet: _walletB);
      await rig.controller.connectAndSignIn();
      await rig.drainCleanup();
      expect(rig.controller.status, isNot(AuthStatus.registrationRequired));
      _expectLocked(rig.controller);
      expect(rig.api.logouts, [_grantCsrf]);
    });

    test(
      'rejected name after the grant expires cannot preserve the grant state',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        final gate = _Gate<AuthAuthenticatedResult>();
        rig.api.onRegister = gate.call;
        final task = rig.controller.register('Nhà Thám Hiểm');
        await gate.entered;
        rig.time = _grantExpiry;
        gate.fail(
          const AuthApiException(
            AuthApiErrorKind.conflict,
            code: 'USERNAME_TAKEN',
          ),
        );
        await task;
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.controller.status, isNot(AuthStatus.registrationRequired));
        expect(rig.controller.errorCode, 'GRANT_EXPIRED');
      },
    );

    test(
      'register success with a mismatched me cannot open gameplay',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        rig.api.meResult = _me(wallet: _walletB);
        await rig.controller.register('Nhà Thám Hiểm');
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.api.logouts, [_sessionCsrf]);
      },
    );
  });

  group('passive restore', () {
    test(
      'matching backend session and wallet restore with no connect/sign popup',
      () async {
        final rig = _Rig();
        await rig.controller.restoreSession();
        expect(rig.calls.first, 'api.me');
        expect(
          rig.calls,
          containsAllInOrder([
            'api.me',
            'wallet.available',
            'wallet.accounts',
            'wallet.chain',
          ]),
        );
        expect(rig.wallet.connectCalls, 0);
        expect(rig.wallet.signatures, isEmpty);
        expect(rig.api.challenges, isEmpty);
        expect(rig.controller.canEnterGame, isTrue);
      },
    );

    test(
      '401 does not touch MetaMask or trust its standalone connection',
      () async {
        final rig = _Rig();
        rig.api.onMe = () => throw const AuthApiException(
          AuthApiErrorKind.unauthenticated,
          statusCode: 401,
        );
        await rig.controller.restoreSession();
        expect(rig.calls, ['api.me']);
        expect(rig.controller.status, AuthStatus.unauthenticated);
        _expectLocked(rig.controller);
      },
    );

    for (final error in [
      AuthApiErrorKind.network,
      AuthApiErrorKind.timeout,
      AuthApiErrorKind.invalidResponse,
    ]) {
      test(
        '$error is not evidence that the server revoked its session',
        () async {
          final rig = _Rig();
          rig.api.onMe = () => throw AuthApiException(error);
          await rig.controller.restoreSession();
          expect(rig.controller.status, AuthStatus.error);
          expect(rig.controller.serverSessionMayBeActive, isTrue);
          expect(rig.wallet.connectCalls, 0);
          _expectLocked(rig.controller);
        },
      );
    }

    for (final mismatch in [
      'different wallet',
      'different chain',
      'no accounts',
      'no provider',
    ]) {
      test(
        '$mismatch: lock and revoke using server CSRF without popup',
        () async {
          final rig = _Rig();
          if (mismatch == 'different wallet') rig.wallet.accounts = [_walletB];
          if (mismatch == 'different chain') rig.wallet.chain = BigInt.one;
          if (mismatch == 'no accounts') rig.wallet.accounts = [];
          if (mismatch == 'no provider') rig.wallet.available = false;
          await rig.controller.restoreSession();
          await rig.drainCleanup();
          _expectLocked(rig.controller);
          expect(rig.api.logouts, [_sessionCsrf]);
          expect(rig.wallet.connectCalls, 0);
          expect(rig.wallet.signatures, isEmpty);
        },
      );
    }

    test(
      'restore mismatch with failed revocation remains explicitly uncertain',
      () async {
        final rig = _Rig();
        rig.wallet.accounts = [_walletB];
        rig.api.onLogout = () =>
            throw const AuthApiException(AuthApiErrorKind.network);
        await rig.controller.restoreSession();
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.controller.logoutPending, isTrue);
        expect(rig.controller.serverSessionMayBeActive, isTrue);
        expect(rig.controller.status, AuthStatus.error);
      },
    );

    test('expired me is rejected before wallet queries', () async {
      final rig = _Rig();
      rig.api.meResult = _me(expires: _start);
      await rig.controller.restoreSession();
      await rig.drainCleanup();
      _expectLocked(rig.controller);
      expect(rig.calls, ['api.me', 'api.logout']);
      expect(rig.controller.errorCode, 'SESSION_EXPIRED');
    });

    test(
      'restoring clears the previous profile while a new me is pending',
      () async {
        final rig = _Rig();
        await rig.controller.restoreSession();
        final gate = _Gate<AuthMeResponse>();
        rig.api.onMe = gate.call;
        final task = rig.controller.restoreSession();
        await gate.entered;
        expect(rig.controller.status, AuthStatus.checkingSession);
        _expectLocked(rig.controller);
        gate.complete(_me());
        await task;
        expect(rig.controller.canEnterGame, isTrue);
      },
    );
  });

  group('wallet events and deterministic races', () {
    for (final type in MetamaskSiweEventType.values) {
      test(
        '$type immediately removes old identity and never logs in another wallet',
        () async {
          final rig = _Rig();
          await rig.controller.connectAndSignIn();
          rig.wallet.accounts = [_walletB];
          rig.wallet.emit(type);
          _expectLocked(rig.controller); // Deliberately before any await.
          expect(rig.controller.walletAddress, isNull);
          expect(rig.controller.chainId, isNull);
          expect(rig.controller.logoutPending, isTrue);
          await rig.drainCleanup();
          expect(rig.api.logouts, [_sessionCsrf]);
          expect(rig.wallet.connectCalls, 1);
          expect(rig.wallet.signatures, hasLength(1));
        },
      );
    }

    test('provider stream error is handled as loss of identity', () async {
      final rig = _Rig();
      await rig.controller.restoreSession();
      rig.wallet.emitError();
      _expectLocked(rig.controller);
      await rig.drainCleanup();
      expect(rig.api.logouts, [_sessionCsrf]);
    });

    test(
      'provider stream closing locks and revokes the current session',
      () async {
        final rig = _Rig();
        await rig.controller.restoreSession();
        await rig.wallet.closeEvents();
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.api.logouts, [_sessionCsrf]);
      },
    );

    test('A signs late after switching to B: no old verify is sent', () async {
      final rig = _Rig();
      final signature = _Gate<String>();
      rig.wallet.onSign = signature.call;
      rig.api.onMe = () => throw const AuthApiException(
        AuthApiErrorKind.unauthenticated,
        statusCode: 401,
      );
      final task = rig.controller.connectAndSignIn();
      await signature.entered;
      rig.wallet.accounts = [_walletB];
      rig.wallet.emit(MetamaskSiweEventType.accountsChanged);
      _expectLocked(rig.controller);
      signature.complete(_signature);
      await task;
      await rig.drainCleanup();
      _expectLocked(rig.controller);
      expect(rig.api.verifications, isEmpty);
    });

    test(
      'away and back while signing still invalidates the old generation',
      () async {
        final rig = _Rig();
        final signature = _Gate<String>();
        rig.wallet.onSign = signature.call;
        rig.api.onMe = () =>
            throw const AuthApiException(AuthApiErrorKind.unauthenticated);
        final task = rig.controller.connectAndSignIn();
        await signature.entered;
        rig.wallet.accounts = [_walletB];
        rig.wallet.emit(MetamaskSiweEventType.accountsChanged);
        rig.wallet.accounts = [_walletA];
        rig.wallet.emit(MetamaskSiweEventType.accountsChanged);
        signature.complete(_signature);
        await task;
        await rig.drainCleanup();
        expect(rig.api.verifications, isEmpty);
        _expectLocked(rig.controller);
      },
    );

    for (final result in ['authenticated', 'registration']) {
      test(
        'late $result verify after chain change is revoked, not published',
        () async {
          final rig = _Rig();
          final verification = _Gate<AuthVerifyResult>();
          rig.api.onVerify = verification.call;
          final task = rig.controller.connectAndSignIn();
          await verification.entered;
          rig.wallet.chain = BigInt.one;
          rig.wallet.emit(MetamaskSiweEventType.chainChanged);
          _expectLocked(rig.controller);
          verification.complete(
            result == 'authenticated'
                ? _authenticated(csrf: _rotatedCsrf)
                : _grant(),
          );
          await task;
          await rig.drainCleanup();
          _expectLocked(rig.controller);
          expect(rig.api.logouts, [
            result == 'authenticated' ? _rotatedCsrf : _grantCsrf,
          ]);
          expect(rig.calls, isNot(contains('api.me')));
        },
      );
    }

    test(
      'two simultaneous login calls share one challenge and signature',
      () async {
        final rig = _Rig();
        final signature = _Gate<String>();
        rig.wallet.onSign = signature.call;
        final first = rig.controller.connectAndSignIn();
        final second = rig.controller.connectAndSignIn();
        await signature.entered;
        expect(rig.wallet.connectCalls, 1);
        expect(rig.api.challenges, hasLength(1));
        signature.complete(_signature);
        await Future.wait([first, second]);
        expect(rig.wallet.signatures, hasLength(1));
        expect(rig.api.verifications, hasLength(1));
        expect(rig.controller.canEnterGame, isTrue);
      },
    );

    test(
      'two registrations share one request and cannot create two profiles',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        final registration = _Gate<AuthAuthenticatedResult>();
        rig.api.onRegister = registration.call;
        final first = rig.controller.register('Nhà Thám Hiểm');
        final second = rig.controller.register('Tên khác');
        await registration.entered;
        expect(rig.api.registrations, hasLength(1));
        registration.complete(_authenticated());
        await Future.wait([first, second]);
        expect(rig.api.registrations, hasLength(1));
        expect(rig.controller.user!.username, 'Nhà Thám Hiểm');
      },
    );

    test(
      'two restores share a pending me without connecting the wallet',
      () async {
        final rig = _Rig();
        final reading = _Gate<AuthMeResponse>();
        rig.api.onMe = reading.call;
        final first = rig.controller.restoreSession();
        final second = rig.controller.restoreSession();
        await reading.entered;
        expect(rig.calls, ['api.me']);
        reading.complete(_me());
        await Future.wait([first, second]);
        expect(rig.calls.where((call) => call == 'api.me'), hasLength(1));
        expect(rig.wallet.connectCalls, 0);
      },
    );

    test(
      'old me completes after logout: it is revoked and never restores play',
      () async {
        final rig = _Rig();
        final reading = _Gate<AuthMeResponse>();
        rig.api.onMe = reading.call;
        final restoring = rig.controller.restoreSession();
        await reading.entered;
        final loggingOut = rig.controller.logout();
        _expectLocked(rig.controller);
        reading.complete(_me(csrf: _rotatedCsrf));
        await Future.wait([restoring, loggingOut]);
        _expectLocked(rig.controller);
        expect(rig.api.logouts, [_rotatedCsrf]);
        expect(rig.controller.status, AuthStatus.unauthenticated);
      },
    );

    test(
      'late register after wallet change revokes the rotated credential',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        final registration = _Gate<AuthAuthenticatedResult>();
        rig.api.onRegister = registration.call;
        final task = rig.controller.register('Nhà Thám Hiểm');
        await registration.entered;
        rig.wallet.accounts = [_walletB];
        rig.wallet.emit(MetamaskSiweEventType.accountsChanged);
        registration.complete(_authenticated(csrf: _rotatedCsrf));
        await task;
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.api.logouts, [_rotatedCsrf]);
      },
    );

    test(
      'reentrant logout from a notifier prevents the next wallet RPC',
      () async {
        final rig = _Rig();
        rig.controller.addListener(() {
          if (rig.controller.status == AuthStatus.connectingWallet) {
            unawaited(rig.controller.logout());
          }
        });
        final task = rig.controller.connectAndSignIn();
        await task;
        await rig.drainCleanup();
        expect(rig.wallet.connectCalls, 0);
        _expectLocked(rig.controller);
      },
    );
  });

  group('logout and uncertain HTTP outcomes', () {
    test(
      'logout locks before HTTP completes and removes authority after success',
      () async {
        final rig = _Rig();
        await rig.controller.connectAndSignIn();
        final revocation = _Gate<void>();
        rig.api.onLogout = revocation.call;
        final first = rig.controller.logout();
        final second = rig.controller.logout();
        _expectLocked(rig.controller);
        expect(rig.controller.status, AuthStatus.loggingOut);
        expect(rig.controller.isLoading, isTrue);
        await revocation.entered;
        expect(rig.api.logouts, [_sessionCsrf]);
        revocation.complete(null);
        await Future.wait([first, second]);
        expect(rig.controller.status, AuthStatus.unauthenticated);
        expect(rig.controller.logoutPending, isFalse);
        expect(rig.controller.serverSessionMayBeActive, isFalse);
        expect(rig.controller.walletAddress, isNull);
        expect(rig.controller.expiresAt, isNull);
        expect(rig.wallet.disposeCalls, 0);
        expect(rig.wallet.connectCalls, 1);
      },
    );

    test(
      'logout failure retains uncertainty and restore performs cleanup only',
      () async {
        final rig = _Rig();
        await rig.controller.connectAndSignIn();
        rig.api.onLogout = () => throw const AuthApiException(
          AuthApiErrorKind.network,
          outcomeUncertain: true,
        );
        await rig.controller.logout();
        expect(rig.controller.status, AuthStatus.error);
        expect(rig.controller.logoutPending, isTrue);
        expect(rig.controller.serverSessionMayBeActive, isTrue);
        _expectLocked(rig.controller);
        rig.api.onLogout = null;
        await rig.controller.restoreSession();
        expect(rig.controller.logoutPending, isFalse);
        _expectLocked(rig.controller);
        expect(rig.api.logouts, [_sessionCsrf, _sessionCsrf]);
      },
    );

    test(
      'a second logout after known success handles absent me idempotently',
      () async {
        final rig = _Rig();
        await rig.controller.connectAndSignIn();
        await rig.controller.logout();
        rig.api.onMe = () =>
            throw const AuthApiException(AuthApiErrorKind.unauthenticated);
        await rig.controller.logout();
        expect(rig.api.logouts, [_sessionCsrf]);
        expect(rig.controller.status, AuthStatus.unauthenticated);
        expect(rig.controller.logoutPending, isFalse);
        _expectLocked(rig.controller);
      },
    );

    test('uncertain verify reconciles current me then revokes, never retries nonce', () async {
      final rig = _Rig();
      rig.api.onVerify = () => throw const AuthApiException(
        AuthApiErrorKind.timeout,
        outcomeUncertain: true,
      );
      rig.api.meResult = _me(csrf: _rotatedCsrf);
      await rig.controller.connectAndSignIn();
      await rig.drainCleanup();
      expect(rig.api.verifications, hasLength(1));
      expect(rig.api.logouts, [_rotatedCsrf]);
      _expectLocked(rig.controller);
    });

    test(
      'underlying mutationPending blocks new HTTP and wallet operations',
      () async {
        final rig = _Rig();
        rig.api.pending = true;
        await rig.controller.connectAndSignIn();
        expect(rig.calls, isEmpty);
        expect(rig.controller.logoutPending, isTrue);
        await rig.controller.restoreSession();
        await rig.controller.register('Nhà Thám Hiểm');
        expect(rig.calls, isEmpty);
        rig.api.pending = false;
        rig.api.meResult = _me(csrf: _rotatedCsrf);
        await rig.controller.logout();
        expect(rig.calls, ['api.me', 'api.logout']);
        expect(rig.api.logouts, [_rotatedCsrf]);
        _expectLocked(rig.controller);
      },
    );

    test(
      'lost grant CSRF plus me 401 is not proof that a cookie was revoked',
      () async {
        final rig = _Rig();
        rig.api.onVerify = () => throw const AuthApiException(
          AuthApiErrorKind.timeout,
          outcomeUncertain: true,
        );
        rig.api.onMe = () => throw const AuthApiException(
          AuthApiErrorKind.unauthenticated,
          statusCode: 401,
        );
        await rig.controller.connectAndSignIn();
        await rig.drainCleanup();
        expect(rig.controller.errorCode, 'GRANT_STATE_UNKNOWN');
        expect(rig.controller.logoutPending, isTrue);
        expect(rig.controller.serverSessionMayBeActive, isTrue);
        expect(rig.api.logouts, isEmpty);
        _expectLocked(rig.controller);
      },
    );

    test(
      'stale register timeout cannot reuse the old grant CSRF to claim logout',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        final registration = _Gate<AuthAuthenticatedResult>();
        rig.api.onRegister = registration.call;
        rig.api.onMe = () =>
            throw const AuthApiException(AuthApiErrorKind.unauthenticated);
        final task = rig.controller.register('Nhà Thám Hiểm');
        await registration.entered;
        rig.wallet.emit(MetamaskSiweEventType.chainChanged);
        registration.fail(
          const AuthApiException(
            AuthApiErrorKind.timeout,
            outcomeUncertain: true,
          ),
        );
        await task;
        await rig.drainCleanup();
        expect(rig.controller.errorCode, 'GRANT_STATE_UNKNOWN');
        expect(rig.api.logouts, isEmpty);
        expect(rig.controller.logoutPending, isTrue);
        _expectLocked(rig.controller);
      },
    );
  });

  group('expiry, periodic checks and disposal', () {
    test(
      'absolute expiry denies gameplay even before a delayed timer fires',
      () async {
        final rig = _Rig();
        await rig.controller.connectAndSignIn();
        rig.time = _sessionExpiry.subtract(const Duration(microseconds: 1));
        expect(rig.controller.canEnterGame, isTrue);
        rig.time = _sessionExpiry;
        expect(rig.controller.canEnterGame, isFalse);
        rig.timers.last.fire();
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.api.logouts, [_sessionCsrf]);
        expect(rig.controller.errorCode, 'SESSION_EXPIRED');
      },
    );

    test(
      'periodic me is at most 60 seconds and uses passive wallet checks',
      () async {
        final rig = _Rig();
        await rig.controller.connectAndSignIn();
        expect(rig.timers.last.delay, const Duration(seconds: 60));
        final reading = _Gate<AuthMeResponse>();
        rig.api.onMe = reading.call;
        rig.timers.last.fire();
        await reading.entered;
        _expectLocked(rig.controller);
        reading.complete(_me());
        await rig.controller
            .restoreSession(); // Coalesces with the timer's operation.
        expect(rig.controller.canEnterGame, isTrue);
        expect(rig.wallet.connectCalls, 1);
        expect(rig.wallet.signatures, hasLength(1));
        expect(rig.calls.where((call) => call == 'api.me'), hasLength(2));
      },
    );

    test(
      'short remaining lifetime schedules expiry earlier than the next minute',
      () async {
        final rig = _Rig();
        final expiry = _start.add(const Duration(seconds: 12));
        rig.api.verifyResult = _authenticated(expires: expiry);
        rig.api.meResult = _me(expires: expiry);
        await rig.controller.connectAndSignIn();
        expect(rig.timers.last.delay, const Duration(seconds: 12));
      },
    );

    test(
      'registration timer only checks expiry and never calls authenticated me',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        rig.time = _start.add(const Duration(seconds: 60));
        rig.timers.last.fire();
        expect(rig.controller.status, AuthStatus.registrationRequired);
        expect(rig.calls, isNot(contains('api.me')));
        rig.time = _grantExpiry;
        rig.timers.last.fire();
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.api.logouts, [_grantCsrf]);
      },
    );

    test(
      'a no-op login while authenticated does not invalidate the expiry timer',
      () async {
        final rig = _Rig();
        await rig.controller.connectAndSignIn();
        await rig.controller.connectAndSignIn();
        expect(rig.wallet.connectCalls, 1);
        rig.time = _sessionExpiry;
        rig.timers.last.fire();
        await rig.drainCleanup();
        expect(rig.controller.status, AuthStatus.unauthenticated);
      },
    );

    test(
      'dispose while me is pending never notifies or restores old state',
      () async {
        final rig = _Rig();
        final reading = _Gate<AuthMeResponse>();
        rig.api.onMe = reading.call;
        var notifications = 0;
        rig.controller.addListener(() => notifications++);
        final task = rig.controller.restoreSession();
        await reading.entered;
        rig.controller.dispose();
        final before = notifications;
        reading.complete(_me());
        await task;
        rig.wallet.emit(MetamaskSiweEventType.accountsChanged);
        expect(notifications, before);
        expect(rig.wallet.cancellations, 1);
        _expectLocked(rig.controller);
      },
    );

    test(
      'post-dispose actions are inert and do not call either dependency',
      () async {
        final rig = _Rig();
        rig.controller.dispose();
        await rig.controller.connectAndSignIn();
        await rig.controller.register('Nhà Thám Hiểm');
        await rig.controller.restoreSession();
        await rig.controller.logout();
        expect(rig.calls, isEmpty);
        _expectLocked(rig.controller);
      },
    );

    test('dispose cancels timers and subscription without owning injected adapters', () async {
      final rig = _Rig();
      await rig.controller.restoreSession();
      rig.controller.dispose();
      expect(rig.timers.every((timer) => !timer.isActive), isTrue);
      expect(rig.wallet.cancellations, 1);
      expect(rig.wallet.disposeCalls, 0);
      expect(rig.api.closeCalls, 0);
      expect(
        rig.api.logouts,
        isEmpty,
      ); // Local disposal does not revoke a server cookie.
    });

    test('explicit ownership disposes both dependencies exactly once', () {
      final rig = _Rig(ownsDependencies: true);
      rig.controller.dispose();
      rig.controller.dispose();
      expect(rig.wallet.disposeCalls, 1);
      expect(rig.api.closeCalls, 1);
    });
  });

  group('safe errors and privacy', () {
    test('missing MetaMask fails before connect or HTTP', () async {
      final rig = _Rig();
      rig.wallet.available = false;
      await rig.controller.connectAndSignIn();
      expect(rig.calls, ['wallet.available']);
      expect(rig.controller.status, AuthStatus.error);
      expect(rig.controller.errorCode, 'WALLET_notInstalled');
      _expectLocked(rig.controller);
    });

    for (final stage in ['connect', 'sign']) {
      for (final code in [
        MetamaskSiweErrorCode.userRejected,
        MetamaskSiweErrorCode.requestPending,
      ]) {
        test('$stage: $code keeps gameplay locked', () async {
          final rig = _Rig();
          final error = MetamaskSiweException(code);
          if (stage == 'connect') {
            rig.wallet.onConnect = () => throw error;
          } else {
            rig.wallet.onSign = () => throw error;
          }
          await rig.controller.connectAndSignIn();
          _expectLocked(rig.controller);
          expect(
            rig.controller.errorCode,
            code == MetamaskSiweErrorCode.userRejected
                ? 'WALLET_REJECTED'
                : 'WALLET_requestPending',
          );
          expect(rig.api.verifications, isEmpty);
          _expectSafeDiagnostic(rig.controller);
        });
      }
    }

    final errors = <String, AuthApiException>{
      'backend unavailable or offline': const AuthApiException(
        AuthApiErrorKind.network,
      ),
      'timeout': const AuthApiException(AuthApiErrorKind.timeout),
      'challenge expired': const AuthApiException(
        AuthApiErrorKind.expired,
        code: 'CHALLENGE_EXPIRED',
      ),
      'signature invalid': const AuthApiException(
        AuthApiErrorKind.unauthenticated,
        code: 'SIGNATURE_INVALID',
      ),
      'nonce used': const AuthApiException(
        AuthApiErrorKind.conflict,
        code: 'CHALLENGE_USED',
      ),
      'CSRF invalid': const AuthApiException(
        AuthApiErrorKind.forbidden,
        code: 'CSRF_INVALID',
      ),
      'Origin forbidden': const AuthApiException(
        AuthApiErrorKind.forbidden,
        code: 'ORIGIN_FORBIDDEN',
      ),
      'chain forbidden': const AuthApiException(
        AuthApiErrorKind.validation,
        code: 'CHAIN_NOT_ALLOWED',
      ),
      'session expired': const AuthApiException(
        AuthApiErrorKind.unauthenticated,
        code: 'SESSION_EXPIRED',
      ),
      'invalid response': const AuthApiException(
        AuthApiErrorKind.invalidResponse,
      ),
      'server unavailable': const AuthApiException(AuthApiErrorKind.server),
    };
    for (final entry in errors.entries) {
      test('${entry.key} never authenticates or retries verify', () async {
        final rig = _Rig();
        rig.api.onVerify = () => throw entry.value;
        await rig.controller.connectAndSignIn();
        await rig.drainCleanup();
        _expectLocked(rig.controller);
        expect(rig.controller.errorMessage, isNotEmpty);
        expect(rig.api.verifications, hasLength(1));
        _expectSafeDiagnostic(rig.controller);
      });
    }

    test('an untrusted exception cannot leak SIWE, signature or CSRF in diagnostics', () async {
      final rig = _Rig();
      rig.api.onVerify = () =>
          throw StateError('$_message $_signature $_sessionCsrf');
      await rig.controller.connectAndSignIn();
      expect(rig.controller.errorCode, 'AUTH_UNEXPECTED');
      _expectLocked(rig.controller);
      _expectSafeDiagnostic(rig.controller);
    });

    test(
      'login and registration do not persist test secrets in browser storage',
      () async {
        final rig = _Rig();
        await rig.enterRegistration();
        await rig.controller.register('Nhà Thám Hiểm');
        final stored = [
          ..._storageValues(_localStorage),
          ..._storageValues(_sessionStorage),
        ];
        for (final sensitive in [
          _sessionCsrf,
          _grantCsrf,
          _signature,
          _message,
        ]) {
          expect(stored.any((value) => value.contains(sensitive)), isFalse);
        }
        _expectSafeDiagnostic(rig.controller);
      },
    );
  });

  group('in-memory HTTP boundary with the real AuthApiClient', () {
    test(
      'register JSON contains only username and sends the grant CSRF header',
      () async {
        final requests = <http.Request>[];
        final transport = MockClient((request) async {
          requests.add(request);
          final Object body;
          final int status;
          switch (request.url.path) {
            case '/api/auth/challenge':
              body = _challengeJson();
              status = 201;
            case '/api/auth/verify':
              body = _grantJson();
              status = 200;
            case '/api/auth/register':
              expect(jsonDecode(request.body), {'username': 'Nhà Thám Hiểm'});
              expect(request.headers['X-CSRF-Token'], _grantCsrf);
              body = _authenticatedJson();
              status = 201;
            case '/api/me':
              body = {..._meJson(), 'chain_id': 31337};
              status = 200;
            default:
              throw StateError('Unexpected mocked endpoint');
          }
          return http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json'},
          );
        });
        final api = AuthApiClient(client: transport);
        addTearDown(() {
          api.close();
          transport.close();
        });
        final rig = _Rig(transport: api);
        await rig.controller.connectAndSignIn();
        await rig.controller.register('Nhà Thám Hiểm');
        expect(requests.map((request) => request.url.path), [
          '/api/auth/challenge',
          '/api/auth/verify',
          '/api/auth/register',
          '/api/me',
        ]);
        expect(rig.controller.canEnterGame, isTrue);
      },
    );

    test('malformed me JSON is rejected by the real decoder without raw error exposure', () async {
      final transport = MockClient(
        (_) async => http.Response(
          '{"user": "$_sessionCsrf"',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final api = AuthApiClient(client: transport);
      addTearDown(() {
        api.close();
        transport.close();
      });
      final rig = _Rig(transport: api);
      await rig.controller.restoreSession();
      _expectLocked(rig.controller);
      expect(rig.controller.status, AuthStatus.error);
      expect(rig.controller.errorCode, 'API_invalidResponse');
      _expectSafeDiagnostic(rig.controller);
    });
  });
}
