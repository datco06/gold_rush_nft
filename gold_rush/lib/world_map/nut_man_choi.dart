import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import '../man_choi.dart';

/// Trạng thái tiến trình, độc lập với số vàng đặt cọc.
enum TrangThaiMan { chuaMo, daMo, hoanThanh }

/// Một ô màn chơi trên World Map.
class NutManChoi extends StatelessWidget {
  final ManChoi man;
  final TrangThaiMan trangThai;
  final bool dangChon;
  final ValueChanged<ManChoi> khiChon;

  const NutManChoi({
    super.key,
    required this.man,
    required this.trangThai,
    required this.khiChon,
    this.dangChon = false,
  });

  String get _nhanTrangThai {
    switch (trangThai) {
      case TrangThaiMan.chuaMo:
        return 'Chưa mở';
      case TrangThaiMan.daMo:
        return 'Đã mở';
      case TrangThaiMan.hoanThanh:
        return 'Hoàn thành';
    }
  }

  IconData get _bieuTuongDiaHinh {
    switch (man.id) {
      case 1:
        return Icons.grass_rounded;
      case 2:
        return Icons.park_rounded;
      case 3:
        return Icons.terrain_rounded;
      case 4:
        return Icons.forest_rounded;
      case 5:
        return Icons.eco_rounded;
      case 6:
        return Icons.diamond_outlined;
      default:
        return Icons.place_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final biKhoa = trangThai == TrangThaiMan.chuaMo;
    final daHoanThanh = trangThai == TrangThaiMan.hoanThanh;
    final mauNoiDung = biKhoa ? MauGame.chuPhu : MauGame.chinh;

    return SizedBox(
      width: 160,
      child: Semantics(
        selected: dangChon,
        child: Material(
          color: MauGame.nen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: dangChon ? MauGame.chinh : MauGame.vien,
              width: dangChon ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // Chạm chỉ xem thông tin, không thực hiện giao dịch.
            onTap: () => khiChon(man),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48,
                    height: 36,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (man.id == 5)
                          CustomPaint(
                            size: const Size(30, 30),
                            painter: _BieuTuongDauLau(mau: mauNoiDung),
                          )
                        else
                          Icon(_bieuTuongDiaHinh, color: mauNoiDung, size: 30),
                        if (biKhoa || daHoanThanh)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: MauGame.nen,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                biKhoa
                                    ? Icons.lock_rounded
                                    : Icons.check_circle_rounded,
                                size: 16,
                                color: mauNoiDung,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Màn ${man.id}',
                    style: TextStyle(
                      color: mauNoiDung,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    man.ten,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MauGame.chu,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _nhanTrangThai,
                    style: const TextStyle(color: MauGame.chuPhu, fontSize: 12),
                  ),
                  if (dangChon) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Đang chọn',
                      style: TextStyle(
                        color: MauGame.chinh,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Đầu lâu dạng pixel cho màn Thung lũng xương.
class _BieuTuongDauLau extends CustomPainter {
  final Color mau;

  const _BieuTuongDauLau({required this.mau});

  @override
  void paint(Canvas canvas, Size size) {
    // Vẽ trên lưới 30 × 30, co giãn theo kích thước nhận được.
    canvas.save();
    canvas.scale(size.width / 30, size.height / 30);

    final but = Paint()
      ..color = mau
      ..isAntiAlias = false;

    canvas.drawRect(const Rect.fromLTWH(6, 3, 18, 3), but);
    canvas.drawRect(const Rect.fromLTWH(3, 6, 24, 15), but);
    canvas.drawRect(const Rect.fromLTWH(8, 21, 14, 6), but);

    final butToi = Paint()
      ..color = MauGame.nen
      ..isAntiAlias = false;

    canvas.drawRect(const Rect.fromLTWH(7, 10, 6, 6), butToi);
    canvas.drawRect(const Rect.fromLTWH(17, 10, 6, 6), butToi);
    canvas.drawRect(const Rect.fromLTWH(13, 17, 4, 3), butToi);
    canvas.drawRect(const Rect.fromLTWH(11, 23, 2, 4), butToi);
    canvas.drawRect(const Rect.fromLTWH(17, 23, 2, 4), butToi);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BieuTuongDauLau oldDelegate) {
    return oldDelegate.mau != mau;
  }
}
