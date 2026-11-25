import 'package:flutter/material.dart';

import '../ngon_ngu/ngon_ngu.dart';

import '../gold_rush_game.dart';

/// Nút bắn nổi trên màn chơi.
class NutBan extends StatelessWidget {
  final GoldRushGame game;

  const NutBan({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final manHinh = MediaQuery.sizeOf(context);
    final leAnToan = MediaQuery.paddingOf(context);
    final compact = manHinh.width < 600 || manHinh.height < 420;
    final size = compact ? 70.0 : 84.0;
    final lePhai = (manHinh.width * .085 - size / 2).clamp(24.0, 120.0);
    final leDuoi = (manHinh.height * .23 - size / 2).clamp(32.0, 150.0);
    return Positioned(
      right: leAnToan.right + lePhai,
      bottom: leAnToan.bottom + leDuoi,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => game.george?.banTheoHuongNhin(),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/joystick_nen.png',
                width: size,
                height: size,
              ),
              ChuGame(
                'BẮN',
                style: TextStyle(
                  color: const Color(0xFFF2F4F7),
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 13 : 15,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
