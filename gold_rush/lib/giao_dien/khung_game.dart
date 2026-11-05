import 'package:flutter/material.dart';

import 'mau_game.dart';

/// Khung dùng chung cho các màn hình phủ lên game.
class KhungGame extends StatelessWidget {
  final String tieuDe;
  final String? phuDe;
  final VoidCallback khiDong;
  final Widget child;
  final double chieuRongToiDa;

  const KhungGame({
    super.key,
    required this.tieuDe,
    required this.khiDong,
    required this.child,
    this.phuDe,
    this.chieuRongToiDa = 1200,
  }) : assert(chieuRongToiDa > 0);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MauGame.nen,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: chieuRongToiDa),
            child: Material(
              color: MauGame.nen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tieuDe,
                            style: const TextStyle(
                              color: MauGame.chinh,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Quay lại Menu',
                          onPressed: khiDong,
                          color: MauGame.chu,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (phuDe != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        phuDe!,
                        style: const TextStyle(color: MauGame.chuPhu),
                      ),
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
