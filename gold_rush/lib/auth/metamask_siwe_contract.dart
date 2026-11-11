/// Platform-independent MetaMask capabilities and wallet data for SIWE.
///
/// Connecting a wallet or receiving a signature grants no Gold Rush access.
/// The backend verifies the original challenge/signature and manages nonce
/// consumption and sessions. This contract has no login state, session,
/// private-key/seed-phrase API or gameplay permission.
///
/// Integration is deliberately separate: the Web adapter still declares its
/// own types today. It must adopt and re-export these shared types before a
/// consumer can use both APIs interchangeably. Provider injection and access
/// remain Web implementation details, outside this contract.
library;

import 'dart:async';

/// Stable codes retained from the existing Web adapter, including transport
/// failures. Implementations must translate raw provider errors into safe data.
enum MetamaskSiweErrorCode {
  notInstalled,
  wrongProvider,
  ambiguousProvider,
  unsupportedProvider,
  userRejected,
  requestPending,
  notConnected,
  accountChanged,
  chainChanged,
  invalidAddress,
  invalidChainId,
  invalidMessage,
  invalidResponse,
  disconnected,
  interop,
  timeout,
  disposed,
}

/// UI-safe error data, without raw provider messages, signatures or SIWE text.
class MetamaskSiweException implements Exception {
  const MetamaskSiweException(this.code, {this.rpcCode});

  final MetamaskSiweErrorCode code;
  final int? rpcCode;

  String get message => switch (code) {
    MetamaskSiweErrorCode.notInstalled =>
      'Chưa thấy MetaMask. Hãy cài tiện ích rồi tải lại trang.',
    MetamaskSiweErrorCode.wrongProvider =>
      'Ví đang có không được nhận diện là MetaMask.',
    MetamaskSiweErrorCode.ambiguousProvider =>
      'Có nhiều provider MetaMask. Cần chọn rõ một provider.',
    MetamaskSiweErrorCode.unsupportedProvider =>
      'Provider thiếu API request hoặc API quản lý sự kiện cần thiết.',
    MetamaskSiweErrorCode.userRejected =>
      'Bạn đã từ chối yêu cầu trong MetaMask.',
    MetamaskSiweErrorCode.requestPending =>
      'MetaMask đang có yêu cầu chờ xử lý. Hãy xem popup đang mở.',
    MetamaskSiweErrorCode.notConnected =>
      'Chưa có tài khoản được cấp quyền. Hãy bấm kết nối MetaMask.',
    MetamaskSiweErrorCode.accountChanged =>
      'Tài khoản ví đã đổi. Hãy lấy challenge mới và xác thực lại.',
    MetamaskSiweErrorCode.chainChanged =>
      'Mạng ví đã đổi. Hãy lấy challenge mới và xác thực lại.',
    MetamaskSiweErrorCode.invalidAddress =>
      'Địa chỉ ví phải là 20 byte hexadecimal.',
    MetamaskSiweErrorCode.invalidChainId =>
      'MetaMask trả chain ID không hợp lệ.',
    MetamaskSiweErrorCode.invalidMessage =>
      'Thông điệp phải giữ nguyên UTF-8, không rỗng và tối đa 4096 byte.',
    MetamaskSiweErrorCode.invalidResponse =>
      'MetaMask trả dữ liệu không đúng định dạng.',
    MetamaskSiweErrorCode.disconnected => 'Provider MetaMask đã mất kết nối.',
    MetamaskSiweErrorCode.interop =>
      'Không giao tiếp được với provider MetaMask.',
    MetamaskSiweErrorCode.timeout => 'MetaMask chưa trả lời. Popup có thể vẫn đang mở; không tự gửi yêu cầu mới.',
    MetamaskSiweErrorCode.disposed => 'Adapter MetaMask đã được đóng.',
  };

  @override
  String toString() => message;
}

/// Wallet identity reported by an adapter, never an authenticated account.
/// Implementations validate the address and positive chain ID before returning.
class MetamaskWalletConnection {
  const MetamaskWalletConnection({
    required this.address,
    required this.chainId,
  });

  /// Lowercase 0x-prefixed 20-byte hex address, as returned by the Web adapter.
  final String address;

  /// Preserve precision, including values above 2^53-1; avoid narrowing to int.
  final BigInt chainId;
}

enum MetamaskSiweEventType {
  accountsChanged,
  chainChanged,
  disconnected,
  invalidProviderData,
}

/// Wallet notification only; no event establishes authentication.
class MetamaskSiweEvent {
  /// Public so implementations in separate libraries can emit shared events.
  /// Payload meanings match the existing Web adapter: accounts for account
  /// changes (empty on lost permission), chainId for network changes, and a
  /// sanitized error for disconnect or invalid provider data.
  MetamaskSiweEvent(
    this.type, {
    List<String> accounts = const [],
    this.chainId,
    this.error,
  }) : accounts = List.unmodifiable(accounts);

  final MetamaskSiweEventType type;
  final List<String> accounts;
  final BigInt? chainId;
  final MetamaskSiweException? error;
}

/// Capabilities required by AuthController's wallet wrapper.
///
/// Implementations accept no private keys and create no sessions. An unsupported
/// platform reports unavailable and rejects connect/sign with typed errors;
/// it must never manufacture an account, chain ID or signature.
abstract interface class MetamaskSiwePort {
  /// Broadcast wallet changes synchronously, before pending operations resume,
  /// so the controller can invalidate old work even after an away-and-back
  /// change. Malformed data uses invalidProviderData with a sanitized error.
  /// The stream must not emit synthetic connection/authentication successes.
  Stream<MetamaskSiweEvent> get events;

  /// Non-interactive availability check: no account/signing request or popup.
  /// Return false for absent/unsupported MetaMask; other failures may be typed
  /// errors, matching the Web adapter's existing behavior.
  Future<bool> checkAvailability();

  /// Only invoke after an explicit user action. A returned wallet identity
  /// proves neither a valid SIWE signature nor a Gold Rush login.
  Future<MetamaskWalletConnection> connect();

  /// Non-interactive read of authorized accounts; empty means no permission.
  /// Implementations validate returned addresses and never invent accounts.
  Future<List<String>> getAccounts();

  /// Non-interactive read of the provider's positive chain ID, without loss of
  /// precision. Unsupported platforms reject instead of supplying a default.
  Future<BigInt> getChainId();

  /// Sign the backend's exact UTF-8 message after explicit user interaction,
  /// using personal_sign/EIP-191. Do not rebuild, trim or double-prefix it.
  /// Validate the account and optional expected chain around signing and reject
  /// changes during the operation. Return only a real provider signature;
  /// cryptographic verification and access decisions remain on the backend.
  Future<String> signSiweMessage({
    required String address,
    required String message,
    BigInt? expectedChainId,
  });

  /// Idempotently release only resources owned by this adapter, close its event
  /// stream and invalidate pending results. This cannot revoke backend sessions
  /// or promise to close an extension popup. Later active calls reject safely.
  void dispose();
}
