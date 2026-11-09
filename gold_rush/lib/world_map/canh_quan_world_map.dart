import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'nut_man_choi.dart';

class CongTrinhWorldMap {
  final int id;
  final String anh;
  final Offset chan;
  final double chieuRong;
  const CongTrinhWorldMap(this.id, this.anh, this.chan, this.chieuRong);
}

/// Một công trình ứng với đúng một ID màn; không chứa luật cọc hay mở khóa.
class BoCucWorldMap {
  BoCucWorldMap._();
  static const kichThuoc = Size(1465, 980);
  static const congTrinh = <CongTrinhWorldMap>[
    CongTrinhWorldMap(1, 'lau_dai.png', Offset(676, 485), 190),
    CongTrinhWorldMap(2, 'nha_quan_tro_v3.png', Offset(530, 606), 90),
    CongTrinhWorldMap(3, 'nha_tho_ren_v3.png', Offset(745, 649), 90),
    CongTrinhWorldMap(4, 'nha_thu_vien_v3.png', Offset(888, 550), 92),
    CongTrinhWorldMap(5, 'nha_don_gac_v3.png', Offset(340, 285), 128),
    CongTrinhWorldMap(6, 'nha_kho_mo_v4.png', Offset(1155, 393), 108),
    CongTrinhWorldMap(7, 'nha_tho_ren_v3.png', Offset(1390, 215), 108),
    CongTrinhWorldMap(8, 'nha_quan_tro_dai_v4.png', Offset(230, 730), 120),
    CongTrinhWorldMap(9, 'nha_don_gac_v3.png', Offset(140, 495), 100),
    CongTrinhWorldMap(10, 'nha_tho_san_v4.png', Offset(480, 440), 100),
    CongTrinhWorldMap(11, 'nha_thu_vien_v3.png', Offset(660, 285), 105),
    CongTrinhWorldMap(12, 'nha_coi_nuoc_v4.png', Offset(860, 285), 110),
    CongTrinhWorldMap(13, 'nha_gia_kim_v4.png', Offset(1120, 580), 106),
    CongTrinhWorldMap(14, 'nha_phao_dai_v4.png', Offset(1390, 590), 118),
    CongTrinhWorldMap(15, 'nha_dinh_thu_v4.png', Offset(1360, 820), 116),
    CongTrinhWorldMap(16, 'nha_quan_tro_v3.png', Offset(1150, 910), 106),
    CongTrinhWorldMap(17, 'nha_coi_gio_v4.png', Offset(930, 880), 104),
    CongTrinhWorldMap(18, 'nha_nha_kinh_v4.png', Offset(710, 830), 110),
    CongTrinhWorldMap(19, 'nha_phap_su_v4.png', Offset(490, 890), 62),
    CongTrinhWorldMap(20, 'nha_thanh_tri_v4.png', Offset(100, 870), 122),
  ];
  static final viTriMan = Map<int, Offset>.unmodifiable({
    for (final c in congTrinh) c.id: c.chan + const Offset(0, 14),
  });
}

/// Chỉ nạp lâu đài gốc, terrain mới và 15 mẫu nhà. Các PNG trang trí cũ
/// không còn được tham chiếu/render nhưng được giữ nguyên trên đĩa.
class TaiNguyenWorldMap {
  TaiNguyenWorldMap._();

  static const thuMuc = 'assets/images/world_map/';
  static const tenAnh = <String>[
    'lau_dai.png',
    'terrain_khu_nha_v3.png',
    'nha_tho_ren_v3.png',
    'nha_quan_tro_v3.png',
    'nha_thu_vien_v3.png',
    'nha_don_gac_v3.png',
    'nha_kho_mo_v4.png',
    'nha_quan_tro_dai_v4.png',
    'nha_tho_san_v4.png',
    'nha_coi_nuoc_v4.png',
    'nha_gia_kim_v4.png',
    'nha_phao_dai_v4.png',
    'nha_dinh_thu_v4.png',
    'nha_coi_gio_v4.png',
    'nha_nha_kinh_v4.png',
    'nha_phap_su_v4.png',
    'nha_thanh_tri_v4.png',
  ];

  // Phần sprite hữu hình, đo từ alpha PNG gốc. Chỉ cắt lề trong lúc vẽ;
  // không sửa file ảnh, không kéo méo và không giải mã lại mỗi frame.
  static const khungNguon = <String, Rect>{
    'nha_kho_mo_v4.png': Rect.fromLTRB(
      17 / 1536,
      131 / 1024,
      1519 / 1536,
      896 / 1024,
    ),
    'nha_quan_tro_dai_v4.png': Rect.fromLTRB(
      10 / 1774,
      15 / 887,
      1766 / 1774,
      871 / 887,
    ),
    'nha_tho_san_v4.png': Rect.fromLTRB(
      7 / 1301,
      8 / 1209,
      1294 / 1301,
      1177 / 1209,
    ),
    'nha_coi_nuoc_v4.png': Rect.fromLTRB(
      23 / 1312,
      7 / 1199,
      1290 / 1312,
      1179 / 1199,
    ),
    'nha_gia_kim_v4.png': Rect.fromLTRB(
      116 / 1312,
      3 / 1199,
      1231 / 1312,
      1181 / 1199,
    ),
    'nha_phao_dai_v4.png': Rect.fromLTRB(
      119 / 1536,
      4 / 1024,
      1393 / 1536,
      1009 / 1024,
    ),
    'nha_dinh_thu_v4.png': Rect.fromLTRB(
      55 / 1312,
      5 / 1199,
      1255 / 1312,
      1171 / 1199,
    ),
    'nha_coi_gio_v4.png': Rect.fromLTRB(
      105 / 1218,
      9 / 1292,
      1071 / 1218,
      1271 / 1292,
    ),
    'nha_nha_kinh_v4.png': Rect.fromLTRB(
      91 / 1254,
      3 / 1254,
      1140 / 1254,
      1240 / 1254,
    ),
    'nha_phap_su_v4.png': Rect.fromLTRB(
      215 / 1024,
      5 / 1536,
      804 / 1024,
      1514 / 1536,
    ),
    'nha_thanh_tri_v4.png': Rect.fromLTRB(
      1 / 1312,
      1 / 1199,
      1310 / 1312,
      1183 / 1199,
    ),
  };

  static Future<Map<String, ui.Image>>? _boNho;
  static Map<String, ui.Image>? _anhDaNap;

  static Map<String, ui.Image>? get anhDaNap => _anhDaNap;

  static Future<Map<String, ui.Image>> nap() => _boNho ??= _napTatCa();

  static Future<Map<String, ui.Image>> _napTatCa() async {
    final daNap = <String, ui.Image>{};
    try {
      for (final ten in tenAnh) {
        final data = await rootBundle.load('$thuMuc$ten');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          targetWidth: ten.startsWith('nha_') ? 256 : null,
        );
        try {
          daNap[ten] = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }
      return _anhDaNap = Map.unmodifiable(daNap);
    } catch (_) {
      for (final anh in daNap.values) {
        anh.dispose();
      }
      _boNho = null;
      rethrow;
    }
  }
}

/// Công trình khóa được chuyển thành bóng tối mờ theo alpha của chính sprite.
class CanhQuanWorldMap extends CustomPainter {
  final Map<String, ui.Image> anh;
  final Map<int, TrangThaiMan> trangThaiCacMan;
  CanhQuanWorldMap(this.anh, {required this.trangThaiCacMan});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final terrain = anh['terrain_khu_nha_v3.png'];
    if (terrain != null) {
      canvas.drawImageRect(
        terrain,
        Rect.fromLTWH(
          70 * terrain.width / 1605,
          0,
          1465 * terrain.width / 1605,
          terrain.height.toDouble(),
        ),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.none,
      );
    } else {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF344534),
      );
    }
    final sorted = [...BoCucWorldMap.congTrinh]
      ..sort((a, b) => a.chan.dy.compareTo(b.chan.dy));
    for (final c in sorted) {
      if (!trangThaiCacMan.containsKey(c.id)) continue;
      _veCongTrinh(canvas, c, trangThaiCacMan[c.id] == TrangThaiMan.chuaMo);
    }
    canvas.restore();
  }

  void _veCongTrinh(Canvas canvas, CongTrinhWorldMap c, bool biKhoa) {
    final image = anh[c.anh];
    if (image == null) return;
    final crop =
        TaiNguyenWorldMap.khungNguon[c.anh] ?? const Rect.fromLTWH(0, 0, 1, 1);
    final source = Rect.fromLTRB(
      crop.left * image.width,
      crop.top * image.height,
      crop.right * image.width,
      crop.bottom * image.height,
    );
    final height = c.chieuRong * source.height / source.width;
    final rect = Rect.fromLTWH(
      c.chan.dx - c.chieuRong / 2,
      c.chan.dy - height,
      c.chieuRong,
      height,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: c.chan - const Offset(0, 6),
        width: c.chieuRong * 0.75,
        height: c.chieuRong * 0.14,
      ),
      Paint()
        ..color = const Color(0x480C170F)
        ..isAntiAlias = false,
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (biKhoa) {
      paint.colorFilter = const ColorFilter.matrix([
        0.35,
        0.10,
        0.03,
        0,
        0,
        0.05,
        0.40,
        0.03,
        0,
        0,
        0.05,
        0.10,
        0.33,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
      paint.imageFilter = ui.ImageFilter.blur(sigmaX: 0.4, sigmaY: 0.4);
    } else {
      paint.colorFilter = const ColorFilter.mode(
        Color(0xFFF0E4C7),
        BlendMode.modulate,
      );
    }
    canvas.drawImageRect(image, source, rect, paint);
  }

  @override
  bool shouldRepaint(CanhQuanWorldMap oldDelegate) =>
      oldDelegate.anh != anh ||
      !mapEquals(oldDelegate.trangThaiCacMan, trangThaiCacMan);
}
