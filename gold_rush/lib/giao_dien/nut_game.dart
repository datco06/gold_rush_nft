import 'package:flutter/material.dart';

import 'mau_game.dart';

/// Nút dùng chung cho World Map và Kho đồ.
class NutGame extends StatelessWidget {
  final String nhan;
  final IconData bieuTuong;
  final VoidCallback? khiBam;
  final bool chinh;
  final bool dangXuLy;

  const NutGame({
    super.key,
    required this.nhan,
    required this.bieuTuong,
    required this.khiBam,
    this.chinh = false,
    this.dangXuLy = false,
  });

  @override
  Widget build(BuildContext context) {
    // Không cho bấm khi đang xử lý.
    final thaoTac = dangXuLy ? null : khiBam;

    final Widget icon = dangXuLy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(bieuTuong);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: chinh
          ? FilledButton.icon(
              onPressed: thaoTac,
              icon: icon,
              label: Text(nhan, textAlign: TextAlign.center),
              style: FilledButton.styleFrom(
                backgroundColor: MauGame.chinh,
                foregroundColor: MauGame.chuTrenVang,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: thaoTac,
              icon: icon,
              label: Text(nhan, textAlign: TextAlign.center),
              style: OutlinedButton.styleFrom(
                foregroundColor: MauGame.chu,
                side: const BorderSide(color: MauGame.vien),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
    );
  }
}
