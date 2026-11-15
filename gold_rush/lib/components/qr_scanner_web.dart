import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
// `web` đã có trong package graph của Flutter Web; không thêm package mới.
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector(JSAny options);

  external JSPromise<JSArray<_BarcodeResult>> detect(JSObject source);
}

extension type _BarcodeResult._(JSObject _) implements JSObject {
  external String get rawValue;
}

int _viewCounter = 0;

Future<String?> moQuetMaQr(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _QrScannerDialog(),
  );
}

class _QrScannerDialog extends StatefulWidget {
  const _QrScannerDialog();

  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  late final String _viewType;
  late final web.HTMLDivElement _root;
  late final web.HTMLVideoElement _video;
  web.MediaStream? _stream;
  _BarcodeDetector? _detector;
  String _thongBao = 'Đang yêu cầu quyền truy cập camera…';
  bool _daTraKetQua = false;
  bool _dangQuet = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'gold-rush-qr-camera-${_viewCounter++}';
    _root = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#050B12'
      ..style.overflow = 'hidden';
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('autoplay', 'true')
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';
    _root.appendChild(_video);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _root);
    WidgetsBinding.instance.addPostFrameCallback((_) => _batDauCamera());
  }

  Future<void> _batDauCamera() async {
    web.MediaStream? stream;
    try {
      // Đừng ép facingMode: trên desktop/macOS thường chỉ có camera FaceTime
      // và một số bản Chrome sẽ trả OverconstrainedError dù trang đã được
      // cấp quyền. `video: true` để trình duyệt tự chọn camera khả dụng.
      stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              video: true.toJS,
              audio: false.toJS,
            ),
          )
          .toDart;
      if (!mounted) {
        for (final track in stream.getTracks().toDart) {
          track.stop();
        }
        return;
      }
      _stream = stream;
      _video.srcObject = stream;

      // Camera đã được mở nhưng play() vẫn có thể bị Chrome từ chối vì mất
      // user-activation sau khi showDialog tạo frame mới. Video đã muted và
      // có autoplay nên không để lỗi play làm hỏng toàn bộ luồng quét.
      try {
        await _video.play().toDart;
      } catch (_) {
        // Thuộc tính autoplay sẽ tự phát khi video nhận được frame đầu tiên.
      }

      final barcodeDetector = globalContext.getProperty<JSAny?>(
        'BarcodeDetector'.toJS,
      );
      if (!barcodeDetector.isA<JSFunction>()) {
        if (mounted) {
          setState(
            () => _thongBao =
                'Camera đã mở nhưng Chrome chưa hỗ trợ nhận diện QR. Hãy cập nhật Chrome.',
          );
        }
        return;
      }
      // BarcodeFormat dùng enum chuẩn của Barcode Detection API.
      // Chrome yêu cầu `qr_code`, không phải tên rút gọn `qr`.
      _detector = _BarcodeDetector({'formats': ['qr_code']}.jsify()!);
      setState(() => _thongBao = 'Đưa mã QR vào khung để quét');
      unawaited(_quetLienTuc());
    } catch (e) {
      _dungCamera();
      if (mounted) {
        setState(
          () => _thongBao = 'Không thể mở camera: ${_thongBaoLoiCamera(e)}',
        );
      }
    }
  }

  String _thongBaoLoiCamera(Object error) {
    final details = error.toString().toLowerCase();
    if (details.contains('notallowed') || details.contains('permission')) {
      return 'Chrome chưa được cấp quyền camera hoặc camera đang bị chặn.';
    }
    if (details.contains('notreadable') || details.contains('in use')) {
      return 'Camera đang được ứng dụng khác sử dụng.';
    }
    if (details.contains('notfound')) {
      return 'Không tìm thấy camera khả dụng trên máy.';
    }
    return 'Chrome không tạo được luồng hình ảnh. Hãy đóng ứng dụng đang dùng camera rồi thử lại.';
  }

  Future<void> _quetLienTuc() async {
    if (_dangQuet) return;
    _dangQuet = true;
    try {
      while (mounted && !_daTraKetQua && _stream != null) {
        try {
          final results = await _detector!.detect(_video).toDart;
          final decoded = results.toDart;
          if (decoded.isNotEmpty) {
            final ma = decoded.first.rawValue.trim();
            if (ma.isNotEmpty) {
              _daTraKetQua = true;
              _dungCamera();
              if (mounted) Navigator.of(context).pop(ma);
              return;
            }
          }
        } catch (_) {
          // Camera vẫn tiếp tục; khung quét không dừng vì một frame lỗi.
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } finally {
      _dangQuet = false;
    }
  }

  void _dungCamera() {
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    }
    _video.srcObject = null;
  }

  @override
  void dispose() {
    _daTraKetQua = true;
    _dungCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('QUÉT MÃ QR QUÀ TẶNG'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Stack(
          fit: StackFit.expand,
          children: [
            HtmlElementView(viewType: _viewType),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFF2C76B), width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xCC081421),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    _thongBao,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('HỦY'),
        ),
      ],
    );
  }
}
