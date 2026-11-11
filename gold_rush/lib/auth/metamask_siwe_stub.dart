/// Unsupported-platform implementation of the SIWE wallet contract.
///
/// The class name matches the Web implementation for a future conditional
/// import. It accepts no provider and performs no wallet, HTTP or login work.
/// AuthController still imports the Web implementation directly today.
library;

import 'dart:async';

import 'metamask_siwe_contract.dart';

export 'metamask_siwe_contract.dart';

/// A typed contract error with platform-specific, safe UI guidance.
class _UnsupportedMetamaskPlatform extends MetamaskSiweException {
  const _UnsupportedMetamaskPlatform()
    : super(MetamaskSiweErrorCode.unsupportedProvider);

  @override
  String get message =>
      'Đăng nhập MetaMask hiện chỉ hỗ trợ trên trình duyệt Web tương thích.';
}

/// No connection, chain ID or signature can be produced on this platform.
class MetamaskSiweWeb implements MetamaskSiwePort {
  /// No discovery or requests. The controller accepts an injected adapter;
  /// Web-specific constructor options and provider access are not part of the
  /// shared contract and are intentionally absent here.
  MetamaskSiweWeb();

  final _events = StreamController<MetamaskSiweEvent>.broadcast(sync: true);
  bool _disposed = false;

  /// No data/error events are emitted. Keep the stream open until dispose so
  /// subscribing does not itself trigger the controller's disconnect handler.
  @override
  Stream<MetamaskSiweEvent> get events => _events.stream;

  void _active() {
    if (_disposed) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.disposed);
    }
  }

  Future<T> _unsupported<T>() async {
    _active();
    throw const _UnsupportedMetamaskPlatform();
  }

  @override
  Future<bool> checkAvailability() async {
    _active();
    return false;
  }

  @override
  Future<MetamaskWalletConnection> connect() =>
      _unsupported<MetamaskWalletConnection>();

  @override
  Future<List<String>> getAccounts() async {
    _active();
    return const <String>[];
  }

  @override
  Future<BigInt> getChainId() => _unsupported<BigInt>();

  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) => _unsupported<String>();

  /// Close only this instance's stream. This revokes no server session and
  /// does not dispose any dependency owned by another component.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_events.close());
  }
}
