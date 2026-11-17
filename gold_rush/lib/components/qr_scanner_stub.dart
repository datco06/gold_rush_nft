import 'dart:async';

import 'package:flutter/material.dart';
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
  bool _daTraKetQua = false;

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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const ChuGame('ĐÓNG'),
        ),
      ],
    );
  }
}
