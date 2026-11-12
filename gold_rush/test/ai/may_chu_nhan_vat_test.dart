import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/anh_nhan_vat.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'anh_nhan_vat_test.dart' show maAnhMau, metadataAnhMau;

Future<Uint8List> pngMau([int canh = 128]) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff336699), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(canh, canh);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

http.Response _metadata() => http.Response(
  jsonEncode(metadataAnhMau()),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('rejects animated PNG with matching dimensions', () async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAACGFjVEwAAAACAAAAAPONk3AAAAAaZmNUTAAAAAAAAACAAAAAgAAAAAAAAAAAAAEACgAA4PBDiwAAAU1JREFUeJzt0jEBACAMwLCBf89DBkcTBT16dmaHrPs7gL8MEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiHtgBQL+dhncPAAAABpmY1RMAAAAAQAAAIAAAACAAAAAAAAAAAAAAQAKAAB7g6lfAAABUWZkQVQAAAACeJzt0jEBACAMwLCBf89DBkcTBT16ZnaHrPs7gL8MEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiDNAnAHiDBBngDgDxBkgzgBxBogzQJwB4gwQZ4A4A8QZIM4AcQaIM0CcAeIMEGeAOAPEGSDOAHEGiHteBwL+gdEzTwAAAABJRU5ErkJggg==',
    );
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );
    final kq = await api.tai(AnhNhanVat.tuJson(metadataAnhMau()));
    expect(kq.loi, LoiAnhNhanVat.phanHoiKhongHopLe);
    expect(kq.png, isNull);
  });

  test('tạo và tải ảnh dùng đúng URL, body, key và ngữ cảnh demo', () async {
    final png = await pngMau();
    final requests = <http.Request>[];
    final api = MayChuNhanVat(
      mayChu: 'http://localhost:8000/base/',
      maNguoiChoiDemo: 'demo_1',
      client: MockClient((request) async {
        requests.add(request);
        return request.method == 'POST'
            ? _metadata()
            : http.Response.bytes(
                png,
                200,
                headers: {'content-type': 'image/png'},
              );
      }),
    );
    final tao = await api.tao(moTa: '  Thợ mỏ mũ vàng  ', maYeuCau: 'req_1');
    expect(tao.loi, isNull);
    final tai = await api.tai(tao.anh!);
    expect(tai.loi, isNull);
    expect(tai.png, orderedEquals(png));
    expect(tai.anh?.maAnh, maAnhMau);
    expect(requests, hasLength(2));
    expect(
      requests.first.url.toString(),
      'http://localhost:8000/base/api/ai/nhan-vat/tao',
    );
    expect(jsonDecode(requests.first.body), {'description': 'Thợ mỏ mũ vàng'});
    expect(requests.first.headers['Idempotency-Key'], 'req_1');
    expect(
      requests.last.url.toString(),
      'http://localhost:8000/base/api/ai/nhan-vat/anh/$maAnhMau',
    );
    expect(requests.last.method, 'GET');
    expect(requests.last.body, isEmpty);
    expect(requests.last.headers['Accept'], 'image/png');
    for (final request in requests) {
      expect(request.headers['X-Demo-Player'], 'demo_1');
      expect(request.followRedirects, isFalse);
    }
  });

  test('chế độ backend không tự gắn danh tính demo', () async {
    final api = MayChuNhanVat(
      mayChu: 'https://example.test',
      client: MockClient((request) async {
        expect(request.headers.containsKey('X-Demo-Player'), isFalse);
        return _metadata();
      }),
    );
    expect((await api.tao(moTa: 'Thợ mỏ', maYeuCau: 'req_1')).anh, isNotNull);
  });

  test('retry giữ cùng mã yêu cầu và chỉ tải lại ảnh khi cần', () async {
    final png = await pngMau();
    final requests = <http.Request>[];
    var post = 0;
    var get = 0;
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return ++post == 1 ? http.Response('', 503) : _metadata();
        }
        return ++get == 1
            ? http.Response('', 503)
            : http.Response.bytes(
                png,
                200,
                headers: {'content-type': 'image/png'},
              );
      }),
    );
    expect(
      (await api.tao(moTa: 'Thợ mỏ', maYeuCau: 'same_key')).coTheThuLai,
      isTrue,
    );
    final tao = await api.tao(moTa: 'Thợ mỏ', maYeuCau: 'same_key');
    expect((await api.tai(tao.anh!)).coTheThuLai, isTrue);
    expect((await api.tai(tao.anh!)).png, orderedEquals(png));
    expect(post, 2);
    expect(get, 2);
    expect(requests.take(2).map((r) => r.headers['Idempotency-Key']), [
      'same_key',
      'same_key',
    ]);
  });

  test('offline và đầu vào sai không gửi mạng', () async {
    final client = MockClient((_) async => fail('Không được gửi mạng'));
    final offline = MayChuNhanVat(mayChu: '', client: client);
    expect(
      (await offline.tao(moTa: 'Thợ mỏ', maYeuCau: 'req')).loi,
      LoiAnhNhanVat.chuaCauHinh,
    );
    expect(
      (await offline.tai(AnhNhanVat.tuJson(metadataAnhMau()))).loi,
      LoiAnhNhanVat.chuaCauHinh,
    );
    final api = MayChuNhanVat(mayChu: 'http://localhost', client: client);
    for (final moTa in ['', ' \n ', 'a' * 501, 'bad\x00text', 'bad\x7ftext']) {
      expect(
        (await api.tao(moTa: moTa, maYeuCau: 'req')).loi,
        LoiAnhNhanVat.yeuCauKhongHopLe,
      );
    }
    for (final key in ['', '../key', 'a' * 65, 'key\n']) {
      expect(
        (await api.tao(moTa: 'Thợ mỏ', maYeuCau: key)).loi,
        LoiAnhNhanVat.yeuCauKhongHopLe,
      );
    }
  });

  for (final code in [403, 404, 409, 422, 429, 503, 302]) {
    test('POST và GET lỗi $code có kiểu và không tự retry', () async {
      var calls = 0;
      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient((_) async {
          calls++;
          return http.Response('private detail', code);
        }),
      );
      final tao = await api.tao(moTa: 'Thợ mỏ', maYeuCau: 'req_1');
      final tai = await api.tai(AnhNhanVat.tuJson(metadataAnhMau()));
      for (final kq in [tao, tai]) {
        expect(kq.maHttp, code);
        expect(
          kq.loi,
          code >= 500 ? LoiAnhNhanVat.mayChu : LoiAnhNhanVat.biTuChoi,
        );
        expect(kq.coTheThuLai, code == 429 || code >= 500);
        expect(kq.png, isNull);
      }
      expect(calls, 2);
    });
  }

  test(
    'metadata không hợp lệ bị chặn trước khi có thể tải ảnh ngoài backend',
    () async {
      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              metadataAnhMau()..['image_url'] = 'https://other.test/private',
            ),
            200,
          ),
        ),
      );
      final kq = await api.tao(moTa: 'Thợ mỏ', maYeuCau: 'req_1');
      expect(kq.loi, LoiAnhNhanVat.phanHoiKhongHopLe);
      expect(kq.anh, isNull);
    },
  );

  test('từ chối MIME sai, PNG bị cắt và kích thước khác metadata', () async {
    final png = await pngMau();
    final nho = await pngMau(64);
    for (final cap in [
      (png, 'image/jpeg'),
      (png.sublist(0, 32), 'image/png'),
      (nho, 'image/png'),
    ]) {
      final api = MayChuNhanVat(
        mayChu: 'http://localhost',
        client: MockClient(
          (_) async => http.Response.bytes(
            cap.$1,
            200,
            headers: {'content-type': cap.$2},
          ),
        ),
      );
      final kq = await api.tai(AnhNhanVat.tuJson(metadataAnhMau()));
      expect(kq.loi, LoiAnhNhanVat.phanHoiKhongHopLe);
      expect(kq.png, isNull);
    }
  });

  test('PNG quá dung lượng bị chặn trong lúc tải', () async {
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: MockClient(
        (_) async => http.Response.bytes(
          List.filled(1024 * 1024 + 1, 0),
          200,
          headers: {'content-type': 'image/png'},
        ),
      ),
    );
    expect(
      (await api.tai(AnhNhanVat.tuJson(metadataAnhMau()))).loi,
      LoiAnhNhanVat.phanHoiKhongHopLe,
    );
  });

  test('timeout GET hủy kết nối đang đọc body', () async {
    var daHuy = false;
    final body = StreamController<List<int>>();
    final client = MockClient.streaming((request, input) async {
      await input.drain<void>();
      (request as http.AbortableRequest).abortTrigger!.then((_) {
        daHuy = true;
        body.addError(http.RequestAbortedException());
        body.close();
      });
      return http.StreamedResponse(
        body.stream,
        200,
        headers: {'content-type': 'image/png'},
      );
    });
    final api = MayChuNhanVat(
      mayChu: 'http://localhost',
      client: client,
      thoiGianCho: const Duration(milliseconds: 10),
    );
    final kq = await api.tai(AnhNhanVat.tuJson(metadataAnhMau()));
    expect(kq.loi, LoiAnhNhanVat.hetThoiGian);
    await Future<void>.delayed(Duration.zero);
    expect(daHuy, isTrue);
    await body.close();
  });

  test('lỗi TLS trên GET trả trạng thái kết nối', () async {
    final api = MayChuNhanVat(
      mayChu: 'https://localhost',
      client: MockClient(
        (_) async => throw const HandshakeException('private detail'),
      ),
    );
    expect(
      (await api.tai(AnhNhanVat.tuJson(metadataAnhMau()))).loi,
      LoiAnhNhanVat.ketNoi,
    );
  });

  test('tạo/tải qua HTTP thật dùng client mặc định', () async {
    final png = await pngMau();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var calls = 0;
    final done = Completer<void>();
    server.listen((request) async {
      expect(request.headers.value('X-Demo-Player'), 'demo_http');
      if (request.method == 'POST') {
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'description': 'Thợ mỏ',
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(metadataAnhMau()));
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(png);
      }
      await request.response.close();
      if (++calls == 2) done.complete();
    });
    final api = MayChuNhanVat(
      mayChu: 'http://127.0.0.1:${server.port}',
      maNguoiChoiDemo: 'demo_http',
    );
    final tao = await api.tao(moTa: 'Thợ mỏ', maYeuCau: 'req_http');
    final tai = await api.tai(tao.anh!);
    await done.future;
    expect(tai.png, orderedEquals(png));
  });
}
