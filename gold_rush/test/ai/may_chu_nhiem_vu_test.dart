import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_nhiem_vu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'nhiem_vu_test.dart' show phanHoiMau;

void main() {
  test('timeout phát tín hiệu hủy cho HTTP client hỗ trợ abort', () async {
    var daHuy = false;
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((request, requestBody) async {
      await requestBody.drain<void>();
      if (request is http.AbortableRequest) {
        request.abortTrigger!.then((_) {
          daHuy = true;
          body.addError(http.RequestAbortedException());
          body.close();
        });
      }
      return http.StreamedResponse(body.stream, 200);
    });
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: client,
      thoiGianCho: const Duration(milliseconds: 10),
    );
    final kq = await api.tao(manChoi: 1, maYeuCau: 'req_1');
    await Future<void>.delayed(Duration.zero);
    expect(kq.loi, LoiNhiemVu.hetThoiGian);
    expect(daHuy, isTrue);
    await body.close();
  });

  test('hủy đọc body lỗi để giải phóng kết nối được truyền vào', () async {
    var daHuy = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        daHuy = true;
      },
    );
    final client = MockClient.streaming((_, body) async {
      await body.drain<void>();
      return http.StreamedResponse(stream.stream, 503);
    });
    final api = MayChuNhiemVu(mayChu: 'http://localhost', client: client);
    final kq = await api.tao(manChoi: 1, maYeuCau: 'req_1');
    expect(kq.loi, LoiNhiemVu.mayChu);
    expect(daHuy, isTrue);
    await stream.close();
  });

  test('giới hạn kích thước body và từ chối UTF-8 hỏng', () async {
    for (final bytes in [
      List.filled(65537, 32),
      [255],
    ]) {
      final api = MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      expect(
        (await api.tao(manChoi: 1, maYeuCau: 'req_1')).loi,
        LoiNhiemVu.phanHoiKhongHopLe,
      );
    }
  });

  test('client mặc định gửi HTTP thật và đọc UTF-8', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final phucVu = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/ai/nhiem-vu/tao');
      expect(request.headers.value('Idempotency-Key'), 'real_http');
      expect(request.headers.value('X-Demo-Player'), 'demo_1');
      expect(jsonDecode(await utf8.decoder.bind(request).join()), {
        'stage_id': 1,
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(phanHoiMau()));
      await request.response.close();
    });
    final api = MayChuNhiemVu(
      mayChu: 'http://127.0.0.1:${server.port}',
      maNguoiChoiDemo: 'demo_1',
    );
    final kq = await api.tao(manChoi: 1, maYeuCau: 'real_http');
    await phucVu;
    expect(kq.nhiemVu?.tieuDe, 'Tìm kho báu');
  });

  test('từ chối thời gian chờ ngoài phạm vi', () {
    for (final duration in [Duration.zero, const Duration(seconds: 61)]) {
      expect(() => MayChuNhiemVu(thoiGianCho: duration), throwsArgumentError);
    }
  });

  test('gửi đúng URL, body và giữ khóa qua lần thử lại', () async {
    final cacYeuCau = <http.Request>[];
    final client = MockClient((request) async {
      cacYeuCau.add(request);
      if (cacYeuCau.length == 1) return http.Response('server error', 503);
      return http.Response(
        jsonEncode(phanHoiMau()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost:8000/',
      maNguoiChoiDemo: 'demo_1',
      client: client,
    );
    final lanDau = await api.tao(manChoi: 1, maYeuCau: 'req_1');
    expect(lanDau.loi, LoiNhiemVu.mayChu);
    expect(lanDau.coTheThuLai, isTrue);
    expect(cacYeuCau, hasLength(1));
    final lanHai = await api.tao(manChoi: 1, maYeuCau: 'req_1');
    expect(lanHai.nhiemVu?.tieuDe, 'Tìm kho báu');
    expect(lanHai.loi, isNull);
    for (final request in cacYeuCau) {
      expect(
        request.url.toString(),
        'http://localhost:8000/api/ai/nhiem-vu/tao',
      );
      expect(request.headers['Idempotency-Key'], 'req_1');
      expect(request.headers['X-Demo-Player'], 'demo_1');
      expect(request.followRedirects, isFalse);
      expect(jsonDecode(request.body), {'stage_id': 1});
    }
  });

  test('chế độ mặc định gửi yêu cầu không có danh tính demo', () async {
    final client = MockClient((request) async {
      expect(request.headers.containsKey('X-Demo-Player'), isFalse);
      return http.Response(
        jsonEncode(phanHoiMau()..['context_source'] = 'verified'),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final kq = await MayChuNhiemVu(
      mayChu: 'https://example.test',
      client: client,
    ).tao(manChoi: 1, maYeuCau: 'req_2');
    expect(kq.nhiemVu?.nguonNguCanh, 'verified');
  });

  test('chưa cấu hình API trả trạng thái offline', () async {
    final api = MayChuNhiemVu(
      mayChu: '',
      client: MockClient((_) async {
        fail('Không được gửi mạng khi offline');
      }),
    );
    expect(
      (await api.tao(manChoi: 1, maYeuCau: 'req_1')).loi,
      LoiNhiemVu.chuaCauHinh,
    );
  });

  for (final code in [401, 403, 404, 409, 422, 429, 500, 503, 302]) {
    test('xử lý HTTP $code mà không ném lỗi', () async {
      final api = MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient((_) async => http.Response('private error', code)),
      );
      final kq = await api.tao(manChoi: 1, maYeuCau: 'req_1');
      expect(kq.nhiemVu, isNull);
      expect(kq.maHttp, code);
      expect(kq.coTheThuLai, code == 429 || code >= 500);
      expect(kq.loi, code >= 500 ? LoiNhiemVu.mayChu : LoiNhiemVu.biTuChoi);
    });
  }

  for (final body in ['not json', '[]', '{}', '{"schema_version":2}']) {
    test('phản hồi sai cấu trúc $body', () async {
      final api = MayChuNhiemVu(
        mayChu: 'http://localhost',
        client: MockClient((_) async => http.Response(body, 200)),
      );
      final kq = await api.tao(manChoi: 1, maYeuCau: 'req_1');
      expect(kq.loi, LoiNhiemVu.phanHoiKhongHopLe);
      expect(kq.coTheThuLai, isFalse);
    });
  }

  test('từ chối phản hồi thuộc màn khác', () async {
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode(phanHoiMau()..['stage_id'] = 2)),
          200,
        ),
      ),
    );
    expect(
      (await api.tao(manChoi: 1, maYeuCau: 'req_1')).loi,
      LoiNhiemVu.phanHoiKhongHopLe,
    );
  });

  test('lỗi mạng có thể thử lại', () async {
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient((_) async => throw http.ClientException('private')),
    );
    final kq = await api.tao(manChoi: 1, maYeuCau: 'req_1');
    expect(kq.loi, LoiNhiemVu.ketNoi);
    expect(kq.coTheThuLai, isTrue);
  });

  test('hết hạn chờ trả trạng thái có thể thử lại', () async {
    final pending = Completer<http.Response>();
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      thoiGianCho: const Duration(milliseconds: 10),
      client: MockClient((_) => pending.future),
    );
    final kq = await api.tao(manChoi: 1, maYeuCau: 'req_1');
    expect(kq.loi, LoiNhiemVu.hetThoiGian);
    expect(kq.coTheThuLai, isTrue);
    pending.complete(http.Response('', 503));
  });

  test('dữ liệu yêu cầu sai bị chặn trước khi gửi mạng', () async {
    final api = MayChuNhiemVu(
      mayChu: 'http://localhost',
      client: MockClient((_) async => fail('Yêu cầu sai không được gửi')),
    );
    for (final cap in [(0, 'ok'), (1001, 'ok'), (1, ''), (1, 'a\nb')]) {
      expect(
        (await api.tao(manChoi: cap.$1, maYeuCau: cap.$2)).loi,
        LoiNhiemVu.yeuCauKhongHopLe,
      );
    }
  });

  test('từ chối URL không an toàn và mã demo sai', () {
    for (final url in [
      'ftp://host',
      'http://user:pass@host',
      'http://host?key=secret',
      'http://host#fragment',
      'host',
    ]) {
      expect(() => MayChuNhiemVu(mayChu: url), throwsArgumentError);
    }
    expect(
      () => MayChuNhiemVu(mayChu: 'http://host', maNguoiChoiDemo: 'a\nb'),
      throwsArgumentError,
    );
  });
}
