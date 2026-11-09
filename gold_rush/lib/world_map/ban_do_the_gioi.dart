import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import '../man_choi.dart';
import 'canh_quan_world_map.dart';
import 'nut_man_choi.dart';

/// Cảnh quan và tương tác chọn màn, không xử lý ví hoặc tự cấp tiến trình.
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
  late Future<Map<String, ui.Image>> _taiAnh = TaiNguyenWorldMap.nap();
  Size _kichThuocVungXem = Size.zero;

  @override
  void dispose() {
    _boDieuKhien.dispose();
    // Ảnh được dùng chung giữa các lần mở map; không dispose ở mỗi overlay.
    super.dispose();
  }

  double _tiLeVuaKhung(Size kichThuoc) =>
      math.min(
        kichThuoc.width / BoCucWorldMap.kichThuoc.width,
        kichThuoc.height / BoCucWorldMap.kichThuoc.height,
      ) *
      1.0;

  void _datGocNhin(double tiLe, double x, double y) {
    _boDieuKhien.value = Matrix4.identity()
      ..setEntry(0, 0, tiLe)
      ..setEntry(1, 1, tiLe)
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
  }

  void _xemToanBanDo() {
    final size = _kichThuocVungXem;
    if (size.isEmpty) return;
    final scale = _tiLeVuaKhung(size);
    _datGocNhin(
      scale,
      (size.width - BoCucWorldMap.kichThuoc.width * scale) / 2,
      (size.height - BoCucWorldMap.kichThuoc.height * scale) / 2,
    );
  }

  void _zoom(double heSo) {
    final size = _kichThuocVungXem;
    if (size.isEmpty) return;
    final scale = (_boDieuKhien.value.getMaxScaleOnAxis() * heSo)
        .clamp(_tiLeVuaKhung(size), 3.0)
        .toDouble();
    final tam = size.center(Offset.zero);
    final diem = _boDieuKhien.toScene(tam);
    _datGocNhin(scale, tam.dx - diem.dx * scale, tam.dy - diem.dy * scale);
  }

  @override
  Widget build(BuildContext context) {
    final danhSach = widget.danhSachMan;
    if (danhSach.isEmpty) return _thongBao('Chưa có dữ liệu màn chơi.');
    if (danhSach.length > 20) {
      return _thongBao('Khu vực này hiện hỗ trợ tối đa 20 màn.');
    }
    if (danhSach.any((m) => !widget.trangThaiCacMan.containsKey(m.id))) {
      return _thongBao('Chưa có đủ dữ liệu tiến trình các màn.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'GOLD RUSH · ATLAS',
                    style: TextStyle(
                      color: Color(0xFFCAB48A),
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Thu nhỏ',
                  onPressed: () => _zoom(1 / 1.25),
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  color: MauGame.chu,
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: 'Phóng to',
                  onPressed: () => _zoom(1.25),
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  color: MauGame.chu,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Toàn bản đồ',
                  onPressed: _xemToanBanDo,
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  color: const Color(0xFFE4C68B),
                  icon: const Icon(Icons.fit_screen),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              if (size.isEmpty) return const SizedBox.shrink();
              if (size != _kichThuocVungXem) {
                final truoc = _kichThuocVungXem;
                _kichThuocVungXem = size;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _kichThuocVungXem != size) return;
                  if (truoc.isEmpty) {
                    _xemToanBanDo();
                  } else {
                    // Giữ vùng đang xem khi xoay thiết bị/resize cửa sổ.
                    final tamCu = _boDieuKhien.toScene(
                      truoc.center(Offset.zero),
                    );
                    final scale = math.max(
                      _boDieuKhien.value.getMaxScaleOnAxis(),
                      _tiLeVuaKhung(size),
                    );
                    _datGocNhin(
                      scale,
                      size.width / 2 - tamCu.dx * scale,
                      size.height / 2 - tamCu.dy * scale,
                    );
                  }
                });
              }
              return ClipRect(
                child: ColoredBox(
                  color: const Color(0xFF19251E),
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        transformationController: _boDieuKhien,
                        alignment: Alignment.topLeft,
                        constrained: false,
                        minScale: _tiLeVuaKhung(size),
                        maxScale: 3,
                        boundaryMargin: const EdgeInsets.all(32),
                        child: SizedBox.fromSize(
                          size: BoCucWorldMap.kichThuoc,
                          child: IgnorePointer(
                            child: FutureBuilder<Map<String, ui.Image>>(
                              future: _taiAnh,
                              initialData: TaiNguyenWorldMap.anhDaNap,
                              builder: (context, snapshot) => RepaintBoundary(
                                child: CustomPaint(
                                  painter: CanhQuanWorldMap(
                                    snapshot.data ?? const {},
                                    trangThaiCacMan: widget.trangThaiCacMan,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Nhãn theo ma trận của bản đồ, nhưng giữ kích thước chữ/vùng bấm.
                      // Cảnh trang trí không bao giờ bắt sự kiện của level.
                      AnimatedBuilder(
                        animation: _boDieuKhien,
                        builder: (context, _) => _cacDiaDiem(size),
                      ),
                      FutureBuilder<Map<String, ui.Image>>(
                        future: _taiAnh,
                        builder: (context, snapshot) {
                          if (!snapshot.hasError) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: Alignment.topCenter,
                            child: Material(
                              color: const Color(0xFF492E29),
                              child: TextButton(
                                onPressed: () => setState(() {
                                  _taiAnh = TaiNguyenWorldMap.nap();
                                }),
                                child: const Text(
                                  'Chưa nạp được ảnh bản đồ. Bấm để thử lại.',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _thongBao(String noiDung) => Center(
    child: Text(noiDung, style: const TextStyle(color: MauGame.chu)),
  );

  Widget _cacDiaDiem(Size size) {
    final gon = size.width < 700 || size.height < 360;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final rong = gon ? 40.0 : 100.0;
    final cao = (gon ? 40.0 : 70.0) * textScale;
    final cacNhan = <({ManChoi man, Offset moc, Rect khung})>[];
    final cacMoc = <({ManChoi man, Offset moc})>[];
    for (var i = 0; i < widget.danhSachMan.length; i++) {
      final man = widget.danhSachMan[i];
      final goc =
          BoCucWorldMap.viTriMan[man.id] ??
          BoCucWorldMap.viTriMan.values.elementAt(i);
      final moc = MatrixUtils.transformPoint(_boDieuKhien.value, goc);
      if (!(Offset.zero & size).inflate(30).contains(moc)) continue;
      cacMoc.add((man: man, moc: moc));
    }
    if (gon) {
      // Đặt các địa điểm sát mép trước: chúng có ít chỗ dịch nhãn hơn.
      double cachMep(Offset p) => math.min(
        math.min(p.dx, size.width - p.dx),
        math.min(p.dy, size.height - p.dy),
      );
      cacMoc.sort((a, b) => cachMep(a.moc).compareTo(cachMep(b.moc)));
    }
    for (final diem in cacMoc) {
      final khung = _datNhan(
        diem.moc,
        Size(rong, cao),
        size,
        cacNhan.map((n) => n.khung).toList(),
      );
      cacNhan.add((man: diem.man, moc: diem.moc, khung: khung));
    }
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DuongDanDiaDiem([
                for (final n in cacNhan)
                  (n.moc, n.khung, n.man.id == widget.manDangChon),
              ]),
            ),
          ),
        ),
        for (final n in cacNhan)
          Positioned(
            left: n.khung.left,
            top: n.khung.top,
            width: n.khung.width,
            child: NutManChoi(
              key: ValueKey('world-map-level-${n.man.id}'),
              man: n.man,
              trangThai: widget.trangThaiCacMan[n.man.id]!,
              dangChon: n.man.id == widget.manDangChon,
              gon: gon,
              khiChon: widget.khiChonMan,
            ),
          ),
      ],
    );
  }

  Rect _datNhan(Offset moc, Size nhan, Size view, List<Rect> daDat) {
    final cacViTri = [
      Offset(moc.dx - nhan.width / 2, moc.dy - nhan.height / 2),
      Offset(moc.dx - nhan.width / 2, moc.dy + 12),
      Offset(moc.dx - nhan.width / 2, moc.dy - nhan.height - 12),
      Offset(moc.dx + 18, moc.dy - nhan.height / 2),
      Offset(moc.dx - nhan.width - 18, moc.dy - nhan.height / 2),
    ];
    Rect gioiHan(Offset p) =>
        Offset(
          p.dx
              .clamp(6.0, math.max(6.0, view.width - nhan.width - 6))
              .toDouble(),
          p.dy
              .clamp(6.0, math.max(6.0, view.height - nhan.height - 6))
              .toDouble(),
        ) &
        nhan;
    final taiMoc = gioiHan(cacViTri.first);
    if (daDat.every((r) => !r.inflate(3).overlaps(taiMoc))) return taiMoc;
    // Tìm vị trí gần nhất; không ưu tiên một hướng xa mốc trên màn hình hẹp.
    Rect? ganNhat;
    var khoangCach = double.infinity;
    for (var y = 6.0; y + nhan.height < view.height; y += 6) {
      for (var x = 6.0; x + nhan.width < view.width; x += 6) {
        final rect = Offset(x, y) & nhan;
        final d = (rect.center - moc).distanceSquared;
        if (d < khoangCach &&
            daDat.every((r) => !r.inflate(3).overlaps(rect))) {
          ganNhat = rect;
          khoangCach = d;
        }
      }
    }
    return ganNhat ?? taiMoc;
  }
}

class _DuongDanDiaDiem extends CustomPainter {
  final List<(Offset, Rect, bool)> cacDiem;
  _DuongDanDiaDiem(this.cacDiem);

  @override
  void paint(Canvas canvas, Size size) {
    for (final (moc, khung, dangChon) in cacDiem) {
      final mau = dangChon ? const Color(0xFFFFD078) : const Color(0xFFCAD2A2);
      final dich = Offset(
        moc.dx.clamp(khung.left, khung.right).toDouble(),
        moc.dy.clamp(khung.top, khung.bottom).toDouble(),
      );
      canvas.drawLine(
        moc,
        dich,
        Paint()
          ..color = mau.withValues(alpha: 0.7)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(moc, dangChon ? 5 : 3.5, Paint()..color = mau);
      canvas.drawCircle(
        moc,
        dangChon ? 8 : 6,
        Paint()
          ..color = mau.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_DuongDanDiaDiem oldDelegate) =>
      oldDelegate.cacDiem != cacDiem;
}
