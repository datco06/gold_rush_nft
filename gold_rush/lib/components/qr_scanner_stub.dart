import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ngon_ngu/ngon_ngu.dart';

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
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  final ImagePicker _imagePicker = ImagePicker();
  bool _daTraKetQua = false;
  bool _dangDocAnh = false;
  String? _thongBao;

  void _nhanKetQua(BarcodeCapture capture) {
    if (_daTraKetQua) return;
    for (final barcode in capture.barcodes) {
      final ma = barcode.rawValue?.trim();
      if (ma == null || ma.isEmpty) continue;
      _daTraKetQua = true;
      unawaited(_controller.stop());
      if (mounted) Navigator.of(context).pop(ma);
      return;
    }
  }

  Future<void> _chonAnhTuGallery() async {
    if (_daTraKetQua || _dangDocAnh) return;
    setState(() {
      _dangDocAnh = true;
      _thongBao = 'Đang đọc mã QR trong ảnh…';
    });
    try {
      final anh = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (anh == null) {
        if (mounted) setState(() => _thongBao = null);
        return;
      }
      final capture = await _controller.analyzeImage(
        anh.path,
        formats: const [BarcodeFormat.qrCode],
      );
      String? ma;
      for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
        final value = barcode.rawValue?.trim();
        if (value != null && value.isNotEmpty) {
          ma = value;
          break;
        }
      }
      if (!mounted) return;
      if (ma == null) {
        setState(
          () => _thongBao =
              'Không tìm thấy mã QR trong ảnh. Hãy chọn ảnh rõ hơn.',
        );
        return;
      }
      _daTraKetQua = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(ma);
    } catch (_) {
      if (mounted) {
        setState(
          () => _thongBao = 'Không đọc được ảnh. Hãy chọn ảnh PNG/JPG khác.',
        );
      }
    } finally {
      if (mounted && !_daTraKetQua) setState(() => _dangDocAnh = false);
    }
  }

  String _thongBaoLoi(MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return 'Vui lòng cấp quyền camera cho Gold Rush trong Cài đặt điện thoại.';
    }
    return 'Không thể mở camera. Hãy thử lại sau.';
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const ChuGame('QUÉT MÃ QR QUÀ TẶNG'),
      content: SizedBox.square(
        dimension: 300,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _nhanKetQua,
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ChuGame(
                      _thongBaoLoi(error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFFF2C76B),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_thongBao != null)
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
                      child: ChuGame(
                        _thongBao!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _daTraKetQua || _dangDocAnh
              ? null
              : _chonAnhTuGallery,
          icon: _dangDocAnh
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_library_outlined),
          label: const ChuGame('CHỌN ẢNH QR'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const ChuGame('ĐÓNG'),
        ),
      ],
    );
  }
}
