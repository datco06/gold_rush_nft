import 'package:http/http.dart' as http;

import 'http_client_boundary_stub.dart'
    if (dart.library.js_interop) 'http_client_boundary_web.dart' as platform;

/// Tạo HTTP client tương thích nền tảng:
/// - Trên Web: BrowserClient với withCredentials = true để gửi cookie phiên bảo mật `gr_session`.
/// - Trên Native/Test: http.Client bình thường, cho phép mock dễ dàng.
http.Client taoHttpClientTrinhDuyet() => platform.taoClientNenTang();

