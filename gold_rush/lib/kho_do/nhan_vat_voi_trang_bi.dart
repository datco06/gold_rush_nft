import 'package:flutter/material.dart';

import 'danh_sach_nhan_vat.dart' show AnhNhanVat;
import 'vat_pham_hien_thi.dart';

/// Hiển thị nhân vật kèm trực quan các trang bị đang mặc (vũ khí chính, vũ khí phụ, giáp)
/// đồng bộ giữa Main Lobby, Hồ sơ nhân vật và Kho đồ.
class NhanVatVoiTrangBi extends StatelessWidget {
  final String tepAnh;
  final double kichThuoc;
  final List<VatPhamHienThi> danhSachVatPham;

  const NhanVatVoiTrangBi({
    super.key,
    required this.tepAnh,
    required this.kichThuoc,
    this.danhSachVatPham = const [],
  });

  VatPhamHienThi? _timTrangBi(OTrangBi o) {
    for (final vp in danhSachVatPham) {
      if (vp.oDangTrangBi == o) return vp;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vuKhiChinh = _timTrangBi(OTrangBi.vuKhiChinh);
    final vuKhiPhu = _timTrangBi(OTrangBi.vuKhiPhu);
    final giap = _timTrangBi(OTrangBi.giap);

    return SizedBox(
      width: kichThuoc,
      height: kichThuoc,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnhNhanVat(tepAnh: tepAnh, kichThuoc: kichThuoc),
          if (vuKhiChinh != null || vuKhiPhu != null || giap != null)
            CustomPaint(
              size: Size.square(kichThuoc),
              painter: _TrangBiTrenNhanVatPainter(
                vuKhiChinh: vuKhiChinh,
                vuKhiPhu: vuKhiPhu,
                giap: giap,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrangBiTrenNhanVatPainter extends CustomPainter {
  final VatPhamHienThi? vuKhiChinh;
  final VatPhamHienThi? vuKhiPhu;
  final VatPhamHienThi? giap;

  const _TrangBiTrenNhanVatPainter({this.vuKhiChinh, this.vuKhiPhu, this.giap});

  Color _mauTheoVatPham(VatPhamHienThi vp, {required bool laVuKhi}) {
    final id = vp.id.toLowerCase();
    if (id.contains('go')) return const Color(0xFFB87A42);
    if (id.contains('sat') || id.contains('thep')) {
      return const Color(0xFF9AC5EB);
    }
    if (id.contains('vang') || id.contains('hoang_kim')) {
      return const Color(0xFFFFCF4D);
    }
    if (id.contains('da')) return const Color(0xFF9E643B);

    return switch (vp.doHiem) {
      DoHiemVatPham.thuong =>
        laVuKhi ? const Color(0xFFB87A42) : const Color(0xFF8B9BB4),
      DoHiemVatPham.khongPhoBien => const Color(0xFF4CD484),
      DoHiemVatPham.hiem => const Color(0xFF39C5FF),
      DoHiemVatPham.suThi => const Color(0xFFB875FF),
      DoHiemVatPham.huyenThoai => const Color(0xFFFFC93C),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final px = (s / 32.0).clamp(1.5, 8.0);

    // 1. Giáp trên thân nhân vật
    if (giap != null) {
      final base = _mauTheoVatPham(giap!, laVuKhi: false);
      final trim = const Color(0xFFFFD86B);
      final chestRect = Rect.fromLTWH(s * 0.34, s * 0.48, s * 0.32, s * 0.19);
      canvas.drawRect(chestRect, Paint()..color = base.withValues(alpha: 0.92));
      canvas.drawRect(
        chestRect,
        Paint()
          ..color = const Color(0xFF182436)
          ..style = PaintingStyle.stroke
          ..strokeWidth = px * 0.45,
      );
      // Cầu vai hai bên
      canvas.drawRect(
        Rect.fromLTWH(s * 0.28, s * 0.48, s * 0.08, s * 0.08),
        Paint()..color = trim,
      );
      canvas.drawRect(
        Rect.fromLTWH(s * 0.64, s * 0.48, s * 0.08, s * 0.08),
        Paint()..color = trim,
      );
      // Huy hiệu ngực
      canvas.drawRect(
        Rect.fromLTWH(s * 0.46, s * 0.53, s * 0.08, s * 0.06),
        Paint()..color = trim,
      );
    }

    // 2. Vũ khí chính bên tay phải
    if (vuKhiChinh != null) {
      final bladeColor = _mauTheoVatPham(vuKhiChinh!, laVuKhi: true);
      final bladePaint = Paint()
        ..color = bladeColor
        ..strokeWidth = px * 1.4
        ..strokeCap = StrokeCap.square;
      final outlinePaint = Paint()
        ..color = const Color(0xFF1A140B)
        ..strokeWidth = px * 2.1
        ..strokeCap = StrokeCap.square;

      final hand = Offset(s * 0.72, s * 0.58);
      final tip = Offset(s * 0.92, s * 0.28);

      // Viền + lưỡi kiếm
      canvas.drawLine(hand, tip, outlinePaint);
      canvas.drawLine(hand, tip, bladePaint);

      // Chắn tay kiếm
      canvas.drawLine(
        Offset(s * 0.66, s * 0.54),
        Offset(s * 0.78, s * 0.62),
        Paint()
          ..color = const Color(0xFFFFC93C)
          ..strokeWidth = px * 1.1
          ..strokeCap = StrokeCap.square,
      );
      // Chuôi kiếm
      canvas.drawLine(
        hand,
        Offset(s * 0.68, s * 0.64),
        Paint()
          ..color = const Color(0xFF5A3718)
          ..strokeWidth = px * 1.1
          ..strokeCap = StrokeCap.square,
      );
    }

    // 3. Vũ khí phụ (cung) bên tay trái
    if (vuKhiPhu != null) {
      final bowColor = _mauTheoVatPham(vuKhiPhu!, laVuKhi: true);
      final bowRect = Rect.fromLTWH(s * 0.10, s * 0.38, s * 0.16, s * 0.34);
      canvas.drawArc(
        bowRect,
        1.7,
        2.88,
        false,
        Paint()
          ..color = bowColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = px * 1.1
          ..strokeCap = StrokeCap.round,
      );
      // Dây cung
      canvas.drawLine(
        Offset(s * 0.22, s * 0.40),
        Offset(s * 0.22, s * 0.70),
        Paint()
          ..color = const Color(0xFFE7EEF6)
          ..strokeWidth = px * 0.45,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrangBiTrenNhanVatPainter oldDelegate) =>
      oldDelegate.vuKhiChinh?.id != vuKhiChinh?.id ||
      oldDelegate.vuKhiPhu?.id != vuKhiPhu?.id ||
      oldDelegate.giap?.id != giap?.id;
}
