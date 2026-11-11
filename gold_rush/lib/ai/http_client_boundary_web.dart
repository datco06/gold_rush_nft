import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Factory HTTP client trên Flutter Web:
/// Thiết lập withCredentials = true để trình duyệt tự động đính kèm cookie HttpOnly `gr_session` và `gr_auth_flow`.
http.Client taoClientNenTang() {
  final client = BrowserClient();
  client.withCredentials = true;
  return client;
}

