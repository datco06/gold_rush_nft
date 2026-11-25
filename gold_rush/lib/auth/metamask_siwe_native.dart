/// Native MetaMask/WalletConnect adapter.
///
/// Reown owns the WalletConnect session and deep-link handoff. This adapter
/// exposes only the same SIWE/RPC boundary used by the Web implementation;
/// it never receives or stores a private key.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'metamask_siwe_contract.dart';

const _addressPattern = r'^0x[0-9a-fA-F]{40}$';
const _signaturePattern = r'^0x[0-9a-fA-F]{130}$';
const nativeLocalRpcUrl = String.fromEnvironment(
  'GOLD_RUSH_LOCAL_RPC_URL',
  defaultValue: 'http://10.0.2.2:8545',
);
const nativeSepoliaRpcUrl = String.fromEnvironment(
  'GOLD_RUSH_SEPOLIA_RPC_URL',
  defaultValue: 'https://ethereum-sepolia-rpc.publicnode.com',
);

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
  MetamaskSiweWeb({
    required BuildContext context,
    required String projectId,
    @visibleForTesting ReownAppKitModal? appKit,
  }) : _projectId = projectId.trim(),
       _context = context,
       _appKit = projectId.trim().isEmpty
           ? null
           : appKit ?? _createAppKit(context, projectId.trim()) {
    _appKit?.onModalConnect.subscribe(_onModalConnect);
    _appKit?.onModalUpdate.subscribe(_onModalUpdate);
    _appKit?.onModalNetworkChange.subscribe(_onModalNetworkChange);
    _appKit?.onSessionEventEvent.subscribe(_onSessionEvent);
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
  String? _lastAddress;
  BigInt? _lastChainId;
  ({String topic, BigInt chainId})? _walletChain;

  static ReownAppKitModal _createAppKit(
    BuildContext context,
    String projectId,
  ) {
    ReownAppKitModalNetworks.addSupportedNetworks('eip155', const [
      ReownAppKitModalNetworkInfo(
        name: 'Hardhat cục bộ',
        chainId: 'eip155:31337',
        currency: 'ETH',
        rpcUrl: nativeLocalRpcUrl,
        explorerUrl: 'https://hardhat.org',
        isTestNetwork: true,
      ),
      ReownAppKitModalNetworkInfo(
        name: 'Sepolia',
        chainId: 'eip155:11155111',
        currency: 'ETH',
        rpcUrl: nativeSepoliaRpcUrl,
        explorerUrl: 'https://sepolia.etherscan.io',
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
    old.onSessionEventEvent.unsubscribe(_onSessionEvent);
    old.onModalDisconnect.unsubscribe(_onModalDisconnect);
    old.onModalError.unsubscribe(_onModalError);
    unawaited(old.dispose());
    _initializing = null;
    _walletChain = null;
    if (_projectId.isEmpty || _disposed) {
      _appKit = null;
      return;
    }
    _appKit = _createAppKit(_context, _projectId);
    _appKit?.onModalConnect.subscribe(_onModalConnect);
    _appKit?.onModalUpdate.subscribe(_onModalUpdate);
    _appKit?.onModalNetworkChange.subscribe(_onModalNetworkChange);
    _appKit?.onSessionEventEvent.subscribe(_onSessionEvent);
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
    final modal = _modal;
    final session = modal.session;
    final walletChain = _walletChain;
    if (walletChain != null && walletChain.topic == session?.topic) {
      return walletChain.chainId;
    }
    // Reown's session.chainId is the first sorted approved chain. Use the
    // restored chain selection only if this session allows it.
    final approved = session?.getApprovedChains(namespace: 'eip155') ?? [];
    final selected = modal.selectedChain?.chainId;
    final chain = selected != null && approved.contains(selected)
        ? selected
        : approved.firstOrNull;
    try {
      if (chain != null && chain.startsWith('eip155:')) {
        return _positiveChainId(chain.substring('eip155:'.length));
      }
    } on FormatException {
      // Report invalid session data through the wallet adapter contract.
    }
    throw const MetamaskSiweException(MetamaskSiweErrorCode.invalidChainId);
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
    if (_modal.isConnected) {
      // Session-restore path: seed suppress guards so a later deep-link
      // handoff does not emit a bare disconnected/invalidProviderData.
      try {
        final connection = _connection();
        _lastAddress = connection.address;
        _lastChainId = connection.chainId;
        return connection;
      } catch (_) {
        rethrow;
      }
    }

    final connected = Completer<MetamaskWalletConnection>();
    final rejected = Completer<MetamaskSiweException>();

    void onConnect(ModalConnect? _) {
      if (!connected.isCompleted && _modal.isConnected) {
        try {
          final connection = _connection();
          _lastAddress = connection.address;
          _lastChainId = connection.chainId;
          connected.complete(connection);
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
    // Seed suppress guards when a readable session exists (session-restore
    // never goes through connect()'s onConnect).
    _lastAddress = address.toLowerCase();
    return [_lastAddress!];
  }

  @override
  Future<BigInt> getChainId() async {
    await _ensureReady();
    final chain = _chainId();
    _lastChainId = chain;
    return chain;
  }

  /// Shared raw EIP-1193-equivalent RPC boundary for native transactions.
  Future<Object?> requestRpc(
    String method, [
    List<Object?> params = const [],
  ]) => _requestRpc(method, params);

  Future<Object?> _requestRpc(
    String method,
    List<Object?> params, {
    BigInt? expectedChainId,
  }) async {
    await _ensureReady();
    final modal = _modal;
    final session = modal.session;
    final topic = session?.topic;
    if (!modal.isConnected || topic == null || topic.isEmpty) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConnected);
    }
    final chain = _chainId();
    if ((expectedChainId != null && chain != expectedChainId) ||
        session
                ?.getApprovedChains(namespace: 'eip155')
                ?.contains('eip155:$chain') !=
            true) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.chainChanged);
    }
    try {
      return await modal
          .request(
            topic: topic,
            chainId: 'eip155:$chain',
            request: SessionRequestParams(method: method, params: params),
          )
          .timeout(const Duration(minutes: 2));
    } on TimeoutException {
      // Drop the stale session so the next attempt opens a fresh MetaMask
      // connection instead of repeating the same dead request.
      try {
        await modal.disconnect();
      } catch (_) {}
      throw const MetamaskSiweException(MetamaskSiweErrorCode.timeout);
    } catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> switchChain(int chainId, {String? name, String? rpcUrl}) async {
    await _ensureReady();
    final modal = _modal;
    final topic = modal.session?.topic;
    if (!modal.isConnected || topic == null || topic.isEmpty) {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.notConnected);
    }
    final beforeSwitch = _walletChain;
    final target = BigInt.from(chainId);
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
      // AppKit already handles adding a missing network on this request.
      await modal
          .requestSwitchToChain(info)
          .timeout(const Duration(minutes: 2));
    } on TimeoutException {
      throw const MetamaskSiweException(MetamaskSiweErrorCode.timeout);
    } catch (error) {
      throw _mapError(error);
    }
    // MetaMask may update the session's approved chains after acknowledging
    // the switch. Wait until requests can be routed to the target chain.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final session = modal.session;
      if (!identical(_appKit, modal) ||
          (session != null && session.topic != topic)) {
        throw const MetamaskSiweException(MetamaskSiweErrorCode.disconnected);
      }
      final approved = session?.getApprovedChains(namespace: 'eip155') ?? [];
      if (approved.contains(info.chainId) &&
          (_chainId() == target ||
              (_walletChain == beforeSwitch &&
                  modal.selectedChain?.chainId == info.chainId))) {
        _walletChain = (topic: topic, chainId: target);
        _emitChainChange(target);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw const MetamaskSiweException(MetamaskSiweErrorCode.chainChanged);
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
    final result = await _requestRpc('personal_sign', [
      _hexMessage(message),
      actual.address,
    ], expectedChainId: actual.chainId);
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
      // Reown fires onModalUpdate on every session refresh (chain switch,
      // app resume, pairing ping). Emitting accountsChanged for the same
      // address makes AuthController log out via WALLET_CHANGED.
      if (connection.address == _lastAddress) {
        // Same account, new chain (damBaoMang / MetaMask switch): emit
        // chainChanged only so AuthController refreshes _chainId, not logout.
        _emitChainChange(connection.chainId);
        return;
      }
      _lastAddress = connection.address;
      _lastChainId = connection.chainId;
      _events.add(
        MetamaskSiweEvent(
          MetamaskSiweEventType.accountsChanged,
          accounts: [connection.address],
          chainId: connection.chainId,
        ),
      );
    } catch (_) {
      // Only surface malformed identity when we have no usable session.
      // Transient errors during MetaMask handoff must not log the user out.
      // Use _appKit (not _modal) so a disposed adapter does not rethrow here.
      if (_lastAddress != null && _appKit?.isConnected == true) return;
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
    if (event?.chainId == null || _events.isClosed) return;
    try {
      _emitChainChange(_chainId());
    } on MetamaskSiweException {
      // The modal can update its selection before a usable session exists.
    }
  }

  void _onSessionEvent(SessionEvent? event) {
    if (event == null ||
        _events.isClosed ||
        event.name != 'chainChanged' ||
        event.topic != _appKit?.session?.topic ||
        !event.chainId.startsWith('eip155:')) {
      return;
    }
    // The event envelope identifies its routing chain. The payload carries
    // the chain the wallet just switched to.
    final data = event.data.toString();
    final value = data.startsWith('eip155:')
        ? data.substring('eip155:'.length)
        : data;
    try {
      final chain = _positiveChainId(value);
      _walletChain = (topic: event.topic, chainId: chain);
      _emitChainChange(chain);
    } on FormatException {
      // Keep the last usable chain when the wallet sends a malformed event.
    }
  }

  void _emitChainChange(BigInt chain) {
    if (_events.isClosed || chain == _lastChainId) return;
    _lastChainId = chain;
    _events.add(
      MetamaskSiweEvent(MetamaskSiweEventType.chainChanged, chainId: chain),
    );
  }

  void _onModalDisconnect(ModalDisconnect? _) {
    if (_events.isClosed) return;
    // Deep-link handoff to MetaMask can emit a spurious disconnect while the
    // session topic is still alive. Only report a real loss of identity.
    if (_lastAddress != null && _appKit?.isConnected == true) return;
    _lastAddress = null;
    _lastChainId = null;
    _walletChain = null;
    _events.add(MetamaskSiweEvent(MetamaskSiweEventType.disconnected));
  }

  void _onModalError(ModalError? event) {
    if (event == null || _events.isClosed) return;
    // ErrorOpeningWallet / pairing noise after returning from MetaMask must
    // not tear down an authenticated session that still has an address.
    if (_lastAddress != null && _appKit?.isConnected == true) return;
    _events.add(
      MetamaskSiweEvent(
        MetamaskSiweEventType.invalidProviderData,
        error: _mapModalError(event),
      ),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final modal = _appKit;
    modal?.onModalConnect.unsubscribe(_onModalConnect);
    modal?.onModalUpdate.unsubscribe(_onModalUpdate);
    modal?.onModalNetworkChange.unsubscribe(_onModalNetworkChange);
    modal?.onSessionEventEvent.unsubscribe(_onSessionEvent);
    modal?.onModalDisconnect.unsubscribe(_onModalDisconnect);
    modal?.onModalError.unsubscribe(_onModalError);
    unawaited(modal?.dispose());
    unawaited(_events.close());
  }
}
