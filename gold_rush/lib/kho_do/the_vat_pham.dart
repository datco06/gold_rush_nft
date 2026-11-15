import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import 'vat_pham_hien_thi.dart';

Color mauDoHiem(DoHiemVatPham doHiem) {
  switch (doHiem) {
    case DoHiemVatPham.thuong:
      return const Color(0xFFAAB5C0);
    case DoHiemVatPham.khongPhoBien:
      return const Color(0xFF43D98B);
    case DoHiemVatPham.hiem:
      return const Color(0xFF36BFFF);
    case DoHiemVatPham.suThi:
      return const Color(0xFFA765FF);
    case DoHiemVatPham.huyenThoai:
      return const Color(0xFFF5B829);
  }
}

String tenDoHiem(DoHiemVatPham doHiem) {
  switch (doHiem) {
    case DoHiemVatPham.thuong:
      return 'Thường';
    case DoHiemVatPham.khongPhoBien:
      return 'Không phổ biến';
    case DoHiemVatPham.hiem:
      return 'Hiếm';
    case DoHiemVatPham.suThi:
      return 'Sử thi';
    case DoHiemVatPham.huyenThoai:
      return 'Huyền thoại';
  }
}

class TheVatPham extends StatefulWidget {
  final VatPhamHienThi vatPham;
  final bool dangChon;
  final ValueChanged<VatPhamHienThi>? khiChon;

  const TheVatPham({
    super.key,
    required this.vatPham,
    this.dangChon = false,
    this.khiChon,
  });

  @override
  State<TheVatPham> createState() => _TheVatPhamState();
}

class _TheVatPhamState extends State<TheVatPham> {
  bool _dangTro = false;

  VatPhamHienThi get vatPham => widget.vatPham;

  IconData get _iconMacDinh {
    switch (vatPham.loai) {
      case LoaiVatPham.vuKhi:
        return Icons.hardware_rounded;
      case LoaiVatPham.giap:
        return Icons.shield_outlined;
      case LoaiVatPham.giay:
        return Icons.directions_run_rounded;
      case LoaiVatPham.vatPham:
        return Icons.inventory_2_outlined;
    }
  }

  String get _tenOTrangBi {
    switch (vatPham.oDangTrangBi) {
      case OTrangBi.vuKhiChinh:
        return 'Vũ khí chính';
      case OTrangBi.vuKhiPhu:
        return 'Vũ khí phụ';
      case OTrangBi.giap:
        return 'Giáp';
      case OTrangBi.giay:
        return 'Giày';
      case null:
        return 'Chưa trang bị';
    }
  }

  Widget _hinhDuPhong() {
    if (vatPham.bieuTuong == BieuTuongVatPham.macDinh) {
      return Icon(_iconMacDinh, color: MauGame.chinh, size: 38);
    }

    return SizedBox.square(
      dimension: 48,
      child: CustomPaint(painter: _HinhVatPham(vatPham.bieuTuong)),
    );
  }

  /// Các sprite vật phẩm là sheet 4x4; thẻ túi đồ chỉ hiển thị frame đầu.
  Widget _hinhVatPham(String asset) {
    return SizedBox.square(
      dimension: 68,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 256,
          minHeight: 256,
          maxWidth: 256,
          maxHeight: 256,
          child: Image.asset(
            asset,
            width: 256,
            height: 256,
            fit: BoxFit.none,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: MauGame.chuPhu),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vp = vatPham;
    final anh = vp.duongDanAnh;
    final mau = mauDoHiem(vp.doHiem);
    final dangChon = widget.dangChon;

    return Semantics(
      selected: dangChon,
      label: '${vp.ten}, ${tenDoHiem(vp.doHiem)}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _dangTro = true),
        onExit: (_) => setState(() => _dangTro = false),
        cursor: widget.khiChon == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _dangTro ? 1.025 : 1,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  mau.withValues(alpha: dangChon ? 0.2 : 0.09),
                  const Color(0xFF0B1626),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: dangChon || _dangTro ? mau : mau.withValues(alpha: 0.7),
                width: dangChon ? 2.2 : 1.2,
              ),
              boxShadow: dangChon || _dangTro
                  ? [
                      BoxShadow(
                        color: mau.withValues(alpha: dangChon ? 0.42 : 0.2),
                        blurRadius: dangChon ? 14 : 8,
                      ),
                    ]
                  : const [],
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.khiChon == null
                    ? null
                    : () => widget.khiChon!(vp),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(
                              Icons.auto_awesome,
                              color: mau,
                              size: 14,
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: anh == null || anh.trim().isEmpty
                                  ? _hinhDuPhong()
                                  : _hinhVatPham(anh),
                            ),
                          ),
                          Text(
                            vp.ten,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MauGame.chu,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          if (vp.dangTrangBi) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Đang trang bị: $_tenOTrangBi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MauGame.chinh,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (vp.soLuong >= 1)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: _NhanThe(noiDung: '×${vp.soLuong}'),
                      ),
                    if (vp.dangTrangBi)
                      const Positioned(
                        right: 6,
                        top: 6,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: MauGame.chinh,
                          size: 17,
                        ),
                      ),
                    if (vp.laDuLieuMau)
                      const Positioned(
                        left: 5,
                        bottom: 5,
                        child: _NhanThe(noiDung: 'DEMO', noiBat: true),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NhanThe extends StatelessWidget {
  final String noiDung;
  final bool noiBat;

  const _NhanThe({required this.noiDung, this.noiBat = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: MauGame.chinh.withValues(alpha: noiBat ? 0.16 : 0.06),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: noiBat ? MauGame.chinh : MauGame.vien),
      ),
      child: Text(
        noiDung,
        style: TextStyle(
          color: noiBat ? MauGame.chinh : MauGame.chuPhu,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Hình dự phòng chỉ phục vụ hiển thị.
class _HinhVatPham extends CustomPainter {
  final BieuTuongVatPham loai;

  const _HinhVatPham(this.loai);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 32);

    final vang = Paint()
      ..color = MauGame.chinh
      ..isAntiAlias = false;

    final thep = Paint()
      ..color = MauGame.chuPhu
      ..isAntiAlias = false;

    switch (loai) {
      case BieuTuongVatPham.kiem:
        canvas.drawRect(const Rect.fromLTWH(14, 4, 5, 17), thep);
        canvas.drawRect(const Rect.fromLTWH(15, 1, 3, 4), thep);
        canvas.drawRect(const Rect.fromLTWH(9, 20, 15, 4), vang);
        canvas.drawRect(const Rect.fromLTWH(14, 24, 5, 6), vang);
        break;

      case BieuTuongVatPham.cung:
        final cung = Path()
          ..moveTo(10, 3)
          ..lineTo(18, 7)
          ..lineTo(23, 16)
          ..lineTo(18, 25)
          ..lineTo(10, 29);

        canvas.drawPath(
          cung,
          Paint()
            ..color = MauGame.chinh
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.miter,
        );

        canvas.drawLine(
          const Offset(10, 3),
          const Offset(10, 29),
          Paint()
            ..color = MauGame.chuPhu
            ..strokeWidth = 1,
        );
        canvas.drawRect(const Rect.fromLTWH(4, 15, 23, 2), thep);
        canvas.drawRect(const Rect.fromLTWH(25, 13, 3, 6), thep);
        break;

      case BieuTuongVatPham.giap:
        final giap = Path()
          ..moveTo(9, 3)
          ..lineTo(13, 7)
          ..lineTo(19, 7)
          ..lineTo(23, 3)
          ..lineTo(30, 10)
          ..lineTo(25, 15)
          ..lineTo(23, 13)
          ..lineTo(23, 29)
          ..lineTo(9, 29)
          ..lineTo(9, 13)
          ..lineTo(7, 15)
          ..lineTo(2, 10)
          ..close();

        canvas.drawPath(giap, thep);
        canvas.drawRect(const Rect.fromLTWH(14, 10, 4, 16), vang);
        break;

      case BieuTuongVatPham.binhHoiPhuc:
        // Cổ chai và thân chai.
        canvas.drawRect(const Rect.fromLTWH(12, 3, 8, 8), thep);
        canvas.drawRect(const Rect.fromLTWH(8, 10, 16, 4), thep);
        canvas.drawRect(const Rect.fromLTWH(5, 14, 22, 12), thep);
        canvas.drawRect(const Rect.fromLTWH(8, 26, 16, 3), thep);

        // Nắp và ký hiệu hồi phục.
        canvas.drawRect(const Rect.fromLTWH(11, 1, 10, 3), vang);
        canvas.drawRect(const Rect.fromLTWH(14, 15, 4, 10), vang);
        canvas.drawRect(const Rect.fromLTWH(11, 18, 10, 4), vang);
        break;

      case BieuTuongVatPham.macDinh:
        break;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HinhVatPham oldDelegate) {
    return oldDelegate.loai != loai;
  }
}
