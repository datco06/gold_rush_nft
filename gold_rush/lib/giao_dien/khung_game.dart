import 'package:flutter/material.dart';

import '../components/ui/game_inventory_controls.dart';
import 'mau_game.dart';

/// Khung dùng chung cho các màn hình phủ lên game.
class KhungGame extends StatelessWidget {
  final String tieuDe;
  final String? phuDe;
  final VoidCallback khiDong;
  final Widget child;
  final double chieuRongToiDa;
  final Widget? nen;

  const KhungGame({
    super.key,
    required this.tieuDe,
    required this.khiDong,
    required this.child,
    this.phuDe,
    this.nen,
    this.chieuRongToiDa = 1200,
  }) : assert(chieuRongToiDa > 0);

  @override
  Widget build(BuildContext context) {
    final coNenTrangTri = nen != null;

    return Material(
      color: MauGame.nen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (nen != null) nen!,
          SafeArea(
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
                      color: coNenTrangTri ? Colors.transparent : MauGame.nen,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              gon ? 10 : 16,
                              gon ? 0 : 6,
                              gon ? 4 : 10,
                              gon ? 0 : 6,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      if (coNenTrangTri) ...[
                                        const Icon(
                                          Icons.inventory_2_rounded,
                                          color: MauGame.chinh,
                                          size: 25,
                                          shadows: [
                                            Shadow(
                                              color: MauGame.chinh,
                                              blurRadius: 12,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 9),
                                      ],
                                      Flexible(
                                        child: Text(
                                          tieuDe,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: MauGame.chinh,
                                            fontSize: gon ? 18 : 23,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.6,
                                            shadows: coNenTrangTri
                                                ? const [
                                                    Shadow(
                                                      color: Color(0xCCFF9D00),
                                                      blurRadius: 12,
                                                    ),
                                                    Shadow(
                                                      color: Colors.black,
                                                      offset: Offset(0, 2),
                                                      blurRadius: 3,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (coNenTrangTri)
                                  GameCloseButton(onTap: khiDong),
                                if (!coNenTrangTri)
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
        ],
      ),
    );
  }
}
