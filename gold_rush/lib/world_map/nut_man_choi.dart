import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import '../man_choi.dart';

/// Trạng thái tiến trình, độc lập với số vàng đặt cọc.
enum TrangThaiMan { chuaMo, daMo, hoanThanh }

/// Một ô màn chơi trên World Map.
class NutManChoi extends StatefulWidget {
  final ManChoi man;
  final TrangThaiMan trangThai;
  final bool dangChon;
  final bool gon;
  final ValueChanged<ManChoi> khiChon;

  const NutManChoi({
    super.key,
    required this.man,
    required this.trangThai,
    required this.khiChon,
    this.dangChon = false,
    this.gon = false,
  });

  @override
  State<NutManChoi> createState() => _NutManChoiState();
}

class _NutManChoiState extends State<NutManChoi> {
  bool _hover = false;

  String get _trangThai => switch (widget.trangThai) {
    TrangThaiMan.chuaMo => 'Chưa mở',
    TrangThaiMan.daMo => 'Đã mở',
    TrangThaiMan.hoanThanh => 'Hoàn thành',
  };

  @override
  Widget build(BuildContext context) {
    final locked = widget.trangThai == TrangThaiMan.chuaMo;
    final completed = widget.trangThai == TrangThaiMan.hoanThanh;
    final active = widget.dangChon || _hover;
    final gold = locked ? const Color(0xFFC4C5B5) : const Color(0xFFF1CF7A);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        button: true,
        selected: widget.dangChon,
        label: 'Màn ${widget.man.id}, ${widget.man.ten}, $_trangThai',
        child: Tooltip(
          message: '${widget.man.ten} · $_trangThai',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.khiChon(widget.man),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: widget.gon ? 32 : 40,
                  height: widget.gon ? 32 : 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _HuyHieu(active: active, gold: gold),
                          child: Center(
                            child: Text.rich(
                              TextSpan(
                                text: widget.gon ? '' : 'Màn ',
                                style: const TextStyle(fontSize: 9),
                                children: [
                                  TextSpan(
                                    text: '${widget.man.id}',
                                    style: TextStyle(
                                      fontSize: widget.gon ? 16 : 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              style: TextStyle(color: gold, height: 1),
                            ),
                          ),
                        ),
                      ),
                      if (locked || completed)
                        Positioned(
                          right: -3,
                          top: -2,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Color(0xFF25382A),
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                locked
                                    ? Icons.lock_rounded
                                    : Icons.check_circle_rounded,
                                color: gold,
                                size: 13,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                if (!widget.gon)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCA1B281F),
                      border: active
                          ? Border(bottom: BorderSide(color: gold, width: 2))
                          : null,
                    ),
                    child: Text(
                      widget.man.ten,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFF3EACD),
                        fontSize: widget.gon ? 11 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (!widget.gon)
                  Text(
                    _trangThai,
                    style: const TextStyle(
                      color: MauGame.chu,
                      fontSize: 9,
                      shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HuyHieu extends CustomPainter {
  final bool active;
  final Color gold;
  _HuyHieu({required this.active, required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    Path diamond(double inset) => Path()
      ..moveTo(c.dx, inset)
      ..lineTo(size.width - inset, c.dy)
      ..lineTo(c.dx, size.height - inset)
      ..lineTo(inset, c.dy)
      ..close();
    if (active) {
      canvas.drawPath(
        diamond(1),
        Paint()
          ..color = gold.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
    canvas.drawPath(
      diamond(4).shift(const Offset(0, 2)),
      Paint()..color = const Color(0xAA101910),
    );
    canvas.drawPath(
      diamond(4),
      Paint()
        ..color = active ? const Color(0xFF45533A) : const Color(0xFF25382A),
    );
    canvas.drawPath(
      diamond(4),
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2 : 1.2,
    );
    canvas.drawPath(
      diamond(8),
      Paint()
        ..color = gold.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HuyHieu oldDelegate) =>
      oldDelegate.active != active || oldDelegate.gold != gold;
}
