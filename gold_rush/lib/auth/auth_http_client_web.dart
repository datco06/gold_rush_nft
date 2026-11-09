/// Web HTTP transport factory for cookie-based Auth.
/// Select this library at the platform boundary; it performs no Auth requests.
library;

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Create a fresh browser client that includes credentials across origins.
///
/// The browser manages HttpOnly cookies and Set-Cookie, subject to its cookie
/// policies and the backend's CORS configuration. Origin and CSRF checks remain
/// required; this factory neither reads cookies nor adds authentication headers.
///
/// The caller owns the client: reuse it for the Auth API lifecycle and close it
/// when done. With AuthApiClient injection, ownership transfers only when
/// closeInjectedClient is explicitly enabled. Closing a client is not logout.
http.Client createAuthHttpClient() {
  final client = BrowserClient();
  client.withCredentials = true;
  return client;
}
