import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_de_xuat_do_kho.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'de_xuat_do_kho_test.dart' show deXuatMau;

http.Response _phanHoi([Map<String, dynamic>? data]) =>
    http.Response.bytes(utf8.encode(jsonEncode(data ?? deXuatMau())), 200);

void main() {
  test('gửi đúng endpoint, body màn chơi và header demo', () async {
    final requests = <http.Request>[];
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost:8000/base/',
      maNguoiChoiDemo: 'demo_1',
      client: MockClient((request) async {
        requests.add(request);
        return _phanHoi();
      }),
    );
    final kq = await api.deXuat(manChoi: 1);
    expect(kq.deXuat?.nguonNguCanh, 'demo');
    expect(kq.deXuat?.heSoTocDo, 1.0);
    expect(kq.loi, isNull);
    expect(requests, hasLength(1));
    expect(
      requests.single.url.toString(),
      'http://localhost:8000/base/api/ai/do-kho/de-xuat',
    );
    expect(jsonDecode(requests.single.body), {'stage_id': 1});
    expect(requests.single.headers['X-Demo-Player'], 'demo_1');
    expect(requests.single.headers.containsKey('Idempotency-Key'), isFalse);
    expect(requests.single.followRedirects, isFalse);
  });

  test('mặc định dùng ngữ cảnh backend, không tự gắn header demo', () async {
    final api = MayChuDeXuatDoKho(
      mayChu: 'https://example.test',
      client: MockClient((request) async {
        expect(request.headers.containsKey('X-Demo-Player'), isFalse);
        return _phanHoi(deXuatMau()..['context_source'] = 'verified');
      }),
    );
    expect((await api.deXuat(manChoi: 1)).deXuat?.nguonNguCanh, 'verified');
  });

  test('offline và màn sai không gửi mạng', () async {
    final client = MockClient((_) async => fail('Không được gửi mạng'));
    expect(
      (await MayChuDeXuatDoKho(mayChu: '', client: client).deXuat(manChoi: 1))
          .loi,
      LoiDeXuatDoKho.chuaCauHinh,
    );
    final api = MayChuDeXuatDoKho(mayChu: 'http://localhost', client: client);
    for (final man in [0, 1001]) {
      expect(
        (await api.deXuat(manChoi: man)).loi,
        LoiDeXuatDoKho.yeuCauKhongHopLe,
      );
    }
  });

  for (final code in [401, 403, 404, 422, 429, 500, 503, 302]) {
    test('HTTP $code trả lỗi có kiểu, không tự retry', () async {
      var soLan = 0;
      final api = MayChuDeXuatDoKho(
        mayChu: 'http://localhost',
        client: MockClient((_) async {
          soLan++;
          return http.Response('private error', code);
        }),
      );
      final kq = await api.deXuat(manChoi: 1);
      expect(
        kq.loi,
        code >= 500 ? LoiDeXuatDoKho.mayChu : LoiDeXuatDoKho.biTuChoi,
      );
      expect(kq.maHttp, code);
      expect(kq.coTheThuLai, code == 429 || code >= 500);
      expect(kq.deXuat, isNull);
      expect(soLan, 1);
    });
  }

  test('từ chối kết quả không khớp màn yêu cầu và dữ liệu sai', () async {
    for (final body in [
      '[]',
      '{}',
      'bad json',
      jsonEncode(deXuatMau()..['stage_id'] = 2),
    ]) {
      final api = MayChuDeXuatDoKho(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(body), 200),
        ),
      );
      expect(
        (await api.deXuat(manChoi: 1)).loi,
        LoiDeXuatDoKho.phanHoiKhongHopLe,
      );
    }
  });

  test('lỗi mạng và lỗi TLS trở thành kết quả để giao diện xử lý', () async {
    for (final error in [
      http.ClientException('private'),
      const HandshakeException('private'),
    ]) {
      final api = MayChuDeXuatDoKho(
        mayChu: 'https://localhost',
        client: MockClient((_) async => throw error),
      );
      final kq = await api.deXuat(manChoi: 1);
      expect(kq.loi, LoiDeXuatDoKho.ketNoi);
      expect(kq.coTheThuLai, isTrue);
    }
  });

  test('timeout phát tín hiệu abort cho kết nối đang đọc', () async {
    var daHuy = false;
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((request, input) async {
      await input.drain<void>();
      (request as http.AbortableRequest).abortTrigger!.then((_) {
        daHuy = true;
        body.addError(http.RequestAbortedException());
        body.close();
      });
      return http.StreamedResponse(body.stream, 200);
    });
    final api = MayChuDeXuatDoKho(
      mayChu: 'http://localhost',
      client: client,
      thoiGianCho: const Duration(milliseconds: 10),
    );
    expect((await api.deXuat(manChoi: 1)).loi, LoiDeXuatDoKho.hetThoiGian);
    await Future<void>.delayed(Duration.zero);
    expect(daHuy, isTrue);
    await body.close();
  });

  test('hủy body lỗi và giới hạn phản hồi trước khi giải mã', () async {
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
    final api = MayChuDeXuatDoKho(mayChu: 'http://localhost', client: client);
    await api.deXuat(manChoi: 1);
    expect(daHuy, isTrue);
    await stream.close();
    for (final bytes in [
      List.filled(65537, 32),
      [255],
    ]) {
      final kq = await MayChuDeXuatDoKho(
        mayChu: 'http://localhost',
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      ).deXuat(manChoi: 1);
      expect(kq.loi, LoiDeXuatDoKho.phanHoiKhongHopLe);
    }
  });

  test('đọc đề xuất từ HTTP thật bằng client mặc định', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final phucVu = server.first.then((request) async {
      expect(request.uri.path, '/api/ai/do-kho/de-xuat');
      expect(jsonDecode(await utf8.decoder.bind(request).join()), {
        'stage_id': 1,
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(deXuatMau()));
      await request.response.close();
    });
    final api = MayChuDeXuatDoKho(mayChu: 'http://127.0.0.1:${server.port}');
    final kq = await api.deXuat(manChoi: 1);
    await phucVu;
    expect(kq.deXuat?.lyDo, 'Chưa đủ lịch sử, đề xuất mức trung tính.');
  });

  test('kiểm tra cấu hình trước khi gửi mạng', () {
    for (final url in [
      'ftp://host',
      'http://user:pass@host',
      'http://host?key=secret',
      'host',
    ]) {
      expect(() => MayChuDeXuatDoKho(mayChu: url), throwsArgumentError);
    }
    expect(
      () => MayChuDeXuatDoKho(maNguoiChoiDemo: 'a\nb'),
      throwsArgumentError,
    );
    expect(
      () => MayChuDeXuatDoKho(thoiGianCho: Duration.zero),
      throwsArgumentError,
    );
  });
}
