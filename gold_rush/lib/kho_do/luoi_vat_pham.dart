import 'package:flutter/material.dart';

import '../ngon_ngu/ngon_ngu.dart';

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
        child: ChuGame(
          'Chưa có vật phẩm.',
          textAlign: TextAlign.center,
          style: TextStyle(color: MauGame.chuPhu),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const khoangCach = 12.0;
        const rongMongMuon = 132.0;

        final soCot =
            ((constraints.maxWidth + khoangCach) / (rongMongMuon + khoangCach))
                .floor()
                .clamp(1, 6)
                .toInt();

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: danhSach.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: soCot,
            mainAxisSpacing: khoangCach,
            crossAxisSpacing: khoangCach,
            childAspectRatio: 0.86,
          ),
          itemBuilder: (context, index) {
            final vatPham = danhSach[index];
            return TheVatPham(
              key: ValueKey(vatPham.id),
              vatPham: vatPham,
              dangChon: vatPham.id == idDangChon,
              khiChon: khiChon,
            );
          },
        );
      },
    );
  }
}
