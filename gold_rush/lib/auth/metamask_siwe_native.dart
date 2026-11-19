/// Native MetaMask/WalletConnect adapter.
///
/// Reown owns the WalletConnect session and deep-link handoff. This adapter
/// exposes only the same SIWE/RPC boundary used by the Web implementation;
/// it never receives or stores a private key.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'metamask_siwe_contract.dart';

const _addressPattern = r'^0x[0-9a-fA-F]{40}$';
const _signaturePattern = r'^0x[0-9a-fA-F]{130}$';

String _hexMessage(String value) =>
    '0x${utf8.encode(value).map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';

BigInt _positiveChainId(String value) {
  final id = value.startsWith('0x')
      ? BigInt.parse(value.substring(2), radix: 16)
      : BigInt.parse(value);
  if (id <= BigInt.zero) throw const FormatException();
  return id;
}

class MetamaskSiweWeb implements MetamaskSiwePort {
  MetamaskSiweWeb({required BuildContext context, required String projectId})
    : _projectId = projectId.trim(),
      _context = context,
      _appKit = projectId.trim().isEmpty
          ? null
          : _createAppKit(context, projectId.trim()) {
    _appKit?.onModalConnect.subscribe(_onModalConnect);
    _appKit?.onModalUpdate.subscribe(_onModalUpdate);
    _appKit?.onModalNetworkChange.subscribe(_onModalNetworkChange);
    _appKit?.onModalDisconnect.subscribe(_onModalDisconnect);
    _appKit?.onModalError.subscribe(_onModalError);
  }

  final String _projectId;
  final BuildContext _context;
  ReownAppKitModal? _appKit;
  final StreamController<MetamaskSiweEvent> _events =
      StreamController<MetamaskSiweEvent>.broadcast();
  Future<void>? _initializing;
  bool _disposed = false;

  static ReownAppKitModal _createAppKit(
    BuildContext context,
    String projectId,
  ) {
    final localRpc = const String.fromEnvironment(
      'GOLD_RUSH_LOCAL_RPC_URL',
      defaultValue: 'http://10.0.2.2:8545',
    );
    ReownAppKitModalNetworks.addSupportedNetworks('eip155', [
      ReownAppKitModalNetworkInfo(
        name: 'Hardhat cục bộ',
        chainId: 'eip155:31337',
        currency: 'ETH',
        rpcUrl: localRpc,
        explorerUrl: 'https://hardhat.org',
        isTestNetwork: true,
      ),
    ]);
    return ReownAppKitModal(
      context: context,
      projectId: projectId,
      metadata: const PairingMetadata(
        name: 'Gold Rush',
        description: 'Gold Rush blockchain game',
        url: String.fromEnvironment(
          'GOLD_RUSH_DAPP_URL',
          defaultValue: 'https://goldrush.example',
        ),
        redirect: Redirect(
          native: String.fromEnvironment(
            'GOLD_RUSH_NATIVE_REDIRECT',
            defaultValue: 'goldrush://',
          ),
          universal: String.fromEnvironment(
            'GOLD_RUSH_APP_LINK',
            defaultValue: 'https://goldrush.example/wc',
          ),
          linkMode: false,
        ),
      ),
      disconnectOnDispose: true,
    );
  }

  ReownAppKitModal get _modal {
    if (_disposed) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.disposed);
    }
    final modal = _appKit;
    if (modal == null) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConfigured);
    }
    return modal;
  }

  /// A failed openModalView can leave Reown's internal `_isOpen` flag true
  /// with an empty widget stack; the next open then crashes. Rebuild the
  /// modal instance so the next attempt starts clean.
  void _resetAppKit() {
    final old = _appKit;
    if (old == null) return;
    old.onModalConnect.unsubscribe(_onModalConnect);
    old.onModalUpdate.unsubscribe(_onModalUpdate);
    old.onModalNetworkChange.unsubscribe(_onModalNetworkChange);
    old.onModalDisconnect.unsubscribe(_onModalDisconnect);
    old.onModalError.unsubscribe(_onModalError);
    unawaited(old.dispose());
    _initializing = null;
    if (_projectId.isEmpty || _disposed) {
      _appKit = null;
      return;
    }
    _appKit = _createAppKit(_context, _projectId);
    _appKit?.onModalConnect.subscribe(_onModalConnect);
    _appKit?.onModalUpdate.subscribe(_onModalUpdate);
    _appKit?.onModalNetworkChange.subscribe(_onModalNetworkChange);
    _appKit?.onModalDisconnect.subscribe(_onModalDisconnect);
    _appKit?.onModalError.subscribe(_onModalError);
  }

  @override
  Stream<MetamaskSiweEvent> get events => _events.stream;

  bool get isConfigured => _projectId.isNotEmpty;

  @override
  Future<bool> checkAvailability() async {
    await _ensureReady();
    return true;
  }

  Future<void> _ensureReady() {
    final modal = _modal;
    final current = _initializing;
    if (current != null) return current;
    final future = modal.init();
    _initializing = future;
    return future;
  }

  String? _address() => _modal.session?.getAddress('eip155');

  BigInt _chainId() {
    final chain = _modal.selectedChain?.chainId ?? _modal.session?.chainId;
    if (chain == null || !chain.contains(':')) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidChainId);
    }
    try {
      return _positiveChainId(chain.substring(chain.indexOf(':') + 1));
    } catch (_) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidChainId);
    }
  }

  MetamaskWalletConnection _connection() {
    final address = _address();
    if (address == null || !RegExp(_addressPattern).hasMatch(address)) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConnected);
    }
    return MetamaskWalletConnection(
      address: address.toLowerCase(),
      chainId: _chainId(),
    );
  }

  @override
  Future<MetamaskWalletConnection> connect() async {
    await _ensureReady();
    if (_modal.isConnected) return _connection();

    final connected = Completer<MetamaskWalletConnection>();
    final rejected = Completer<MetamaskSiweException>();

    void onConnect(ModalConnect? _) {
      if (!connected.isCompleted && _modal.isConnected) {
        try {
          connected.complete(_connection());
        } catch (error) {
          connected.completeError(error);
        }
      }
    }

    void onError(ModalError? event) {
      if (event == null || rejected.isCompleted || connected.isCompleted) {
        return;
      }
      rejected.complete(_mapModalError(event));
    }

    _modal.onModalConnect.subscribe(onConnect);
    _modal.onModalError.subscribe(onError);
    try {
      try {
        await _modal.openModalView();
      } catch (error) {
        // Empty WidgetStack / null Navigator: poisoned open state.
        _resetAppKit();
        rethrow;
      }
      onConnect(null);
      return await Future.any([
        connected.future,
        rejected.future.then<MetamaskWalletConnection>(
          (error) => Future<MetamaskWalletConnection>.error(error),
        ),
      ]).timeout(const Duration(minutes: 2));
    } on MetamaskSiweException {
      rethrow;
    } on TimeoutException {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.timeout);
    } catch (error) {
      throw _mapError(error);
    } finally {
      final modal = _appKit;
      modal?.onModalConnect.unsubscribe(onConnect);
      modal?.onModalError.unsubscribe(onError);
    }
  }

  @override
  Future<List<String>> getAccounts() async {
    await _ensureReady();
    final address = _address();
    if (address == null) return const [];
    if (!RegExp(_addressPattern).hasMatch(address)) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidResponse);
    }
    return [address.toLowerCase()];
  }

  @override
  Future<BigInt> getChainId() async {
    await _ensureReady();
    return _chainId();
  }

  /// Shared raw EIP-1193-equivalent RPC boundary for native transactions.
  Future<Object?> requestRpc(
    String method, [
    List<Object?> params = const [],
  ]) async {
    await _ensureReady();
    final modal = _modal;
    final session = modal.session;
    final topic = session?.topic;
    if (!modal.isConnected || topic == null || topic.isEmpty) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConnected);
    }
    try {
      return await modal.request(
        topic: topic,
        chainId: 'eip155:${_chainId()}',
        request: SessionRequestParams(method: method, params: params),
      );
    } catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> switchChain(int chainId, {String? name, String? rpcUrl}) async {
    await _ensureReady();
    final info = ReownAppKitModalNetworkInfo(
      name: name ?? 'Mạng $chainId',
      chainId: 'eip155:$chainId',
      currency: 'ETH',
      rpcUrl: rpcUrl ?? '',
      explorerUrl: chainId == 11155111
          ? 'https://sepolia.etherscan.io'
          : 'https://hardhat.org',
      isTestNetwork: true,
    );
    try {
      await _modal.requestSwitchToChain(info);
    } catch (_) {
      await _modal.requestAddChain(info);
    }
  }

  @override
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  }) async {
    if (!_validMessage(message)) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidMessage);
    }
    final actual = _connection();
    if (actual.address != address.toLowerCase()) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.accountChanged);
    }
    if (expectedChainId != null && actual.chainId != expectedChainId) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.chainChanged);
    }
    final result = await requestRpc('personal_sign', [
      _hexMessage(message),
      actual.address,
    ]);
    if (result is! String || !RegExp(_signaturePattern).hasMatch(result)) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidResponse);
    }
    final after = _connection();
    if (after.address != actual.address) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.accountChanged);
    }
    if (after.chainId != actual.chainId) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.chainChanged);
    }
    return result;
  }

  static bool _validMessage(String value) =>
      value.isNotEmpty && utf8.encode(value).length <= 4096;

  MetamaskSiweException _mapModalError(ModalError event) {
    if (event is WalletNotInstalled) {
      return const MetamaskSiweException(MetamaskSiweErrorCode.notInstalled);
    }
    if (event is UserRejectedConnection || event is UserRejectedRequest) {
      return const MetamaskSiweException(MetamaskSiweErrorCode.userRejected);
    }
    if (event is ErrorOpeningWallet) {
      return const MetamaskSiweException(MetamaskSiweErrorCode.interop);
    }
    return _mapError(event);
  }

  MetamaskSiweException _mapError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('reject') ||
        text.contains('denied') ||
        text.contains('4001')) {
      return const MetamaskSiweException(
        MetamaskSiweErrorCode.userRejected,
        rpcCode: 4001,
      );
    }
    if (text.contains('-32002') || text.contains('pending')) {
      return const MetamaskSiweException(
        MetamaskSiweErrorCode.requestPending,
        rpcCode: -32002,
      );
    }
    if (text.contains('not installed') || text.contains('wallet app')) {
      return const MetamaskSiweException(MetamaskSiweErrorCode.notInstalled);
    }
    if (text.contains('disconnect') || text.contains('session')) {
      return const MetamaskSiweException(MetamaskSiweErrorCode.disconnected);
    }
    return const MetamaskSiweException(MetamaskSiweErrorCode.interop);
  }

  void _onModalConnect(ModalConnect? event) {
    if (event == null || _events.isClosed) return;
    try {
      final connection = _connection();
      _events.add(
        MetamaskSiweEvent(
          MetamaskSiweEventType.accountsChanged,
          accounts: [connection.address],
          chainId: connection.chainId,
        ),
      );
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

  void _onModalUpdate(ModalConnect? event) => _onModalConnect(event);

  void _onModalNetworkChange(ModalNetworkChange? event) {
    if (event == null || _events.isClosed) return;
    final chain = event.chainId;
    if (chain == null || !chain.contains(':')) return;
    try {
      _events.add(
        MetamaskSiweEvent(
          MetamaskSiweEventType.chainChanged,
          chainId: _positiveChainId(chain.substring(chain.indexOf(':') + 1)),
        ),
      );
    } catch (_) {
      _events.add(
        MetamaskSiweEvent(
          MetamaskSiweEventType.invalidProviderData,
          error: const MetamaskSiweException(
            MetamaskSiweErrorCode.invalidChainId,
          ),
        ),
      );
    }
  }

  void _onModalDisconnect(ModalDisconnect? _) {
    if (!_events.isClosed) {
      _events.add(MetamaskSiweEvent(MetamaskSiweEventType.disconnected));
    }
  }

  void _onModalError(ModalError? event) {
    if (event != null && !_events.isClosed) {
      _events.add(
        MetamaskSiweEvent(
          MetamaskSiweEventType.invalidProviderData,
          error: _mapModalError(event),
        ),
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final modal = _appKit;
    modal?.onModalConnect.unsubscribe(_onModalConnect);
    modal?.onModalUpdate.unsubscribe(_onModalUpdate);
    modal?.onModalNetworkChange.unsubscribe(_onModalNetworkChange);
    modal?.onModalDisconnect.unsubscribe(_onModalDisconnect);
    modal?.onModalError.unsubscribe(_onModalError);
    unawaited(modal?.dispose());
    unawaited(_events.close());
  }
}
