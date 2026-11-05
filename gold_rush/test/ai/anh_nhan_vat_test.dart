import 'package:flutter_test/flutter_test.dart';
import 'package:gold_rush/ai/anh_nhan_vat.dart';

const maAnhMau = 'img_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> metadataAnhMau() => {
  'image_id': maAnhMau,
  'image_url': '/api/ai/nhan-vat/anh/$maAnhMau',
  'width': 128,
  'height': 128,
  'status': 'ready',
  'generation_source': 'demo',
  'context_source': 'demo',
  'schema_version': 1,
};

void main() {
  test('đọc metadata ảnh demo và ngữ cảnh đã xác minh', () {
    final demo = AnhNhanVat.tuJson(metadataAnhMau());
    expect(demo.maAnh, maAnhMau);
    expect(demo.duongDanAnh, '/api/ai/nhan-vat/anh/$maAnhMau');
    expect(demo.chieuRong, 128);
    expect(demo.chieuCao, 128);
    expect(demo.nguonSinh, 'demo');
    expect(demo.nguonNguCanh, 'demo');
    final model = AnhNhanVat.tuJson(
      metadataAnhMau()
        ..['generation_source'] = 'image_model'
        ..['context_source'] = 'verified',
    );
    expect(model.nguonSinh, 'image_model');
    expect(model.nguonNguCanh, 'verified');
  });

  for (final truong in metadataAnhMau().keys) {
    test('thiếu trường $truong bị từ chối', () {
      expect(
        () => AnhNhanVat.tuJson(metadataAnhMau()..remove(truong)),
        throwsFormatException,
      );
    });
  }
  final sai = <String, dynamic>{
    'image_id': '../private',
    'image_url': 'https://other.test/image.png',
    'width': 128.0,
    'height': 64,
    'status': 'processing',
    'generation_source': 'unknown',
    'context_source': 'client',
    'schema_version': true,
  };
  for (final truong in sai.entries) {
    test('trường ${truong.key} sai bị từ chối', () {
      expect(
        () => AnhNhanVat.tuJson(metadataAnhMau()..[truong.key] = truong.value),
        throwsFormatException,
      );
    });
  }
  test('URL phải khớp ID và đường dẫn ảnh của backend', () {
    for (final url in [
      '/api/ai/nhan-vat/anh/img_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      '//other.test/image.png',
      '/api/ai/nhan-vat/anh/$maAnhMau?key=secret',
      'C:/private/image.png',
    ]) {
      expect(
        () => AnhNhanVat.tuJson(metadataAnhMau()..['image_url'] = url),
        throwsFormatException,
      );
    }
  });
  test('từ chối phiên bản sai kiểu và ID thừa ký tự', () {
    for (final version in [1.0, 2]) {
      expect(
        () => AnhNhanVat.tuJson(metadataAnhMau()..['schema_version'] = version),
        throwsFormatException,
      );
    }
    expect(
      () => AnhNhanVat.tuJson(metadataAnhMau()..['image_id'] = '$maAnhMau\n'),
      throwsFormatException,
    );
  });
}
