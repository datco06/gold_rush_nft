/// AuthGate transitively imports Web-only Auth dependencies. Run:
/// flutter test --platform chrome test/auth/auth_gate_test.dart
///
/// The real controller, Welcome and Register widgets are exercised. Only
/// external wallet/API operations are fake; no HTTP, extension, RPC, Database,
/// cookie or browser storage is accessed. These tests prove UI gating and a
/// disposable test subtree's lifecycle, not backend authorization or Flame's
/// audio/request cleanup. Test credentials/signatures are never printed.
@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/auth/auth_api_client.dart';
import 'package:gold_rush/auth/auth_controller.dart';
import 'package:gold_rush/auth/metamask_siwe_web.dart';
import 'package:gold_rush/auth/ui/auth_gate.dart';
import 'package:gold_rush/auth/ui/register_screen.dart';
import 'package:gold_rush/auth/ui/welcome_screen.dart';

const _walletA = '0x1111111111111111111111111111111111111111';
const _walletB = '0x2222222222222222222222222222222222222222';
const _userId = '80574202-05bd-4577-8edf-d480b37cf9a2';
const _challengeId = 'c21ad4be-b54e-4ecb-9c99-62dbdcedc677';
const _credential = 'dummy-test-credential';
final _chain = BigInt.from(31337);
// Fixed future dates keep RegisterScreen's independent real-clock expiry check
// from interfering with controller tests. No expiry test waits on wall time.
final _start = DateTime.utc(2099, 1, 1);
final _expires = _start.add(const Duration(hours: 8));
final _grantExpires = _start.add(const Duration(minutes: 10));
final _signature = '0x${'1' * 130}'; // Not a real signed message.

Map<String, Object?> _user(String wallet) => {
  'id': wallet == _walletA ? _userId : _challengeId,
  'wallet_address': wallet,
  'username': wallet == _walletA ? 'Nhà Thám Hiểm' : 'Người Chơi Hai',
  'avatar': 'george',
  'created_at': _start.toIso8601String(),
};

AuthMeResponse _me({String wallet = _walletA, BigInt? chain}) =>
    AuthMeResponse.fromJson({
      'user': _user(wallet),
      'chain_id': chain ?? _chain,
      'expires_at': _expires.toIso8601String(),
      'csrf_token': _credential,
    });

AuthAuthenticatedResult _authenticated({String wallet = _walletA}) =>
    AuthAuthenticatedResult.fromJson({
      'status': 'authenticated',
      'user': _user(wallet),
      'expires_at': _expires.toIso8601String(),
      'csrf_token': _credential,
    });

AuthRegistrationRequired _registration() => AuthRegistrationRequired.fromJson({
  'status': 'registration_required',
  'wallet_address': _walletA,
  'expires_at': _grantExpires.toIso8601String(),
  'csrf_token': _credential,
});

/// Explicit rendezvous points control races without sleep or polling. The
/// entered Future means the production controller reached that dependency.
class _Gate<T> {
  final _entered = Completer<void>();
  final _result = Completer<T>();
  Future<void> get entered => _entered.future;
  Future<T> call() {
    if (!_entered.isCompleted) _entered.complete();
    return _result.future;
  }

  void complete(T result) => _result.complete(result);
  void fail(Object error) => _result.completeError(error);
}

class _Wallet implements AuthWallet {
  _Wallet() {
    _events = StreamController<MetamaskSiweEventType>.broadcast(
      sync: true,
      onListen: () => subscriptions++,
      onCancel: () => cancellations++,
    );
  }

  late final StreamController<MetamaskSiweEventType> _events;
  final calls = <String>[];
  List<String> accounts = [_walletA];
  BigInt chain = _chain;
  bool available = true;
  int subscriptions = 0;
  int cancellations = 0;
  int disposeCalls = 0;
  Future<MetamaskWalletConnection> Function()? connecting;
  Future<String> Function()? signing;

  @override
  Stream<MetamaskSiweEventType> get events => _events.stream;
  @override
  Future<bool> checkAvailability() async {
    calls.add('available');
    return available;
  }

  @override
  Future<MetamaskWalletConnection> connect() async {
    calls.add('connect');
    return connecting == null
        ? MetamaskWalletConnection(address: accounts.first, chainId: chain)
        : await connecting!();
  }

  @override
  Future<List<String>> getAccounts() async {
    calls.add('accounts');
    return List.of(accounts);
  }

  @override
  Future<BigInt> getChainId() async {
    calls.add('chain');
    return chain;
  }

  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) async {
    calls.add('sign');
    return signing == null ? _signature : await signing!();
  }

  void emit(MetamaskSiweEventType type) => _events.add(type);
  Future<void> close() => _events.close();
  @override
  void dispose() {
    disposeCalls++;
    unawaited(close());
  }
}

/// No constructor/HTTP transport from AuthApiClient is invoked. Captured data
/// is limited to non-secret call names, name input and boolean comparisons.
class _Api implements AuthApiClient {
  final calls = <String>[];
  final usernames = <String>[];
  bool pending = false;
  bool logoutUsedExpectedCredential = true;
  int closeCalls = 0;
  AuthVerifyResult verifyResult = _authenticated();
  AuthMeResponse meResult = _me();
  Future<AuthChallengeResponse> Function()? challenging;
  Future<AuthVerifyResult> Function()? verifying;
  Future<AuthAuthenticatedResult> Function()? registering;
  Future<AuthMeResponse> Function()? reading;
  Future<void> Function()? revoking;

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
    calls.add('challenge');
    return challenging == null ? challenge() : await challenging!();
  }

  AuthChallengeResponse challenge() => AuthChallengeResponse.fromJson({
    'challenge_id': _challengeId,
    'message': 'Gold Rush test message; signature verification is faked.',
    'expires_at': _start.add(const Duration(minutes: 5)).toIso8601String(),
  });

  @override
  Future<AuthVerifyResult> verify({
    required String challengeId,
    required String message,
    required String signature,
  }) async {
    calls.add('verify');
    return verifying == null ? verifyResult : await verifying!();
  }

  @override
  Future<AuthAuthenticatedResult> register({
    required String username,
    required String csrfToken,
  }) async {
    calls.add('register');
    usernames.add(username);
    return registering == null ? _authenticated() : await registering!();
  }

  @override
  Future<AuthMeResponse> getMe() async {
    calls.add('me');
    return reading == null ? meResult : await reading!();
  }

  @override
  Future<void> logout({required String csrfToken}) async {
    calls.add('logout');
    logoutUsedExpectedCredential &= csrfToken == _credential;
    if (revoking != null) await revoking!();
  }

  @override
  void close() => closeCalls++;
  @override
  void dispose() => close();
}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  int _ticks = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _ticks;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _ticks++;
    callback();
  }
}

/// Counts public lifecycle calls while retaining the REAL authentication
/// state machine and canEnterGame. Only a defensive exception test opts into
/// throwing from restore; no test fabricates an authenticated state/getter.
class _ObservedController extends AuthController {
  _ObservedController({
    required super.wallet,
    required super.api,
    required super.clock,
    required super.timerFactory,
  });
  int addedListeners = 0;
  int removedListeners = 0;
  int disposeCalls = 0;
  int restoreCalls = 0;
  bool throwOnRestore = false;
  @override
  void addListener(VoidCallback listener) {
    addedListeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removedListeners++;
    super.removeListener(listener);
  }

  @override
  Future<void> restoreSession() {
    restoreCalls++;
    if (throwOnRestore) throw StateError('Test restore exception');
    return super.restoreSession();
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

class _Rig {
  _Rig() {
    controller = _ObservedController(
      wallet: wallet,
      api: api,
      clock: () => time,
      timerFactory: (delay, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(() async {
      controller.dispose();
      await wallet.close();
      expect(timers.where((timer) => timer.isActive), isEmpty);
    });
  }

  final wallet = _Wallet();
  final api = _Api();
  final timers = <_ManualTimer>[];
  late final _ObservedController controller;
  DateTime time = _start;
  Future<void> drainCleanup() async {
    if (controller.logoutPending) await controller.logout();
  }

  Future<void> registration() async {
    api.verifyResult = _registration();
    await controller.connectAndSignIn();
    expect(controller.status, AuthStatus.registrationRequired);
  }

  void absentSession() {
    api.reading = () async => throw const AuthApiException(
      AuthApiErrorKind.unauthenticated,
      statusCode: 401,
    );
  }
}

class _GameLog {
  _GameLog() {
    addTearDown(events.close);
  }
  int builderCalls = 0;
  int mounts = 0;
  int builds = 0;
  int disposals = 0;
  int timerTicks = 0;
  int streamEvents = 0;
  int taps = 0;
  final events = StreamController<int>.broadcast(sync: true);
  final mountedIdentities = <String>[];
}

class _Gameplay extends StatefulWidget {
  const _Gameplay(this.log, {required this.identity});
  final _GameLog log;
  final String identity;
  @override
  State<_Gameplay> createState() => _GameplayState();
}

class _GameplayState extends State<_Gameplay> {
  late final Timer _timer;
  late final StreamSubscription<int> _subscription;
  @override
  void initState() {
    super.initState();
    widget.log.mounts++;
    widget.log.mountedIdentities.add(widget.identity);
    _timer = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => widget.log.timerTicks++,
    );
    _subscription = widget.log.events.stream.listen(
      (_) => widget.log.streamEvents++,
    );
  }

  @override
  Widget build(BuildContext context) {
    widget.log.builds++;
    return TextButton(
      key: const ValueKey('protected-gameplay'),
      onPressed: () => widget.log.taps++,
      child: Text('Protected ${widget.identity}'),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    unawaited(_subscription.cancel());
    widget.log.disposals++;
    super.dispose();
  }
}

Finder get _game => find.byType(_Gameplay, skipOffstage: false);
void _expectNeverBuilt(_GameLog log) {
  expect(_game, findsNothing);
  expect(log.builderCalls, 0);
  expect(log.mounts, 0);
}

/// Every mount/rebuild uses the same Gate key and stable builder by default.
/// Unmount the UI before closing streams/controllers. Restore physical metrics
/// and the platform lifecycle for the next independent test.
class _Harness {
  _Harness(this.tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  final WidgetTester tester;
  final _builders = <_GameLog, WidgetBuilder>{};
  Future<void> mount(
    _Rig rig,
    _GameLog log, {
    bool restore = true,
    bool resume = true,
    bool retainGame = false,
    Size size = const Size(1366, 768),
    double textScale = 1,
    WidgetBuilder? builder,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final stableBuilder = _builders.putIfAbsent(
      log,
      () => (context) {
        log.builderCalls++;
        return _Gameplay(log, identity: rig.controller.walletAddress!);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: AuthGate(
          key: const ValueKey('gate-under-test'),
          controller: rig.controller,
          authenticatedBuilder: builder ?? stableBuilder,
          restoreOnMount: restore,
          recheckOnResume: resume,
          retainGameDuringSessionCheck: retainGame,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }
}

void main() {
  group('integrated game continuity', () {
    testWidgets('passive recheck hides existing game and preserves its State', (
      tester,
    ) async {
      final rig = _Rig();
      final log = _GameLog();
      final host = _Harness(tester);
      await rig.controller.restoreSession();
      await host.mount(rig, log, retainGame: true);
      final reading = _Gate<AuthMeResponse>();
      rig.api.reading = reading.call;
      rig.timers.last.fire();
      await reading.entered;
      await tester.pump();
      expect(rig.controller.canEnterGame, isFalse);
      expect(find.byType(_Gameplay), findsNothing);
      expect(_game, findsOneWidget); // Offstage, never interactive.
      expect(log.disposals, 0);
      final task = rig.controller.restoreSession();
      reading.complete(_me());
      await task;
      await tester.pumpAndSettle();
      expect(find.byType(_Gameplay), findsOneWidget);
      expect(log.mounts, 1);
      expect(log.disposals, 0);
    });

    testWidgets('401 during retained recheck destroys the game', (
      tester,
    ) async {
      final rig = _Rig();
      final log = _GameLog();
      final host = _Harness(tester);
      await rig.controller.restoreSession();
      await host.mount(rig, log, retainGame: true);
      rig.absentSession();
      rig.timers.last.fire();
      await rig.controller.restoreSession();
      await tester.pumpAndSettle();
      expect(_game, findsNothing);
      expect(log.disposals, 1);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets(
      'wallet event during retained recheck destroys game and ignores late me',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log, retainGame: true);
        final reading = _Gate<AuthMeResponse>();
        rig.api.reading = reading.call;
        rig.timers.last.fire();
        await reading.entered;
        final task = rig.controller.restoreSession();
        rig.wallet.emit(MetamaskSiweEventType.chainChanged);
        await tester.pump();
        expect(_game, findsNothing);
        expect(log.disposals, 1);
        reading.complete(_me());
        await task;
        await rig.drainCleanup();
        await tester.pumpAndSettle();
        expect(_game, findsNothing);
        expect(rig.controller.canEnterGame, isFalse);
      },
    );
  });
  group('startup and restore', () {
    testWidgets(
      'initial with restore disabled never creates gameplay or requests auth',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await host.mount(rig, log, restore: false);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('auth-gate-status')), findsOneWidget);
        expect(rig.api.calls, isEmpty);
        expect(rig.wallet.calls, isEmpty);
        _expectNeverBuilt(log);
      },
    );

    testWidgets(
      'default restore runs once; rebuilds after 401 remain Welcome',
      (tester) async {
        final rig = _Rig()..absentSession();
        final log = _GameLog();
        final host = _Harness(tester);
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        expect(rig.controller.restoreCalls, 1);
        expect(rig.api.calls, ['me']);
        expect(rig.wallet.calls, isEmpty);
        _expectNeverBuilt(log);
      },
    );

    testWidgets(
      'checkingSession stays locked until backend and passive wallet reads succeed',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        final reading = _Gate<AuthMeResponse>();
        rig.api.reading = reading.call;
        await host.mount(rig, log);
        await reading.entered;
        expect(rig.controller.status, AuthStatus.checkingSession);
        _expectNeverBuilt(log);
        reading.complete(_me());
        await tester.pumpAndSettle();
        expect(_game, findsOneWidget);
        expect(log.mounts, 1);
        expect(rig.wallet.calls, isNot(contains('connect')));
        expect(rig.wallet.calls, isNot(contains('sign')));
      },
    );

    testWidgets('pending parent restore is not restarted by the Gate', (
      tester,
    ) async {
      final rig = _Rig();
      final log = _GameLog();
      final host = _Harness(tester);
      final reading = _Gate<AuthMeResponse>();
      rig.api.reading = reading.call;
      final task = rig.controller.restoreSession();
      await reading.entered;
      await host.mount(rig, log);
      _expectNeverBuilt(log);
      expect(rig.controller.restoreCalls, 1);
      expect(rig.api.calls, ['me']);
      reading.complete(_me());
      await task;
      await tester.pumpAndSettle();
      expect(log.mounts, 1);
    });

    testWidgets(
      'already unauthenticated parent state is preserved without another restore',
      (tester) async {
        final rig = _Rig()..absentSession();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(rig.controller.restoreCalls, 1);
        _expectNeverBuilt(log);
      },
    );

    testWidgets(
      'authenticated parent controller immediately builds game without redoing me',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        final calls = List.of(rig.api.calls);
        await host.mount(rig, log);
        expect(_game, findsOneWidget);
        expect(log.mounts, 1);
        expect(rig.api.calls, calls);
        expect(rig.controller.restoreCalls, 1);
      },
    );

    testWidgets(
      'parent can complete restore after mounting with automatic restore disabled',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await host.mount(rig, log, restore: false);
        _expectNeverBuilt(log);
        await rig.controller.restoreSession();
        await tester.pumpAndSettle();
        expect(log.mounts, 1);
        expect(_game, findsOneWidget);
      },
    );

    testWidgets(
      'enabling restoreOnMount for an initial controller schedules exactly one restore',
      (tester) async {
        final rig = _Rig()..absentSession();
        final log = _GameLog();
        final host = _Harness(tester);
        await host.mount(rig, log, restore: false);
        expect(rig.controller.restoreCalls, 0);
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        await host.mount(rig, log);
        expect(rig.controller.restoreCalls, 1);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        _expectNeverBuilt(log);
      },
    );

    for (final mismatch in ['wallet', 'chain', 'no account', 'no provider']) {
      testWidgets('valid backend session with $mismatch cannot mount game', (
        tester,
      ) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        if (mismatch == 'wallet') rig.wallet.accounts = [_walletB];
        if (mismatch == 'chain') rig.wallet.chain = BigInt.one;
        if (mismatch == 'no account') rig.wallet.accounts = [];
        if (mismatch == 'no provider') rig.wallet.available = false;
        await host.mount(rig, log);
        await rig.drainCleanup();
        await tester.pumpAndSettle();
        _expectNeverBuilt(log);
        expect(rig.api.calls, contains('logout'));
        expect(rig.wallet.calls, isNot(contains('connect')));
      });
    }

    testWidgets(
      'restore network failure opens safe error UI without claiming revocation',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        rig.api.reading = () async =>
            throw const AuthApiException(AuthApiErrorKind.network);
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(rig.controller.serverSessionMayBeActive, isTrue);
        _expectNeverBuilt(log);
      },
    );
  });

  group('login and registration', () {
    testWidgets(
      'connect, challenge, signature, verify and me each remain locked until complete',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        final connecting = _Gate<MetamaskWalletConnection>();
        final challenging = _Gate<AuthChallengeResponse>();
        final signing = _Gate<String>();
        final verifying = _Gate<AuthVerifyResult>();
        final reading = _Gate<AuthMeResponse>();
        rig.wallet.connecting = connecting.call;
        rig.api.challenging = challenging.call;
        rig.wallet.signing = signing.call;
        rig.api.verifying = verifying.call;
        rig.api.reading = reading.call;
        final task = rig.controller.connectAndSignIn();
        await connecting.entered;
        await host.mount(rig, log);
        expect(rig.controller.status, AuthStatus.connectingWallet);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        _expectNeverBuilt(log);
        connecting.complete(
          MetamaskWalletConnection(address: _walletA, chainId: _chain),
        );
        await challenging.entered;
        await tester.pump();
        expect(rig.controller.status, AuthStatus.requestingChallenge);
        _expectNeverBuilt(log);
        challenging.complete(rig.api.challenge());
        await signing.entered;
        await tester.pump();
        expect(rig.controller.status, AuthStatus.awaitingSignature);
        _expectNeverBuilt(log);
        signing.complete(_signature);
        await verifying.entered;
        await tester.pump();
        expect(rig.controller.status, AuthStatus.verifying);
        _expectNeverBuilt(log);
        verifying.complete(_authenticated());
        await reading.entered;
        await tester.pump();
        _expectNeverBuilt(log);
        reading.complete(_me());
        await task;
        await tester.pumpAndSettle();
        expect(_game, findsOneWidget);
        expect(log.mounts, 1);
      },
    );

    testWidgets('auth failure cannot call authenticatedBuilder', (
      tester,
    ) async {
      final rig = _Rig();
      final log = _GameLog();
      final host = _Harness(tester);
      rig.api.verifying = () async => throw const AuthApiException(
        AuthApiErrorKind.unauthenticated,
        code: 'SIGNATURE_INVALID',
      );
      await rig.controller.connectAndSignIn();
      await host.mount(rig, log);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      _expectNeverBuilt(log);
    });

    testWidgets(
      'registration grant opens real RegisterScreen without another restore',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.registration();
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        expect(find.byType(RegisterScreen), findsOneWidget);
        expect(rig.controller.restoreCalls, 0);
        _expectNeverBuilt(log);
      },
    );

    testWidgets(
      'registering and subsequent me are locked; only confirmed session opens game',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.registration();
        await host.mount(rig, log);
        final registering = _Gate<AuthAuthenticatedResult>();
        final reading = _Gate<AuthMeResponse>();
        rig.api.registering = registering.call;
        rig.api.reading = reading.call;
        final task = rig.controller.register('Nhà Thám Hiểm');
        await registering.entered;
        await tester.pump();
        expect(find.byType(RegisterScreen), findsOneWidget);
        expect(rig.controller.status, AuthStatus.registering);
        _expectNeverBuilt(log);
        registering.complete(_authenticated());
        await reading.entered;
        await tester.pump();
        _expectNeverBuilt(log);
        reading.complete(_me());
        await task;
        await tester.pumpAndSettle();
        expect(_game, findsOneWidget);
        expect(log.mounts, 1);
      },
    );

    testWidgets(
      'Register submit uses real controller and automatically transitions the Gate',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.registration();
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('register-username')),
          'Nhà Thám Hiểm',
        );
        await host.tap(find.byKey(const ValueKey('register-submit')));
        await tester.pumpAndSettle();
        expect(rig.api.usernames, ['Nhà Thám Hiểm']);
        expect(log.mounts, 1);
        expect(find.byType(RegisterScreen), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('duplicate username keeps registration and cannot open game', (
      tester,
    ) async {
      final rig = _Rig();
      final log = _GameLog();
      final host = _Harness(tester);
      await rig.registration();
      await host.mount(rig, log);
      rig.api.registering = () async => throw const AuthApiException(
        AuthApiErrorKind.conflict,
        code: 'USERNAME_TAKEN',
      );
      await rig.controller.register('Nhà Thám Hiểm');
      await tester.pumpAndSettle();
      expect(rig.controller.status, AuthStatus.registrationRequired);
      expect(find.byType(RegisterScreen), findsOneWidget);
      _expectNeverBuilt(log);
    });

    testWidgets(
      'Register back selects Welcome without logout; create-character reopens grant',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.registration();
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        final before = List.of(rig.api.calls);
        await host.tap(find.byKey(const ValueKey('register-back')));
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(rig.controller.status, AuthStatus.registrationRequired);
        expect(rig.api.calls, before);
        _expectNeverBuilt(log);
        await host.tap(find.byKey(const ValueKey('welcome-primary-action')));
        await tester.pumpAndSettle();
        expect(find.byType(RegisterScreen), findsOneWidget);
        expect(rig.api.calls, before);
      },
    );

    testWidgets('expired grant is locked and never opens gameplay', (
      tester,
    ) async {
      final rig = _Rig();
      final log = _GameLog();
      final host = _Harness(tester);
      await rig.registration();
      await host.mount(rig, log);
      rig.time = _grantExpires;
      rig.timers.last.fire();
      await rig.drainCleanup();
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(rig.controller.canEnterGame, isFalse);
      _expectNeverBuilt(log);
    });

    testWidgets(
      'expired grant cannot be bypassed by a captured create-character callback',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.registration();
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        await host.tap(find.byKey(const ValueKey('register-back')));
        await tester.pumpAndSettle();
        final callback = tester
            .widget<WelcomeScreen>(find.byType(WelcomeScreen))
            .onRegistrationRequired!;
        rig.time = _grantExpires;
        rig.timers.last.fire();
        await rig.drainCleanup();
        await callback();
        await tester.pumpAndSettle();
        _expectNeverBuilt(log);
        expect(find.byType(RegisterScreen), findsNothing);
      },
    );
  });

  group('authenticated builder and lifecycle', () {
    testWidgets(
      'builder receives mounted context under the existing MaterialApp',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        BuildContext? received;
        await host.mount(
          rig,
          log,
          builder: (context) {
            received = context;
            log.builderCalls++;
            expect(context.mounted, isTrue);
            expect(Theme.of(context).brightness, Brightness.dark);
            expect(MediaQuery.sizeOf(context), const Size(1366, 768));
            expect(Navigator.of(context), isNotNull);
            return _Gameplay(log, identity: _walletA);
          },
        );
        expect(received, isNotNull);
        expect(_game, findsOneWidget);
        expect(find.byType(MaterialApp), findsOneWidget);
        expect(log.mounts, 1);
        expect(log.builds, greaterThanOrEqualTo(1));
      },
    );

    testWidgets(
      'ordinary parent rebuild preserves game State and does not restore',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        final state = tester.state(_game);
        await host.mount(rig, log);
        await host.mount(rig, log);
        expect(identical(tester.state(_game), state), isTrue);
        expect(log.mounts, 1);
        expect(log.disposals, 0);
        expect(rig.controller.restoreCalls, 1);
        await host.tap(find.byKey(const ValueKey('protected-gameplay')));
        expect(log.taps, 1);
      },
    );

    for (final invalid in ['expired', 'transport mutation pending']) {
      testWidgets(
        'authenticated-looking status with $invalid cannot invoke builder',
        (tester) async {
          final rig = _Rig();
          final log = _GameLog();
          final host = _Harness(tester);
          await rig.controller.restoreSession();
          if (invalid == 'expired') rig.time = _expires;
          if (invalid == 'transport mutation pending') rig.api.pending = true;
          expect(rig.controller.status, AuthStatus.authenticated);
          expect(rig.controller.canEnterGame, isFalse);
          await host.mount(rig, log);
          _expectNeverBuilt(log);
        },
      );
    }

    for (final event in MetamaskSiweEventType.values) {
      testWidgets(
        '$event unmounts game and stops its disposable timer/stream',
        (tester) async {
          final rig = _Rig();
          final log = _GameLog();
          final host = _Harness(tester);
          await rig.controller.restoreSession();
          await host.mount(rig, log);
          rig.wallet.accounts = [_walletB];
          rig.wallet.emit(event);
          expect(rig.controller.canEnterGame, isFalse);
          await tester.pump();
          expect(_game, findsNothing);
          expect(log.disposals, 1);
          final ticks = log.timerTicks;
          final events = log.streamEvents;
          log.events.add(1);
          await rig.drainCleanup();
          // Advance fake time to test cancellation, not to wait for an auth result.
          await tester.pump(const Duration(milliseconds: 200));
          expect(log.timerTicks, ticks);
          expect(log.streamEvents, events);
          expect(log.mounts, 1);
          expect(find.byType(WelcomeScreen), findsOneWidget);
        },
      );
    }

    testWidgets(
      'loggingOut removes game while server revocation is still pending',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        final revoking = _Gate<void>();
        rig.api.revoking = revoking.call;
        final task = rig.controller.logout();
        await revoking.entered;
        await tester.pump();
        expect(_game, findsNothing);
        expect(log.disposals, 1);
        expect(find.text('ĐANG ĐĂNG XUẤT...'), findsOneWidget);
        expect(rig.controller.serverSessionMayBeActive, isTrue);
        revoking.complete(null);
        await task;
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(rig.api.logoutUsedExpectedCredential, isTrue);
      },
    );

    testWidgets(
      'logout network failure keeps game disposed and offers controller retry',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        rig.api.revoking = () async => throw const AuthApiException(
          AuthApiErrorKind.network,
          outcomeUncertain: true,
        );
        await rig.controller.logout();
        await tester.pumpAndSettle();
        expect(_game, findsNothing);
        expect(log.disposals, 1);
        expect(rig.controller.logoutPending, isTrue);
        expect(rig.controller.serverSessionMayBeActive, isTrue);
        expect(find.text('THỬ ĐĂNG XUẤT LẠI'), findsOneWidget);
        rig.api.revoking = null;
        await host.tap(find.byKey(const ValueKey('welcome-primary-action')));
        await tester.pumpAndSettle();
        expect(rig.controller.logoutPending, isFalse);
        expect(_game, findsNothing);
        expect(log.mounts, 1);
        expect(rig.wallet.calls, isNot(contains('connect')));
      },
    );

    testWidgets(
      'session expiry removes the old tree, not an overlay over a live game',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        rig.time = _expires;
        rig.timers.last.fire();
        await tester.pump();
        expect(_game, findsNothing);
        expect(log.disposals, 1);
        await rig.drainCleanup();
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(log.mounts, 1);
      },
    );

    testWidgets(
      'current periodic checkingSession disposes and later recreates gameplay',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        final reading = _Gate<AuthMeResponse>();
        rig.api.reading = reading.call;
        rig.timers.last.fire();
        await reading.entered;
        await tester.pump();
        expect(_game, findsNothing);
        expect(log.disposals, 1);
        expect(rig.controller.status, AuthStatus.checkingSession);
        final task = rig.controller.restoreSession();
        reading.complete(_me());
        await task;
        await tester.pumpAndSettle();
        expect(log.mounts, 2);
        // Deliberate regression documentation: periodic recheck currently resets
        // the gameplay subtree, even for the same valid server session.
      },
    );

    testWidgets(
      'loss and recovery between frames still replaces old game State',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        final oldState = tester.state(_game);
        await rig.controller.restoreSession();
        await tester.pumpAndSettle();
        expect(identical(tester.state(_game), oldState), isFalse);
        expect(log.disposals, 1);
        expect(log.mounts, 2);
      },
    );

    testWidgets(
      'wallet B receives a fresh game State instead of wallet A profile',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        rig.wallet.accounts = [_walletB];
        rig.wallet.emit(MetamaskSiweEventType.accountsChanged);
        await rig.drainCleanup();
        await tester.pumpAndSettle();
        expect(log.disposals, 1);
        rig.api.verifyResult = _authenticated(wallet: _walletB);
        rig.api.meResult = _me(wallet: _walletB);
        await rig.controller.connectAndSignIn();
        await tester.pumpAndSettle();
        expect(log.mounts, 2);
        expect(log.mountedIdentities, [_walletA, _walletB]);
        expect(find.text('Protected $_walletB'), findsOneWidget);
        expect(find.text('Protected $_walletA'), findsNothing);
      },
    );
  });

  group('races and controller replacement', () {
    testWidgets(
      'old restore result cannot unlock Gate after controller replacement',
      (tester) async {
        final first = _Rig();
        final second = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        final oldReading = _Gate<AuthMeResponse>();
        final newReading = _Gate<AuthMeResponse>();
        first.api.reading = oldReading.call;
        second.api.reading = newReading.call;
        await host.mount(first, log);
        await oldReading.entered;
        await host.mount(second, log);
        await newReading.entered;
        oldReading.complete(_me());
        await tester.pump();
        _expectNeverBuilt(log);
        newReading.fail(
          const AuthApiException(AuthApiErrorKind.unauthenticated),
        );
        await tester.pumpAndSettle();
        _expectNeverBuilt(log);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(first.controller.restoreCalls, 1);
        expect(second.controller.restoreCalls, 1);
      },
    );

    testWidgets(
      'old controller events do not remove game owned by replacement controller',
      (tester) async {
        final first = _Rig();
        final second = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await first.controller.restoreSession();
        await second.controller.restoreSession();
        await host.mount(first, log);
        await host.mount(second, log);
        expect(log.mounts, 2);
        expect(log.disposals, 1);
        expect(
          first.controller.addedListeners,
          first.controller.removedListeners,
        );
        expect(first.controller.disposeCalls, 0);
        expect(second.controller.disposeCalls, 0);
        first.wallet.emit(MetamaskSiweEventType.chainChanged);
        await first.drainCleanup();
        await tester.pumpAndSettle();
        expect(_game, findsOneWidget);
        expect(log.disposals, 1);
        expect(second.controller.canEnterGame, isTrue);
      },
    );

    testWidgets(
      'late verify after chain change is revoked without mounting gameplay',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        final verifying = _Gate<AuthVerifyResult>();
        rig.api.verifying = verifying.call;
        final task = rig.controller.connectAndSignIn();
        await verifying.entered;
        await host.mount(rig, log);
        rig.wallet.chain = BigInt.one;
        rig.wallet.emit(MetamaskSiweEventType.chainChanged);
        verifying.complete(_authenticated());
        await task;
        await rig.drainCleanup();
        await tester.pumpAndSettle();
        _expectNeverBuilt(log);
        expect(rig.api.calls.where((call) => call == 'logout'), hasLength(1));
        expect(rig.api.logoutUsedExpectedCredential, isTrue);
      },
    );

    testWidgets(
      'logout during pending me rejects the old result as access evidence',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        final reading = _Gate<AuthMeResponse>();
        rig.api.reading = reading.call;
        await host.mount(rig, log);
        await reading.entered;
        final logout = rig.controller.logout();
        await tester.pump();
        _expectNeverBuilt(log);
        reading.complete(_me());
        await logout;
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        _expectNeverBuilt(log);
        expect(rig.api.calls, ['me', 'logout']);
      },
    );

    testWidgets(
      'dispose during pending restore removes listeners without disposing parent controller',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        final reading = _Gate<AuthMeResponse>();
        rig.api.reading = reading.call;
        await host.mount(rig, log);
        await reading.entered;
        await tester.pumpWidget(const SizedBox.shrink());
        expect(rig.controller.addedListeners, rig.controller.removedListeners);
        expect(rig.controller.disposeCalls, 0);
        reading.complete(_me());
        await tester.pumpAndSettle();
        expect(rig.controller.canEnterGame, isTrue);
        _expectNeverBuilt(log);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'rebuilds never add duplicate Gate listeners or wallet subscriptions',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        await host.mount(rig, log);
        await host.mount(rig, log);
        expect(
          rig.controller.addedListeners - rig.controller.removedListeners,
          1,
        );
        expect(rig.wallet.subscriptions, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(rig.controller.addedListeners, rig.controller.removedListeners);
        expect(rig.controller.disposeCalls, 0);
        expect(rig.api.closeCalls, 0);
        expect(rig.wallet.disposeCalls, 0);
      },
    );

    testWidgets(
      'captured Welcome registration callback cannot bypass wallet invalidation',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.registration();
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        await host.tap(find.byKey(const ValueKey('register-back')));
        await tester.pumpAndSettle();
        final callback = tester
            .widget<WelcomeScreen>(find.byType(WelcomeScreen))
            .onRegistrationRequired!;
        rig.wallet.emit(MetamaskSiweEventType.disconnected);
        await rig.drainCleanup();
        await callback();
        await tester.pumpAndSettle();
        _expectNeverBuilt(log);
        expect(find.byType(RegisterScreen), findsNothing);
      },
    );

    testWidgets(
      'unexpected restore exception is locked, safe and explicitly retryable',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        rig.controller.throwOnRestore = true;
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        expect(find.text('CHƯA THỂ KIỂM TRA HỒ SƠ'), findsOneWidget);
        expect(find.textContaining('Test restore exception'), findsNothing);
        _expectNeverBuilt(log);
        rig.controller.throwOnRestore = false;
        await host.tap(find.text('THỬ LẠI'));
        await tester.pumpAndSettle();
        expect(log.mounts, 1);
        expect(rig.controller.restoreCalls, 2);
      },
    );

    testWidgets(
      'synchronous builder-triggered logout cannot mount returned gameplay',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(
          rig,
          log,
          builder: (context) {
            log.builderCalls++;
            unawaited(rig.controller.logout());
            return _Gameplay(log, identity: _walletA);
          },
        );
        await rig.drainCleanup();
        await tester.pumpAndSettle();
        expect(log.builderCalls, 1);
        expect(log.mounts, 0);
        expect(_game, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('resume checks', () {
    testWidgets(
      'default resume revalidates once and locks during the pending check',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log);
        final reading = _Gate<AuthMeResponse>();
        rig.api.reading = reading.call;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await reading.entered;
        await tester.pump();
        expect(_game, findsNothing);
        expect(log.disposals, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(rig.api.calls.where((call) => call == 'me'), hasLength(2));
        final task = rig.controller.restoreSession();
        reading.complete(_me());
        await task;
        await tester.pumpAndSettle();
        expect(log.mounts, 2);
        expect(rig.wallet.calls, isNot(contains('connect')));
        expect(rig.wallet.calls, isNot(contains('sign')));
      },
    );

    testWidgets(
      'recheckOnResume false leaves checks to parent and preserves mounted game',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await rig.controller.restoreSession();
        await host.mount(rig, log, resume: false);
        final before = List.of(rig.api.calls);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(rig.api.calls, before);
        expect(log.mounts, 1);
        expect(log.disposals, 0);
        expect(_game, findsOneWidget);
      },
    );

    testWidgets('resume returning 401 keeps gameplay removed', (tester) async {
      final rig = _Rig();
      final log = _GameLog();
      final host = _Harness(tester);
      await rig.controller.restoreSession();
      await host.mount(rig, log);
      rig.absentSession();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_game, findsNothing);
      expect(log.disposals, 1);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets(
      'resume from unauthenticated Welcome never starts a wallet popup or restore',
      (tester) async {
        final rig = _Rig()..absentSession();
        final log = _GameLog();
        final host = _Harness(tester);
        await host.mount(rig, log);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(rig.controller.restoreCalls, 1);
        expect(rig.wallet.calls, isEmpty);
        _expectNeverBuilt(log);
      },
    );
  });

  group('responsive real Auth screens', () {
    for (final size in [
      const Size(1440, 900),
      const Size(1280, 720),
      const Size(390, 844),
    ]) {
      for (final screen in ['loading', 'Welcome', 'Register']) {
        testWidgets(
          '$screen at $size has no overflow or unauthorized gameplay',
          (tester) async {
            final rig = _Rig();
            final log = _GameLog();
            final host = _Harness(tester);
            if (screen == 'Welcome') {
              rig.absentSession();
              await rig.controller.restoreSession();
            }
            if (screen == 'Register') await rig.registration();
            await host.mount(rig, log, restore: false, size: size);
            await tester.pumpAndSettle();
            if (screen == 'loading') {
              expect(
                find.byKey(const ValueKey('auth-gate-status')),
                findsOneWidget,
              );
            }
            if (screen == 'Welcome') {
              expect(find.byType(WelcomeScreen), findsOneWidget);
            }
            if (screen == 'Register') {
              expect(find.byType(RegisterScreen), findsOneWidget);
              await tester.ensureVisible(
                find.byKey(const ValueKey('register-submit')),
              );
            }
            expect(tester.takeException(), isNull);
            _expectNeverBuilt(log);
          },
        );
      }
    }

    testWidgets(
      'small loading viewport with text scaled 2.0 remains scrollable',
      (tester) async {
        final rig = _Rig();
        final log = _GameLog();
        final host = _Harness(tester);
        await host.mount(
          rig,
          log,
          restore: false,
          size: const Size(320, 320),
          textScale: 2,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectNeverBuilt(log);
      },
    );
  });
}
