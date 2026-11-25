import 'package:flutter/widgets.dart';

import '../gold_rush_game.dart';
import '../ngon_ngu/ngon_ngu.dart';
import 'bo_cuc_dieu_khien.dart';

/// Nút bắn nổi trên màn chơi.
class NutBan extends StatelessWidget {
  final GoldRushGame game;

  const NutBan({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final leAnToan = MediaQuery.paddingOf(context);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boCuc = BoCucDieuKhien(constraints.biggest, leAnToan);
          return Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.only(right: boCuc.phai, bottom: boCuc.duoi),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => game.george?.banTheoHuongNhin(),
                child: SizedBox.square(
                  dimension: boCuc.kichThuoc,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset('assets/images/joystick_nen.png'),
                      Center(
                        child: ChuGame(
                          'BẮN',
                          style: TextStyle(
                            color: const Color(0xFFF2F4F7),
                            fontWeight: FontWeight.w800,
                            fontSize: boCuc.gon ? 14 : 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
