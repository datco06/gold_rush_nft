/// Auth HTTP API with a platform-selected default transport: credentialed
/// browser HTTP on Web, or an unsupported-platform client on VM/native.
/// No MetaMask calls, app-wide login state, cookie access, storage or logging.
///
/// The browser owns Origin and HttpOnly cookies. The default Web factory uses
/// withCredentials=true (fetch credentials:include). Injected clients retain
/// their caller-supplied configuration and must provide equivalent credentials,
/// honor followRedirects=false and must NOT retry Auth mutations automatically.
/// Use the same instance for challenge/verify/register/me/logout. Keep localhost
/// consistent with frontend config; never silently replace it with 127.0.0.1.
///
/// Timeouts cannot undo a server commit or a browser Set-Cookie. Mutations are
/// serialized until their underlying exchange settles, even after timeout.
/// outcomeUncertain tells the later Auth Controller to lock/reconcile the flow,
/// not start a new login or claim logout succeeded. This transport neither
/// persists CSRF nor decides whether gameplay may open. No request is retried.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_http_client_stub.dart'
    if (dart.library.js_interop) 'auth_http_client_web.dart'
    as platform_http;

enum AuthApiErrorKind {
  invalidConfiguration,
  invalidRequest,
  network,
  timeout,
  validation,
  unauthenticated,
  forbidden,
  conflict,
  expired,
  rateLimited,
  server,
  unexpectedStatus,
  invalidResponse,
  requestPending,
  closed,
}

/// No raw response, URL, input, JavaScript error or sensitive token is retained.
class AuthApiException implements Exception {
  const AuthApiException(
    this.kind, {
    this.statusCode,
    this.code,
    this.field,
    this.outcomeUncertain = false,
  });

  final AuthApiErrorKind kind;
  final int? statusCode;
  final String? code;
  final String? field;
  final bool outcomeUncertain;

  String get message {
    if (code == 'USERNAME_TAKEN') return 'Tên nhà thám hiểm đã được sử dụng.';
    if (code == 'USERNAME_INVALID') return 'Tên nhân vật không hợp lệ.';
    if (code == 'CSRF_INVALID') {
      return 'CSRF không hợp lệ. Cần đối chiếu lại phiên.';
    }
    if (code == 'WALLET_ALREADY_REGISTERED') {
      return 'Ví đã có tài khoản. Hãy xác thực lại để đăng nhập.';
    }
    if (code == 'CHALLENGE_USED') {
      return 'Challenge đã được sử dụng. Hãy bắt đầu xác thực mới.';
    }
    return switch (kind) {
      AuthApiErrorKind.invalidConfiguration =>
        'Cấu hình HTTP Auth không hợp lệ.',
      AuthApiErrorKind.invalidRequest => 'Dữ liệu gửi tới Auth không hợp lệ.',
      AuthApiErrorKind.network =>
        'Không liên lạc được Auth. Kiểm tra Backend, mạng và CORS.',
      AuthApiErrorKind.timeout =>
        'Auth chưa trả lời trong thời hạn; chưa xác định kết quả trên máy chủ.',
      AuthApiErrorKind.validation => 'Máy chủ từ chối dữ liệu yêu cầu.',
      AuthApiErrorKind.unauthenticated =>
        'Phiên hoặc quyền xác thực không còn hợp lệ.',
      AuthApiErrorKind.forbidden =>
        'Yêu cầu không được phép. Kiểm tra Origin và CSRF.',
      AuthApiErrorKind.conflict =>
        'Dữ liệu Auth xung đột; cần kiểm tra lại luồng xác thực.',
      AuthApiErrorKind.expired => 'Challenge hoặc quyền xác thực đã hết hạn.',
      AuthApiErrorKind.rateLimited =>
        'Quá nhiều yêu cầu. Hãy thử lại sau theo hướng dẫn máy chủ.',
      AuthApiErrorKind.server => 'Máy chủ Auth tạm thời không sẵn sàng.',
      AuthApiErrorKind.unexpectedStatus =>
        'Máy chủ trả HTTP status ngoài hợp đồng Auth.',
      AuthApiErrorKind.invalidResponse =>
        'Dữ liệu Auth trả về không đúng hợp đồng.',
      AuthApiErrorKind.requestPending =>
        'Yêu cầu Auth trước vẫn đang xử lý; chưa được gửi mutation mới.',
      AuthApiErrorKind.closed => 'HTTP client Auth đã được đóng.',
    };
  }

  @override
  String toString() => message;
}

const _malformed = AuthApiException(AuthApiErrorKind.invalidResponse);
const _invalidInput = AuthApiException(AuthApiErrorKind.invalidRequest);
final _maxChainId = (BigInt.one << 256) - BigInt.one;

bool _matches(String text, String pattern) {
  final match = RegExp(pattern).firstMatch(text);
  return match != null && match.start == 0 && match.end == text.length;
}

bool _validUtf8(String text) => utf8.decode(utf8.encode(text)) == text;

Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    throw _malformed;
  }
  return Map<String, Object?>.from(value);
}

String _text(Object? value, {int min = 1, int max = 4096}) {
  if (value is! String ||
      value.length > max * 2 ||
      !_validUtf8(value) ||
      value.runes.length < min ||
      value.runes.length > max) {
    throw _malformed;
  }
  return value;
}

String _wallet(Object? value) {
  final text = _text(value, max: 42);
  if (!_matches(text, r'0x[0-9a-fA-F]{40}')) throw _malformed;
  return text.toLowerCase();
}

String _uuid(Object? value) {
  final text = _text(value, max: 36);
  if (!_matches(
    text,
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  )) {
    throw _malformed;
  }
  return text.toLowerCase();
}

String _csrf(Object? value) {
  final text = _text(value, max: 1024);
  if (text.codeUnits.any((point) => point < 0x21 || point > 0x7e)) {
    throw _malformed;
  }
  return text;
}

DateTime _utcTime(Object? value) {
  final text = _text(value, max: 40);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(text);
  if (match == null || match.end != text.length) throw _malformed;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final [year, month, day, hour, minute, second] = parts;
  final calendar = DateTime.utc(year, month, day);
  if (year < 1 ||
      calendar.year != year ||
      calendar.month != month ||
      calendar.day != day ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      (match.group(8) != null && int.parse(match.group(8)!) > 23) ||
      (match.group(9) != null && int.parse(match.group(9)!) > 59)) {
    throw _malformed;
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc) throw _malformed;
  return parsed.toUtc();
}

class AuthChallengeResponse {
  const AuthChallengeResponse._(this.challengeId, this.message, this.expiresAt);

  factory AuthChallengeResponse.fromJson(Object? value) {
    final json = _object(value, {'challenge_id', 'message', 'expires_at'});
    final message = _text(json['message']);
    if (utf8.encode(message).length > 4096) throw _malformed;
    return AuthChallengeResponse._(
      _uuid(json['challenge_id']),
      message,
      _utcTime(json['expires_at']),
    );
  }

  final String challengeId;
  final String message;
  final DateTime expiresAt;

  @override
  String toString() => 'AuthChallengeResponse(<redacted>)';
}

class AuthPublicUser {
  const AuthPublicUser._(
    this.id,
    this.walletAddress,
    this.username,
    this.avatar,
    this.createdAt,
  );

  factory AuthPublicUser.fromJson(Object? value) {
    final json = _object(value, {
      'id',
      'wallet_address',
      'username',
      'avatar',
      'created_at',
    });
    if (json['avatar'] != 'george') throw _malformed;
    return AuthPublicUser._(
      _uuid(json['id']),
      _wallet(json['wallet_address']),
      _text(json['username'], min: 3, max: 20),
      'george',
      _utcTime(json['created_at']),
    );
  }

  final String id;
  final String walletAddress;
  final String username;
  final String avatar;
  final DateTime createdAt;

  @override
  String toString() => 'AuthPublicUser';
}

sealed class AuthVerifyResult {
  const AuthVerifyResult._(this.expiresAt, this.csrfToken);

  factory AuthVerifyResult.fromJson(Object? value) {
    if (value is! Map) throw _malformed;
    return switch (value['status']) {
      'authenticated' => AuthAuthenticatedResult.fromJson(value),
      'registration_required' => AuthRegistrationRequired.fromJson(value),
      _ => throw _malformed,
    };
  }

  final DateTime expiresAt;
  final String csrfToken;
  String get status;

  @override
  String toString() => 'AuthVerifyResult($status, <redacted>)';
}

final class AuthAuthenticatedResult extends AuthVerifyResult {
  const AuthAuthenticatedResult._(this.user, super.expiresAt, super.csrfToken)
    : super._();

  factory AuthAuthenticatedResult.fromJson(Object? value) {
    final json = _object(value, {'status', 'user', 'expires_at', 'csrf_token'});
    if (json['status'] != 'authenticated') throw _malformed;
    return AuthAuthenticatedResult._(
      AuthPublicUser.fromJson(json['user']),
      _utcTime(json['expires_at']),
      _csrf(json['csrf_token']),
    );
  }

  final AuthPublicUser user;
  @override
  String get status => 'authenticated';
}

final class AuthRegistrationRequired extends AuthVerifyResult {
  const AuthRegistrationRequired._(
    this.walletAddress,
    super.expiresAt,
    super.csrfToken,
  ) : super._();

  factory AuthRegistrationRequired.fromJson(Object? value) {
    final json = _object(value, {
      'status',
      'wallet_address',
      'expires_at',
      'csrf_token',
    });
    if (json['status'] != 'registration_required') throw _malformed;
    return AuthRegistrationRequired._(
      _wallet(json['wallet_address']),
      _utcTime(json['expires_at']),
      _csrf(json['csrf_token']),
    );
  }

  final String walletAddress;
  @override
  String get status => 'registration_required';
}

class AuthMeResponse {
  const AuthMeResponse._(
    this.user,
    this.chainId,
    this.expiresAt,
    this.csrfToken,
  );

  factory AuthMeResponse.fromJson(Object? value) {
    final json = _object(value, {
      'user',
      'chain_id',
      'expires_at',
      'csrf_token',
    });
    final raw = json['chain_id'];
    // Map callers may supply BigInt or a provably safe Dart/JS integer. The HTTP
    // decoder below recovers the original JSON integer BEFORE JS rounding.
    final BigInt chain;
    if (raw is BigInt) {
      chain = raw;
    } else if (raw is int && raw > 0 && raw <= 9007199254740991) {
      chain = BigInt.from(raw);
    } else {
      throw _malformed;
    }
    if (chain <= BigInt.zero || chain > _maxChainId) throw _malformed;
    return AuthMeResponse._(
      AuthPublicUser.fromJson(json['user']),
      chain,
      _utcTime(json['expires_at']),
      _csrf(json['csrf_token']),
    );
  }

  final AuthPublicUser user;
  final BigInt chainId;
  final DateTime expiresAt;
  final String csrfToken;

  @override
  String toString() => 'AuthMeResponse(<redacted>)';
}

/// JSON has integer chain IDs up to uint256, while JSON.parse/Dart web numbers
/// lose precision above 2^53-1. Validate JSON normally, then scan only TOP-LEVEL
/// keys (decoding escapes) to recover the exact chain_id numeric lexeme. Strings
/// and nested values cannot masquerade as that field. Duplicate keys, quoted
/// numbers, fractions and exponents are rejected for chain_id, never rounded.
BigInt _wireChainId(String source) {
  var depth = 0;
  BigInt? result;
  for (var i = 0; i < source.length; i++) {
    final unit = source.codeUnitAt(i);
    if (unit == 0x22) {
      final start = i;
      i++;
      while (i < source.length && source.codeUnitAt(i) != 0x22) {
        if (source.codeUnitAt(i) == 0x5c) i++;
        i++;
      }
      if (depth != 1) continue;
      var next = i + 1;
      while (next < source.length && source.codeUnitAt(next) <= 0x20) {
        next++;
      }
      if (next >= source.length || source[next] != ':') continue;
      if (jsonDecode(source.substring(start, i + 1)) != 'chain_id') continue;
      if (result != null) throw _malformed;
      next++;
      final end = source.indexOf(RegExp(r'[,}]'), next);
      if (end < 0) throw _malformed;
      final token = source.substring(next, end).trim();
      if (!_matches(token, r'[1-9][0-9]{0,77}')) throw _malformed;
      result = BigInt.parse(token);
    } else if (unit == 0x7b || unit == 0x5b) {
      depth++;
    } else if (unit == 0x7d || unit == 0x5d) {
      depth--;
    }
  }
  if (result == null || result > _maxChainId) throw _malformed;
  return result;
}

class AuthApiClient {
  AuthApiClient({
    String baseUrl = 'http://localhost:8000',
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    bool closeInjectedClient = false,
  }) : baseUri = _baseUri(baseUrl),
       _client = client ?? platform_http.createAuthHttpClient(),
       _ownsClient = client == null || closeInjectedClient {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 2)) {
      if (client == null) _client.close();
      throw const AuthApiException(AuthApiErrorKind.invalidConfiguration);
    }
  }

  final Uri baseUri;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;
  bool _mutationPending = false;

  /// True until the real exchange settles, including after a timeout.
  bool get mutationPending => _mutationPending;

  static Uri _baseUri(String value) {
    try {
      final uri = Uri.parse(value);
      if (value != value.trim() ||
          value.contains('\\') ||
          value.contains('@') ||
          value.codeUnits.any((c) => c <= 0x20 || c >= 0x7f) ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          uri.authority.contains('@') ||
          uri.hasQuery ||
          uri.hasFragment ||
          !{'', '/'}.contains(uri.path) ||
          uri.port < 1 ||
          uri.port > 65535 ||
          (uri.scheme == 'http' &&
              !{'localhost', '127.0.0.1', '::1'}.contains(uri.host))) {
        throw const AuthApiException(AuthApiErrorKind.invalidConfiguration);
      }
      return uri.replace(path: '');
    } catch (_) {
      throw const AuthApiException(AuthApiErrorKind.invalidConfiguration);
    }
  }

  Future<AuthChallengeResponse> createChallenge({
    required String walletAddress,
    required BigInt chainId,
  }) {
    try {
      _wallet(walletAddress);
      if (chainId <= BigInt.zero || chainId > _maxChainId) throw _invalidInput;
    } catch (_) {
      throw _invalidInput;
    }
    // Embed ONLY a validated BigInt decimal literal; encode all string values.
    final body =
        '{"wallet_address":${jsonEncode(walletAddress)},"chain_id":$chainId}';
    return _send(
      'POST',
      '/api/auth/challenge',
      201,
      AuthChallengeResponse.fromJson,
      body: body,
      bootstrap: true,
    );
  }

  Future<AuthVerifyResult> verify({
    required String challengeId,
    required String message,
    required String signature,
  }) {
    try {
      _uuid(challengeId);
      if (message.isEmpty ||
          !_validUtf8(message) ||
          utf8.encode(message).length > 4096 ||
          !_matches(signature, r'0x[0-9a-fA-F]{130}')) {
        throw _invalidInput;
      }
    } catch (_) {
      throw _invalidInput;
    }
    return _send(
      'POST',
      '/api/auth/verify',
      200,
      AuthVerifyResult.fromJson,
      bootstrap: true,
      body: jsonEncode({
        'challenge_id': challengeId,
        'message': message,
        'signature': signature,
      }),
    );
  }

  Future<AuthAuthenticatedResult> register({
    required String username,
    required String csrfToken,
  }) {
    // Backend is the source of Unicode NFC/casefold/username uniqueness policy.
    if (!_validUtf8(username) ||
        username.isEmpty ||
        username.runes.length > 256) {
      throw _invalidInput;
    }
    return _send(
      'POST',
      '/api/auth/register',
      201,
      AuthAuthenticatedResult.fromJson,
      body: jsonEncode({'username': username}),
      csrfToken: csrfToken,
    );
  }

  Future<AuthMeResponse> getMe() =>
      _send('GET', '/api/me', 200, AuthMeResponse.fromJson);

  /// A network/timeout error never means the backend revoked its session.
  Future<void> logout({required String csrfToken}) => _send<void>(
    'POST',
    '/api/auth/logout',
    204,
    (_) {},
    body: '{}',
    csrfToken: csrfToken,
  );

  Future<T> _send<T>(
    String method,
    String path,
    int expected,
    T Function(Object?) parse, {
    String? body,
    bool bootstrap = false,
    String? csrfToken,
  }) async {
    if (_closed) throw const AuthApiException(AuthApiErrorKind.closed);
    // Also block /me while an old Set-Cookie mutation may still be pending.
    if (_mutationPending) {
      throw const AuthApiException(AuthApiErrorKind.requestPending);
    }
    if (csrfToken != null) {
      try {
        _csrf(csrfToken);
      } catch (_) {
        throw _invalidInput;
      }
    }
    final bytes = body == null ? const <int>[] : utf8.encode(body);
    if (bytes.length > 8192) throw _invalidInput;
    final request = http.Request(method, baseUri.resolve(path))
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = bytes;
    }
    if (bootstrap) request.headers['X-Gold-Rush-Auth'] = '1';
    if (csrfToken != null) request.headers['X-CSRF-Token'] = csrfToken;
    final mutation = method != 'GET';
    if (mutation) _mutationPending = true;
    final exchange = _exchange(request, expected, parse, mutation: mutation)
        .whenComplete(() {
          if (mutation) _mutationPending = false;
        });
    try {
      return await exchange.timeout(timeout);
    } on TimeoutException {
      throw AuthApiException(
        AuthApiErrorKind.timeout,
        outcomeUncertain: mutation,
      );
    }
  }

  Future<T> _exchange<T>(
    http.Request request,
    int expected,
    T Function(Object?) parse, {
    required bool mutation,
  }) async {
    int? status;
    try {
      final response = await _client.send(request);
      status = response.statusCode;
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 65536) throw _malformed;
        bytes.addAll(chunk);
      }
      if (_closed) throw const AuthApiException(AuthApiErrorKind.closed);
      if (status != expected) throw _httpError(status, bytes, mutation);
      if (expected == 204) return parse(null);
      if (response.headers['content-type']
              ?.split(';')
              .first
              .trim()
              .toLowerCase() !=
          'application/json') {
        throw _malformed;
      }
      final source = utf8.decode(bytes);
      final value = jsonDecode(source);
      if (request.url.path == '/api/me' &&
          value is Map &&
          value.containsKey('chain_id')) {
        value['chain_id'] = _wireChainId(source);
      }
      return parse(value);
    } on AuthApiException catch (error) {
      throw AuthApiException(
        error.kind,
        statusCode: error.statusCode ?? status,
        code: error.code,
        field: error.field,
        outcomeUncertain:
            error.outcomeUncertain ||
            (mutation &&
                {
                  AuthApiErrorKind.invalidResponse,
                  AuthApiErrorKind.closed,
                }.contains(error.kind)),
      );
    } on TimeoutException {
      throw AuthApiException(
        AuthApiErrorKind.timeout,
        statusCode: status,
        outcomeUncertain: mutation,
      );
    } on http.ClientException {
      // Browser fetch does not reliably distinguish CORS/DNS/refused/offline.
      throw AuthApiException(
        AuthApiErrorKind.network,
        statusCode: status,
        outcomeUncertain: mutation,
      );
    } on FormatException {
      throw AuthApiException(
        AuthApiErrorKind.invalidResponse,
        statusCode: status,
        outcomeUncertain: mutation,
      );
    } catch (_) {
      throw AuthApiException(
        AuthApiErrorKind.network,
        statusCode: status,
        outcomeUncertain: mutation,
      );
    }
  }

  AuthApiException _httpError(int status, List<int> bytes, bool mutation) {
    String? code;
    String? field;
    try {
      final body = jsonDecode(utf8.decode(bytes));
      final detail = body is Map ? body['detail'] : null;
      if (detail is Map) {
        final value = detail['code'];
        if (value is String && _matches(value, r'[A-Z][A-Z0-9_]{0,63}')) {
          code = value;
        }
        if (detail['field'] == 'username') field = 'username';
      } else if (detail is List) {
        code = 'VALIDATION_ERROR';
        if (detail.any(
          (item) =>
              item is Map &&
              item['loc'] is List &&
              (item['loc'] as List).length == 2 &&
              item['loc'][0] == 'body' &&
              item['loc'][1] == 'username',
        )) {
          field = 'username';
        }
      }
    } catch (_) {
      // Never echo raw body, input, validation context or server message.
    }
    final kind = switch (status) {
      400 || 422 => AuthApiErrorKind.validation,
      401 => AuthApiErrorKind.unauthenticated,
      403 => AuthApiErrorKind.forbidden,
      409 => AuthApiErrorKind.conflict,
      410 => AuthApiErrorKind.expired,
      429 => AuthApiErrorKind.rateLimited,
      >= 500 && <= 599 => AuthApiErrorKind.server,
      _ => AuthApiErrorKind.unexpectedStatus,
    };
    return AuthApiException(
      kind,
      statusCode: status,
      code: code,
      field: field,
      outcomeUncertain:
          mutation && (status >= 500 || status >= 200 && status < 400),
    );
  }

  /// Closes only an owned transport unless closeInjectedClient was requested.
  /// This does NOT log out or clear browser cookies. A controller must complete
  /// server logout separately; closing a request cannot undo server-side work.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  void dispose() => close();

  @override
  String toString() => 'AuthApiClient';
}
