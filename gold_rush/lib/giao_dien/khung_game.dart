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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Khi cửa sổ tạm thu về kích thước rất nhỏ,
            // chưa dựng tiêu đề và nội dung cần diện tích tương tác.
            if (constraints.maxWidth < 240 || constraints.maxHeight < 160) {
              return const SizedBox.expand();
            }

            final gon = constraints.maxHeight < 500;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: chieuRongToiDa),
                child: Material(
                  color: MauGame.nen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          gon ? 12 : 20,
                          gon ? 0 : 8,
                          gon ? 4 : 12,
                          gon ? 0 : 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tieuDe,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: MauGame.chinh,
                                  fontSize: gon ? 20 : 24,
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
                          padding: EdgeInsets.fromLTRB(
                            gon ? 12 : 20,
                            0,
                            gon ? 12 : 20,
                            gon ? 4 : 12,
                          ),
                          child: Text(
                            phuDe!,
                            maxLines: gon ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: MauGame.chuPhu),
                          ),
                        ),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
