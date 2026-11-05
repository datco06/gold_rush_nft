import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import '../man_choi.dart';
import 'nut_man_choi.dart';

/// Hiển thị bản đồ và gửi sự kiện chọn màn.
/// Không xử lý đặt cọc hoặc tự quyết định tiến trình.
class BanDoTheGioi extends StatefulWidget {
  final List<ManChoi> danhSachMan;
  final Map<int, TrangThaiMan> trangThaiCacMan;
  final int? manDangChon;
  final ValueChanged<ManChoi> khiChonMan;

  const BanDoTheGioi({
    super.key,
    required this.danhSachMan,
    required this.trangThaiCacMan,
    required this.khiChonMan,
    this.manDangChon,
  });

  @override
  State<BanDoTheGioi> createState() => _BanDoTheGioiState();
}

class _BanDoTheGioiState extends State<BanDoTheGioi> {
  final TransformationController _boDieuKhien = TransformationController();

  static const double _chieuRong = 1800;
  static const double _chieuCao = 1000;

  static const List<Offset> _viTri = [
    Offset(100, 620),
    Offset(380, 420),
    Offset(660, 610),
    Offset(940, 350),
    Offset(1220, 510),
    Offset(1500, 230),
  ];

  Size _kichThuocVungXem = Size.zero;

  @override
  void dispose() {
    _boDieuKhien.dispose();
    super.dispose();
  }

  double _tiLeVuaKhung(Size kichThuoc) {
    return math.min(
          kichThuoc.width / _chieuRong,
          kichThuoc.height / _chieuCao,
        ) *
        0.98;
  }

  void _datGocNhin(double tiLe, double x, double y) {
    final maTran = Matrix4.identity()
      ..setEntry(0, 0, tiLe)
      ..setEntry(1, 1, tiLe)
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);

    _boDieuKhien.value = maTran;
  }

  void _xemToanBanDo() {
    final kichThuoc = _kichThuocVungXem;
    if (kichThuoc.isEmpty) return;

    final tiLe = _tiLeVuaKhung(kichThuoc);

    _datGocNhin(
      tiLe,
      (kichThuoc.width - _chieuRong * tiLe) / 2,
      (kichThuoc.height - _chieuCao * tiLe) / 2,
    );
  }

  void _zoom(double heSo) {
    final kichThuoc = _kichThuocVungXem;
    if (kichThuoc.isEmpty) return;

    final tiLeCu = _boDieuKhien.value.getMaxScaleOnAxis();
    final tiLeMoi = (tiLeCu * heSo)
        .clamp(_tiLeVuaKhung(kichThuoc) * 0.7, 3.0)
        .toDouble();

    final tam = Offset(kichThuoc.width / 2, kichThuoc.height / 2);
    final diemTrongBanDo = _boDieuKhien.toScene(tam);

    _datGocNhin(
      tiLeMoi,
      tam.dx - diemTrongBanDo.dx * tiLeMoi,
      tam.dy - diemTrongBanDo.dy * tiLeMoi,
    );
  }

  @override
  Widget build(BuildContext context) {
    final danhSach = widget.danhSachMan;

    if (danhSach.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có dữ liệu màn chơi.',
          style: TextStyle(color: MauGame.chu),
        ),
      );
    }

    if (danhSach.length > _viTri.length) {
      return const Center(
        child: Text(
          'Khu vực này hiện hỗ trợ tối đa 6 màn.',
          style: TextStyle(color: MauGame.chu),
        ),
      );
    }

    final thieuTrangThai = danhSach.any(
      (man) => !widget.trangThaiCacMan.containsKey(man.id),
    );

    if (thieuTrangThai) {
      return const Center(
        child: Text(
          'Chưa có đủ dữ liệu tiến trình các màn.',
          style: TextStyle(color: MauGame.chu),
        ),
      );
    }

    final cacDiem = [
      for (var i = 0; i < danhSach.length; i++)
        _viTri[i] + const Offset(80, 70),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gộp tiêu đề và công cụ để dành chiều cao cho bản đồ.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 0,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forest_rounded, color: MauGame.chinh, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'RỪNG KHỞI ĐẦU',
                    style: TextStyle(
                      color: MauGame.chinh,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Thu nhỏ',
                    onPressed: () => _zoom(1 / 1.25),
                    color: MauGame.chu,
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: 'Phóng to',
                    onPressed: () => _zoom(1.25),
                    color: MauGame.chu,
                    icon: const Icon(Icons.add),
                  ),
                  TextButton.icon(
                    onPressed: _xemToanBanDo,
                    icon: const Icon(Icons.fit_screen, size: 20),
                    label: const Text('Toàn bản đồ'),
                    style: TextButton.styleFrom(foregroundColor: MauGame.chinh),
                  ),
                  const Tooltip(
                    message:
                        'Kéo để di chuyển bản đồ. '
                        'Cuộn chuột hoặc chụm hai ngón '
                        'để thu/phóng.',
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.help_outline_rounded,
                        color: MauGame.chuPhu,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final kichThuoc = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );

              if (kichThuoc.isEmpty) {
                return const SizedBox.shrink();
              }

              if (kichThuoc != _kichThuocVungXem) {
                _kichThuocVungXem = kichThuoc;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _kichThuocVungXem == kichThuoc) {
                    _xemToanBanDo();
                  }
                });
              }

              return ClipRect(
                child: InteractiveViewer(
                  transformationController: _boDieuKhien,
                  alignment: Alignment.topLeft,
                  constrained: false,
                  minScale: _tiLeVuaKhung(kichThuoc) * 0.7,
                  maxScale: 3,
                  boundaryMargin: const EdgeInsets.all(1800),
                  child: SizedBox(
                    width: _chieuRong,
                    height: _chieuCao,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _NenBanDo(cacDiem)),
                        ),
                        for (var i = 0; i < danhSach.length; i++)
                          Positioned(
                            left: _viTri[i].dx,
                            top: _viTri[i].dy,
                            child: NutManChoi(
                              man: danhSach[i],
                              trangThai:
                                  widget.trangThaiCacMan[danhSach[i].id]!,
                              dangChon: danhSach[i].id == widget.manDangChon,
                              khiChon: widget.khiChonMan,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Nền cảnh quan, không ảnh hưởng dữ liệu gameplay.
class _NenBanDo extends CustomPainter {
  final List<Offset> cacDiem;

  _NenBanDo(this.cacDiem);

  static const _mauCo = Color(0xFF477A3B);
  static const _mauCoSang = Color(0xFF548B43);
  static const _mauCoToi = Color(0xFF3D6C34);
  static const _mauNgonCo = Color(0xFF78A652);
  static const _mauBong = Color(0x330D2416);
  static const _mauThanCay = Color(0xFF765039);
  static const _mauLaToi = Color(0xFF244C31);
  static const _mauLa = Color(0xFF32653B);
  static const _mauLaSang = Color(0xFF4E8545);
  static const _mauVienDuong = Color(0xFF6F5738);
  static const _mauDat = Color(0xFFB18B54);
  static const _mauDatSang = Color(0xFFCFAC70);
  static const _mauDa = Color(0xFF788078);
  static const _mauDaSang = Color(0xFFA2AA98);
  static const _mauHoa = Color(0xFFFFDC78);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, Paint()..color = _mauCo);

    for (var hang = 0; hang < size.height / 64; hang++) {
      for (var cot = 0; cot < size.width / 64; cot++) {
        final giaTri = (cot * 17 + hang * 31) % 11;
        final o = Rect.fromLTWH(cot * 64.0, hang * 64.0, 64, 64);

        if (giaTri < 3) {
          canvas.drawRect(o, Paint()..color = _mauCoSang);
        } else if (giaTri > 8) {
          canvas.drawRect(o, Paint()..color = _mauCoToi);
        }

        final x = cot * 64.0 + 12 + giaTri;
        final y = hang * 64.0 + 26;

        _veCo(canvas, Offset(x, y));

        if (giaTri == 4) {
          _veHoa(canvas, Offset(x + 20, y + 18));
        }
      }
    }

    if (cacDiem.length >= 2) {
      final duongDi = Path()..moveTo(cacDiem.first.dx, cacDiem.first.dy);

      for (final diem in cacDiem.skip(1)) {
        duongDi.lineTo(diem.dx, diem.dy);
      }

      _veDuong(canvas, duongDi, _mauVienDuong, 42);
      _veDuong(canvas, duongDi, _mauDat, 32);
      _veDuong(canvas, duongDi, _mauDatSang, 12);
    }

    for (var hang = 0; hang < 8; hang++) {
      for (var cot = 0; cot < 14; cot++) {
        final viTri = Offset(
          70.0 + cot * 128 + (hang.isEven ? 0 : 40),
          180.0 + hang * 106,
        );

        if (_ganDuongHoacMan(viTri)) continue;

        final loai = (cot * 7 + hang * 13) % 9;

        if (loai < 5) {
          _veCay(canvas, viTri);
        } else if (loai == 6) {
          _veDa(canvas, viTri);
        } else {
          _veHoa(canvas, viTri);
          _veCo(canvas, viTri + const Offset(14, 12));
        }
      }
    }

    canvas.restore();
  }

  void _veDuong(Canvas canvas, Path duong, Color mau, double doRong) {
    canvas.drawPath(
      duong,
      Paint()
        ..color = mau
        ..style = PaintingStyle.stroke
        ..strokeWidth = doRong
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  void _veCo(Canvas canvas, Offset diem) {
    final but = Paint()..color = _mauNgonCo;

    canvas.drawRect(Rect.fromLTWH(diem.dx, diem.dy, 3, 9), but);
    canvas.drawRect(Rect.fromLTWH(diem.dx - 5, diem.dy + 3, 3, 5), but);
    canvas.drawRect(Rect.fromLTWH(diem.dx + 5, diem.dy + 1, 3, 7), but);
  }

  void _veHoa(Canvas canvas, Offset diem) {
    canvas.drawRect(
      Rect.fromLTWH(diem.dx, diem.dy + 4, 3, 9),
      Paint()..color = _mauLaToi,
    );

    final but = Paint()..color = _mauHoa;

    canvas.drawRect(Rect.fromLTWH(diem.dx - 3, diem.dy, 9, 3), but);
    canvas.drawRect(Rect.fromLTWH(diem.dx, diem.dy - 3, 3, 9), but);
  }

  void _veCay(Canvas canvas, Offset diem) {
    final x = diem.dx;
    final y = diem.dy;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y + 25), width: 62, height: 20),
      Paint()..color = _mauBong,
    );

    canvas.drawRect(
      Rect.fromLTWH(x - 6, y, 12, 30),
      Paint()..color = _mauThanCay,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 30, y - 25, 60, 36),
      Paint()..color = _mauLaToi,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 23, y - 43, 46, 48),
      Paint()..color = _mauLa,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 14, y - 53, 28, 16),
      Paint()..color = _mauLa,
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 17, y - 36, 18, 12),
      Paint()..color = _mauLaSang,
    );
    canvas.drawRect(
      Rect.fromLTWH(x + 5, y - 17, 12, 8),
      Paint()..color = _mauLaSang,
    );
  }

  void _veDa(Canvas canvas, Offset diem) {
    canvas.drawOval(
      Rect.fromLTWH(diem.dx - 20, diem.dy + 8, 44, 16),
      Paint()..color = _mauBong,
    );
    canvas.drawRect(
      Rect.fromLTWH(diem.dx - 16, diem.dy - 9, 34, 26),
      Paint()..color = _mauDa,
    );
    canvas.drawRect(
      Rect.fromLTWH(diem.dx - 9, diem.dy - 16, 22, 12),
      Paint()..color = _mauDa,
    );
    canvas.drawRect(
      Rect.fromLTWH(diem.dx - 10, diem.dy - 8, 14, 7),
      Paint()..color = _mauDaSang,
    );
  }

  bool _ganDuongHoacMan(Offset diem) {
    for (final tam in cacDiem) {
      if ((diem.dx - tam.dx).abs() < 130 && (diem.dy - tam.dy).abs() < 145) {
        return true;
      }
    }

    for (var i = 1; i < cacDiem.length; i++) {
      final a = cacDiem[i - 1];
      final b = cacDiem[i];
      final ab = b - a;
      final doDaiBinhPhuong = ab.dx * ab.dx + ab.dy * ab.dy;

      if (doDaiBinhPhuong == 0) continue;

      final ap = diem - a;
      final tiLe = ((ap.dx * ab.dx + ap.dy * ab.dy) / doDaiBinhPhuong)
          .clamp(0.0, 1.0)
          .toDouble();

      final diemGanNhat = a + ab * tiLe;

      if ((diem - diemGanNhat).distance < 85) {
        return true;
      }
    }

    return false;
  }

  @override
  bool shouldRepaint(covariant _NenBanDo oldDelegate) {
    if (oldDelegate.cacDiem.length != cacDiem.length) {
      return true;
    }

    for (var i = 0; i < cacDiem.length; i++) {
      if (oldDelegate.cacDiem[i] != cacDiem[i]) {
        return true;
      }
    }

    return false;
  }
}
