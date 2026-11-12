import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import 'the_vat_pham.dart';
import 'vat_pham_hien_thi.dart';

class LuoiVatPham extends StatelessWidget {
  final List<VatPhamHienThi> danhSach;
  final String? idDangChon;
  final ValueChanged<VatPhamHienThi>? khiChon;

  const LuoiVatPham({
    super.key,
    required this.danhSach,
    this.idDangChon,
    this.khiChon,
  });

  @override
  Widget build(BuildContext context) {
    if (danhSach.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Chưa có vật phẩm.',
          textAlign: TextAlign.center,
          style: TextStyle(color: MauGame.chuPhu),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const khoangCach = 12.0;
        const rongMongMuon = 220.0;

        final soCot =
            ((constraints.maxWidth + khoangCach) / (rongMongMuon + khoangCach))
                .floor()
                .clamp(1, 6)
                .toInt();

        final rongThe =
            (constraints.maxWidth - (soCot - 1) * khoangCach) / soCot;

        return Wrap(
          spacing: khoangCach,
          runSpacing: khoangCach,
          children: [
            for (final vatPham in danhSach)
              SizedBox(
                width: rongThe,
                child: TheVatPham(
                  key: ValueKey(vatPham.id),
                  vatPham: vatPham,
                  dangChon: vatPham.id == idDangChon,
                  khiChon: khiChon,
                ),
              ),
          ],
        );
      },
    );
  }
}
