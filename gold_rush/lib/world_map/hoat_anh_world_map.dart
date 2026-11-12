import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'canh_quan_world_map.dart';

/// Bốn hướng mặt của George trên World Map, khớp với 4 hàng của `george.png`.
enum HuongGeorgeWorldMap {
  xuong(0),
  trai(1),
  phai(2),
  len(3);

  final int hangSprite;
  const HuongGeorgeWorldMap(this.hangSprite);

  static HuongGeorgeWorldMap tuVector(Offset v) {
    if (v.dx.abs() >= v.dy.abs()) {
      return v.dx >= 0 ? HuongGeorgeWorldMap.phai : HuongGeorgeWorldMap.trai;
    }
    return v.dy >= 0 ? HuongGeorgeWorldMap.xuong : HuongGeorgeWorldMap.len;
  }
}

/// Painter chuyên trách vẽ cảnh vật chuyển động ở 6 vùng và nhân vật George trên World Map.
///
/// Tách riêng khỏi `CanhQuanWorldMap` trong một `RepaintBoundary` độc lập để
/// không phải vẽ lại nền địa hình và 20 công trình tĩnh ở mỗi khung hình.
class HoatAnhWorldMapPainter extends CustomPainter {
  final double thoiGian;
  final Offset viTriGeorge;
  final HuongGeorgeWorldMap huongGeorge;
  final bool dangDiChuyenGeorge;
  final int nodeGeorgeHienTai;
  final LoTrinhGeorgeWorldMap? loTrinhDangDi;
  final ui.Image? anhGeorge;
  final Rect? vungNhinThay;

  const HoatAnhWorldMapPainter({
    required this.thoiGian,
    required this.viTriGeorge,
    required this.huongGeorge,
    required this.dangDiChuyenGeorge,
    required this.nodeGeorgeHienTai,
    this.loTrinhDangDi,
    this.anhGeorge,
    this.vungNhinThay,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Chỉ vẽ nhân vật George trên World Map (đã bỏ toàn bộ hiệu ứng động cảnh vật và đường đi thêm).
    _veGeorge(canvas);

    canvas.restore();
  }

  void _veGeorge(Canvas canvas) {
    final pos = viTriGeorge;

    // Bóng đổ và vòng định vị tĩnh dưới chân George.
    canvas.drawOval(
      Rect.fromCenter(center: pos + const Offset(0, 3), width: 34, height: 14),
      Paint()..color = const Color(0x990A140D),
    );
    canvas.drawOval(
      Rect.fromCenter(center: pos + const Offset(0, 3), width: 38, height: 16),
      Paint()
        ..color = const Color(0xFFFFDF73)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    final image = anhGeorge;
    final buoc = dangDiChuyenGeorge ? ((thoiGian * 9).floor() % 4) : 0;
    final nhun = dangDiChuyenGeorge ? (buoc.isOdd ? -2.0 : 0.0) : 0.0;

    final dst = Rect.fromLTWH(pos.dx - 24, pos.dy - 46 + nhun, 48, 48);

    if (image != null) {
      final cellW = image.width / 4.0;
      final cellH = image.height / 4.0;
      final src = Rect.fromLTWH(
        buoc * cellW,
        huongGeorge.hangSprite * cellH,
        cellW,
        cellH,
      );

      final vienPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false
        ..colorFilter = const ColorFilter.mode(
          Color(0xFFFFF3C4),
          BlendMode.srcIn,
        );
      for (final d in const [
        Offset(-1.5, 0),
        Offset(1.5, 0),
        Offset(0, -1.5),
        Offset(0, 1.5),
      ]) {
        canvas.drawImageRect(image, src, dst.shift(d), vienPaint);
      }

      canvas.drawImageRect(
        image,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false,
      );
    } else {
      _veGeorgePixelDuPhong(canvas, dst.center, buoc);
    }
  }

  void _veGeorgePixelDuPhong(Canvas canvas, Offset tam, int buoc) {
    // Viền sáng quanh nhân vật dự phòng.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: tam, width: 28, height: 36),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xAAFFF3C4),
    );
    // Mũ thám hiểm.
    canvas.drawRect(
      Rect.fromCenter(center: tam + const Offset(0, -12), width: 22, height: 7),
      Paint()..color = const Color(0xFFD6A14B),
    );
    // Khuôn mặt.
    canvas.drawRect(
      Rect.fromCenter(center: tam + const Offset(0, -4), width: 15, height: 10),
      Paint()..color = const Color(0xFFF5CBA7),
    );
    // Áo thám hiểm.
    canvas.drawRect(
      Rect.fromCenter(center: tam + const Offset(0, 6), width: 18, height: 12),
      Paint()..color = const Color(0xFF3A7CA5),
    );
    // Chân bước đi.
    final lechChan = (buoc % 2 == 1) ? 3.0 : 0.0;
    canvas.drawRect(
      Rect.fromLTWH(tam.dx - 6, tam.dy + 11 - lechChan, 5, 7),
      Paint()..color = const Color(0xFF5C4033),
    );
    canvas.drawRect(
      Rect.fromLTWH(tam.dx + 1, tam.dy + 11 + lechChan, 5, 7),
      Paint()..color = const Color(0xFF5C4033),
    );
  }

  @override
  bool shouldRepaint(HoatAnhWorldMapPainter oldDelegate) =>
      oldDelegate.thoiGian != thoiGian ||
      oldDelegate.viTriGeorge != viTriGeorge ||
      oldDelegate.huongGeorge != huongGeorge ||
      oldDelegate.dangDiChuyenGeorge != dangDiChuyenGeorge ||
      oldDelegate.nodeGeorgeHienTai != nodeGeorgeHienTai ||
      oldDelegate.anhGeorge != anhGeorge ||
      oldDelegate.vungNhinThay != vungNhinThay;
}
