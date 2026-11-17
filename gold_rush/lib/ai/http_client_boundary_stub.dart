import 'package:http/http.dart' as http;

import '../auth/auth_http_client_native.dart';

/// Factory mặc định trên nền tảng không phải trình duyệt (VM/test).
http.Client taoClientNenTang() => createAuthHttpClient();
