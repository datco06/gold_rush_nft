/// Default Auth HTTP transport for platforms without browser cookie support.
/// This library performs no network, cookie, storage or authentication work.
library;

import 'package:http/http.dart' as http;

/// Matches the Web factory's API while refusing unsupported Auth requests.
///
/// The caller owns this fresh client and closes it at the end of its lifecycle.
/// Explicitly injected test transports remain separate from this default. A
/// future native login needs its own wallet/session design, not a cookie jar
/// that pretends to provide browser authentication.
http.Client createAuthHttpClient() => _UnsupportedAuthHttpClient();

class _UnsupportedAuthHttpClient extends http.BaseClient {
  bool _closed = false;

  /// Reject before reading/finalizing the request or opening any connection.
  /// Do not attach the request URI: it may contain sensitive caller input.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException(
      _closed
          ? 'HTTP client Auth đã được đóng.'
          : 'HTTP Auth hiện chỉ được hỗ trợ trên Flutter Web.',
    );
  }

  /// Idempotent local cleanup only; this neither sends logout nor clears a
  /// server session. No sockets, streams or background tasks are owned here.
  @override
  void close() {
    _closed = true;
  }
}
