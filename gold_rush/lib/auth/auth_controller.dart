/// Auth orchestration, with no widgets, storage, transactions or globals.
///
/// Wallet capabilities and data come from the platform-independent SIWE
/// contract. The parent selects and injects a Web adapter, native stub or fake;
/// this controller creates no default adapter and needs no platform import.
/// AuthApiClient still imports Web libraries, so importing this controller on
/// native remains blocked until the HTTP transport is separated too. Existing
/// fakes can still implement AuthWallet and AuthApiClient in browser tests.
/// Inject ONE app-owned MetaMask adapter and HTTP client; do not share the HTTP
/// client with other controllers issuing Auth mutations concurrently.
///
/// The existing Vi API hides its provider. Sharing the exact provider with Vi,
/// installing an Auth Gate, cross-tab invalidation and persisting a non-secret
/// logout-pending flag across reloads require later integration work. This
/// controller neither modifies Vi nor claims to protect existing game routes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_api_client.dart';
import 'metamask_siwe_contract.dart';

enum AuthStatus {
  initial,
  checkingSession,
  unauthenticated,
  connectingWallet,
  requestingChallenge,
  awaitingSignature,
  verifying,
  registrationRequired,
  registering,
  authenticated,
  loggingOut,
  error,
}

/// Read-only identity and explicit signing capability, never a transaction API.
/// The event stream must deliver changes synchronously, before async work can
/// resume. Ownership stays with the caller unless disposeDependencies is true.
abstract interface class AuthWallet {
  Stream<MetamaskSiweEventType> get events;
  Future<bool> checkAvailability();
  Future<MetamaskWalletConnection> connect();
  Future<List<String>> getAccounts();
  Future<BigInt> getChainId();
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  });
  void dispose();
}

/// Wraps an injected adapter without discovery, RPC or another wallet instance.
class MetamaskAuthWallet implements AuthWallet {
  const MetamaskAuthWallet(this.adapter);

  final MetamaskSiwePort adapter;

  @override
  Stream<MetamaskSiweEventType> get events =>
      adapter.events.map((event) => event.type);
  @override
  Future<bool> checkAvailability() => adapter.checkAvailability();
  @override
  Future<MetamaskWalletConnection> connect() => adapter.connect();
  @override
  Future<List<String>> getAccounts() => adapter.getAccounts();
  @override
  Future<BigInt> getChainId() => adapter.getChainId();
  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) => adapter.signSiweMessage(
    address: address,
    message: message,
    expectedChainId: expectedChainId,
  );
  @override
  void dispose() => adapter.dispose();
}

typedef AuthTimerFactory = Timer Function(Duration delay, void Function() fire);

class _Cancelled implements Exception {
  const _Cancelled();
}

class _AuthFailure implements Exception {
  const _AuthFailure(this.code, this.message);
  final String code;
  final String message;
}

class AuthController extends ChangeNotifier {
  /// No HTTP, provider discovery or popup is started here. A single event
  /// subscription is installed and removed by dispose(). The caller owns both
  /// dependencies by default, including when using AuthController.web.
  AuthController({
    required this._wallet,
    required this._api,
    DateTime Function()? clock,
    AuthTimerFactory? timerFactory,
    this.disposeDependencies = false,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new {
    _subscription = _wallet.events.listen(
      _walletChanged,
      onError: (Object _, StackTrace _) =>
          _walletChanged(MetamaskSiweEventType.invalidProviderData),
      onDone: () => _walletChanged(MetamaskSiweEventType.disconnected),
    );
  }

  /// Retains the existing constructor name for source compatibility. Any SIWE
  /// port can be injected, including an unsupported-platform stub; selecting an
  /// implementation neither authenticates it nor changes dependency ownership.
  AuthController.web({
    required MetamaskSiwePort wallet,
    required AuthApiClient api,
    DateTime Function()? clock,
    AuthTimerFactory? timerFactory,
    bool disposeDependencies = false,
  }) : this(
         wallet: MetamaskAuthWallet(wallet),
         api: api,
         clock: clock,
         timerFactory: timerFactory,
         disposeDependencies: disposeDependencies,
       );

  final AuthWallet _wallet;
  final AuthApiClient _api;
  final DateTime Function() _clock;
  final AuthTimerFactory _timerFactory;
  final bool disposeDependencies;
  late final StreamSubscription<MetamaskSiweEventType> _subscription;
  Timer? _timer;
  Future<void>? _operation;
  Future<void>? _logoutOperation;
  int _epoch = 0;
  bool _disposed = false;
  bool _logoutPending = false;
  bool _serverSessionMayBeActive = false;
  bool _unknownCredential = false;
  String? _csrfToken;
  AuthStatus _status = AuthStatus.initial;
  String? _walletAddress;
  BigInt? _chainId;
  AuthPublicUser? _user;
  DateTime? _expiresAt;
  String? _errorMessage;
  String? _errorCode;

  AuthStatus get status => _status;
  String? get csrfToken => _csrfToken;
  String? get walletAddress => _walletAddress;
  BigInt? get chainId => _chainId;
  AuthPublicUser? get user => _user;
  DateTime? get expiresAt => _expiresAt;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  bool get logoutPending => _logoutPending;

  /// Uncertainty is explicit; locking the UI is not proof of DB revocation.
  bool get serverSessionMayBeActive => _serverSessionMayBeActive;
  bool get isLoading =>
      !_disposed &&
      switch (_status) {
        AuthStatus.checkingSession ||
        AuthStatus.connectingWallet ||
        AuthStatus.requestingChallenge ||
        AuthStatus.awaitingSignature ||
        AuthStatus.verifying ||
        AuthStatus.registering ||
        AuthStatus.loggingOut => true,
        _ => false,
      };

  /// A future Auth Gate must consult this getter, never just walletAddress.
  bool get canEnterGame =>
      !_disposed &&
      !_logoutPending &&
      !_api.mutationPending &&
      _status == AuthStatus.authenticated &&
      _user != null &&
      _walletAddress == _user!.walletAddress &&
      _chainId != null &&
      _expiresAt != null &&
      _expiresAt!.isAfter(_now());

  bool get isAuthenticated => canEnterGame;
  DateTime _now() => _clock().toUtc();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _guard(int epoch) {
    if (_disposed || epoch != _epoch || _logoutPending) {
      throw const _Cancelled();
    }
  }

  void _stage(AuthStatus status, int epoch) {
    _guard(epoch);
    _status = status;
    _notify();
    // A listener can synchronously logout/dispose during notification.
    _guard(epoch);
  }

  void _clearIdentity() {
    _timer?.cancel();
    _timer = null;
    _user = null;
    _walletAddress = null;
    _chainId = null;
    _expiresAt = null;
  }

  void _remember(String csrf) {
    if (_disposed) return;
    // Capture even a stale response so queued cleanup can revoke its cookie.
    _csrfToken = csrf;
    _serverSessionMayBeActive = true;
    _unknownCredential = false;
  }

  Future<void> _run(Future<void> Function(int epoch) body) {
    if (_disposed) return Future<void>.value();
    if (_logoutOperation != null) return _logoutOperation!;
    if (_operation != null) return _operation!;
    if (_logoutPending) return logout();
    if (_api.mutationPending) {
      _unknownCredential = true;
      return _requestLogout(
        const _AuthFailure(
          'HTTP_PENDING',
          'Yêu cầu cũ vẫn đang xử lý. Chưa thể xác nhận thu hồi phiên; hãy thử đăng xuất lại sau.',
        ),
      );
    }
    final done = Completer<void>();
    _operation = done.future;
    final epoch = ++_epoch;
    _errorMessage = null;
    _errorCode = null;
    unawaited(() async {
      try {
        await body(epoch);
      } on _Cancelled {
        // Invalidated operations can never publish their old profile.
      } catch (error) {
        if (!_disposed && epoch == _epoch) {
          final failure = _failure(error);
          if (error is AuthApiException && error.outcomeUncertain) {
            _unknownCredential = true;
            _serverSessionMayBeActive = true;
          }
          _clearIdentity();
          _status = AuthStatus.error;
          _errorCode = failure.code;
          _errorMessage = failure.message;
          _notify();
          if (_csrfToken != null || _unknownCredential) {
            unawaited(_requestLogout(failure));
          }
        } else if (!_disposed &&
            error is AuthApiException &&
            error.outcomeUncertain) {
          _unknownCredential = true;
          _serverSessionMayBeActive = true;
        }
      } finally {
        _operation = null;
        done.complete();
      }
    }());
    return done.future;
  }

  Future<void> _checkWallet(int epoch, String address, BigInt chain) async {
    _guard(epoch);
    final accounts = await _wallet.getAccounts();
    _guard(epoch);
    if (accounts.isEmpty) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConnected);
    }
    if (accounts.first.toLowerCase() != address.toLowerCase()) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.accountChanged);
    }
    final currentChain = await _wallet.getChainId();
    _guard(epoch);
    if (currentChain != chain) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.chainChanged);
    }
    final again = await _wallet.getAccounts();
    _guard(epoch);
    if (again.isEmpty || again.first.toLowerCase() != address.toLowerCase()) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.accountChanged);
    }
  }

  void _notExpired(DateTime expiry, {bool grant = false}) {
    if (!expiry.isAfter(_now())) {
      throw _AuthFailure(
        grant ? 'GRANT_EXPIRED' : 'SESSION_EXPIRED',
        grant
            ? 'Quyền tạo nhân vật đã hết hạn. Hãy ký xác thực mới.'
            : 'Phiên đã hết hạn. Hãy kết nối và ký xác thực lại.',
      );
    }
  }

  /// Only a button action should call this method. There is no automatic retry
  /// of verify/register: a failed response may already have consumed the nonce.
  Future<void> connectAndSignIn() {
    if (!_logoutPending &&
        (_status == AuthStatus.authenticated ||
            _status == AuthStatus.registrationRequired)) {
      return Future<void>.value();
    }
    return _run(_connectAndSignIn);
  }

  Future<void> _connectAndSignIn(int epoch) async {
    _clearIdentity();
    _stage(AuthStatus.connectingWallet, epoch);
    if (!await _wallet.checkAvailability()) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notInstalled);
    }
    _guard(epoch);
    final connection = await _wallet.connect();
    _guard(epoch);
    final address = connection.address.toLowerCase();
    final chain = connection.chainId;
    _walletAddress = address;
    _chainId = chain;
    await _checkWallet(epoch, address, chain);
    _stage(AuthStatus.requestingChallenge, epoch);
    final challenge = await _api.createChallenge(
      walletAddress: address,
      chainId: chain,
    );
    _guard(epoch);
    if (!challenge.expiresAt.isAfter(_now())) {
      throw const _AuthFailure(
        'CHALLENGE_EXPIRED',
        'Thông điệp đăng nhập đã hết hạn. Hãy lấy thông điệp mới.',
      );
    }
    await _checkWallet(epoch, address, chain);
    _stage(AuthStatus.awaitingSignature, epoch);
    final signature = await _wallet.signSiweMessage(
      address: address,
      message: challenge.message,
      expectedChainId: chain,
    );
    _guard(epoch);
    await _checkWallet(epoch, address, chain);
    _stage(AuthStatus.verifying, epoch);
    final result = await _api.verify(
      challengeId: challenge.challengeId,
      message: challenge.message,
      signature: signature,
    );
    _remember(result.csrfToken);
    _guard(epoch);
    await _checkWallet(epoch, address, chain);
    switch (result) {
      case AuthAuthenticatedResult():
        await _confirm(result, epoch, address, chain);
      case AuthRegistrationRequired():
        if (result.walletAddress != address) throw _identityMismatch;
        _notExpired(result.expiresAt, grant: true);
        _expiresAt = result.expiresAt;
        _stage(AuthStatus.registrationRequired, epoch);
        _scheduleCheck(epoch);
    }
  }

  Future<void> register(String username) => _run((epoch) async {
    if (_status != AuthStatus.registrationRequired ||
        _csrfToken == null ||
        _walletAddress == null ||
        _chainId == null ||
        _expiresAt == null) {
      throw const _AuthFailure(
        'REGISTRATION_REQUIRED',
        'Hãy ký xác thực ví trước khi tạo nhân vật.',
      );
    }
    final address = _walletAddress!;
    final chain = _chainId!;
    _notExpired(_expiresAt!, grant: true);
    _timer?.cancel();
    await _checkWallet(epoch, address, chain);
    _stage(AuthStatus.registering, epoch);
    final AuthAuthenticatedResult result;
    try {
      result = await _api.register(username: username, csrfToken: _csrfToken!);
    } on AuthApiException catch (error) {
      if (!_disposed && error.outcomeUncertain) {
        _unknownCredential = true;
        _serverSessionMayBeActive = true;
      }
      _guard(epoch);
      final retryName =
          !error.outcomeUncertain &&
          (error.code == 'USERNAME_TAKEN' ||
              error.code == 'USERNAME_INVALID' ||
              error.field == 'username' &&
                  error.kind == AuthApiErrorKind.validation ||
              error.kind == AuthApiErrorKind.invalidRequest);
      if (!retryName) rethrow;
      _notExpired(_expiresAt!, grant: true);
      await _checkWallet(epoch, address, chain);
      _errorCode = error.code == 'USERNAME_TAKEN'
          ? 'USERNAME_TAKEN'
          : 'USERNAME_INVALID';
      _errorMessage = error.code == 'USERNAME_TAKEN'
          ? 'Tên nhà thám hiểm đã được sử dụng. Hãy chọn tên khác.'
          : 'Tên nhân vật không hợp lệ. Hãy kiểm tra rồi thử lại.';
      _stage(AuthStatus.registrationRequired, epoch);
      _scheduleCheck(epoch);
      return;
    }
    _remember(result.csrfToken);
    _guard(epoch);
    await _confirm(result, epoch, address, chain);
  });

  static const _identityMismatch = _AuthFailure(
    'IDENTITY_MISMATCH',
    'Phiên máy chủ không khớp ví, mạng hoặc hồ sơ vừa xác thực. Hãy đăng nhập lại.',
  );

  bool _sameUser(AuthPublicUser a, AuthPublicUser b) =>
      a.id == b.id &&
      a.walletAddress == b.walletAddress &&
      a.username == b.username &&
      a.avatar == b.avatar &&
      a.createdAt == b.createdAt;

  Future<void> _confirm(
    AuthAuthenticatedResult result,
    int epoch,
    String address,
    BigInt chain,
  ) async {
    if (result.user.walletAddress != address) throw _identityMismatch;
    _notExpired(result.expiresAt);
    _guard(epoch);
    final me = await _api.getMe();
    _remember(me.csrfToken);
    _guard(epoch);
    if (!_sameUser(me.user, result.user) ||
        me.chainId != chain ||
        me.expiresAt != result.expiresAt ||
        me.csrfToken != result.csrfToken) {
      throw _identityMismatch;
    }
    await _acceptMe(me, epoch);
  }

  /// /me first, then eth_accounts/eth_chainId only. A pending logout is always
  /// completed instead of restoring, so a network failure cannot reopen play.
  Future<void> restoreSession() => _run((epoch) async {
    _clearIdentity();
    _stage(AuthStatus.checkingSession, epoch);
    final AuthMeResponse me;
    try {
      me = await _api.getMe();
    } on AuthApiException catch (error) {
      _guard(epoch);
      if (error.kind != AuthApiErrorKind.unauthenticated) {
        _serverSessionMayBeActive = true;
        rethrow;
      }
      _csrfToken = null;
      _serverSessionMayBeActive = false;
      _unknownCredential = false;
      _errorCode = 'SESSION_INVALID';
      _errorMessage = 'Chưa có phiên đăng nhập hợp lệ. Hãy ký xác thực ví.';
      _stage(AuthStatus.unauthenticated, epoch);
      return;
    }
    _remember(me.csrfToken);
    _guard(epoch);
    await _acceptMe(me, epoch);
  });

  Future<void> _acceptMe(AuthMeResponse me, int epoch) async {
    _notExpired(me.expiresAt);
    _guard(epoch);
    if (!await _wallet.checkAvailability()) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notInstalled);
    }
    _guard(epoch);
    await _checkWallet(epoch, me.user.walletAddress, me.chainId);
    _notExpired(me.expiresAt);
    _guard(epoch);
    _walletAddress = me.user.walletAddress;
    _chainId = me.chainId;
    _user = me.user;
    _expiresAt = me.expiresAt;
    _stage(AuthStatus.authenticated, epoch);
    _scheduleCheck(epoch);
  }

  /// An absolute-expiry check plus at most 60 seconds between /me checks.
  /// Timer/clock injection permits deterministic tests without sleeping.
  void _scheduleCheck(int epoch) {
    _guard(epoch);
    _timer?.cancel();
    final remaining = _expiresAt!.difference(_now());
    final delay = remaining < const Duration(seconds: 60)
        ? remaining
        : const Duration(seconds: 60);
    _timer = _timerFactory(delay < Duration.zero ? Duration.zero : delay, () {
      if (_disposed || epoch != _epoch || _logoutPending) return;
      if (!_expiresAt!.isAfter(_now())) {
        unawaited(
          _requestLogout(
            _AuthFailure(
              _status == AuthStatus.registrationRequired
                  ? 'GRANT_EXPIRED'
                  : 'SESSION_EXPIRED',
              'Quyền xác thực đã hết hạn. Hãy ký xác thực mới.',
            ),
          ),
        );
      } else if (_status == AuthStatus.authenticated) {
        unawaited(restoreSession());
      } else if (_status == AuthStatus.registrationRequired) {
        _scheduleCheck(epoch);
      }
    });
  }

  void _walletChanged(MetamaskSiweEventType event) {
    if (_disposed) return;
    // The first permission grant normally emits accountsChanged while connect
    // is waiting. The adapter validates its returned identity itself. All later
    // changes, including away-and-back and malformed events, invalidate work.
    if (event == MetamaskSiweEventType.accountsChanged &&
        _status == AuthStatus.connectingWallet &&
        _walletAddress == null) {
      return;
    }
    final failure = switch (event) {
      MetamaskSiweEventType.accountsChanged => const _AuthFailure(
        'WALLET_CHANGED',
        'Ví đã thay đổi. Hãy xác thực lại ví đang chọn.',
      ),
      MetamaskSiweEventType.chainChanged => const _AuthFailure(
        'CHAIN_CHANGED',
        'Mạng ví đã thay đổi. Hãy ký xác thực lại.',
      ),
      _ => const _AuthFailure(
        'WALLET_DISCONNECTED',
        'Ví mất kết nối hoặc trả sự kiện không hợp lệ.',
      ),
    };
    unawaited(_requestLogout(failure));
  }

  /// Locks synchronously, then waits for the old operation before revocation.
  /// Multiple calls share the same cleanup. An underlying timed-out mutation
  /// is never retried or bypassed; the player can retry logout once it settles.
  Future<void> logout() => _requestLogout(null);

  Future<void> _requestLogout(_AuthFailure? reason) {
    if (_disposed) return Future<void>.value();
    ++_epoch;
    _logoutPending = true;
    _clearIdentity();
    _status = AuthStatus.loggingOut;
    if (reason != null) {
      _errorCode = reason.code;
      _errorMessage = reason.message;
    }
    if (_logoutOperation != null) {
      _notify();
      return _logoutOperation!;
    }
    final previous = _operation;
    final done = Completer<void>();
    _logoutOperation = done.future;
    _notify();
    unawaited(() async {
      try {
        if (previous != null) await previous;
        if (_disposed) return;
        if (_api.mutationPending) {
          throw const _AuthFailure(
            'HTTP_PENDING',
            'Yêu cầu cũ chưa kết thúc. Chưa xác nhận thu hồi phiên; hãy thử đăng xuất lại sau.',
          );
        }
        // A timeout may have rotated the browser cookie. Never send a known
        // old CSRF as if it were the credential for that new session.
        if (_csrfToken == null || _unknownCredential) {
          try {
            final me = await _api.getMe();
            _remember(me.csrfToken);
          } on AuthApiException catch (error) {
            if (error.kind != AuthApiErrorKind.unauthenticated) rethrow;
            if (_unknownCredential) {
              // /me rejects BOTH absent sessions and registration grants.
              // There is no API to recover a lost grant's CSRF. Stay locked;
              // do not claim revocation merely because /me returned 401.
              throw const _AuthFailure(
                'GRANT_STATE_UNKNOWN',
                'Chưa đối chiếu được cookie sau yêu cầu lỗi. Quyền đăng ký có thể còn trên máy chủ; chưa thể xác nhận đăng xuất.',
              );
            }
          }
        }
        if (_disposed) return;
        final csrf = _csrfToken;
        if (csrf != null) await _api.logout(csrfToken: csrf);
        if (_disposed) return;
        _csrfToken = null;
        _unknownCredential = false;
        _serverSessionMayBeActive = false;
        _logoutPending = false;
        _status = AuthStatus.unauthenticated;
        if (reason == null) {
          _errorCode = null;
          _errorMessage = null;
        }
        _notify();
      } catch (error) {
        if (!_disposed) {
          // Preserve even a possibly old CSRF for a subsequent explicit retry.
          if (error is AuthApiException && error.outcomeUncertain) {
            _unknownCredential = true;
          }
          _serverSessionMayBeActive = true;
          _logoutPending = true;
          _status = AuthStatus.error;
          _errorCode = _failure(error).code;
          _errorMessage =
              '${_failure(error).message} '
              'Gameplay đã khóa; chưa xác nhận phiên máy chủ được thu hồi.';
          _notify();
        }
      } finally {
        _logoutOperation = null;
        done.complete();
      }
    }());
    return done.future;
  }

  _AuthFailure _failure(Object error) {
    if (error is _AuthFailure) return error;
    if (error is MetamaskSiweException) {
      if (error.code == MetamaskSiweErrorCode.userRejected) {
        return _AuthFailure(
          'WALLET_REJECTED',
          _status == AuthStatus.awaitingSignature
              ? 'Bạn đã từ chối ký thông điệp đăng nhập.'
              : 'Bạn đã từ chối kết nối MetaMask.',
        );
      }
      return _AuthFailure('WALLET_${error.code.name}', error.message);
    }
    if (error is AuthApiException) {
      final message = switch (error.code) {
        'CHAIN_NOT_ALLOWED' || 'CHAIN_ID_NOT_ALLOWED' =>
          'Mạng Blockchain này chưa được phép đăng nhập.',
        'ORIGIN_INVALID' || 'ORIGIN_FORBIDDEN' =>
          'Địa chỉ trang không được máy chủ cho phép đăng nhập.',
        'SIGNATURE_INVALID' || 'SIWE_SIGNATURE_INVALID' =>
          'Chữ ký đăng nhập không hợp lệ. Hãy ký thông điệp mới.',
        'CHALLENGE_EXPIRED' =>
          'Thông điệp đăng nhập đã hết hạn. Hãy lấy thông điệp mới.',
        'GRANT_EXPIRED' || 'GRANT_INVALID' =>
          'Quyền tạo nhân vật không còn hợp lệ. Hãy ký xác thực mới.',
        'SESSION_EXPIRED' => 'Phiên đã hết hạn. Hãy ký xác thực lại.',
        _ => error.message,
      };
      // Do not expose arbitrary backend codes, bodies or exception.toString().
      return _AuthFailure('API_${error.kind.name}', message);
    }
    return const _AuthFailure(
      'AUTH_UNEXPECTED',
      'Không thể hoàn tất xác thực. Hãy kiểm tra kết nối và thử lại.',
    );
  }

  /// Disposal is local resource cleanup, NOT a server logout. In-flight HTTP
  /// can still set cookies. Await logout before disposal when revocation is
  /// required. No late callback may restore state or notify after this point.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _timer?.cancel();
    unawaited(_subscription.cancel());
    _clearIdentity();
    _csrfToken = null;
    if (disposeDependencies) {
      _wallet.dispose();
      _api.close();
    }
    super.dispose();
  }

  @override
  String toString() => 'AuthController(${_status.name})';
}
