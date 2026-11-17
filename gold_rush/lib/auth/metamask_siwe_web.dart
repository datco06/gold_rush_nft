/// Web-only MetaMask transport. Import conditionally at the future composition
/// root; this file performs no HTTP, login, storage, transactions or gas calls.
///
/// Vi currently hides its provider and has no signing/disposal capability. It
/// cannot safely supply personal_sign through its public API. This adapter uses
/// the browser's EXISTING MetaMask provider, never creates another Vi or caches
/// accounts. Prefer injecting the same JSObject at a future composition root.
/// selectedProvider exposes that object; sharing it with the current private
/// _ViWeb still requires a separately authorized integration change.
///
/// Construct ONE adapter per app/controller, subscribe to events before use and
/// dispose it at app shutdown. Every event invalidates in-flight signing, even
/// if the user switches away and back. The future Auth Controller must lock its
/// UI and revoke server sessions; provider events do not do that themselves.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'metamask_siwe_contract.dart';

export 'metamask_siwe_contract.dart';

extension type _Request._(JSObject _) implements JSObject {
  external factory _Request({String method, JSArray<JSAny?> params});
}

@JS('Event')
extension type _DomEvent._(JSObject _) implements JSObject {
  external factory _DomEvent(String type);
}

class MetamaskSiweWeb implements MetamaskSiwePort {
  /// Construction never discovers providers, requests accounts, signs or opens
  /// popups. Discovery is lazy. Provider IDs/flags are self-reported discovery
  /// hints, not cryptographic proof of the extension's publisher.
  MetamaskSiweWeb({
    JSObject? provider,
    Duration requestTimeout = const Duration(seconds: 90),
    Duration discoveryWait = const Duration(milliseconds: 200),
  }) : this._(provider, requestTimeout, discoveryWait);

  MetamaskSiweWeb._(this._provider, this.requestTimeout, this.discoveryWait) {
    if (requestTimeout <= Duration.zero ||
        discoveryWait < Duration.zero ||
        discoveryWait > const Duration(seconds: 2)) {
      throw ArgumentError('Timeout phải dương; discoveryWait từ 0 đến 2 giây.');
    }
  }

  final Duration requestTimeout;
  final Duration discoveryWait;
  JSObject? _provider;
  Future<JSObject>? _preparing;
  final _events = StreamController<MetamaskSiweEvent>.broadcast(sync: true);
  final _listeners = <String, JSFunction>{};
  final _pending = <Completer<JSAny?>>{};
  String? _removeMethod;
  bool _disposed = false;
  bool _interactiveBusy = false;
  bool _popupPending = false;
  int _revision = 0;
  MetamaskSiweErrorCode _lastChange = MetamaskSiweErrorCode.accountChanged;

  @override
  Stream<MetamaskSiweEvent> get events => _events.stream;

  /// Null until selected. Never causes discovery or RPC just by reading it.
  JSObject? get selectedProvider => _disposed ? null : _provider;

  void _active() {
    if (_disposed) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.disposed);
    }
  }

  bool _function(JSObject object, String name) =>
      object.getProperty<JSAny?>(name.toJS).isA<JSFunction>();

  bool _metamask(JSObject object) {
    final flag = object.getProperty<JSAny?>('isMetaMask'.toJS);
    return flag.isA<JSBoolean>() && (flag as JSBoolean).toDart;
  }

  Future<JSObject> _discover() async {
    final found = <JSObject>[];
    void add(JSObject provider) {
      if (!found.any((item) => item.strictEquals(provider).toDart)) {
        found.add(provider);
      }
    }

    final listener = ((JSAny? value) {
      if (_disposed) return;
      try {
        if (!value.isA<JSObject>()) return;
        final detail = (value as JSObject).getProperty<JSAny?>('detail'.toJS);
        if (!detail.isA<JSObject>()) return;
        final object = detail as JSObject;
        final info = object.getProperty<JSAny?>('info'.toJS);
        final provider = object.getProperty<JSAny?>('provider'.toJS);
        if (!info.isA<JSObject>() || !provider.isA<JSObject>()) return;
        final rdns = (info as JSObject).getProperty<JSAny?>('rdns'.toJS);
        if (rdns.isA<JSString>()) {
          final name = (rdns as JSString).toDart;
          if ((name == 'io.metamask' || name.startsWith('io.metamask.')) &&
              _metamask(provider as JSObject)) {
            add(provider);
          }
        }
      } catch (_) {
        // An unrelated/untrusted wallet announcement must not crash discovery.
      }
    }).toJS;
    var attached = false;
    try {
      if (_function(globalContext, 'addEventListener') &&
          _function(globalContext, 'removeEventListener') &&
          _function(globalContext, 'dispatchEvent')) {
        globalContext.callMethod(
          'addEventListener'.toJS,
          'eip6963:announceProvider'.toJS,
          listener,
        );
        attached = true;
        globalContext.callMethod(
          'dispatchEvent'.toJS,
          _DomEvent('eip6963:requestProvider'),
        );
        await Future<void>.delayed(discoveryWait);
      }
    } finally {
      if (attached) {
        globalContext.callMethod(
          'removeEventListener'.toJS,
          'eip6963:announceProvider'.toJS,
          listener,
        );
      }
    }
    _active();
    // Match the existing wallet's EIP-6963 preference, but never fall back to an
    // arbitrary other wallet. Pin the selected object for this adapter's life.
    if (found.isEmpty) {
      final injected = globalContext.getProperty<JSAny?>('ethereum'.toJS);
      if (!injected.isA<JSObject>()) {
        throw const MetamaskSiweException(MetamaskSiweErrorCode.notInstalled);
      }
      final provider = injected as JSObject;
      final providers = provider.getProperty<JSAny?>('providers'.toJS);
      if (providers.isA<JSArray<JSAny?>>()) {
        for (final candidate in (providers as JSArray<JSAny?>).toDart) {
          if (candidate.isA<JSObject>() && _metamask(candidate as JSObject)) {
            add(candidate);
          }
        }
      } else if (_metamask(provider)) {
        add(provider);
      }
    }
    if (found.isEmpty) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.wrongProvider);
    }
    if (found.length != 1) {
      throw const MetamaskSiweException(
        MetamaskSiweErrorCode.ambiguousProvider,
      );
    }
    return found.single;
  }

  Future<JSObject> _prepare() async {
    _active();
    if (_listeners.isNotEmpty) return _provider!;
    final preparing = _preparing;
    if (preparing != null) return preparing;
    final future = () async {
      try {
        final provider = _provider ?? await _discover();
        _active();
        if (!_metamask(provider)) {
          throw const MetamaskSiweException(
            MetamaskSiweErrorCode.wrongProvider,
          );
        }
        final remove = _function(provider, 'removeListener')
            ? 'removeListener'
            : 'off';
        if (!_function(provider, 'request') ||
            !_function(provider, 'on') ||
            !_function(provider, remove)) {
          throw const MetamaskSiweException(
            MetamaskSiweErrorCode.unsupportedProvider,
          );
        }
        _provider = provider;
        _removeMethod = remove;
        for (final name in ['accountsChanged', 'chainChanged', 'disconnect']) {
          final listener = ((JSAny? value) => _event(name, value)).toJS;
          _listeners[name] = listener;
          provider.callMethod('on'.toJS, name.toJS, listener);
        }
        return provider;
      } on MetamaskSiweException {
        _detach();
        rethrow;
      } catch (_) {
        _detach();
        throw const MetamaskSiweException(MetamaskSiweErrorCode.interop);
      }
    }();
    _preparing = future;
    try {
      return await future;
    } finally {
      _preparing = null;
    }
  }

  /// Checks availability without any accounts/connection/signing RPC or popup.
  /// Other unsupported/interop cases are typed errors rather than "not installed".
  @override
  Future<bool> checkAvailability() async {
    try {
      await _prepare();
      return true;
    } on MetamaskSiweException catch (error) {
      if (error.code == MetamaskSiweErrorCode.notInstalled ||
          error.code == MetamaskSiweErrorCode.wrongProvider) {
        return false;
      }
      rethrow;
    }
  }

  String _address(String value) {
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value)) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidAddress);
    }
    return value.toLowerCase();
  }

  List<String> _accounts(JSAny? value) {
    try {
      if (!value.isA<JSArray<JSAny?>>()) {
        throw const MetamaskSiweException(
          MetamaskSiweErrorCode.invalidResponse,
        );
      }
      final accounts = <String>[];
      for (final item in (value as JSArray<JSAny?>).toDart) {
        if (!item.isA<JSString>()) {
          throw const MetamaskSiweException(
            MetamaskSiweErrorCode.invalidResponse,
          );
        }
        accounts.add(_address((item as JSString).toDart));
      }
      return List.unmodifiable(accounts);
    } on MetamaskSiweException {
      rethrow;
    } catch (_) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.interop);
    }
  }

  BigInt _chain(JSAny? value) {
    if (!value.isA<JSString>()) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidChainId);
    }
    final text = (value as JSString).toDart;
    if (!RegExp(r'^0x[0-9a-fA-F]{1,64}$').hasMatch(text)) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidChainId);
    }
    final id = BigInt.parse(text.substring(2), radix: 16);
    if (id <= BigInt.zero) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidChainId);
    }
    return id;
  }

  MetamaskSiweException _providerError(JSAny? value) {
    int? code;
    try {
      if (value.isA<JSObject>()) {
        final raw = (value as JSObject).getProperty<JSAny?>('code'.toJS);
        if (raw.isA<JSNumber>()) {
          final number = (raw as JSNumber).toDartDouble;
          if (number.isFinite &&
              number == number.truncateToDouble() &&
              number.abs() <= 2147483647) {
            code = number.toInt();
          }
        }
      }
    } catch (_) {
      return const MetamaskSiweException(MetamaskSiweErrorCode.interop);
    }
    final kind = switch (code) {
      4001 => MetamaskSiweErrorCode.userRejected,
      -32002 => MetamaskSiweErrorCode.requestPending,
      4100 => MetamaskSiweErrorCode.notConnected,
      4200 || -32601 => MetamaskSiweErrorCode.unsupportedProvider,
      4900 || 4901 => MetamaskSiweErrorCode.disconnected,
      _ => MetamaskSiweErrorCode.interop,
    };
    return MetamaskSiweException(kind, rpcCode: code);
  }

  Future<JSAny?> _request(
    String method, [
    List<String> params = const [],
  ]) async {
    final provider = await _prepare();
    _active();
    final interactive =
        method == 'eth_requestAccounts' || method == 'personal_sign';
    final done = Completer<JSAny?>();
    _pending.add(done);
    if (interactive) _popupPending = true;
    var settled = false;
    void settle(JSAny? value, {bool failed = false}) {
      if (settled) return;
      settled = true;
      if (interactive) _popupPending = false;
      _pending.remove(done);
      if (done.isCompleted) return;
      if (_disposed) {
        done.completeError(
          const MetamaskSiweException(MetamaskSiweErrorCode.disposed),
        );
      } else if (failed) {
        done.completeError(_providerError(value));
      } else {
        done.complete(value);
      }
    }

    try {
      final result = provider.callMethod<JSAny?>(
        'request'.toJS,
        _Request(
          method: method,
          params: params.map((item) => item.toJS).toList().toJS,
        ),
      );
      if (!result.isA<JSObject>() || !_function(result as JSObject, 'then')) {
        throw const MetamaskSiweException(
          MetamaskSiweErrorCode.invalidResponse,
        );
      }
      result.callMethod(
        'then'.toJS,
        ((JSAny? value) => settle(value)).toJS,
        ((JSAny? value) => settle(value, failed: true)).toJS,
      );
    } catch (error) {
      if (interactive) _popupPending = false;
      _pending.remove(done);
      if (!done.isCompleted) {
        done.completeError(
          error is MetamaskSiweException
              ? error
              : const MetamaskSiweException(MetamaskSiweErrorCode.interop),
        );
      }
    }
    return done.future.timeout(
      requestTimeout,
      onTimeout: () {
        _revision++;
        _lastChange = MetamaskSiweErrorCode.timeout;
        // Do not clear _popupPending: timeout cannot close/cancel a provider popup.
        throw const MetamaskSiweException(MetamaskSiweErrorCode.timeout);
      },
    );
  }

  /// Non-interactive restore check: an empty list is a normal disconnected state.
  @override
  Future<List<String>> getAccounts() async =>
      _accounts(await _request('eth_accounts'));

  @override
  Future<BigInt> getChainId() async => _chain(await _request('eth_chainId'));

  Future<T> _interactive<T>(Future<T> Function() action) async {
    _active();
    if (_interactiveBusy || _popupPending) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.requestPending);
    }
    _interactiveBusy = true;
    try {
      return await action();
    } finally {
      _interactiveBusy = false;
    }
  }

  void _unchanged(int revision) {
    _active();
    if (revision != _revision) throw MetamaskSiweException(_lastChange);
  }

  Future<void> _requireAccount(String address) async {
    final accounts = await getAccounts();
    if (accounts.isEmpty) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConnected);
    }
    if (accounts.first != address) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.accountChanged);
    }
  }

  /// Only call from an explicit connect-button action. No Gold Rush login occurs.
  @override
  Future<MetamaskWalletConnection> connect() => _interactive(() async {
    final accounts = _accounts(await _request('eth_requestAccounts'));
    if (accounts.isEmpty) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConnected);
    }
    final revision = _revision;
    final address = accounts.first;
    await _requireAccount(address);
    final chainId = await getChainId();
    await _requireAccount(address);
    _unchanged(revision);
    return MetamaskWalletConnection(address: address, chainId: chainId);
  });

  /// Call only after an explicit sign-button action and a backend challenge.
  /// Uses personal_sign([hex(UTF8(originalMessage)), address]), not eth_sign,
  /// transactions or a locally rebuilt SIWE message. Backend verifies EIP-191.
  /// A returned signature is NOT proof that Gold Rush granted authentication.
  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) => _interactive(() async {
    final normalized = _address(address);
    final bytes = utf8.encode(message);
    if (bytes.isEmpty || bytes.length > 4096 || utf8.decode(bytes) != message) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidMessage);
    }
    await _prepare();
    final revision = _revision;
    await _requireAccount(normalized);
    final beforeChain = await getChainId();
    if (expectedChainId != null && beforeChain != expectedChainId) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.chainChanged);
    }
    _unchanged(revision);
    final hex =
        '0x${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
    final result = await _request('personal_sign', [hex, normalized]);
    _unchanged(revision);
    await _requireAccount(normalized);
    if (await getChainId() != beforeChain) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.chainChanged);
    }
    _unchanged(revision);
    if (!result.isA<JSString>()) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidResponse);
    }
    final signature = (result as JSString).toDart;
    if (!RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(signature)) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidResponse);
    }
    return signature; // In-memory return only; never log or persist it here.
  });

  void _event(String name, JSAny? value) {
    if (_disposed) return;
    _revision++;
    _lastChange = switch (name) {
      'chainChanged' => MetamaskSiweErrorCode.chainChanged,
      'disconnect' => MetamaskSiweErrorCode.disconnected,
      _ => MetamaskSiweErrorCode.accountChanged,
    };
    try {
      final event = switch (name) {
        'accountsChanged' => MetamaskSiweEvent(
          MetamaskSiweEventType.accountsChanged,
          accounts: _accounts(value),
        ),
        'chainChanged' => MetamaskSiweEvent(
          MetamaskSiweEventType.chainChanged,
          chainId: _chain(value),
        ),
        _ => MetamaskSiweEvent(
          MetamaskSiweEventType.disconnected,
          error: const MetamaskSiweException(
            MetamaskSiweErrorCode.disconnected,
          ),
        ),
      };
      _events.add(event);
    } catch (_) {
      _events.add(
        MetamaskSiweEvent(
          MetamaskSiweEventType.invalidProviderData,
          error: const MetamaskSiweException(
            MetamaskSiweErrorCode.invalidResponse,
          ),
        ),
      );
    }
  }

  void _detach() {
    final provider = _provider;
    final remove = _removeMethod;
    if (provider != null && remove != null) {
      for (final entry in _listeners.entries) {
        try {
          provider.callMethod(remove.toJS, entry.key.toJS, entry.value);
        } catch (_) {
          // A broken provider may refuse removal. Disposed callbacks stay inert.
        }
      }
    }
    _listeners.clear();
  }

  /// Remove only this adapter's listeners; never remove another wallet user's
  /// listeners or claim this disconnects the MetaMask extension/server cookie.
  /// Pending results are rejected, but existing provider popups cannot be closed.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    _detach();
    _provider = null;
    for (final request in _pending) {
      if (!request.isCompleted) {
        request.completeError(
          const MetamaskSiweException(MetamaskSiweErrorCode.disposed),
        );
      }
    }
    _pending.clear();
    unawaited(_events.close());
  }
}
