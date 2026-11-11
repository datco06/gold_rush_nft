import 'package:http/http.dart' as http;

/// Factory mặc định trên nền tảng không phải trình duyệt (VM/test).
http.Client taoClientNenTang() => http.Client();

