import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

import '../cau_hinh.dart';

final _ngauNhien = Random();

Vector2 _huongNgauNhien(double lucToiThieu, double lucToiDa) {
  final goc = _ngauNhien.nextDouble() * 2 * pi;
  final luc = lucToiThieu + _ngauNhien.nextDouble() * (lucToiDa - lucToiThieu);
  return Vector2(cos(goc), sin(goc)) * luc;
}

/// Chùm tia sáng bắn ra khi nhặt được đồng xu (Chương 9 — hiệu ứng hạt).
///
/// `ParticleSystemComponent` tự xoá mình khỏi cây component khi hạt cuối cùng
/// hết vòng đời, nên không cần dọn dẹp thủ công.
class HieuUngNhatXu extends ParticleSystemComponent {
  HieuUngNhatXu(Vector2 viTri)
      : super(
          position: viTri,
          priority: 3,
          particle: Particle.generate(
            count: 12,
            lifespan: 0.55,
            generator: (i) => AcceleratedParticle(
              speed: _huongNgauNhien(24, 64),
              acceleration: Vector2(0, 90), // rơi xuống như tàn pháo hoa
              child: ComputedParticle(
                renderer: (canvas, hat) {
                  // hat.progress chạy từ 0 đến 1 -> hạt mờ và nhỏ dần.
                  final mo = (1 - hat.progress).clamp(0.0, 1.0);
                  final son = Paint()
                    ..color = const Color(0xFFFFD84D).withValues(alpha: mo);
                  canvas.drawCircle(Offset.zero, 1.6 * mo + 0.4, son);
                },
              ),
            ),
          ),
        );
}

/// Vụ nổ khi kẻ địch lao vào George rồi tự huỷ.
class HieuUngNoKeDich extends ParticleSystemComponent {
  HieuUngNoKeDich(Vector2 viTri, Color mau)
      : super(
          position: viTri,
          priority: 3,
          particle: Particle.generate(
            count: 22,
            lifespan: 0.7,
            generator: (i) => AcceleratedParticle(
              speed: _huongNgauNhien(30, 110),
              acceleration: Vector2(0, 60),
              child: ComputedParticle(
                renderer: (canvas, hat) {
                  final mo = (1 - hat.progress).clamp(0.0, 1.0);
                  final son = Paint()..color = mau.withValues(alpha: mo);
                  canvas.drawRect(
                    Rect.fromCenter(
                      center: Offset.zero,
                      width: 2.2 * mo + 0.6,
                      height: 2.2 * mo + 0.6,
                    ),
                    son,
                  );
                },
              ),
            ),
          ),
        );
}

/// Bóng đổ dưới chân nhân vật (Chương 9 — hiệu ứng lớp).
///
/// KHÔNG làm bóng bằng một component con, vì Flame vẽ component cha TRƯỚC rồi
/// mới vẽ các con, nên bóng sẽ nằm đè lên nhân vật. Cách đúng là vẽ bóng ngay
/// trong hàm render của nhân vật, trước khi gọi super.render.
class Bong {
  Bong._();

  static final Paint _son = Paint()..color = const Color(0x40000000);

  /// Gọi ở đầu hàm render của nhân vật, toạ độ là hệ toạ độ cục bộ của sprite
  /// (gốc nằm ở góc trên-trái của ô 16×16).
  static void ve(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(CauHinh.kichThuocO / 2, CauHinh.kichThuocO - 1.5),
        width: 9,
        height: 3.5,
      ),
      _son,
    );
  }
}
