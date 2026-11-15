import 'package:flutter/material.dart';

Future<String?> moQuetMaQr(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('QUÉT MÃ QR'),
      content: const Text('Quét QR hiện chỉ hỗ trợ trên trình duyệt Web.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ĐÓNG'),
        ),
      ],
    ),
  );
}
