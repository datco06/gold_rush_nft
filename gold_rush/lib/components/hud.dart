import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../cau_hinh.dart';
import '../man_choi.dart';

/// Thanh máu, điểm số, số xu còn lại và đồng hồ đếm ngược (màn có giới hạn thời gian).
///
/// HUD được gắn vào `camera.viewport`, KHÔNG gắn vào world. Khác biệt rất
/// quan trọng: thứ nằm trong world thì trôi theo bản đồ khi camera di chuyển,
/// còn thứ nằm trong viewport thì luôn đứng yên ở đúng chỗ trên màn hình.
///
/// Toạ độ trong viewport tính bằng pixel màn hình thật, nên cỡ chữ ở đây là
/// cỡ chữ thật, không bị camera phóng to thu nhỏ.
class Hud extends PositionComponent {
  final int Function() layMau;
  final int Function() layDiem;
  final int Function() layXuConLai;

  /// Số giây còn lại; null = màn không giới hạn thời gian (ẩn đồng hồ).
  final double? Function() layGiayConLai;

  static const double _rongThanh = 132;
  static const double _caoThanh = 12;
  static const double _le = 14;

  late final TextComponent _chuDiem;
  late final TextComponent _chuXu;
  late final TextComponent _chuGio;

  bool _gioGap = false;
  double _mauHienThi = 1.0; // 0..1, chạy mượt tới giá trị thật

  Hud({
    required this.layMau,
    required this.layDiem,
    required this.layXuConLai,
    required this.layGiayConLai,
  }) : super(priority: 100);

  /// Dưới 15 giây: đồng hồ chuyển đỏ.
  static final TextPaint _kieuGioGap = TextPaint(
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w900,
      color: Color(0xFFFF6B5E),
      shadows: [Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 2)],
    ),
  );

  static final TextPaint _kieuChu = TextPaint(
    style: const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: CauHinh.mauChu,
      shadows: [Shadow(color: Colors.black87, offset: Offset(0, 1), blurRadius: 2)],
    ),
  );

  @override
  Future<void> onLoad() async {
    _chuDiem = TextComponent(
      text: 'ĐIỂM 0',
      textRenderer: _kieuChu,
      anchor: Anchor.topRight,
    );
    _chuXu = TextComponent(
      text: 'XU 0',
      textRenderer: _kieuChu,
      anchor: Anchor.topRight,
    );
    _chuGio = TextComponent(
      text: '',
      textRenderer: _kieuChu,
      anchor: Anchor.topCenter,
    );
    addAll([_chuDiem, _chuXu, _chuGio]);
    _datViTriChu();
  }

  @override
  void onGameResize(Vector2 kichThuoc) {
    super.onGameResize(kichThuoc);
    size = kichThuoc;
    if (isLoaded) _datViTriChu();
  }

  void _datViTriChu() {
    _chuDiem.position = Vector2(size.x - _le, _le - 2);
    _chuXu.position = Vector2(size.x - _le, _le + 18);
    _chuGio.position = Vector2(size.x / 2, _le - 2);
  }

  @override
  void update(double dt) {
    super.update(dt);

    final mucTieu = (layMau() / CauHinh.mauToiDa).clamp(0.0, 1.0);
    // Nội suy để thanh máu tụt mượt thay vì giật một nhát — chi tiết nhỏ
    // nhưng khiến người chơi cảm nhận được cú đánh vừa nhận.
    _mauHienThi += (mucTieu - _mauHienThi) * (dt * 8).clamp(0.0, 1.0);

    _chuDiem.text = 'ĐIỂM ${layDiem()}';
    _chuXu.text = 'XU CÒN ${layXuConLai()}';
    final con = layGiayConLai();
    _chuGio.text = con == null ? '' : '⏱ ${dinhDangGiay(con)}';
    final gap = con != null && con < 15;
    if (gap != _gioGap) {                  // chỉ đổi kiểu chữ khi cần, không phải mỗi khung hình
      _gioGap = gap;
      _chuGio.textRenderer = gap ? _kieuGioGap : _kieuChu;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final khung = Rect.fromLTWH(_le, _le, _rongThanh, _caoThanh);
    final bo = RRect.fromRectAndRadius(khung, const Radius.circular(6));

    canvas.drawRRect(bo, Paint()..color = CauHinh.mauMauNen);

    if (_mauHienThi > 0) {
      final trong = Rect.fromLTWH(
        _le + 2,
        _le + 2,
        (_rongThanh - 4) * _mauHienThi,
        _caoThanh - 4,
      );
      // Máu thấp thì chuyển sang đỏ đậm để cảnh báo.
      final mau = Color.lerp(
        const Color(0xFF9E1B12),
        CauHinh.mauMau,
        _mauHienThi.clamp(0.0, 1.0),
      )!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(trong, const Radius.circular(4)),
        Paint()..color = mau,
      );
    }

    canvas.drawRRect(
      bo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x88FFFFFF),
    );
  }
}
