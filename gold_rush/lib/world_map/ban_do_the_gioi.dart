import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../giao_dien/mau_game.dart';
import '../man_choi.dart';
import 'canh_quan_world_map.dart';
import 'hoat_anh_world_map.dart';
import 'nut_man_choi.dart';

/// Cảnh quan và tương tác chọn màn trên World Map mở rộng.
/// Không xử lý ví hoặc tự cấp tiến trình mở khóa màn.
class BanDoTheGioi extends StatefulWidget {
  final List<ManChoi> danhSachMan;
  final Map<int, TrangThaiMan> trangThaiCacMan;
  final int? manDangChon;
  final ValueChanged<ManChoi> khiChonMan;
  final ValueChanged<int>? khiGeorgeDenMan;
  final String tepAnhGeorge;
  final bool? chayHoatAnhLienTuc;

  const BanDoTheGioi({
    super.key,
    required this.danhSachMan,
    required this.trangThaiCacMan,
    required this.khiChonMan,
    this.manDangChon,
    this.khiGeorgeDenMan,
    this.tepAnhGeorge = 'george.png',
    this.chayHoatAnhLienTuc,
  });

  @override
  State<BanDoTheGioi> createState() => BanDoTheGioiState();
}

class BanDoTheGioiState extends State<BanDoTheGioi>
    with TickerProviderStateMixin {
  final TransformationController _boDieuKhien = TransformationController();
  late Future<Map<String, ui.Image>> _taiAnh = TaiNguyenWorldMap.nap();
  late Future<ui.Image?> _taiAnhGeorge = TaiNguyenWorldMap.napAnhGeorge(
    widget.tepAnhGeorge,
  );
  Size _kichThuocVungXem = Size.zero;

  late final AnimationController _boNhipCanhVat;
  late final AnimationController _boDieuKhienGeorge;

  late int _nodeGeorgeHienTai;
  late Offset _viTriGeorge;
  HuongGeorgeWorldMap _huongGeorge = HuongGeorgeWorldMap.xuong;
  LoTrinhGeorgeWorldMap? _loTrinhGeorge;

  int get nodeGeorgeHienTai => _nodeGeorgeHienTai;
  Offset get viTriGeorge => _viTriGeorge;
  HuongGeorgeWorldMap get huongGeorge => _huongGeorge;
  bool get dangDiChuyenGeorge => _boDieuKhienGeorge.isAnimating;
  LoTrinhGeorgeWorldMap? get loTrinhGeorge => _loTrinhGeorge;
  TransformationController get boDieuKhienCamera => _boDieuKhien;

  bool get _trongMoiTruongKiemThu {
    if (widget.chayHoatAnhLienTuc != null) {
      return !widget.chayHoatAnhLienTuc!;
    }
    final ten = WidgetsBinding.instance.runtimeType.toString();
    return ten.contains('TestWidgetsFlutterBinding') ||
        ten.contains('AutomatedTest') ||
        ten.contains('LiveTest');
  }

  bool _daMo(int id) {
    final st = widget.trangThaiCacMan[id];
    return st == TrangThaiMan.daMo || st == TrangThaiMan.hoanThanh;
  }

  int _xacDinhNodeKhoiDau() {
    final chon = widget.manDangChon;
    if (chon != null && _daMo(chon)) return chon;

    // Ưu tiên màn đang mở mới nhất theo tiến trình.
    for (final m in widget.danhSachMan.reversed) {
      if (widget.trangThaiCacMan[m.id] == TrangThaiMan.daMo) {
        return m.id;
      }
    }
    for (final m in widget.danhSachMan.reversed) {
      if (widget.trangThaiCacMan[m.id] == TrangThaiMan.hoanThanh) {
        return m.id;
      }
    }
    return widget.danhSachMan.isEmpty ? 1 : widget.danhSachMan.first.id;
  }

  @override
  void initState() {
    super.initState();
    _nodeGeorgeHienTai = _xacDinhNodeKhoiDau();
    _viTriGeorge =
        BoCucWorldMap.viTriMan[_nodeGeorgeHienTai] ??
        BoCucWorldMap.viTriMan[1]!;

    _boNhipCanhVat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    if (widget.chayHoatAnhLienTuc == true && !_trongMoiTruongKiemThu) {
      _boNhipCanhVat.repeat();
    }

    _boDieuKhienGeorge =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 360),
        )..addListener(_capNhatBuocDiGeorge)
        ..addStatusListener(_khiTrangThaiDiChuyenDoi);
  }

  @override
  void didUpdateWidget(covariant BanDoTheGioi oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tepAnhGeorge != widget.tepAnhGeorge) {
      _taiAnhGeorge = TaiNguyenWorldMap.napAnhGeorge(widget.tepAnhGeorge);
    }

    // Khi tiến trình thay đổi từ bên ngoài (ví dụ đăng nhập SIWE hoặc thắng màn),
    // đồng bộ vị trí George về màn hợp lệ.
    if (oldWidget.trangThaiCacMan != widget.trangThaiCacMan) {
      if (!_daMo(_nodeGeorgeHienTai)) {
        _boDieuKhienGeorge.stop();
        _loTrinhGeorge = null;
        _nodeGeorgeHienTai = _xacDinhNodeKhoiDau();
        _viTriGeorge =
            BoCucWorldMap.viTriMan[_nodeGeorgeHienTai] ?? _viTriGeorge;
      } else if (widget.manDangChon != null &&
          _daMo(widget.manDangChon!) &&
          widget.manDangChon != _nodeGeorgeHienTai &&
          !_boDieuKhienGeorge.isAnimating) {
        _diChuyenGeorgeDen(widget.manDangChon!);
      }
    }
  }

  @override
  void dispose() {
    _boDieuKhienGeorge.dispose();
    _boNhipCanhVat.dispose();
    _boDieuKhien.dispose();
    // Ảnh được dùng chung giữa các lần mở map; không dispose ở mỗi overlay.
    super.dispose();
  }

  void _capNhatBuocDiGeorge() {
    final lt = _loTrinhGeorge;
    if (lt == null) return;
    final kq = lt.noiSuy(_boDieuKhienGeorge.value);
    _viTriGeorge = kq.viTri;
    _huongGeorge = HuongGeorgeWorldMap.tuVector(kq.huong);

    // Nếu người chơi đang phóng to bản đồ, camera tự động đi theo George.
    final size = _kichThuocVungXem;
    if (!size.isEmpty) {
      final scale = _boDieuKhien.value.getMaxScaleOnAxis();
      if (scale > _tiLeVuaKhung(size) * 1.08) {
        final dich = BoCucWorldMap.tinhDichChuyenTapTrungDiem(
          diemTheGioi: _viTriGeorge,
          tiLe: scale,
          kichThuocKhung: size,
        );
        _datGocNhin(scale, dich.dx, dich.dy);
      }
    }
  }

  void _khiTrangThaiDiChuyenDoi(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      final lt = _loTrinhGeorge;
      if (lt != null) {
        _nodeGeorgeHienTai = lt.denMan;
        _viTriGeorge =
            BoCucWorldMap.viTriMan[_nodeGeorgeHienTai] ?? _viTriGeorge;
        _huongGeorge = HuongGeorgeWorldMap.xuong;
        _loTrinhGeorge = null;
        widget.khiGeorgeDenMan?.call(_nodeGeorgeHienTai);
        if (mounted) setState(() {});
      }
    }
  }

  /// Di chuyển George theo đường mòn tới node màn `idDich` nếu màn đó đã mở.
  bool diChuyenGeorgeDen(int idDich) => _diChuyenGeorgeDen(idDich);

  bool _diChuyenGeorgeDen(int idDich) {
    if (!_daMo(idDich)) return false;

    // Nếu đang đi dở thì lấy node xuất phát gần nhất đã mở để không bao giờ rời đường mòn.
    if (_boDieuKhienGeorge.isAnimating && _loTrinhGeorge != null) {
      _boDieuKhienGeorge.stop();
    }

    if (idDich == _nodeGeorgeHienTai && !_boDieuKhienGeorge.isAnimating) {
      _viTriGeorge = BoCucWorldMap.viTriMan[idDich] ?? _viTriGeorge;
      _loTrinhGeorge = null;
      widget.khiGeorgeDenMan?.call(idDich);
      return true;
    }

    final lt = BoCucWorldMap.timLoTrinh(
      _nodeGeorgeHienTai,
      idDich,
      widget.trangThaiCacMan,
    );
    if (lt == null) return false;

    _loTrinhGeorge = lt;
    final soChang = math.max(1, lt.cacManDiQua.length - 1);
    _boDieuKhienGeorge.duration = Duration(
      milliseconds: (220 * soChang).clamp(240, 600),
    );
    _boDieuKhienGeorge.forward(from: 0);
    return true;
  }

  double _tiLeVuaKhung(Size kichThuoc) =>
      math.min(
        kichThuoc.width / BoCucWorldMap.kichThuoc.width,
        kichThuoc.height / BoCucWorldMap.kichThuoc.height,
      ) *
      1.0;

  void _datGocNhin(double tiLe, double x, double y, {double le = 0.0}) {
    final size = _kichThuocVungXem;
    final dich = size.isEmpty
        ? Offset(x, y)
        : BoCucWorldMap.gioiHanDichChuyenCamera(
            tiLe: tiLe,
            dichChuyen: Offset(x, y),
            kichThuocKhung: size,
            le: le,
          );
    _boDieuKhien.value = Matrix4.identity()
      ..setEntry(0, 0, tiLe)
      ..setEntry(1, 1, tiLe)
      ..setEntry(2, 2, tiLe)
      ..setEntry(0, 3, dich.dx)
      ..setEntry(1, 3, dich.dy);
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

  /// Đưa camera tập trung vào vị trí hiện tại của George (có giới hạn biên bản đồ).
  void tapTrungVaoGeorge({double? tiLe}) {
    final size = _kichThuocVungXem;
    if (size.isEmpty) return;
    final minScale = _tiLeVuaKhung(size);
    final currentScale = _boDieuKhien.value.getMaxScaleOnAxis();
    final scale = (tiLe ?? math.max(currentScale, minScale * 1.45))
        .clamp(minScale, 3.0)
        .toDouble();
    final dich = BoCucWorldMap.tinhDichChuyenTapTrungDiem(
      diemTheGioi: _viTriGeorge,
      tiLe: scale,
      kichThuocKhung: size,
    );
    _datGocNhin(scale, dich.dx, dich.dy);
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

  void _gioiHanCameraSauTuongTac() {
    final size = _kichThuocVungXem;
    if (size.isEmpty) return;
    final m = _boDieuKhien.value;
    final scale = m.getMaxScaleOnAxis().clamp(_tiLeVuaKhung(size), 3.0);
    final tx = m.entry(0, 3);
    final ty = m.entry(1, 3);
    _datGocNhin(scale, tx, ty, le: 32);
  }

  Rect? _tinhVungNhinThay(Size size) {
    if (size.isEmpty) return null;
    final trenTrai = _boDieuKhien.toScene(Offset.zero);
    final duoiPhai = _boDieuKhien.toScene(Offset(size.width, size.height));
    return Rect.fromPoints(trenTrai, duoiPhai);
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

    final vungGeorge = BoCucWorldMap.vungCuaMan(_nodeGeorgeHienTai);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'GOLD RUSH · ATLAS · ${vungGeorge.ten.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCAB48A),
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Định vị George',
                  onPressed: tapTrungVaoGeorge,
                  visualDensity: VisualDensity.compact,
                  iconSize: 17,
                  color: const Color(0xFFFFD56B),
                  icon: const Icon(Icons.my_location),
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

              final nhipHoatAnh = Listenable.merge([
                _boNhipCanhVat,
                _boDieuKhienGeorge,
                _boDieuKhien,
              ]);

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
                        onInteractionEnd: (_) => _gioiHanCameraSauTuongTac(),
                        child: SizedBox.fromSize(
                          size: BoCucWorldMap.kichThuoc,
                          child: IgnorePointer(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                FutureBuilder<Map<String, ui.Image>>(
                                  future: _taiAnh,
                                  initialData: TaiNguyenWorldMap.anhDaNap,
                                  builder: (context, snapshot) =>
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          painter: CanhQuanWorldMap(
                                            snapshot.data ?? const {},
                                            trangThaiCacMan:
                                                widget.trangThaiCacMan,
                                          ),
                                        ),
                                      ),
                                ),
                                FutureBuilder<ui.Image?>(
                                  future: _taiAnhGeorge,
                                  initialData: TaiNguyenWorldMap.anhGeorgeDaNap(
                                    widget.tepAnhGeorge,
                                  ),
                                  builder: (context, georgeSnap) =>
                                      RepaintBoundary(
                                        child: AnimatedBuilder(
                                          animation: nhipHoatAnh,
                                          builder: (context, _) {
                                            final t =
                                                _boNhipCanhVat.value *
                                                    math.pi *
                                                    2 +
                                                _boDieuKhienGeorge.value * 4.0;
                                            return CustomPaint(
                                              painter: HoatAnhWorldMapPainter(
                                                thoiGian: t,
                                                viTriGeorge: _viTriGeorge,
                                                huongGeorge: _huongGeorge,
                                                dangDiChuyenGeorge:
                                                    _boDieuKhienGeorge
                                                        .isAnimating,
                                                nodeGeorgeHienTai:
                                                    _nodeGeorgeHienTai,
                                                loTrinhDangDi: _loTrinhGeorge,
                                                anhGeorge: georgeSnap.data,
                                                vungNhinThay: _tinhVungNhinThay(
                                                  size,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                ),
                              ],
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

  void _khiBamNutMan(ManChoi man) {
    if (_daMo(man.id)) {
      _diChuyenGeorgeDen(man.id);
    }
    widget.khiChonMan(man);
  }

  Widget _cacDiaDiem(Size size) {
    final manHinhNho = size.width < 700 || size.height < 360;
    final scale = _boDieuKhien.value.getMaxScaleOnAxis();
    final daPhongToSau = scale > _tiLeVuaKhung(size) * 1.35;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

    final cacNhan = <({ManChoi man, Offset moc, Rect khung, bool gon})>[];
    final cacMoc = <({ManChoi man, Offset moc, bool gon, Size kichThuoc})>[];
    for (var i = 0; i < widget.danhSachMan.length; i++) {
      final man = widget.danhSachMan[i];
      final goc =
          BoCucWorldMap.viTriMan[man.id] ??
          BoCucWorldMap.viTriMan.values.elementAt(i);
      final moc = MatrixUtils.transformPoint(_boDieuKhien.value, goc);
      if (!(Offset.zero & size).inflate(30).contains(moc)) continue;

      final laManChinh = man.id <= 6;
      final gonMan = manHinhNho || (!laManChinh && !daPhongToSau);
      final rong = gonMan ? (laManChinh ? 40.0 : 30.0) : (laManChinh ? 102.0 : 92.0);
      final cao =
          (gonMan ? (laManChinh ? 40.0 : 30.0) : (laManChinh ? 70.0 : 62.0)) *
          textScale;
      cacMoc.add((
        man: man,
        moc: moc,
        gon: gonMan,
        kichThuoc: Size(rong, cao),
      ));
    }
    if (manHinhNho) {
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
        diem.kichThuoc,
        size,
        cacNhan.map((n) => n.khung).toList(),
      );
      cacNhan.add((
        man: diem.man,
        moc: diem.moc,
        khung: khung,
        gon: diem.gon,
      ));
    }
    return Stack(
      children: [
        if (!manHinhNho && !daPhongToSau)
          for (final vung in BoCucWorldMap.cacVung)
            Builder(
              builder: (context) {
                final p = MatrixUtils.transformPoint(
                  _boDieuKhien.value,
                  vung.viTriBienBao,
                );
                if (!(Offset.zero & size).contains(p)) {
                  return const SizedBox.shrink();
                }
                final mo =
                    widget.trangThaiCacMan[vung.idManChinh] !=
                    TrangThaiMan.chuaMo;
                return Positioned(
                  left: (p.dx - 64).clamp(6.0, size.width - 134.0),
                  top: (p.dy - 14).clamp(6.0, size.height - 28.0),
                  width: 128,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xD917211A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: mo
                              ? vung.mauVien.withValues(alpha: 0.85)
                              : const Color(0xFF6B736C),
                          width: 1.2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          'VÙNG ${vung.idManChinh} · ${vung.ten.toUpperCase()}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mo
                                ? const Color(0xFFF7EBD2)
                                : const Color(0xFFBFC4BC),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DuongDanDiaDiem([
                for (final n in cacNhan)
                  (
                    n.moc,
                    n.khung,
                    n.man.id == widget.manDangChon,
                    n.man.id <= 6,
                  ),
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
              gon: n.gon,
              khiChon: _khiBamNutMan,
            ),
          ),
      ],
    );
  }

  Rect _datNhan(Offset moc, Size nhan, Size view, List<Rect> daDat) {
    final cacViTri = [
      Offset(moc.dx - nhan.width / 2, moc.dy + 2),
      Offset(moc.dx - nhan.width / 2, moc.dy - nhan.height / 2),
      Offset(moc.dx - nhan.width / 2, moc.dy - nhan.height - 10),
      Offset(moc.dx + 16, moc.dy - nhan.height / 2),
      Offset(moc.dx - nhan.width - 16, moc.dy - nhan.height / 2),
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
    for (final v in cacViTri) {
      final ungVien = gioiHan(v);
      if (daDat.every((r) => !r.inflate(3).overlaps(ungVien))) {
        return ungVien;
      }
    }
    final taiMoc = gioiHan(cacViTri.first);
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
  final List<(Offset, Rect, bool, bool)> cacDiem;
  _DuongDanDiaDiem(this.cacDiem);

  @override
  void paint(Canvas canvas, Size size) {
    for (final (moc, khung, dangChon, laManChinh) in cacDiem) {
      if (!laManChinh && !dangChon) continue;
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
