import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/may_chu_de_xuat_do_kho.dart';
import 'package:gold_rush/ai/may_chu_nhan_vat.dart';
import 'package:gold_rush/ai/may_chu_nhiem_vu.dart';
import 'package:http/http.dart' as http;

void main() {
  const base = String.fromEnvironment('GOLD_RUSH_AI_TEST_API');
  const runId = String.fromEnvironment('GOLD_RUSH_AI_TEST_RUN');
  const boQua = base == '' && runId == '';

  group(
    'Flutter gọi backend AI demo qua HTTP thật',
    () {
      late final http.Client transport;
      final player = 'flutter_$runId';

      setUpAll(() async {
        transport = http.Client();
        final uri = Uri.parse(base);
        expect(uri.scheme, 'http');
        expect(uri.host, '127.0.0.1');
        expect(uri.userInfo, isEmpty);
        expect(uri.query, isEmpty);
        expect(uri.fragment, isEmpty);
        expect(uri.path, anyOf('', '/'));
        expect(uri.port, inInclusiveRange(1, 65535));
        expect(runId, matches(RegExp(r'^[0-9a-f]{32}$')));
        final request = http.Request('GET', uri.resolve('/api/health'))
          ..followRedirects = false;
        final response = await transport
            .send(request)
            .timeout(const Duration(seconds: 5));
        try {
          expect(response.statusCode, 200);
          expect(
            response.headers['x-demo-run'],
            runId,
            reason:
                'Chỉ gọi server do scripts/chay_demo_ai.py tạo cho phiên này.',
          );
        } finally {
          await response.stream.listen(null).cancel();
        }
      });

      tearDownAll(() => transport.close());

      test(
        'nhiệm vụ đọc đúng schema, retry giữ ID và màn khác bị từ chối',
        () async {
          final api = MayChuNhiemVu(
            mayChu: base,
            maNguoiChoiDemo: player,
            client: transport,
          );
          final first = await api.tao(manChoi: 1, maYeuCau: 'quest_1');
          expect(first.loi, isNull);
          expect(first.maHttp, 200);
          expect(first.nhiemVu?.manChoi, 1);
          expect(first.nhiemVu?.nguonNguCanh, 'demo');
          expect(first.nhiemVu?.nguonSinh, 'rule_based');
          expect(first.nhiemVu?.vangThuong, 0);
          final retry = await api.tao(manChoi: 1, maYeuCau: 'quest_1');
          expect(retry.loi, isNull);
          expect(retry.nhiemVu?.id, first.nhiemVu?.id);
          final denied = await api.tao(manChoi: 2, maYeuCau: 'quest_2');
          expect(denied.maHttp, 403);
          expect(denied.nhiemVu, isNull);
          expect(denied.coTheThuLai, isFalse);
        },
      );

      test('đề xuất độ khó đọc đúng fallback và giữ quyền theo màn', () async {
        final api = MayChuDeXuatDoKho(
          mayChu: base,
          maNguoiChoiDemo: player,
          client: transport,
        );
        final result = await api.deXuat(manChoi: 1);
        expect(result.loi, isNull);
        expect(result.deXuat?.manChoi, 1);
        expect(result.deXuat?.nguonNguCanh, 'demo');
        expect(result.deXuat?.nguon, 'fallback');
        expect(result.deXuat?.diemHieuSuat, isNull);
        expect(result.deXuat?.soVan, 0);
        expect(result.deXuat?.heSoTocDo, 1.0);
        final denied = await api.deXuat(manChoi: 2);
        expect(denied.maHttp, 403);
        expect(denied.deXuat, isNull);
      });

      test(
        'ảnh giải mã PNG thật, retry giữ ID và không tải chéo chủ sở hữu',
        () async {
          final api = MayChuNhanVat(
            mayChu: base,
            maNguoiChoiDemo: player,
            client: transport,
          );
          final first = await api.tao(
            moTa: 'Thợ mỏ đội mũ vàng',
            maYeuCau: 'image_1',
          );
          expect(first.loi, isNull);
          expect(first.anh?.nguonNguCanh, 'demo');
          expect(first.anh?.nguonSinh, 'demo');
          expect(first.anh?.chieuRong, 128);
          expect(first.anh?.chieuCao, 128);
          final image = await api.tai(first.anh!);
          expect(image.loi, isNull);
          expect(image.png, isNotEmpty);
          final retry = await api.tao(
            moTa: 'Thợ mỏ đội mũ vàng',
            maYeuCau: 'image_1',
          );
          expect(retry.loi, isNull);
          expect(retry.anh?.maAnh, first.anh?.maAnh);
          final other = MayChuNhanVat(
            mayChu: base,
            maNguoiChoiDemo: 'other_$runId',
            client: transport,
          );
          final denied = await other.tai(first.anh!);
          expect(denied.maHttp, 404);
          expect(denied.png, isNull);
        },
      );
    },
    skip: boQua
        ? 'Cần bật kiểm thử HTTP theo README (API và run ID của demo runner).'
        : false,
  );
}
