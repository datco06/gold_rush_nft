import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import '../man_choi.dart';

/// Trạng thái tiến trình, độc lập với số vàng đặt cọc.
enum TrangThaiMan { chuaMo, daMo, hoanThanh }

/// Một ô màn chơi trên World Map:
/// - Màn 1–6 (cốt lõi): Huy hiệu Hoàng Kim lớn kèm băng rôn tên địa danh & trạng thái.
/// - Màn 7–20 (địa danh mở rộng): Hiện tên cùng mốc màn trên màn hình lớn;
///   thu gọn trên thiết bị nhỏ để tránh chồng nhãn.
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
    final laManChinh = widget.man.id <= 6;
    final locked = widget.trangThai == TrangThaiMan.chuaMo;
    final completed = widget.trangThai == TrangThaiMan.hoanThanh;
    final active = widget.dangChon || _hover;
    final gold = locked
        ? (laManChinh ? const Color(0xFFD2D4C5) : const Color(0xFFA8B0A4))
        : (laManChinh ? const Color(0xFFFFD966) : const Color(0xFFE5C478));

    final kichThuocHuyHieu = widget.gon
        ? (laManChinh ? 32.0 : 26.0)
        : (laManChinh ? 40.0 : 32.0);

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
                  width: kichThuocHuyHieu,
                  height: kichThuocHuyHieu,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _HuyHieu(
                            active: active,
                            gold: gold,
                            laManChinh: laManChinh,
                          ),
                          child: Center(
                            child: Text.rich(
                              TextSpan(
                                text: widget.gon ? '' : 'Màn ',
                                style: const TextStyle(fontSize: 8.5),
                                children: [
                                  TextSpan(
                                    text: '${widget.man.id}',
                                    style: TextStyle(
                                      fontSize: widget.gon
                                          ? (laManChinh ? 15 : 11.5)
                                          : (laManChinh ? 17 : 13.5),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
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
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2F23),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: gold.withValues(alpha: 0.45),
                                width: 0.8,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(1.5),
                              child: Icon(
                                locked
                                    ? Icons.lock_rounded
                                    : Icons.check_circle_rounded,
                                color: gold,
                                size: widget.gon && !laManChinh ? 10 : 12,
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
                      color: laManChinh
                          ? const Color(0xE61A261D)
                          : const Color(0xCC1B281F),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: active
                            ? gold
                            : gold.withValues(alpha: laManChinh ? 0.55 : 0.28),
                        width: active ? 1.5 : 1.0,
                      ),
                    ),
                    child: Text(
                      widget.man.ten,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFF7EED2),
                        fontSize: laManChinh ? 11.5 : 10.5,
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
  final bool laManChinh;

  _HuyHieu({
    required this.active,
    required this.gold,
    required this.laManChinh,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // Màn chơi biểu tượng hình tròn: bóng đổ, viền hoàng kim, tâm xanh lục/ngọc
    final r = size.width * 0.44;
    canvas.drawCircle(
      c + const Offset(0, 2),
      r,
      Paint()..color = const Color(0x990A140D),
    );

    if (active) {
      canvas.drawCircle(
        c,
        r + 3.5,
        Paint()
          ..color = gold.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = active
            ? const Color(0xFF2E4832)
            : (laManChinh ? const Color(0xFF1E3224) : const Color(0xFF1B281F)),
    );

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = gold.withValues(
          alpha: active ? 1.0 : (laManChinh ? 0.95 : 0.8),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.4 : (laManChinh ? 2.0 : 1.4),
    );

    if (laManChinh) {
      canvas.drawCircle(
        c,
        r - 3.5,
        Paint()
          ..color = gold.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }
  }

  @override
  bool shouldRepaint(_HuyHieu oldDelegate) =>
      oldDelegate.active != active ||
      oldDelegate.gold != gold ||
      oldDelegate.laManChinh != laManChinh;
}
