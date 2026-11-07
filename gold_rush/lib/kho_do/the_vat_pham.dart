import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import 'vat_pham_hien_thi.dart';

class TheVatPham extends StatelessWidget {
  final VatPhamHienThi vatPham;
  final bool dangChon;
  final ValueChanged<VatPhamHienThi>? khiChon;

  const TheVatPham({
    super.key,
    required this.vatPham,
    this.dangChon = false,
    this.khiChon,
  });

  String get _tenLoai {
    switch (vatPham.loai) {
      case LoaiVatPham.vuKhi:
        return 'Vũ khí';
      case LoaiVatPham.giap:
        return 'Giáp';
      case LoaiVatPham.vatPham:
        return 'Vật phẩm';
    }
  }

  String get _tenDoHiem {
    switch (vatPham.doHiem) {
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

  IconData get _iconMacDinh {
    switch (vatPham.loai) {
      case LoaiVatPham.vuKhi:
        return Icons.hardware_rounded;
      case LoaiVatPham.giap:
        return Icons.shield_outlined;
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

  @override
  Widget build(BuildContext context) {
    final vp = vatPham;
    final anh = vp.duongDanAnh;

    return Semantics(
      selected: dangChon,
      child: Material(
        color: MauGame.nen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: dangChon ? MauGame.chinh : MauGame.vien,
            width: dangChon ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: khiChon == null ? null : () => khiChon!(vp),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (vp.laDuLieuMau)
                      const _NhanThe(noiDung: 'DEMO', noiBat: true),
                    _NhanThe(
                      noiDung: vp.nguon == NguonVatPham.nft
                          ? 'Nguồn NFT'
                          : 'Trong game',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MauGame.chinh.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: anh == null || anh.trim().isEmpty
                      ? _hinhDuPhong()
                      : Image.asset(
                          anh,
                          width: 64,
                          height: 64,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          errorBuilder: (context, error, stackTrace) {
                            return const Tooltip(
                              message: 'Không tải được ảnh vật phẩm',
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: MauGame.chuPhu,
                                size: 32,
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  vp.ten,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MauGame.chu,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${vp.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MauGame.chuPhu, fontSize: 11),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_tenLoai · $_tenDoHiem',
                  style: const TextStyle(color: MauGame.chinh, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (vp.thuocTinh.isEmpty)
                  const Text(
                    'Chưa có thông tin thuộc tính',
                    style: TextStyle(color: MauGame.chuPhu, fontSize: 12),
                  )
                else
                  for (final thuocTinh in vp.thuocTinh.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${thuocTinh.key}: ${thuocTinh.value}',
                        style: const TextStyle(
                          color: MauGame.chuPhu,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      vp.dangTrangBi
                          ? Icons.check_circle_outline_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: vp.dangTrangBi ? MauGame.chinh : MauGame.chuPhu,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        vp.dangTrangBi
                            ? 'Đang trang bị: $_tenOTrangBi'
                            : 'Chưa trang bị',
                        style: TextStyle(
                          color: vp.dangTrangBi
                              ? MauGame.chinh
                              : MauGame.chuPhu,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (vp.nguon == NguonVatPham.nft) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Thông tin NFT chưa phải xác nhận quyền sở hữu.',
                    style: TextStyle(
                      color: MauGame.chuPhu,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
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
