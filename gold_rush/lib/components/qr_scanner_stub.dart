import 'package:flutter/material.dart';
import '../ngon_ngu/ngon_ngu.dart';

Future<String?> moQuetMaQr(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const ChuGame('QUÉT MÃ QR'),
      content: const ChuGame('Quét QR hiện chỉ hỗ trợ trên trình duyệt Web.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const ChuGame('ĐÓNG'),
        ),
      ],
    ),
  );
}
