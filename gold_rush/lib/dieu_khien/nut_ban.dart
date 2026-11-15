import 'package:flutter/material.dart';

import '../gold_rush_game.dart';
import '../ngon_ngu/ngon_ngu.dart';

/// Nút bắn nổi trên màn chơi.
class NutBan extends StatelessWidget {
  final GoldRushGame game;

  const NutBan({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 26,
      bottom: 26,
      child: GestureDetector(
        onTap: () => game.george?.banTheoHuongNhin(),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset('assets/images/joystick_nen.png'),
              const ChuGame(
                'BẮN',
                style: TextStyle(
                  color: Color(0xFFF2F4F7),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
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
