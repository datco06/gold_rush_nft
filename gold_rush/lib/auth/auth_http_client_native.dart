/// Small in-memory cookie transport shared by Auth and protected game APIs.
///
/// Cookies are held only for the current process; no private key, SIWE
/// signature or session cookie is written to APK storage. The server still
/// requires its explicit Origin and CSRF headers for mutations.
library;

import 'package:http/http.dart' as http;

final _session = _NativeSession();

http.Client createAuthHttpClient() => _session;

class _NativeSession extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Map<String, String> _cookies = <String, String>{};

  final String _origin = const String.fromEnvironment(
    'GOLD_RUSH_NATIVE_ORIGIN',
    defaultValue: 'http://localhost:5174',
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.putIfAbsent('Origin', () => _origin);
    request.headers.putIfAbsent('Accept', () => 'application/json');
    if (_cookies.isNotEmpty) {
      request.headers['Cookie'] = _cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
    }
    final response = await _inner.send(request);
    _readCookies(response.headers['set-cookie']);
    return response;
  }

  void _readCookies(String? header) {
    if (header == null || header.isEmpty) return;
    for (final match in RegExp(
      r'(?:^|,\s*)([A-Za-z0-9_]+)=([^;\s,]*)',
    ).allMatches(header)) {
      final name = match.group(1)!;
      final value = match.group(2)!;
      if (value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  @override
  void close() {
    // The process-wide session is shared with MayChuPhieu and gameplay APIs.
    // AuthApiClient.close() must not invalidate those clients mid-session.
  }
}
