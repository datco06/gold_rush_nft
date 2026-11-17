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
    final compact = manHinh.width < 600 || manHinh.height < 420;
    final size = compact ? 60.0 : 72.0;
    return Positioned(
      right: compact ? 14 : 26,
      bottom: compact ? 14 : 26,
      child: GestureDetector(
        onTap: () => game.george?.banTheoHuongNhin(),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset('assets/images/joystick_nen.png'),
              ChuGame(
                'BẮN',
                style: TextStyle(
                  color: const Color(0xFFF2F4F7),
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 12 : 14,
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
