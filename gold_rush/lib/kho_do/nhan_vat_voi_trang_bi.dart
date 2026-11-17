import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'danh_sach_nhan_vat.dart' show AnhNhanVat;
import 'vat_pham_hien_thi.dart';

/// Hiển thị một khung hình (frame 0) từ sprite sheet trang bị 4x4 (256x256),
/// dùng cho các ô trang bị, danh sách và bảng hiển thị trang bị hiện tại.
class HinhTrangBiFrame extends StatelessWidget {
  final String asset;
  final double kichThuoc;
  final Widget? fallback;

  const HinhTrangBiFrame({
    super.key,
    required this.asset,
    required this.kichThuoc,
    this.fallback,
  });

  static String chuanHoaAssetPath(String path) {
    if (path.startsWith('assets/')) return path;
    if (path.startsWith('images/')) return 'assets/$path';
    return 'assets/images/trang_bi/$path';
  }

  @override
  Widget build(BuildContext context) {
    final duongDan = chuanHoaAssetPath(asset);

    return SizedBox.square(
      dimension: kichThuoc,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: kichThuoc * 4,
          maxWidth: kichThuoc * 4,
          minHeight: kichThuoc * 4,
          maxHeight: kichThuoc * 4,
          child: Image.asset(
            duongDan,
            width: kichThuoc * 4,
            height: kichThuoc * 4,
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, _, _) =>
                fallback ??
                const Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFF8EA1B5),
                ),
          ),
        ),
      ),
    );
  }
}

/// Hiển thị nhân vật kèm trực quan các trang bị đang mặc (vũ khí chính, vũ khí phụ, giáp)
/// đồng bộ giữa Main Lobby, Hồ sơ nhân vật và Kho đồ theo đúng layout trong game.
class NhanVatVoiTrangBi extends StatelessWidget {
  final String tepAnh;
  final double kichThuoc;
  final List<VatPhamHienThi> danhSachVatPham;
  final ui.Image? anhNhanVat;

  const NhanVatVoiTrangBi({
    super.key,
    required this.tepAnh,
    required this.kichThuoc,
    this.danhSachVatPham = const [],
    this.anhNhanVat,
  });

  VatPhamHienThi? _timTrangBi(OTrangBi o) {
    for (final vp in danhSachVatPham) {
      if (vp.oDangTrangBi == o) return vp;
    }
    return null;
  }

  Widget _lopSprite4x4({
    required String duongDanAnh,
    required double kichThuoc,
    required double tyLe,
    Offset offset16x16 = Offset.zero,
  }) {
    final kichThuocLop = kichThuoc * tyLe;
    final tamX = kichThuoc / 2 + (offset16x16.dx / 16.0) * kichThuoc;
    final tamY = kichThuoc / 2 + (offset16x16.dy / 16.0) * kichThuoc;

    return Positioned(
      left: tamX - kichThuocLop / 2,
      top: tamY - kichThuocLop / 2,
      width: kichThuocLop,
      height: kichThuocLop,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: kichThuocLop * 4,
          maxWidth: kichThuocLop * 4,
          minHeight: kichThuocLop * 4,
          maxHeight: kichThuocLop * 4,
          child: Image.asset(
            HinhTrangBiFrame.chuanHoaAssetPath(duongDanAnh),
            width: kichThuocLop * 4,
            height: kichThuocLop * 4,
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vuKhiChinh = _timTrangBi(OTrangBi.vuKhiChinh);
    final vuKhiPhu = _timTrangBi(OTrangBi.vuKhiPhu);
    final giap = _timTrangBi(OTrangBi.giap);
    final giay = _timTrangBi(OTrangBi.giay);

    final vuKhi = vuKhiChinh ?? vuKhiPhu;

    final coAnhVuKhi =
        vuKhi?.duongDanAnh != null && vuKhi!.duongDanAnh!.trim().isNotEmpty;
    final coAnhGiap =
        giap?.duongDanAnh != null && giap!.duongDanAnh!.trim().isNotEmpty;
    final coAnhGiay =
        giay?.duongDanAnh != null && giay!.duongDanAnh!.trim().isNotEmpty;

    return SizedBox(
      width: kichThuoc,
      height: kichThuoc,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 1. Sprite nhân vật gốc
          AnhNhanVat(
            tepAnh: tepAnh,
            kichThuoc: kichThuoc,
            anhTrongBoNho: anhNhanVat,
          ),

          // 2. Giày (nếu có sprite sheet, đặt đúng vào phần chân như trong game)
          if (coAnhGiay)
            _lopSprite4x4(
              duongDanAnh: giay.duongDanAnh!,
              kichThuoc: kichThuoc,
              tyLe: 0.55,
              offset16x16: const Offset(0, 6.0),
            ),

          // 3. Giáp (nếu có sprite sheet, offset (0, 0) như trong game)
          if (coAnhGiap)
            _lopSprite4x4(
              duongDanAnh: giap.duongDanAnh!,
              kichThuoc: kichThuoc,
              tyLe: 0.72,
              offset16x16: const Offset(0, 0),
            ),

          // 4. Vũ khí chính/phụ (súng cầm ở đầu tay, cán gắn vào tay chĩa thẳng theo hướng mặt)
          // Tọa độ lệch (5.0, 4.0) khớp hoàn toàn với TrangBiGeorge.viTriVuKhi(HuongDi.xuong) trong game.
          if (coAnhVuKhi)
            _lopSprite4x4(
              duongDanAnh: vuKhi.duongDanAnh!,
              kichThuoc: kichThuoc,
              tyLe: 0.55,
              offset16x16: const Offset(5.0, 4.0),
            ),

          // 5. Fallback CustomPaint cho trang bị mô phỏng không có ảnh asset
          if ((vuKhiChinh != null && !coAnhVuKhi) ||
              (vuKhiPhu != null && !coAnhVuKhi) ||
              (giap != null && !coAnhGiap))
            CustomPaint(
              size: Size.square(kichThuoc),
              painter: _TrangBiTrenNhanVatPainter(
                vuKhiChinh: coAnhVuKhi ? null : vuKhiChinh,
                vuKhiPhu: coAnhVuKhi ? null : vuKhiPhu,
                giap: coAnhGiap ? null : giap,
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
